# Hardset — decisions of record

Phase 0. Every claim below was checked against a primary source (the on-disk iOS 26.4 SDK,
SQLiteData's own source at the pinned version, or Apple's published guidelines). Where the
handoff brief and the source disagreed, the source won and the difference is recorded here.

## Verified as briefed

| Claim | Evidence |
|---|---|
| Deployment target must be iOS 26.1 | `AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)` is `@available(iOS 26.1, *)`; the `stopButton:` overload is deprecated as of 26.1. AlarmKit swiftinterface lines 62–65. |
| Widget extension is mandatory | `AlarmAttributes<Metadata>: ActivityKit.ActivityAttributes` (line 15). The rest timer's presentation is a Live Activity, renderable only from a widget extension. |
| AlarmKit has no API to change a running countdown | Full mutation surface is `schedule`, `countdown`, `cancel`, `stop`, `pause`, `resume`. ±15 s is therefore cancel-then-reschedule. |
| AlarmKit's paused presentation carries no dates | `AlarmPresentationState.Mode.Paused` has only `totalCountdownDuration` and `previouslyElapsedDuration`. `Mode.Countdown` has `startDate`/`fireDate`. The app must own the deadline. |
| Sign-out erases local data by default | Two independent paths, both default — see below. |
| Schema restrictions (UNIQUE, reserved names, additive-only) | Confirmed, and **larger** than briefed — see below. |
| AlarmKit needs no entitlement, but needs `NSAlarmKitUsageDescription` | Confirmed. Without the key, scheduling fails at runtime. |

## Corrected against the brief

### 1. The sign-out wipe has two paths, and "install a delegate" is not the fix

`SyncEngine.handleAccountChange` wipes when `delegate == nil` (SyncEngine.swift:1359-1365), **and**
`SyncEngineDelegate`'s default protocol extension wipes when a delegate exists but omits the method
(SyncEngineDelegate.swift:84-101). Swift supplies that default silently — no warning.

So the brief's proposed test ("assert the delegate is installed") is both impossible and
insufficient: `SyncEngine.delegate` is an internal non-`public` `let`, and a present-but-default
delegate still destroys data. The tests here are behavioural instead: fire a sign-out, assert the
rows survive.

Also: `SyncEngine` retains its delegate **strongly** (non-`weak` `let`), so `HardsetSyncDelegate`
holds no reference back to the engine.

### 2. Sign-out is recoverable, not unrecoverable

`deleteLocalData()` never touches CloudKit; the package's own snapshot test shows the `CKRecord`
still present afterwards. Genuinely unrecoverable data is only what never uploaded, plus anything
the user cannot find after switching accounts. The mitigation is unchanged, but the severity
framing was wrong. Unregistered tables also survive the wipe entirely.

### 3. `Task.detached` for AlarmKit does not compile — it *is* the bug

The brief's remedy fails. `AlarmManager.AlarmConfiguration` is the one non-`Sendable` type in
AlarmKit's public surface, and `schedule(id:configuration:)` is nonisolated `async`. Building the
config on the main actor and awaiting `schedule` is a hard Swift 6 error. Verified both ways:

