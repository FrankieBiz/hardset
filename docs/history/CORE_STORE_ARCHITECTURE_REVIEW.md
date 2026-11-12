# Core and Store systems review

Reviewed 2026-10-24 against repository baseline `b5b93df`, `CODEX.md`, the implementation, tests, and SQLiteData 1.10.0 at its resolved revision. Maintainer: FrankieBiz <frankabisignano@gmail.com>.

This is a review and implementation worklist. Recommendations below have not been implemented. Competitor statements describe their public documentation, not access to their private schemas, source code, or measured performance.

## Architectural judgment

Keep Foundation-only, nonisolated HardsetCore; GRDB/SQLiteData; private CloudKit replication; typed identifiers; canonical kilograms; and persistence before a logged checkmark, record announcement, or rest request. The three core invariants are sound. The required pivots concern ownership, recovery, history completeness, and equipment identity around those invariants.

The strongest defensible positioning is a locally authoritative, recoverable log with explicit equipment provenance. Offline logging alone is already available elsewhere. No comparative latency measurements were performed, so this review does not claim Hardset is faster than any named product.

## Competitor evidence

| Product | Verified public behavior | Implication for Hardset |
| --- | --- | --- |
| Hevy | Its own comparison documentation says routines, logging, prior performance, and history work offline and sync on reconnection. Its machine-tracking help recommends duplicating an exercise for each machine/gym. Its help center documents workout export. | Offline support and export are existing expectations. First-class physical machine identity avoids duplicating movement taxonomy merely to keep load histories separate. [Offline documentation](https://www.hevyapp.com/compare/strong/), [machine tracking](https://help.hevyapp.com/hc/en-us/articles/43651329105687-Tracking-Progress-on-Gym-Machines-And-Why-It-Can-Be-Inconsistent), [export instructions](https://help.hevyapp.com/hc/en-us/articles/34953501503895-How-to-Share-Workouts-and-Routines-in-Hevy). |
| Strong | Strong documents background synchronization to Strong Cloud and CSV export; that export cannot be imported back into Strong. Its account help acknowledges local data that has not synced. Hevy's comparison reports Strong offline logging/history, but that is a competitor's account rather than independent testing. | Strong is not evidence that every set requires a server round trip. Hardset can distinguish itself through account-free local authority and a restorable archive. [Cloud sync](https://help.strongapp.io/article/241-force-sync), [account/local data](https://help.strongapp.io/article/143-strong-account), [CSV export](https://help.strongapp.io/article/235-export-workout-data). |
| MacroFactor Workouts | Its own support explicitly says it is not offline-first, has limited offline caching, and may require internet at launch for account/subscription validation. It supports quick/granular spreadsheet export and adjustable exercise equipment. | This is a documented contrast for reliable cold launch without a network. Equipment customization already exists in this market; the cited documentation does not establish whether history is keyed by physical machine. Evaluate Workouts separately from the nutrition app. [Connectivity](https://help.macrofactorapp.com/en/articles/366-troubleshoot-internet-connectivity), [export](https://help.macrofactorapp.com/en/articles/356-export-your-data-workouts), [equipment options](https://help.macrofactorapp.com/en/articles/333-accessing-exercise-options-during-a-workout). |
| RP Hypertrophy | RP documents account access and a browser-accessible app alongside native availability. Its September 24, 2026 release notes describe fixes for save errors during navigation on slow connections. | A service-backed workflow is evident; universal offline failure and its internal storage design are not established. Reliable local commits and recoverable rest state are useful differentiators, but no measured superiority follows from these docs. Offline and export guarantees were not established by the sources reviewed. [Product/access](https://rpstrength.com/pages/hypertrophy-app), [release notes](https://releases.rpstrength.com/hypertrophy). |
| Boostcamp | Its current features page says a loaded program works offline and sessions sync to the cloud on reconnection. | Downloaded/offline training is already supported. Hardset should demonstrate cold-launch logging, recovery, and new-equipment creation without a connection. Export/restore guarantees and physical machine history keys were not established by the sources reviewed. [Features](https://www.boostcamp.app/features). |

Do not infer competitors' duration columns, timer implementations, database queries per render, or flattened internal keys from screenshots. The Hevy workaround is direct evidence of a user-facing limitation; it is not proof of the other products' private data models.

## What needs to pivot architecturally

### P0: Give the local database and sync engine one stable owner

`HardsetApp.swift` retains the engine in view `@State`, but constructs it in an unguarded `.task`. View lifetime, task re-entry, and multiple windows should not determine database trigger ownership. An earlier engine-lifetime failure is already recorded in `Database.swift` and `SyncEngineRetentionTests.swift`.

Move store opening, the writer, delegate, and engine into one application-lifetime owner in the package composition layer; keep the app shell thin. Construct one engine per writer, make initialization idempotent, and retain it even while replication is stopped. Model opening failure explicitly: `assertionFailure` followed by continuation is not a durable recovery state. Keep local logging available during network failures and expose sync failure separately from local-save failure.

This is a lifecycle correction, not a proposal to replace GRDB or put a backend on the set-writing path.

### P0: Separate retaining data from permission to replicate it

Keep the explicit `HardsetSyncDelegate.syncEngine(_:accountChanged:)` implementation. Removing it restores destructive defaults. However, retaining rows is only one account-change invariant.

The current delegate reduces events to `signedIn`/`signedOut`/`switchedAccounts`, discards account identity, and emits an in-memory stream. No application consumer of that stream or `lastChange` was found. There is no durable owner binding, account-switch replication gate, or user-visible account resolution.

Add a device-local owner binding and explicit states for local-only, syncing with the bound account, and awaiting a decision after an account change. Preserve the existing database; stop replication when ownership is unresolved. Require an explicit choice before transferring retained history to a different account. First-time attachment of local-only history also needs a deliberate policy. An ownership gate must operate before send/fetch starts; a banner after automatic replication is insufficient.

SQLiteData 1.10.0 defaults to starting automatically, exposes `startImmediately`, `start()` and `stop()`, and enqueues unknown local records on sign-in before notifying the delegate. Therefore an account-policy check cannot live solely in a late UI stream subscriber. Verify account detection, startup ordering, stopped-engine writes, and restart behavior with real accounts. Cross-account leakage is a risk identified from missing policy, not an observed integration-test result.

### P0: Complete rest as a durable state machine

`RestTimerState` is a good value model, but `deviceRestTimer` is currently just a table and row type. There is no Store read/write path and no launch restoration. `RestTimerController` starts idle and holds its deadline, alarm ID, and metadata only in memory.

Add a device-local rest repository and reconcile persisted intent with actual AlarmKit alarms on launch/foreground. Persist state transitions, not ticking seconds. Keep `.running(endsAt:)`, `.paused(remaining:)`, and `.idle`; a frozen remainder is valid only while paused. Track scheduling intent and outcome so a crash between database persistence and an OS alarm operation is recoverable without pretending the two systems share a transaction.

Use a serialized operation sequence or generation token across scheduling awaits. The 400 ms debounce coalesces pending taps but does not make already-running async schedules atomic. `start` also overwrites the existing alarm ID before its cancellation, so a second start can lose the handle needed to cancel the old alarm. Cancellation and scheduling failures must remain visible. Do not promise force-quit/reboot/Focus behavior until the physical-device checklist passes.

Absolute dates survive suspension and serialization; they do not, by themselves, solve user/NTP wall-clock changes. Define reconciliation on significant time changes. Any in-process monotonic-clock aid must preserve the persisted deadline invariant.

### P1: Make history completeness explicit

Keep immutable `PriorPerformanceSnapshot` and event-driven loads. Change what the snapshot represents: exact latest-session sets per progression key, separately computed all-time record benchmarks, and explicit missing/unavailable/truncated history states. A bounded recent sample is not an all-time history.

Load at session start/resume and explicit add-exercise or change-machine events; never in a render. Pin the snapshot during a live session unless the user deliberately refreshes it. Keep any current-session benchmark accumulator separate from the immutable snapshot. A sync arrival should not overwrite a draft being typed.

The architecture needs bounded output and indexed queries, rather than arbitrary row caps that silently change answers. SQL `LIMIT` alone does not bound scanning or sorting work.

### P1: Preserve exercise identity and make load context explicit

Keep exercise × physical machine as the minimum comparison key. Do not replace it with exercise name, machine brand, or model. Two physical units of the same model can still require separate histories.

Resolve `machineID == nil`: it currently means both known free-weight work and equipment not recorded. Those facts must have different domain representations and labels. Add equipment/load context only where it changes comparison meaning: per-hand versus total external load, assistance versus added load, unilateral side, or a material machine configuration change. Preserve unknown states rather than inventing resistance conversions. New fields/tables must be additive and old rows must remain explicitly unknown.

Keep cross-machine examples separate from same-machine suggestions. The current default allows automatic cross-machine prefill; change that policy to an explicit choice. A note saying another machine supplied a number does not make its load comparable.

### P1: Make ownership tangible through export and restore

Private CloudKit avoids a Hardset-operated user-data backend but remains Apple-dependent, eventually synchronized storage. It is not an independent backup: deletes and unwanted edits can replicate. No portable workout export/restore path was found.

Add a versioned, lossless archive plus a human-readable export. Preserve IDs, machine attribution, units, timestamps, unknown taxonomy tokens, and provenance. Validate and preview imports before committing a transaction; define idempotence and duplicate identity handling. Exclude transient rest/OS alarm handles from portable workout restore. Use GRDB's supported backup/snapshot facilities rather than copying a live SQLite main file without its WAL state.

## What needs to improve in Core

| Priority | Finding and evidence | Required improvement |
| --- | --- | --- |
| P0 | `ExerciseLogState.lastLoggedRecord()` has no per-set machine provenance. A compiled probe logged A at 100 kg, changed to B whose prior was 50 kg, then appended a set: the new B draft contained 100 kg. | Carry immutable logged-set load context into `SetSlot`/recovery summaries, or maintain last-performed values per progression key. Never reuse A's load as B's current-session suggestion. |
| P1 | `ProgressionAnalyzer.machineChanges` groups by session, retains the first machine, and takes the maximum across all that session's machines. Probe: session one A=100/B=200, session two B=180 reports A-to-B delta −20. | Group by session and machine, define transitions using performed timestamps with deterministic tie-breaking, and keep every maximum attached to its own machine. |
| P1 | `SetEntryDraft.resolved()` accepts positive infinity; a compiled probe returned `isLoggable == true`. The stored-rest initializer accepts nonnegative infinite seconds before converting them to `Duration`. | Require finite numeric values at public/import/storage decoding boundaries. Keep zero added load valid. Validate increments as positive and finite; validate RPE when present. Avoid inventing universal load ceilings for all modalities. |
| P1 | `SessionTimeline.finish` guards local mutation, while the public initializer and synthesized decoding can receive invalid peer/import instants. Invalid ordering currently becomes absent duration without a reason. | Preserve derived duration and immutable start; expose invalid/implausible timeline status distinctly from an open session. Validate non-finite instants and imported values. Do not repair a finish using `Date()`. |
| P1 | `PriorPerformanceSnapshot` has no completeness/error state; fallback equipment selection sorts by the timestamp of the heaviest set rather than latest performance. | Represent provenance and completeness explicitly; use actual latest-performance recency with deterministic ties. Require exact-key data for record claims. |
| P2 | `PersonalRecordDetector` receives an array described as all previous work, but its Store caller supplies at most 1,000 recent rows. Unknown machine increment falls back to a kilogram plate step. | Accept compact, complete benchmarks with explicit coverage and load context. Make unknown increment policy visible and consistent across load/e1RM record kinds; do not guess a machine's achievable step. |

All changes must remain Foundation-only, nonisolated, and Swift 6 `Sendable` where values cross isolation boundaries. The existing package settings correctly enable Swift 6 and `NonisolatedNonsendingByDefault`. Keep database and AlarmKit handles out of Core. Do not use `@unchecked Sendable` or actor isolation to conceal modeling problems.

## What needs to improve in Store

| Priority | Finding and evidence | Required improvement |
| --- | --- | --- |
| P0 | `Migrations.swift` still registers only `v1`; commit `33c1038` added `curatedName` and `sessionExerciseID` by editing that migration. Debug builds enable `eraseDatabaseOnSchemaChange`. | Add forward migrations for any durable database created by the earlier schema. A database already marked `v1` will not rerun it; debug erasure hides that failure and can destroy history. Remove erasure before real user data, preserve old fixtures, and verify upgrades without resets. |
| P1 | `priorPerformanceSnapshot` applies a global 500-row limit across requested exercises and all machines, then excludes the current session in Swift. | Exclude the current session in SQL before limiting. Fetch complete latest sessions per exact key, with cross-machine examples separately budgeted. A frequently trained movement or busy machine must not starve another key. Honor `asOf` as a cutoff if it means an actual historical boundary; currently it is only a stamp. |
| P1 | `completedSets` returns the latest 1,000 rows but feeds all-time record claims; a better older set can disappear. `logSet` swallows a history-read error into an empty array. | Compute all-time maxima and reps-at-load with indexed SQL aggregates, or a complete rebuildable local projection. Distinguish unavailable history from no history, suppress unjustified claims, and keep the logging write available. |
| P1 | `ProgressionStore.samples` sorts ascending then limits to 2,000. Past the cap it permanently omits the newest work. | Fetch an explicit date window or paginate with a stable cursor. If showing recent history, select newest first and reorder for display. Preserve session completeness at boundaries. |
| P1 | Session start writes the session and each plan row in separate transactions. `addExercise` commits its row before reading the data needed for in-memory state. | Give each command an appropriate transaction boundary. A failed startup must not leave a partial active plan; a failed add must not return failure after silently adding an exercise. Build recovery from one consistent database read where practical. |
| P1 | `logSet` checks draft completeness but not that the session is open, the supplied plan row belongs to it/exercise, or that the machine context is valid. Machine updates do not check an affected-row count. | Validate local commands inside their write transaction; reject writes after finish and mismatched references. Verify that expected rows were updated before mutating memory. Keep inbound peer validation tolerant and observable rather than rejecting it through new synchronized SQL constraints. |
| P1 | Set IDs are minted inside each log call; ordinals are derived from local maxima. This prevents local ordinal collisions but cannot coordinate two offline devices or deduplicate a retried logical command after loss of acknowledgment. | Accept a stable command/set ID for retries, use existing primary-key identity for idempotence, and define deterministic order such as ordinal/time/ID. Do not add a synchronized `UNIQUE(session, ordinal)` constraint. Define concurrent logging/finishing semantics; an offline global lock cannot be guaranteed. |
| P1 | Hard-deleting a machine sets historic `machineID` to NULL, which collapses its sets into the existing nil series. Deleting an exercise cascades its logs. Current archive APIs are the correct protection. | Keep identity-bearing entities archived/tombstoned and resolvable for history. Test peer deletion and restore paths. Do not claim anonymous/null history is free-weight work. |
| P1 | `VolumeStore.attributionIndex` excludes archived exercises, so archiving a movement removes its historical muscle attribution. Report sets and attribution are read in separate transactions. Seeding updates attribution in place. | Include referenced archived exercises when reporting history, read report inputs consistently, and state whether old reports use current or recorded attribution. If historical reproducibility is required, add an attribution version/snapshot instead of silently rewriting meaning. |
| P2 | Synchronous Store reads/writes run from a `@MainActor` coordinator and feature callbacks. No database calls were found directly in logger render bodies, but synchronous calls can still block interaction. | Profile session start, log taps, picker search, and sync contention on device. Use GRDB async operations where measurement justifies them; keep UI state on MainActor. Recheck state after awaits and preserve persist-before-claim with in-flight command deduplication. |
| P2 | Current indexes omit the time ordering/filtering used by several history and volume queries. | Measure `EXPLAIN QUERY PLAN`; consider non-unique indexes over exercise/machine/completedAt with a stable tie-breaker, completedAt for volume windows, and session/plan lookup paths. Evaluate write amplification before adding all candidates. |

## Permanent schema rules and migration traps

The authoritative library reference is the [SQLiteData CloudKit guide at the resolved revision](https://github.com/pointfreeco/sqlite-data/blob/fcd8dced6edad0f1f97b1141de528116cd19eadb/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md). The code in the checked-out dependency was also inspected.

1. **Never rewrite an applied migration.** Add named migrations. Test a populated old database upgrading into the new one, repeated launch, and old/new clients exchanging data. A clean-install schema test cannot prove an upgrade.
2. **Names and IDs are protocol.** No synchronized table/column removal or rename; no primary-key reassignment to fix a spelling. Evolve semantics through additive fields/tables. Keep muscle raw values and unknown-token round trips stable.
3. **One globally unique primary key per synchronized table.** Keep UUID text keys and the documented `NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())` form. Join tables need synthetic single keys. No autoincrement or compound primary keys.
4. **No extra synchronized uniqueness constraints.** Duplicate gym names and offline-created machine aliases are valid distributed states. Reconcile logical duplicates explicitly without deleting their history. Do not confuse the primary key's NOT NULL conflict clause with permission to use destructive row replacement casually.
5. **New required fields must support old writers.** Use a meaningful default plus the documented NULL conflict handling, or make the new column nullable. A new required relationship without an honest default must start nullable. Never backfill guessed machine identity.
6. **Foreign-key graphs must stay acyclic and reference registered sync tables.** Use supported `CASCADE`/`SET NULL`/`SET DEFAULT` actions; omitted `ON DELETE` becomes unsupported `NO ACTION`. Review history loss from otherwise syntactically valid cascades. SQLiteData 1.10.0 skips its delete-action validation on multi-FK tables, so keep direct pragma tests.
7. **Reserved names need an application gate.** Preserve `SchemaRules` checks for CloudKit names, library prefixes, record-name constraints, and BLOB hash collisions. The current generic column-name helper does not check collisions between a BLOB column and another column named with its `_hash` suffix; add that when BLOBs are introduced.
8. **Keep synchronized data tolerant of old peers.** Preserve the project's no-CHECK policy for synchronized tables. `STRICT` typing does not enforce semantic validity. Validate local commands and classify/quarantine invalid peer values in projections without destructive normalization. Device-local tables may use stronger constraints where useful.
9. **Column-wise last-edit-wins is not a domain transaction.** A local SQLite transaction does not create a cross-device invariant across records/fields. Define concurrent finish, machine-change, and deletion behavior. Keep committed set payloads stable in v1; before adding edits, decide whether correlated load/reps/context need versioned replacement records to avoid hybrid merges. A full event-sourcing rewrite is not justified for this task.
10. **Test actual registration.** `HardsetMigrations.syncedTableNames` and `HardsetDatabase.makeSyncEngine` currently enumerate tables separately. Tests of the name list alone cannot prove the actual engine excludes local tables. Eliminate drift or assert the actual configuration. Keep `deviceRestTimer`/`deviceHealthSamples` local and preserve the recorded decision to defer bodyweight sync.
11. **Pin and test library behavior.** `Package.resolved` pins SQLiteData 1.10.0/GRDB 7.11.1; the manifest permits newer compatible releases. Validate schema, unknown-field preservation, account policy, and migrations when updating the lockfile. Do not assume every rule is a permanent property of later dependency versions.
12. **CloudKit deployment is a separate gate.** Deploy additive production schema before distributing a build that writes it, under the existing release approval process. Exercise delayed uploads, quota/network errors, retry, deletion, account changes, and mixed app versions. Local commit acknowledgment must never depend on sync acknowledgment.

## Verification and implementation order

Observed in this review:

- `make check` passed: 86 Swift files parsed; 162 Core tests in 22 suites; 45 Store tests in five suites.
- `python3 Tools/generate_project.py` exited successfully but changed the committed HardsetFeature product IDs/order. Regeneration is therefore not currently a clean reproducibility check. Its output was inspected and the generated project restored byte-for-byte to the review baseline; this documentation task does not include project-file changes.
- Those Linux checks compile exact copies of Core and a Store subset with pinned dependencies and the official SQLite UUID extension. They exclude `Database.swift`, `SyncSetup.swift`, and 13 of the 18 Store test files. They do not establish CloudKit/schema/delegate correctness or SwiftUI/AlarmKit compilation.
- A temporary executable compiled all current Core sources in Swift 6 mode with `NonisolatedNonsendingByDefault`; it reproduced the cross-machine append prefill, mixed-machine delta, and infinite-load acceptance described above. The probe did not modify project source/tests.
- `DEVICE-CHECKLIST.md` records a prior simulator build and workflow pass, superseding stale statements in `HANDOFF.md`/`DECISIONS.md` that the app has never compiled. Physical-device AlarmKit and two-device CloudKit checks remain unchecked. This session did not run Xcode or device tests.

Implement in this order: repair upgrade safety and disable erasure for real data; establish stable database/sync ownership and account gating; complete rest persistence/reconciliation; fix machine provenance; repair snapshot and record completeness; harden command transactions and retries; add export/restore and query-plan tuning. Expand the Linux gate to the other portable Store suites, and use macOS/iOS CI for the full target graph and CloudKit-specific tests.

Acceptance evidence should include old-database upgrades without loss; restart after every persistence/OS-operation boundary; A/B/A machine switches with duplicate exercise blocks; histories beyond every current row cap; failed reads/writes and disk-full paths; exactly one logical set per retried command; zero database activity during logger redraw/scroll with no user command; and real-account sync tests showing both retention and ownership separation.
