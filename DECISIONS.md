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

### 24. A split is a partition, and no plan may be graded

A split in this app is an **arrangement of movements the lifter already trains, across days they
chose**. It is not a program, it prescribes nothing, and it carries no set counts. Full spec in
`docs/SPLITS-spec.md`; this records why the obvious feature — "build me a balanced split" — is not
buildable rather than merely unbuilt.

Four candidate quality axes, each closed off by a number computed in `SplitCalibrationProbe`:

- **A weekly set target.** `VolumeAnalyzer.weeklyTarget` returns `.unevaluated` for all 22 muscles,
  per #19. A generator that assigns set counts has nothing to optimise against.
- **Muscle coverage.** Every conventional split leaves 6–8 muscles at zero credit, five of them
  common to all of them (forearms, abs, obliques, neck, hip abductors). A coverage score marks down
  a well-built PPL and a bro split identically, for not training necks.
- **Total weekly volume.** A conventional PPL puts all six modelled muscles inside the studied range
  at 90 weekly sets; a perfectly reasonable 3-day full body does it at 42. Any formula treating
  volume as a quality axis must call one of those worse, and neither is.
- **A composite grade.** Only 6 of 22 muscles are `.modelled`, so a whole-body grade would be
  two-thirds territory the dose-response model refuses to speak about.

**What is left is still useful, and is what shipped.** The lifter has already told the app every
movement they train. Re-dealing that set across a different number of days is arithmetic over data
they authored, so it asserts nothing. The line, stated once: the app **may** decide which day a
movement they already do lands on; it **may not** decide how many sets of it they do, or introduce a
movement they have never logged as a recommendation.

**Two statements survive, and only two.** Which muscles nothing credits — a fact about a partition,
needing no target. And which of the six modelled muscles the plan credits with the fewest movements
— comparative and within-plan, because those six are the tokens where the literature supports a
direction at all, and no target gives any of them a floor.

**The load-bearing consequence: a plan has no set counts, so it has no volume.** Plan-level figures
count *movements* and *days*, which are facts about the arrangement itself. Running a plan through
`VolumeAnalyzer` would mean inventing a set count per movement, and a fractional-set figure derived
from an invented input is exactly the laundered guess this app exists to refuse. So
`SplitPlanAssessment` and `MuscleVolumeReport` are deliberately different types with different
vocabularies — one describes a plan, the other a logged week, and they are not interchangeable.

Enforced structurally rather than by discipline: **there is no `plannedSets` column on any split
table, and there never will be.** `sessionExercises` has one because that is the lifter typing what
they intend to do today; a split is the surface where the app does the arranging, so a set-count
column there is the hole a prescription engine climbs through. Omitting it makes the prescribing
version unrepresentable — the same move as `sessions` having no duration column, per #21.
`SchemaTests.splitsCarryNoPrescription` says so as a named test, because the column inventory alone
would let it back in as one more unremarkable line. Adding the column later is the permitted
direction under #4, so recording a lifter's *own* per-movement target stays available as a
deliberate additive change.

The three tables went into the **v1 migration** rather than a v2, because nothing has shipped and no
build has reached a device — v1 is still the single designed artefact it claims to be, and this was
the last moment a column could be reconsidered for free.

---

## The logger's missing shapes

### 25. Supersets and drop sets are timing, not prescription

The two gaps a 2026 competitive teardown was right about, and the largest functional distance
between this app and the loggers it has to match before anything else matters. `superset`,
`dropSet` and `myo` had **zero occurrences** in `Packages/HardsetKit/Sources`.

**Why they are permissible at all**, in an app that refuses to prescribe: neither asserts anything
about training. A superset is the lifter pairing their own movements, and it changes *when the rest
timer is armed* — once per round instead of once per set — and nothing else. A drop is the lifter
continuing their own set at a lower load, and it changes when rest is armed too: not until the chain
ends. Set counts stay the lifter's, loads stay the lifter's, and the app picks neither the pairing
nor the drop percentage. This is the same arithmetic-over-authored-data ground that permits splits
under #24, and `SupersetAndDropStoreTests` pins it: a superset records exactly what the same sets
record apart.

**One rule, not conditions scattered down the write path.** `SupersetRest.shouldArmRest` is pure and
Foundation-only, and it is the whole behaviour: a warm-up arms nothing; a set with a drop queued
behind it arms nothing; a set inside a superset arms nothing until every other member has caught up
*or has finished*. That last clause is load-bearing — without it a partner with fewer sets blocks
rest forever once it is done, and the lifter's last sets of the longer movement never start a timer.