- The brief's approach: `error: non-Sendable 'AlarmManager.AlarmConfiguration<M>'-typed result can
  not be returned from main actor-isolated global function 'makeConfig()' to nonisolated context`
- The fix (`RestAlarmService.schedule`, a `nonisolated static func` that builds *and* consumes the
  config in one isolation domain): compiles clean with `-warnings-as-errors`.

Two things the brief did not mention: `AlarmManager.shared` is fine to touch from anywhere (that
worry can be dropped), and `authorizationState` is **synchronous** — `await`ing it warns, and
switching over it requires `@unknown default`.

**Verification-method correction:** `swiftc -typecheck` gives a false all-clear on all of these.
Region-based isolation is enforced in SIL, so concurrency work must be checked with `swiftc -c`
or a real build.

### 4. The schema has more permanent constraints than briefed

Confirmed: nine reserved column names, no `UNIQUE` outside the primary key, additive-only.
Additionally, all verified in source:

- Primary keys must be `TEXT ... NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())`. The
  `ON CONFLICT REPLACE` must sit immediately after `NOT NULL`. Auto-increment integers are banned.
- Every table needs a single, **non-compound** primary key — including join tables, which need a
  synthetic `id`.
- `ON DELETE` must be `CASCADE`/`SET NULL`/`SET DEFAULT`. **Omitting `ON DELETE` throws**, because
  SQLite defaults to `NO ACTION`.
- Foreign key **cycles, including self-references, are forbidden** (`.cycleDetected`). No
  `parentID REFERENCES sameTable(id)`, ever.
- Every foreign key from a synced table must target another **synced** table.
- `recordName` is `<primaryKey>:<tableName>`: ASCII, <255 bytes, no leading underscore. Enforced by
  a `RAISE(ABORT)` trigger at write time.
- SQLiteData writes its own sidecar fields (`sqlitedata_icloud_userModificationTime`, per-column
  variants, `<column>_hash` for BLOBs, `_recordChangeTag`), so those name shapes are unusable too.

**What is NOT validated** — each a way to ship a permanently broken schema with a green suite:
reserved column names (no validation exists at all), compound primary keys (origin is still
`"pk"`), `NOT NULL` without a default (the library's check is dead code), removing/renaming
columns or tables (documented only; fails silently at sync time), and — critically — **`ON DELETE`
on tables with 2+ foreign keys**, because the validator is gated on `foreignKeys.count == 1`.
In this schema that skips `machineExercises`, `sessionExercises` and `loggedSets`, so `SchemaTests`
checks all of them directly.

### 5. Bodyweight does not sync in v1

The brief's rule — HealthKit-derived values are device-local, user-typed bodyweight may sync —
has no textual basis. Guideline 5.1.3(ii) and Paid Applications Agreement 3.3.3(D) describe
"personal health information" as a **category**, source-agnostically, and 3.3.3(D) names CloudKit
explicitly. A bodyweight attached to an identity is the same information however it was entered.

The asymmetry decides it: enabling sync for a table later is additive and permitted; disabling it
later does not recall what already reached iCloud. So `bodyweightEntries` exists locally and is
**not registered** with the SyncEngine (`HardsetMigrations.deferredSyncTableNames`). Turning it on
is a deliberate decision to make with the guideline text in hand.

### 6. Privacy manifest is smaller than expected

One required-reason declaration: `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`.
`NSPrivacyCollectedDataTypes` is **empty** — RevenueCat declares its own purchase-history entry and
Apple's SDK-inheritance rule means we must not restate it. GRDB ships its own manifest with an
empty accessed-API list and links SQLite dynamically, so no file-timestamp or disk-space
declaration is warranted. Purchase history still must be disclosed in the App Store Connect
questionnaire, where the inheritance rule does not apply.

## Deliberate deviations from the brief

**A fourth package target, `HardsetAlarm`.** The brief specified three and placed the alarm
metadata in `HardsetCore` "Foundation-only". Those conflict: conforming to `AlarmMetadata` requires
importing AlarmKit, which ships only in the iPhoneOS SDK and is unavailable on macCatalyst, so
Core would stop building for macOS. Since `AlarmMetadata` requires nothing beyond
`Codable & Hashable & Sendable`, the conformance is a free retroactive extension in a small
iOS-only target. The payoff is concrete: the engine and store suites run on the host with
`swift test`, no simulator — which is how 54 tests run in ~0.1 s despite the brief expecting tests
couldn't run locally at all.

**GRDB declared directly.** Already transitively present and inside the locked "GRDB 7.11+ with
SQLiteData" decision; SQLiteData re-exports only a subset of it (not `Row`, which the schema
pragma tests need).

## Dependency cost, flagged

`sqlite-data` resolves to **1.10.0** and pulls in 14 packages: GRDB 7.11.1,
swift-structured-queries 0.36.0, swift-sharing, swift-dependencies, swift-perception,
swift-collections, swift-identified-collections, swift-concurrency-extras, combine-schedulers,
swift-clocks, swift-custom-dump, swift-snapshot-testing, xctest-dynamic-overlay, swift-syntax.

Two things worth knowing: `@Table`, `@Column`, `#sql` and `#bind` are **not** SQLiteData API — they
belong to swift-structured-queries, re-exported. That package is pinned at a **0.x** version, so a
0.37 could break source compatibility inside a SQLiteData patch bump. Treat it as a first-class
dependency to watch. And swift-syntax means macro expansion, which is what makes a sandboxed
`xcodebuild` fail here.

