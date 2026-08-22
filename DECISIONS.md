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

## The muscle taxonomy and what rests on it

### 15. Adding a muscle token is cheap; renaming one is impossible

The single fact a future contributor most needs. SQLiteData forbids column renames forever and
CloudKit's production schema is additive-only, so nothing constrains the *set of string values* a
TEXT column may hold — but a re-spelling after a build reaches a second device is a data migration
across every user's device, visible only as volume that quietly stopped counting. `Muscle`'s raw
values are pinned by a test for exactly this reason.

### 16. `MuscleKey` is a struct because Swift has no per-case access control

An enum with `case known(Muscle) / case unrecognised(String)` cannot prevent
`.unrecognised("chest")` being constructed — a distinct `Hashable` value returning an identical
`storedValue`, which would split one muscle's volume across two dictionary keys while the grand
total still reconciled. A private stored `String` with one public initialiser makes that
unrepresentable. Storage is byte-preserved and never normalised, so a round trip cannot rewrite a
peer's data.

### 17. The 0.5 indirect credit is an adopted convention, not an inherited finding

Pelland et al. fixed the weight a priori and compared three fixed schemes (1.0 / 0.5 / 0.0) for
model fit; no weight was estimated from data, and their own discussion calls it "an assumption" and
"a heuristic". The claim "the weight was fitted under that labelling, so we are entitled to it" is
false and must not appear anywhere. The `stabilizer` weight of 0 is a second Hardset convention and
is not part of the scheme that was tested. `SetCounting.source.methodology` says all of this in the
text App Review reads, and a test asserts it keeps saying it.

### 18. Three quantities, three names, so they cannot be conflated

`fractionalSets` may be compared to a curve. `hardSets` is a count of completed working sets.
`setsTouchingGroup` counts sets once per group and is the only group-level number the app may show —
summing fractional credits across a group triple-counts a bench press. `VolumeAnalyzer.report`
takes sets and attribution and nothing else, so no threshold can leak from warnings into arithmetic.

### 19. There are no weekly set targets, and that is a finding

`weeklyTarget` returns `.unevaluated` for every muscle. No per-muscle weekly target is established:
the corpus gives a dose-response relationship for eight measured sites, not targets; the ancestor's
bands were uncited practitioner numbers; and the ~4-fractional-set figure is the volume at which
modelled gain first exceeds the smallest detectable effect size — a detectability artefact, not a
biological floor. The function exists anyway so future warning code can only iterate *evaluated*
targets, which makes "warn with no target" unrepresentable.

### 20. Machine series are never merged

A single line through two different leg presses draws progress the lifter did not make. Every
machine is its own series, and `MachineChange.explanation` states the load delta and that it is "a
difference between the machines rather than a change in strength" — refusing to call it progress or
regression, because across a switch it is neither.

### 21. A broken duration is withheld, not displayed

The ancestor shipped 9,749-minute workouts to its history screen as achievements. `SessionTimeline`
already refuses to store a duration; `HistoryView` additionally renders "Length unknown" for a span
longer than any real workout, because the honest statement is that we do not know how long it took.

## The design language

### 22. Colour is information, and three chart hues is a measured limit, not a taste

The visual direction is Whoop's instrument feeling with Apple's restraint: near-black ground,
one hero number per screen, thin marks, no decoration. Dark-only in v1, forced at the root rather
than following the system — one palette tuned precisely beats two tuned adequately. Light mode
stays a later decision, kept cheap by never naming a token for an appearance and by leaving the
light slot in `Tokens.Color.dynamic` in place.

**Chrome is greyscale and the accent is white**, the same value as `textPrimary`. It follows from
the rule that the brightest thing on screen should be the thing you are doing, and it removes the
usual dark-app failure where a brand hue competes with every status colour at once. The accent had
been `Color.accentColor`, so the app's identity was whatever tint the device carried.

**Four simultaneous chart hues do not pass on this ground.** Measured all-pairs, not judged: a
cool-only set — the most obviously "sleek" choice, and the first one tried — collapses to 1.1 dE
between blue and violet under deuteranopia, i.e. identical. Adding a green fourth slot fails too
(5.7 dE against purple, 14.9 against blue on *normal* vision, under the floor of 15). Three pass,
with 8.8 dE worst-case. So hue is spent on the **gym** and machines within a gym separate by stroke
dash and marker shape — which falls out of the data model, since a machine belongs to a gym, and it
is a better encoding than the one that failed.

Consequently **status hue may never enter a plot rect and series hue may never leave one.** Status
`low` and series amber differ by only 8.4 dE; as large swatches you can just about tell them apart,
and as 2 px marks — which is what a chart line is — you cannot. The separation has to be structural.

Three eyeballed palettes failed the validator before these values were derived. Colour separation
is computable, so it gets computed: re-run the validator on any change here rather than judging it.

Everything above is implemented. The motion system in `docs/UI-GUIDELINES.md` §5 is **specified and
deliberately not built**: haptic-and-pixel co-timing and a 100 ms acknowledgement budget are not
judgeable in a simulator, and AlarmKit has never fired on hardware, so the rest timer gets proven
before it gets decorated. `Tokens.Motion` ships as the vocabulary so there is nothing to invent
later.

### 23. Catalogue ids are derived from the slug, and that had been lost

Every `CatalogExercise.id` is a permanent primary key that logged sets reference, and every one of
the original 50 is a valid UUID **version 5** — a hash. So a deterministic scheme existed, and it
was the right choice: hashing is what makes two devices seeding the catalogue write identical rows
instead of duplicating each other, and there is no backstop, because SQLiteData forbids `UNIQUE` on
anything but the primary key of a synchronized table.

The scheme was written down nowhere — not in the file, not here, not in the taxonomy spec. 684
combinations of standard namespace and name template failed to reproduce the ids, so it was
genuinely lost rather than merely undocumented. The consequence is not hypothetical: two authors
adding the same movement would each have minted a different id, giving one exercise two permanent
rows on an additive-only schema, and the file's own comment claims those fixed ids are precisely
what prevents that.

Recorded now, and enforced:

    id = uuid5(uuid5(NAMESPACE_DNS, "catalog.hardset.app"), slug)
    namespace = 0dd2c109-7335-5eb0-aba6-8f1ee6e4f48a

`Tools/catalog_id.py` assigns it and rejects a malformed slug, because the slug is part of the key
and a typo in it is permanent. `CatalogIdSchemeTests` pins both halves: every entry outside the
grandfathered list must derive, **and** the grandfathered list must be exactly the set that does
not — so it cannot grow silently. The original 50 keep their ids, because changing one orphans
every set that references it.

The lesson generalises past this file: a deterministic identifier scheme with no recorded
derivation is a random scheme with extra steps.