**The research corpus said defer drop sets, and that reasoning does not apply here.**
`docs/research/r3-research.md:91` recommends shipping supersets in v1 and holding drop sets to 1.1
because "auto-advance blocks adding drop sets" — the specific complaint logged against Alpha
Progression. Hardset has no auto-advance: `grep -n "autoAdvance"` over the sources returns nothing,
and the log control acts on `nextUnloggedSlotID` without ever moving focus. The objection was
against a feature this app does not have, so it does not transfer.

The same corpus proposed modelling `SetKind {working, warmup, amrap, drop, backoff}` up front so a
later release would be "a UI change rather than a migration." **Refused as speculative.** #4 runs
one way: a column may be added at any time and never removed or renamed. So an unbuilt case costs
nothing to defer and a guessed one commits the schema to a vocabulary no screen has been designed
against. Three cases ship. Myo-reps and cluster sets are refused outright — they need genuine
sub-set structure with intra-set rests, which means a second concurrent alarm and a nested model.

**Storage is two flags, and the type is what makes the fourth state unwritable.** `isWarmup`
predates this and is filtered on in SQL in half a dozen places, so it stays; `isDropSet` sits beside
it. `STRICT` tables forbid `CHECK`, so "a warm-up that is also a drop" cannot be excluded in SQL —
`SetKind.storage` is the only thing that produces the pair, which is what excludes it. The decode
resolves the impossible combination rather than throwing, unlike `RestTimerState`, because it sits
on the crash-recovery path where throwing would take a whole workout's written sets down with one
bad row.

### 26. A drop set adds no set, and that is a convention with nothing behind it

Held to exactly the standard #17 holds the 0.5 indirect credit to. There is **no established
convention** for mapping a drop onto a set count: the dose-response scheme the counting follows was
fitted to studies of conventionally performed sets, and the drop-set literature describes the
technique as one set carried past failure at reducing loads rather than as several sets.

Hardset counts the chain **once**, as the set it continues. The only ground claimed for that is
that it is the reading which cannot manufacture volume — counting each drop separately would report
three sets dropped twice as nine, and every weekly figure in the app would inflate the moment
anyone used the feature. `SetCounting.dropSetConvention` says so in the text App Review reads, it is
interpolated into `SetCounting.source.methodology` so the disclosure cannot drift from the code, and
`dropConventionIsDisclosed` asserts it keeps saying it — including that it is "not a judgement"
about the technique, because "the app will not report this as a set" and "this is worth less than a
set" are different statements and only one of them is supportable.

**Tonnage is unaffected, because tonnage is arithmetic rather than convention.** Every drop's load
and reps count in full. `SessionVolume` reports `dropSets` separately for the same reason it
reports warm-ups separately: work that vanishes from a summary looks like a bug.