## Findings added after the first authoritative run

### 7. Spike B cannot be built as specified — `MockCloudContainer` is `package`-scoped

The brief asked for a `CKSyncEngine` conformance harness driving two stores through all six
documented sync scenarios. That is not reachable from application code.
`MockCloudContainer` is declared `package final class` in
`Sources/SQLiteData/CloudKit/Internal/MockCloudContainer.swift:7`, and `SQLiteDataTestSupport` —
the only test-facing module the package ships — contains exactly one symbol, `assertQuery`. There
is no public test double for CloudKit.

Two consequences. SQLiteData already exercises those six scenarios across ~25 files in
`Tests/SQLiteDataTests/CloudKitTests/`, so re-testing the library's merge semantics was never our
job. What *is* our job is that our schema and our delegate behave against a real container, and
that is a two-device integration test, not a unit test. Spike B is therefore redefined as section C
of `DEVICE-CHECKLIST.md`. Vendoring or forking SQLiteData to expose the mock was considered and
rejected: it buys coverage of someone else's code at the cost of owning a fork of the sync layer.

### 8. The app target cannot be compiled from a sandboxed command line

`swift test --disable-sandbox` runs the full package suite (54 tests, 7 suites) because SwiftPM's
own `--disable-sandbox` lets the macro plugin server run. `xcodebuild` has no equivalent flag —
`-disable-sandbox` is rejected as an invalid option — and fails with
`error: external macro implementation type 'SwiftMacros.TaskLocalMacro' could not be found ...
swift-plugin-server produced malformed response`. `-skipMacroValidation` clears the *trust* gate
but not this one; the plugin server itself execs fine, so the failure is in the sandboxed
plugin-server transport, not in the binary or the project.

So: **the package suite is verified, the app and widget targets are not.** They have never been
compiled in this environment. The unblock is a one-time Trust & Enable inside Xcode
(`DEVICE-CHECKLIST.md` section A), after which command-line builds should work. Until someone
confirms that, treat "the app builds" as an open question rather than an assumption — including in
any CI plan, since Xcode Cloud will hit the same macro trust step on first run.

## Findings from building the logger

### 9. StructuredQueries needs `#bind` around assigned values

`.update { $0.column = value }` fails to compile for literals *and* for optional columns, with
`'subscript(dynamicMember:)' is unavailable: Use '#bind' to explicitly wrap this value`. Variables
assigned to non-optional columns are fine, which makes the rule easy to half-learn. Wrap every
assignment.

### 10. `swiftc -typecheck` and a cached `swift build` both give false all-clears

Two separate traps, one lesson. Region-based isolation is enforced in SIL, so concurrency errors
only appear under `swiftc -c` or a real build. And `swift build --target X` happily reports
`Build of target 'X' complete!` at `[0/1]` having compiled nothing — after adding files, `touch`
the sources and confirm the compiler actually names them.

### 11. Module default isolation leaks into extensions and function references

`HardsetStore` and `HardsetUI` default to `MainActor`, so a plain `struct` or `extension` written
there is MainActor-isolated. Passing `Type.init(row:)` as a function value into a nonisolated
closure then fails with "loses global actor 'MainActor'". Every type that touches a database queue
is explicitly `nonisolated`, matching the schema types.

### 12. Record detection has to read history *before* the write

Detecting personal records after persisting the set means comparing the set against itself, so a
genuine best can never win. `SessionCoordinator.logSet` therefore reads history first, writes, and
only then announces — which also preserves the persist-before-claim rule, since a failed write
announces nothing.

### 13. Public API must not leak the `@Table` row types

The row types are `internal` and their column names are permanently frozen. Returning them from a
public method fails to compile, which is the right outcome: `SessionRecord`, `LoggedSetRecord`,
`PlannedExerciseRecord` and `CatalogEntry` are the store's public vocabulary, speaking typed
identifiers and `SessionTimeline` rather than raw `UUID`s and loose dates.

### 14. Two definitions of the pound had already appeared

`StrengthMath.displayRounded` carried a local `2.2046226218` while `WeightUnit` used the defined
`1/0.45359237`. Two constants, slightly different, three weeks into a greenfield codebase — which
is how a single-source-of-truth rule fails in practice. Conversion now goes through `WeightUnit`
only.