**Three read paths had to learn this, and the dangerous one is the prefill.** A drop is the lightest
load of the session by construction, so leaving drops in `priorPerformanceSnapshot` would hand next
week's opening row the bottom of last week's chain — a suggestion that gets *lighter* every time the
lifter trains hard. They are also excluded from `completedSets` (a deliberately reduced load is not
a record benchmark) and from `ProgressionStore.samples` (the chart plots a session's best work).

### 27. Rest cannot be learned from what this app stores, and the arithmetic says so

The same teardown recommended fixing the missing rest default by learning it — "a default learned
from the lifter's own median observed rest on that movement asserts nothing about physiology," which
would have been the identical argument that permits splits and #25. **It does not survive contact
with the schema, and the reason is worth recording so it is not re-proposed.**

**The app does not observe rest.** `loggedSets` stores `completedAt` and nothing else temporal;
across all thirteen tables the only other timestamps are `sessions.startedAt` and the rest timer's
own device row. There is no set-*start* time anywhere. So the only interval derivable from a
lifter's history is finish-to-finish:

```
gap(set N → set N+1) = rest + work(N+1)
```

`work(N+1)` is never recorded, and it is not negligible: a working set of 8–12 reps runs roughly
25–40 s against a 60–180 s rest, so the finish-to-finish median **overestimates rest by roughly a
fifth to a third**. A timer defaulted to it fires around when the lifter would historically have
*finished* the next set, not started it.

That makes it the exact shape this project's corpus catalogues at scale — a real measurement
presented as a different quantity. The honest claim available is a bound (rest is never more than
the gap), and a bound is not a default.

**Not fixed by measuring rest from the timer, either — that is circular while the timer defaults to
off.** The lifter has to turn it on before the app can observe anything to learn from. Breaking the
circle properly means the timer being on by default, which is the question this was supposed to
answer.

So: no learned rest default. The underlying defect is real and stays open — `restSeconds` defaults
to `0` and lives only in Settings, so the flagship feature does not start itself — but the fix is a
choice the lifter makes at a moment that makes sense, not a number derived from data that cannot
carry it. #6's refusal of a *literature* default stands unchanged and was never the thing in
question.

---

## Getting submittable

### 28. The icon is generated, for the same reason the project file is

`Tools/generate_icon.py`, not a drawing. The two colours in it are `Tokens.Color.ground` and
`Tokens.Color.accent`, so the icon cannot drift from the locked palette — if #22 ever moves, this is
a one-line change rather than a trip through a design tool. It is geometry, not commissioned art,
and it is deliberately in the locked palette so that replacing it later is a swap rather than a
redesign.

Two constraints that are not stylistic and are easy to get wrong once:

- **Opaque RGB, never RGBA.** iOS rejects an app icon carrying an alpha channel at upload. The
  script composites on the ground colour and saves RGB.
- **Supersampled 4× then LANCZOS.** Drawing at 1024 directly leaves visible stair-stepping on the
  shaft's rounded ends.

Related: `AccentColor` was still Xcode's default blue (`#2E82F6`), which contradicted #22 outright.
It is the achromatic accent now. That asset is not decoration — it tints system-drawn controls the
design tokens never reach.

### 29. Dark-only has to be declared to the system, not just to SwiftUI

`HardsetRootView` sets `.preferredColorScheme(.dark)`, and that governs the SwiftUI tree only. Two
things sit outside it, and both were wrong:

- **The launch screen.** `UILaunchScreen` was an empty dict, so the system painted its default
  background — white on any device in light mode. Every cold launch of a dark-only app began with a
  white flash. Now `UIColorName` points at a `LaunchBackground` colorset holding the ground value.
- **System-drawn chrome.** Sheets, alerts, the keyboard and scroll indicators follow the device's
  interface style, not a SwiftUI modifier. `UIUserInterfaceStyle` is `Dark`.

Verified rather than assumed: with the simulator in **light** appearance the app now renders
`(8, 10, 14)` — exactly `#080A0E` — where it previously leaked white.

Both keys come out together if light mode is ever built. #22 keeps that open, which is why the
token names still carry no "dark".

### 30. The training log is exportable, and exports nothing derived

A training log the owner cannot get out of the app is a hostage, and "data loss / no export" is one
of the loudest complaints in this category's reviews (`prior-research.md:576`). It is also the
honest consequence of the app's own claim: if these numbers are worth trusting, they are worth
owning.

**One row per logged set, and nothing computed.** No fractional credit, no estimated one-rep max, no
weekly totals. Every one of those is derived by code whose conventions are stated and revisable —
#17's 0.5 credit, #26's drop counting — and writing them into a file freezes a convention into an
artefact that outlives it. What is exported is what the lifter did, which cannot go stale.

**Kilograms, always**, matching storage, with `weight_kg` in the column name so nobody has to guess.
The display unit is a preference; converting on the way out would put the lifter's rounding into
their own archive.

**Escaping is its own tested type**, because a file that opens cleanly with one column shifted is
worse than one that fails to write — nobody finds out for months. One real bug fell straight out of
that test: in Swift `"\r\n"` is a **single grapheme cluster**, so `field.contains("\n")` is `false`
for a field containing a CRLF. A pasted note would have gone out unquoted, ending its row early and
shifting every column after it. `CSV.escape` matches on unicode scalars.

### 31. Every derived number is disclosed in one place, as well as in situ

`MethodologyIndexScreen`. The app already answered Guideline 1.4.1 where each number appears, each
sheet generated from the same `EvidenceSource` the code computes with. The gap was that a reviewer —
or a lifter deciding whether to trust any of it — had no way to see the whole set without finding
every screen that hides one. The sources are already public values, so listing them costs nothing
and gives App Review a single place to be pointed at.

### 32. Nothing invents a legal URL; privacy remains readable offline

The public privacy policy and Terms of Use pages do not exist yet, so `LegalLinks.live` holds `nil`
for external links. A link to a page that does not exist is worse than no link: App Review taps
every one, and a 404 is a rejection with a slower turnaround than a missing feature. Privacy is the
exception to hiding the surface: Settings always opens the policy bundled with the binary, and the
same screen adds the canonical online copy when `LegalLinks.live.privacyPolicy` is configured.
`submissionBlockers` names what is still owed in the same words `DEVICE-CHECKLIST.md` §E uses, so
"are we ready" has one answer rather than a memory of one.

---

## Getting it onto a phone

### 33. The app asks about rest once; it still does not prescribe one

`restSeconds` defaulted to `0`, and `0` meant both "no timer" and "never asked". Conflating those is
why the flagship feature never started itself: a lifter who never opened Settings had the rest timer
silently off forever — **and nothing ever requested the AlarmKit permission**, because the request
is triggered by choosing a duration. A fresh install could not have alerted even if it had tried.

`hasChosenRest` separates the two, and the first time a workout starts the app puts the question up:
the same options Settings offers, "No timer" first, and "Not now" as a real answer that is not asked
again.

**Asking is not prescribing**, and the distinction is the whole justification. #6 refuses a
*literature* rest default and #27 refuses a *learned* one — both are the app asserting a number.
Neither says the app may not put the question in front of the person whose decision it is. Nothing
is preselected, nothing is marked recommended, and the sheet says in as many words that Hardset has
no recommended rest length and will not invent one.

Verified on device rather than reasoned about: fresh install → start workout → the sheet appears →
choosing 1:30 fires the AlarmKit permission prompt → the first logged set arms a 1:30 timer labelled
with the movement. None of that chain had ever run before.

### 34. Signing goes through the generator, not the Xcode UI

`Tools/generate_project.py` reads `HARDSET_TEAM_ID` from the environment and writes
`DEVELOPMENT_TEAM` into every target. It is not committed, because a team identifier is
account-specific and a checked-in one is wrong for everybody but its owner. Setting it in Xcode's
Signing & Capabilities tab instead would work exactly until the next regeneration silently dropped
it — the same class of trap as hand-editing the project file.

`--local` (or `HARDSET_LOCAL=1`) omits `CODE_SIGN_ENTITLEMENTS` entirely. **iCloud/CloudKit and push
are paid-membership capabilities**, so an entitlements file requesting them fails the install
outright on a free Apple ID rather than degrading. Dropping them costs sync and nothing else: the
app already runs local-only when the sync engine cannot start, and every part of a workout is local.

That path is what made #35 necessary.

### 35. A sync engine that cannot start is not an assertion failure

`HardsetApp` caught a failed `SyncEngine` construction and called `assertionFailure`, on the
reasoning that the only possible cause is a schema mistake caught by `SchemaTests`. That reasoning
was incomplete: a build signed with a free personal team has no CloudKit entitlement, so it reaches
that line on **every** launch. An assertion is a no-op in Release and a trap in Debug — which means
the default build configuration would have crashed on launch, on the day the app was first taken to
a gym. It logs and runs local-only now. A real schema mistake still fails loudly in `SchemaTests`,
on the host, before anything is installed.

### 36. History is paged, because a workout you cannot reach is one the app forgot

`recentSessions()` defaulted to `limit: 50` and `HistoryScreen` passed no argument, so the list
stopped at fifty workouts with no footer, no count and no way further back. Verified against a
seeded 60-session history: **10 sessions and 75 logged sets sat in the database, unreachable.** At
three sessions a week that is month four, and to the lifter it is indistinguishable from data loss
in an app whose entire claim is that its numbers can be trusted.

Paged rather than uncapped: someone with years of training should not render all of it to check
last Tuesday. The footer is `nil` when a read returns fewer rows than the page size, which is what
makes its absence informative — no button means nothing older exists, rather than the list having
quietly stopped.

Worth recording how it was found. It is invisible with a week of data, which is all anyone had ever
put in front of this app; it took seeding twenty weeks of realistic training to see it at all. The
same pass found three more surfaces that only fail at length — see `HANDOFF.md` §8e.

### 37. `ShareLink` is the control, not sheet content

The export shipped broken twice in one sitting, and both failures were presentation shape rather
than logic — the CSV was written correctly every time.

**First**, the `.sheet` was attached to the `Section` that owned the button. This whole view is
already inside a presented sheet, and a second `.sheet` nested that deep **dismissed Settings**
instead of presenting over it. Tapping Export closed the screen and appeared to do nothing.

**Second**, once hoisted onto the `NavigationStack`, it presented a near-empty sheet containing a
single "Share…" link. `.sheet { ShareLink(…) }` renders the link as *content*; it does not become
the system share sheet.

So the row **is** a `ShareLink`. That has a real consequence worth stating, because it is what
drives the rest of the shape: `ShareLink` needs its item at init, so it cannot write the file
lazily on tap. The CSV is therefore written once in `.task` when the sheet appears, and the row
renders "Preparing export…" until it exists.

Two smaller things fell out of the same pass. The set count was `try? export.loggedSetCount()`
inline in `body` — a `COUNT(*)` over `loggedSets` on **every body evaluation**, so flipping the RPE
toggle re-queried the table. Hoisted into `@State`, read once. And the write is synchronous on the
main actor: `Task.detached` is a `sending`-closure error here because `ExportStore` arrives already
main-actor-isolated, and the invariant that actually matters is "no database work *per render*",
not "no database work". 450 sets produced a 72 KB file, so the read is milliseconds; if a log ever
grows enough to be felt, make `ExportStore` `Sendable` and move it off the actor.

Verified on device end to end: one tap, the system share sheet, "Save to Files", 72 KB, Settings
still behind it.

### 38. A user movement may inherit muscles from a curated one, but never its evidence

A movement typed at the rack credited exactly one muscle, `direct`, `low` certainty. So
`Nautilus High Lever Row` credited lats and nothing else, while the curated `Chest Supported Row` it
is plainly a variant of credits rear delts, upper back and biceps too. Every weekly figure that
movement touched was quietly short — and for a lifter whose gym is mostly brand-specific machines,
that is most of their training.

`NewExerciseSheet` now offers a "Based on" template. The muscles and their roles carry over. The
**provenance does not**: `InheritedAttribution.inherited(from:primary:)` rewrites every contribution
to the user source with no citation, and caps certainty at `.low` by `min` — so a contribution that
was already `.unevaluated` stays `.unevaluated` rather than being promoted on its way through. The
literature cited for a chest-supported row is evidence about *that* movement; a lifter asserting
their lever row is like it is one person's judgement about one machine.

Two things make this honest rather than merely convenient, and both came out of an audit that
refuted the spec's original reasoning. The spec said "Phase 2 lives or dies on the
source-and-citation swap." **That was backwards.** Nothing outside the JSON encoder reads
`.certainty`, `.sourceID` or `.citation`, so the swap alone changes nothing anyone sees, while a
silent copy would mint up to eight per-muscle arithmetic facts the lifter never saw. That is
strictly worse than the single guess it replaced, because the single guess *under*-claims.

So: the inherited muscles are shown as rows that can be switched off, and only what is left on is
written — the endorsement is real, not implied. And the rewrite happens at the **store** boundary,
not in the sheet, so no future caller can write an inherited attribution that still carries the
trial's provenance. Stabilisers are dropped: they credit nothing, and the sheet lists credited
muscles only, so inheriting one would be a claim that never appeared on screen to be refused.

The same audit found `SetCounting.certaintyCeiling` had been dead its whole life — `public`, called
only by its own tests — while `VolumeAnalyzer.doseResponse` computed the identical rule inline.
`doseResponse` now calls it, and the ~25-set cut point is read from `studiedRangeCeiling` instead of
being retyped as a literal.

### 39. A suggested machine name may resolve to a machine here, never merge one from elsewhere

Machine names are now offered back when adding one, because the same machine at a second gym was
retyped from scratch and "Hammer Strength Iso-Lateral Row" is not a name anyone retypes identically.
A near miss did not fail loudly — it silently created a third machine with a third empty history,
and invariant #10 forbids merging two machines, so there was no way back.

The rule is a **partition**, and it is the whole design:

- A name already at **this** gym resolves to that machine. Autocomplete makes re-picking one likely
  rather than rare, and an unconditional insert would answer "that one" with a brand-new machine
  holding no history. Matching normalises case and spacing, because a lifter at a rack does not
  reproduce either.
- A name from **another** gym creates a new machine, and the sheet says so in as many words: its
  loads start empty and are not shared with the one at the other gym. Anything vaguer and the
  feature reads as "merge my machines", which is the one thing #10 forbids.

`GymStore.resolveMachine(at:named:)` is the only sanctioned path from a name field to a machine;
calling `createMachine` straight from user input is now the bug. `setMachineArchived` also gained the
unarchive direction it never had — archiving from the new library screen would otherwise be a
one-way door, which is exactly how a mistyped duplicate becomes permanent.

### 40. Every declaration in `HardsetStore` must say `nonisolated`, and a test now enforces it

This module is built with `.defaultIsolation(MainActor.self)`, which is why every store type in it
spells out `public nonisolated struct`. An **extension** that omits the same word is silently
`@MainActor`, and the compiler says nothing — the type's API is then split across two isolation
domains, most of it callable from anywhere and part of it main-actor-only.

It does not fail at build time. It fails as **SIGTRAP with no message**, apparently *on entry* to
the function, so nothing logged inside it ever prints and the crash reads as though the call site
were at fault. The triggers are closures handed to the standard library — `filter`, `sorted`;
`map(\.someKeyPath)` and plain `for` loops do not trip it, because a key path carries no isolation
and a loop body is not a closure.

That combination is genuinely misleading: it looks exactly like a codegen bug, and it survives
`swift package clean`. Writing `MachineLibrary.swift` cost hours to it, and every intermediate
"fix" — loops instead of `filter`, two sort passes instead of one comparator, a struct instead of a
tuple — only moved the symptom while leaving a store that claims to be callable from any context and
is not. The diagnosis only became visible when marking the extension `nonisolated` finally made the
compiler name a main-actor-isolated call.

`IsolationContractTests` sweeps `Sources/HardsetStore` and fails when an extension of a nonisolated
store type declares members that are neither. `extension GymStore` in `GymStore.swift` was already
carrying the same latent defect and is now fixed.

## Knowing where you are in your own plan

### 41. A plan day's identity is recorded on the session, not inferred from what it contained

`SplitDayRecord` carried no notion of when a day was last trained, so on a three- or four-day split
the lifter had to remember where they were — which is the job a training log exists to do. The
figure is now read from a new `sessions.splitDayID`, written when "Start this day" opens a workout.

**Recorded rather than derived, and that is the decision.** The alternative was matching a session's
movements back onto a plan day, which is a guess: two days sharing a movement, a day trained with a
substitution, or an empty workout that happened to contain the right three lifts all defeat it.
"You last trained Pull six days ago" either is a fact or has no business on screen. DECISION #4
permits adding a column at any time and forbids removing one, so the honest option was also the
cheap one.

`ON DELETE SET NULL`, never CASCADE: deleting a day from a plan reshapes the plan and must not delete
the training done on it. The linkage is forgotten, the workout stays. `SchemaTests` pins the column
and `SplitRotationStoreTests` pins the invariant.

**What is on screen is a fact, not a recommendation.** Each day reads "Last trained 10 days ago", and
the single day waiting longest also says "longest since trained" — a statement about the lifter's own
history, in the same family as the planner's existing "Fewest movements" label. It is deliberately
not "next up", "due", or "today's workout": `SplitRotation.longestSinceTrained` returns nil for a
one-day plan and for a plan nothing has ever been trained from, because in both cases naming a day
would assert an order the lifter never established. A never-trained day counts as longest, ties break
on the lifter's own ordering, and `SplitRotationCopyTests` bans the prescriptive vocabulary outright.

### 42. Recency is counted in days through the second week, because the system format is not usable here

`Date.formatted(.relative(presentation: .named))` collapses everything from seven to thirteen days
into "last week". That is precisely the range a weekly split lives in, so a day trained ten days ago
and a day trained seven days ago rendered **identically** — and those are the two the lifter is
choosing between. Found by seeding twenty weeks and reading the screen; the suite was green.

`TrainingRecency.phrase` says "today", "yesterday", "N days ago" to thirteen, then "N weeks ago".
The boundary at thirteen also makes "1 weeks ago" unreachable. Counted in **calendar** days rather
than elapsed seconds: a set logged at 22:00 and one at 07:00 the next morning are a day apart to the
person who did them. The progression browser was moved onto the same function, so the app words one
fact one way.

### 43. Browsing backwards stops where the training does

The volume tab's week navigator had no floor, so it paged into empty seven-day windows for as long as
someone kept tapping, and "Nothing logged" meant both "you rested that week" and "you had not started
yet" — the same ambiguity the history list's absent footer was changed to avoid.

`VolumeStore.earliestCountableSet` is the floor, and it is filtered **exactly** as `countableSets`
is. That agreement is the point rather than a detail: counting every row instead let the control
offer an earlier window whose only content was a warm-up, which then rendered "0 working sets" and
"Nothing logged" — the button promising something the screen it governs cannot show. Found by paging
to the boundary against a seeded store, not by a test.

### 44. A workout started from a plan day takes that day's name

Every session the app created was nameless: `SessionCoordinator.start` accepted a `title` and no
caller ever passed one, so history could label a workout only with its date. Starting the day the
lifter had already called "Push" and then showing them a dateless row discards a name the app was
holding. It is still renameable from the live session, which is the path that always existed.

Fixing it exposed a latent defect worth recording: `start` wrote the title to the session row but
built the coordinator **without** it, while `resume` reads it back. Harmless while nothing passed a
title; the moment a plan day did, the live screen said "Name this workout" over a row that said
"Push", and a force-quit made the name appear out of nowhere.

### 45. Seeding a realistic *length* of history is a repo tool, not an ad-hoc script

Four of the defects above were found by running the app against twenty weeks of training and none by
the suite. A week of data hides all of them, and a week is what a hand-driven walkthrough produces.
`Tools/seed_history.py` writes sixty sessions across twenty weeks through sqlite3 directly, and is
the first thing to reach for before judging any progress surface.

Three things it must keep doing, each learned by getting it wrong: resolve the **bundle identifier**
from the device rather than assuming one (it is configurable, and a wrong guess reports itself as a
missing schema); resolve movements by **`catalogSlug`**, not display name, because seeding by name
creates uncurated duplicates that the app then honestly reports as "Not attributed" — making every
muscle figure downstream unjudgeable; and re-resolve the **container path** every run, because it
changes on each reinstall.

### 46. A changed v1 migration does not upgrade a v1 database

Adding `sessions.splitDayID` inside the existing `v1` `CREATE TABLE` made every fresh database and
every schema test pass, but did nothing for an installed database whose `grdb_migrations` already
contained `v1`. The first Release smoke test against a retained simulator container found the real
result: every session query failed with `no such column: sessions.splitDayID`.

The v1 table definition is restored to the shape already installed, and
`v2-session-split-day` adds the nullable foreign key with `ALTER TABLE`. `SchemaTests` now creates an
actual v1 database, inserts an existing workout, runs the remaining migration, and proves the row,
column, and `ON DELETE SET NULL` relationship all survive. The Release app was then installed over
the same failing simulator container without uninstalling; both migrations are recorded, SQLite's
integrity check is `ok`, and the recovery error is gone.

## Perfecting the plan system

### 46. A plan has no gym, so its machines are reconciled at the moment one is known

A machine belongs to one gym. A plan does not, and its entries were chosen from whatever
`lastUsedGym()` happened to be — so starting a plan built at one gym while standing in another opened
every row bound to the *other* gym's machine and showed its load history as though it were the
equipment in front of you. Sets logged that way go into a machine series the lifter never touched,
which corrupts differentiator #2 silently. Proven on device: four movements, four `MISMATCH`.

It was an oversight, not a design. The logger's picker has always been gym-scoped
(`canPickMachines` requires a gym; `machines(at:)`, `recentMachines(for:at:)`), and `logSet` validates
nothing — the plan was the one path around it. The gym sheet even states the invariant being broken:
"machines belong to a gym."

**A plan still has no gym, deliberately.** `splits.gymID` would force a lifter who runs one
arrangement at two gyms to keep two plans, which is a worse product than reconciling. So
`plannedExercises(for:at:)` decides per movement: same gym keeps it; a different gym resolves to a
same-named machine *here* if one exists; otherwise the row opens unbound; and no gym at all drops it,
because a session with no gym can only ever log `machineID == nil`.

Name resolution is scoped to this gym and normalises the way `existingMachine(named:at:)` does, so
DECISION #39 and invariant #10 both hold — nothing is created and no two histories merge. It composes
with the machine-change disclosure already in the logger: the resolved row shows "From another
machine", so the lifter knows the prefill is not from the machine they are standing at.

The planner's gym is now the root's `selectedGym` rather than its own `lastUsedGym()` in three places.
Those are different questions, and after switching gyms the planner went on offering the old gym's
machines while its own button would start a workout somewhere else.

### 47. Re-dealing rearranges movements; it does not reset what the lifter authored

`replace` wrote `machineID: nil` for every entry and took day names from the dealer, so one tap of
"Deal" discarded every machine the lifter had named and renamed "Push / Pull / Legs" to "Day 1 / Day 2
/ Day 3". No undo. The confirmation said only "This replaces the current arrangement. Your logged
workouts are not affected" — true, and materially incomplete, which makes agreeing to it meaningless.

Machines and intended set counts are now carried by movement (queued, so a movement planned twice
keeps both of its machines), and day names by position. The confirmation names what it keeps.

### 48. An intended set count is the lifter's, and three guards keep it that way

`splitEntries.targetSets`, additive and nullable. The spec's section 3 argued against a set-count
column and the argument was about the *dealer* being able to fill one; section 6 then named this exact
extension — "per-movement set targets of the lifter's own. Additive later if asked for" — and it was
asked for. The refusal was never "no number may exist", it is "the app may not author one".

The hop needed no new machinery: `PlannedExercise.plannedSets` was already `Int?` and
`sessionExercises.plannedSets` already existed, so a day with set counts opens the logger with that
many rows, and a day without still takes its rows from history.

Guarded harder than the ban it replaces. `splitsCarryNoPrescription` still bans every name the app
could deal out and argues this exemption in its own doc comment rather than dropping a list entry;
`targetSetsIsNullableAndUndefaulted` proves the schema cannot supply a value (a `NOT NULL DEFAULT 3`
would prescribe three sets to everyone without a line of code); and
`appNeverAuthorsATargetSetCount` sweeps `Sources` for a literal assignment. That last one was verified
to fail, naming file and line, before being trusted, and strips comments first — a ban that trips on
its own explanation is the trap HANDOFF §9 records for the "score" substring test.

### 49. Order is the lifter's, in both directions, and a plan may report frequency without ranking it

`moveEntry` had always taken a target position and the only interaction that reached it dropped it, so
what the lifter does first when fresh was unorderable. There was no `moveDay` at all, and day order is
both the order the plan reads in and the tie-break `SplitRotation.longestSinceTrained` uses — a plan
whose days cannot be reordered has an arrangement the lifter cannot correct. Both are menus, for the
reason already recorded: a drag has no discoverable affordance and no VoiceOver equivalent.

`SplitPlanAssessment.creditingDays` existed with no consumer and its own note says how it may be
shown: "a UI may show this and may **not rank it**", because no training frequency is established. So
`modelledDayCredits` is ordered by `Muscle.allCases` (ordering by count would be the ranking the note
forbids), restricted to the six `.modelled` muscles (§2 permits no claim about the other 16 beyond
zero-versus-nonzero, and a per-day count is such a claim), and omits muscles nothing credits. The
footer says it on its face: "not a target… these are not ranked and none is better than another."

### 50. A movement the lifter retired is reported, not removed — and keeps its name

Archiving is a soft delete, so a retired movement stays in the plan while the picker stops offering
it. `retiredMovements(in:)` reports them and the row says "Retired — still starts, no longer offered".
Reported rather than filtered, because dropping the row would be the app quietly editing someone's
plan.

Adding that marker exposed a second defect, found by archiving a movement and looking: the planner
built its rows only from `selectableExercises()`, which excludes archived rows, so the retired
movement rendered as "Unknown movement / Not attributed" — a movement the lifter named, reported as
though the app had never heard of it. `CatalogSeeder.entries(for:)` looks up by id and does not filter
on archived. **Naming what is already there is a different question from offering something new**, and
one list cannot answer both.

### 51. v1 is immutable; a new column is its own migration

Recorded because this pass got it wrong first. `splitDayID` and `targetSets` were both added by
editing v1's `CREATE TABLE`, which makes *fresh* installs pass `SchemaTests` while leaving an
already-installed database without the column forever — v1 is already recorded in `grdb_migrations`
there, so it will never run again. `eraseDatabaseOnSchemaChange` hides this in DEBUG only when the
schema differs, and here it did not.

Both are now additive migrations (`v2-session-split-day`, `v3-split-entry-target-sets`). The symptom
when the two conventions were mixed was a launch-time `duplicate column name` and the app's own
"Can't open your training history" screen — which behaved exactly as designed, naming the failing
statement and stating that nothing had been deleted.

Consequence for the column pin: `ALTER TABLE` appends, so a migrated column sorts **last** in
`columnInventoryIsPinned`. Its position there is the migration's fingerprint, not a preference.

### 52. A named gym machine is one authoring action, and movement order is visible

Movement actions existed only in a long-press context menu. That made changing order technically
possible and practically hidden, especially when the row itself gave no indication that it had
actions. Every plan row now has a visible move/edit control with up, down, and move-to-day actions;
the machine label is also a direct button, including an explicit “Add machine” state. The context
menu remains as a shortcut, but it is no longer the only route.

The second dead end was split across two otherwise working flows. “Your own movement” created an
exercise, while “Add a machine” existed only inside the live workout's machine picker — the planner
did not pass that picker's creation closure at all. A proper noun such as “Panatta Chest Press”
therefore required typing the same name twice and, from a plan, leaving the flow entirely.

`NewExerciseDraft` now carries an optional same-named machine. When a gym is selected, the creation
sheet offers to save the name as both the movement and that gym's physical machine, defaults that
choice on when the modality is Machine, resolves rather than duplicates an existing machine at that
gym, links it to the new movement, and selects it immediately in either a plan or a live workout.
The machine picker in the planner also exposes its own add path for an existing movement.

### 53. Storage latency never masquerades as a dead interaction

The first performance pass optimized the logger's render loop and left almost every other screen
performing synchronous SQLite work from a `@MainActor` view. That was hard to notice with an empty
simulator and increasingly visible with years of workouts: opening History, Volume, Progress,
Machines, or Plan; searching movements; preparing an export; starting a workout; and recovering an
interrupted workout could all monopolize the UI actor. Some flows then swallowed their read failure
or briefly rendered a false empty state, so latency and failure both looked like an unresponsive
tap.

Store handles explicitly conform to `Sendable` because their only stored dependency is
SQLiteData's thread-safe `DatabaseWriter`; a compile-time contract pins that promise. Feature
screens now build their read models in user-initiated detached tasks, batch related reads, debounce
movement search by 120 ms, discard cancelled or stale results, and publish only completed snapshots
back on the main actor. Launch catalogue seeding, session start, and crash recovery use the same
boundary. Busy states disable duplicate commits and say what is happening; failed reads keep saved
data intact and say so instead of presenting a convincing empty list.

Two interaction corrections belong to the same rule. A checked set button now performs the inverse
action—unlog—instead of calling log again and appearing dead, and movement notes/superset/removal
actions have a visible menu instead of requiring an undiscoverable long press. Removing a movement
that already has logged rows asks for confirmation because that action changes the current workout,
while earlier history remains untouched.
