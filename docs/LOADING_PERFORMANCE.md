# Loading performance

## Verified database milestone — 2026-11-07

Objective: improve loading throughout Hardset while preserving workout data,
machine-specific history, and zero database work during logger rendering.
The first milestone covers indexed Store reads; it does not establish app-wide
completion or device latency.

Owned paths: Store migrations, HistoryStore migration tests, the local query
benchmark, and the Makefile check gate. Acceptance criteria:

- Existing v1 databases gain indexes through a forward migration.
- The upgrade preserves workout rows and query results; reopening is idempotent.
- Rolling volume, progression, exact-machine history, session sets, and session
  plans use indexed searches without temporary sorting in the representative SQL.
- New indexes are non-unique and leave synchronized table shapes unchanged.
- `make check` passes; project regeneration matches the committed project.

`v2_loadingIndexes` adds five non-unique indexes matching the date windows,
equality predicates, and ordering used by VolumeStore, ProgressionStore, and
LoggerStore. The original v1 migration is unchanged. Existing narrower indexes
are retained; removing redundant indexes can be evaluated separately after
measuring storage and write costs on a device.

Run `python3 Tools/check_query_performance.py --require-indexes` to execute the
literal migration SQL against 100,000 sets and 25,000 plan rows, compare query
results before/after the upgrade, inspect query plans, and verify foreign keys.
The gate rejects scans and temporary sorts; timing is informational so host load
does not cause flaky failures. SQL query shapes mirror the Store predicates and
ordering; they are not a capture of StructuredQueries-generated SQL. Native
Store tests separately execute the real migrator and Store paths.

Representative median times from five warm in-memory reads on Linux:

| Query | Before | After |
| --- | ---: | ---: |
| Rolling volume, 1,200 returned sets | 4.342 ms | 1.079 ms |
| Progression, 1,500 returned sets | 1.978 ms | 1.446 ms |
| Machine history, 1,000 returned sets | 1.704 ms | 0.914 ms |
| Session recovery, 20 returned sets | 0.021 ms | 0.018 ms |
| Session plan, 5 returned rows | 0.625 ms | 0.004 ms |

All five plans use indexed searches after migration, with no temporary sort.
Before migration, volume and plan loading scan entire tables; the other three
queries sort their matches. The regression command was run before the change
and failed for all five query shapes, then passed with the forward migration.

Verification: `make check` passed (90 Swift files parsed, 171 Core tests,
46 Store tests across five local suites, and query-plan gate).
`python3 Tools/generate_project.py` produced identical project and scheme files.
Linux checks exclude SwiftUI, CloudKit wiring, AlarmKit, and iOS app compilation.

## Verified workout-start milestone — 2026-11-07

`SessionCoordinator.start` now prepares history and machine-increment reads
before saving, then commits the session and all planned exercise rows together.
An internal Store command returns the saved plan IDs for the coordinator to bind
to exercise states. The public empty-session API uses the same write path.
`PlannedExercise` is explicitly nonisolated, matching its immutable, Sendable
value semantics when captured by the database writer.

A twelve-exercise start previously used thirteen write transactions. A native
SQL-trace regression test measures one now, without expanding or logging bound
arguments. This reduces commit overhead; elapsed device startup time has not
been measured. Tests also pin exercise positions and planned set counts.

Failure injection proved that the original implementation left a partial
session/plan when the second plan row failed, and left an empty open session
when the initial history read failed. Both now leave no new session or plan.
Adding a movement during a workout also prepares its history/state before saving
the plan row, so a history-read failure no longer saves an invisible movement
that could reappear after recovery or be duplicated on retry.

All four regression tests were run against the original implementation and
failed for the expected behaviors, then passed against the changed sources.
No production instrumentation remains.

Acceptance: atomic startup rollback, no durable state after preparation failure,
one startup write transaction, preserved plan ordering/counts, no persisted
movement after failed add preparation, and passing existing recovery/logging tests.
Verification: `make check` passed (90 Swift files, 171 Core tests, 50 Store tests,
and the query-plan gate). Project regeneration remains byte-identical.

## Verified prior-performance milestone — 2026-11-07

The shared 500-row snapshot window is removed. `LoggerStore` discovers equipment
IDs for each requested exercise, selects the newest working-set session per
equipment key, loads that whole session, and separately selects its all-time
heaviest working set. The excluded live session is filtered in SQL in every
selection. All queries run inside one database read transaction, and the result
remains an immutable snapshot with no database handle.

This uses one identifier query per exercise plus three queries per equipment
key, instead of decoding a shared recent sample. It decodes only the latest
session's sets and one benchmark row per key, without truncating either less-used
equipment or unusually large sessions. Identifier discovery still visits the
requested exercise's indexed history; this is not a claim of constant-time
loading for arbitrary history size. Duplicate requested exercises are deduplicated.
`asOf` remains the capture timestamp rather than a historical cutoff. The unused
public `rowLimit` parameter is removed because it cannot express complete history.

`v3_historyBenchmarks` adds a non-unique partial index for working-set benchmark
ordering. A native test captures the actual StructuredQueries-generated benchmark
SQL and verifies that it uses this index without a temporary sort. The separate
100,000-set SQL microbenchmark measured 0.375 ms before the loading indexes versus
0.003 ms after for that single selection. This does not measure the complete
snapshot operation or iPhone session-start latency.

Other-machine fallback now selects by the latest session's performance date,
rather than the date of the machine's heaviest set, using a linear selection
with stable machine-ID tie-breaking. Exact machine matches still take precedence.
The existing other-machine assumption flag is preserved; provenance/prefill
policy improvements remain separate work.

Five Store regressions failed against the original loader: starvation across
exercises, starvation across machines, truncated latest sessions, missing older
bests, and live-session exclusion consuming the row budget. All pass now, along
with existing warm-up/machine-separation tests. A Core regression also reproduced
and fixed the fallback recency error. Upgrade/reopen tests cover both current v1
and v2 databases; they do not cover the historically different v1 schemas.

Acceptance: complete latest-session sets and all-time heaviest sets per equipment,
SQL exclusion before selection, preserved warm-up/machine separation, indexed
benchmark reads, correct fallback recency, and passing upgrade/reopen checks.
`make check` passed: 90 Swift files parsed, 172 Core tests, 56 Store tests across
five local suites, and six large-fixture query-plan checks. Project/scheme
regeneration is byte-identical. SwiftUI, CloudKit, AlarmKit and device performance
remain outside these Linux checks.

## Verified record-detection milestone — 2026-11-07

Logging no longer uses the most recent 1,000 sets as an all-time record source.
Within the set's write transaction, Store selects at most fourteen actual
comparison sets: the heaviest working set, the most reps within the candidate
load tolerance, and the heaviest eligible load at each of the twelve estimable
rep counts. For a fixed rep count the estimate is monotonic in load, so these
representatives preserve all three comparisons made by the existing Core
detector. The estimate formula and eligibility constants remain in Core.

The load-tolerance predicate is shared with Core. The SQL weight interval is
widened by one representable value before applying the exact absolute-difference
predicate, preserving floating-point behavior at the tolerance boundary.
`v4_recordComparisons` adds a non-unique partial index for rep/load point queries;
v1 through v3 remain intact. Warm-ups skip record reads, and empty history stops
after the initial benchmark probe. Set-ordinal assignment now reads one SQL
maximum instead of decoding all earlier sets in the exercise.

Comparison reads occur before insertion under the same write transaction, so
another writer cannot insert a competing benchmark between comparison and save.
The coordinator publishes returned claims only after commit, and clears old
claims on each log attempt. A failed save leaves no checkmark or new rest timer.
A comparison decoding error suppresses claims and still attempts the set save;
an unreadable old date was tested while a new valid set saved successfully.
`completedSets` remains a bounded browsing API and is no longer called by the
production record-detection path.

Tests reproduced false heaviest-load, reps-at-load, and estimated-max claims
when their real benchmarks predated a thousand newer sets. They now pass.
A separate failed-save test reproduced a stale prior celebration and now passes.
Differential tests compare compact selection with complete-history detection
across 65 sequential candidates, including tolerance boundaries, zero load,
eligible/ineligible rep counts, and estimate weight boundaries. The test requires
genuine records in all three categories rather than accepting only empty results.
SQL tracing verifies comparison reads share the save transaction, and native
query-plan checks verify all twelve emitted rep queries use the new index without
sorting history.

`make check` passed: 90 Swift files parsed, 172 Core tests, 62 Store tests across
five local suites, and seven query-plan checks. A supplemental run adding the
existing `RecordDetectionTests.swift` passed 72 Store tests across six suites;
that file remains outside the installed checker's default five-suite list.
Upgrade/reopen tests pass from current v1, v2, and v3 databases. Project/scheme
regeneration is byte-identical. The single best-at-reps SQL query measured
0.241 ms before loading indexes versus 0.003 ms after in the 100,000-set fixture;
this does not measure total logging latency or device performance.

## Verified local-write validation milestone — 2026-11-07

Store now validates local commands inside their write transactions. Adding plan
rows, changing equipment, and logging sets require an existing open session and
existing references. Supplied set-plan IDs must match the workout, movement, and
equipment being logged. Equipment must belong to the workout's gym when that gym
is known. Older sessions without a recorded gym retain their machine provenance.
Archiving remains a picker visibility policy; existing archived references are
not invalidated by these existence/context checks.

Machine changes accept expected session/exercise IDs, which the coordinator
passes so a plan row reparented by another writer cannot change a different
workout. Deleted, reparented, or ignored updates leave the coordinator's exercise
state unchanged. Rejected set writes leave drafts unlogged, record claims empty,
and rest timers unstarted. Every session/plan/set insert and equipment/finish
update checks that exactly one row was affected, preventing success after a
`RAISE(IGNORE)` operation. A skipped row inside initial plan creation rolls back
the entire workout.

Validation uses primary-key lookups before record-history queries. Session
validation projects only gym ID and the open/closed flag, avoiding session notes
and timestamp decoding on each logged set. Exercise and machine validation also
project only the identifiers needed. Startup deduplicates exercise/machine
references before validation. This adds bounded validation work; total device
logging latency remains unmeasured.

Seventeen baseline scenarios reproduced accepted invalid writes or successful
no-op commands before the change, then passed with typed error expectations.
Additional coordinator tests cover a workout closed elsewhere and plan rows
deleted, moved to another session/exercise, changed to different equipment, or
subject to ignored updates. Missing-reference tests verify explicit errors with
no partial rows. Existing machine/gym suites preserve valid machine transitions,
recovery, and equipment history for sessions with no recorded gym.

`make check` passed: 90 Swift files, 172 Core tests, 70 Store tests in five local
suites, and seven query-plan checks. The expanded Store run adding record,
machine-change, machine-state, gym-selection, gym-store, and divergence test files
passed 120 tests across twelve suites. Project/scheme regeneration matched the
committed files. No synchronized schema or migration changed. These local command
checks do not define conflict resolution between devices that logged/finished
independently while offline; native sync/device validation remains outstanding.

## Verified next-set provenance milestone — 2026-11-07

The normal live machine-switch guard already existed. Recovery bypassed it:
the Store-to-Core adapter omitted each logged set's machine ID, and Core assigned
nil IDs to the currently selected machine. This could make a 100 kg set performed
elsewhere become the next suggestion on equipment whose actual history was
30 kg. The adapter now forwards each saved machine ID and completion timestamp,
and Core preserves nil equipment IDs without assigning another machine.

Each exercise state captures its most recently saved working-set values per
progression key. Initialization, ordered recovery, and successful log events own
that data; warm-ups do not replace it. Appending a set reads that key directly
when available, so it follows save order even when rows were logged out of
display order. Later draft changes cannot rewrite the captured prefill values.
Repeated log callbacks leave the saved set ID/equipment unchanged, and the
equipment setter is confined to the Core file. Future successful edit/undo
commands must explicitly refresh this captured data.

The coordinator captures the completion instant once and uses it for both the
Store write and Core's saved-value record. Recovery forwards the stored instant.
Direct legacy Core callers retain the old epoch default when no timestamp is
supplied; the app's Store path always supplies its saved timestamp. Recovery
ordering uses ordinal, completion time, and set ID, formatting UUIDs only for
ties. No additional database queries or migrations were introduced.

Regression tests were run against original sources and reproduced nil-ID
reassignment, wrong post-recovery machine suggestions, display-order prefill,
repeated-callback relabelling, draft edits changing next-set values, and lost
completion timestamps. Tests now preserve both nil and named equipment through
live/recovered flows, save order, working-set values, warm-up exclusion, and
returning to earlier equipment. Existing labelled other-machine history borrowing
and history-based remaining planned rows retain their behavior.

`make check` passed: 90 Swift files, 177 Core tests, 72 Store tests across five
local suites, and seven query-plan checks. The expanded Store run passed 122
tests across twelve suites. Project/scheme regeneration remained identical.
The direct lookup removes reverse row searching from the common append path;
no device latency or frame-time improvement has been measured.

## Verified legacy-schema repair milestone — 2026-11-07

Git history confirms that `33c1038` added `exercises.curatedName` and
`loggedSets.sessionExerciseID` by editing v1 after the original schema in
`c1677fb`. Databases already marked v1 skipped those additions. The default
debug migrator then erased historical databases when it detected that difference;
release-style migration left the missing columns unrepaired.

Automatic schema erasure is disabled in all configurations. The new additive
`v5_legacyV1Columns` migration checks each column independently and adds only
what is missing. Earlier migration bodies are unchanged. Existing values,
indexes, table identities, and foreign keys remain intact. Old sets keep a null
plan-row hint when none was recorded; the migration does not guess their block.
If repair fails on an unsupported schema, its DDL rolls back and unrelated
records remain present.

An empty previous catalogue name now means unknown provenance. Seeding preserves
nonempty stored names in that case while updating catalogue-owned metadata.
Names with known provenance still receive normal three-way rename handling.
This conservatively preserves older names that cannot be distinguished from
user edits, including untracked historical catalogue spellings.

The frozen fixture embeds all thirteen original SQL statements independently
of current migrations, with comments/indentation removed. Its SHA256 is
`b681497419b5997112503cb59f121c573a248d5c4b3b9e2e3dad26af13f8680c`;
a source comparison against the historical commit confirmed the match. Sixteen
file-backed variants cover neither/either/both columns present, v1/v4 migration
markers, and default/release-style policy. Tests compare every original value
across all ten application tables, close/reopen and migrate again, read history,
resume the actual workout coordinator, log a new linked set, check foreign keys, and seed twice without losing names,
notes, or archives. Failed-repair rollback and erasure-policy tests also pass.

`make check` passed: 90 Swift files, 177 Core tests, 76 Store tests across five
local suites, and seven query-plan checks. Project/scheme regeneration matched.
Release verification also passed 177 Core tests and 154 Store tests across all
fourteen portable Store test files (sixteen suites). These are Linux package
builds; CloudKit, AlarmKit, SwiftUI, app/widget compilation, and device behavior
remain outside this verification.
The SQL microbenchmark mirrors conditional column-add guards on its fresh
fixture; native migrator tests establish the actual upgrade behavior.
Disabling debug erasure also removes GRDB's temporary schema-reconstruction
database from normal debug migration checks. App launch timing and native
CloudKit-backed upgrades still require device/Apple-platform verification.

## Verified recovery-snapshot milestone — 2026-11-07

Recovery previously read the open session, plan metadata, logged sets, and prior
performance through four independent database read transactions. A deterministic
two-connection WAL test committed a movement/load/history change after plan
metadata was fetched. The old loader then combined movement A's plan with the
new 900 kg set and 200 kg history, describing neither committed database version.

`LoggerStore.recoverySnapshot` now gathers all recovery inputs inside one
`database.read` closure. Connection-scoped helpers share the existing query
implementations with the public read APIs, avoiding nested or reentrant writer
reads. The connection remains inside the closure; the coordinator receives an
immutable, Sendable value bundle and constructs its state after the read ends.
No query limits, reconstruction rules, public read APIs, or migrations changed.

The regression test now returns the coherent earlier version: movement A,
100 kg logged, and 80 kg history. Its independent writer demonstrably commits
during the load, and the next recovery sees the complete newer version:
movement B, 900 kg logged, and 300 kg history. A trace test measures one read
transaction instead of four. Both tests were run against the original loader
and failed for the expected interleaving/transaction-count defects, then passed.

This provides consistency at the read snapshot. It does not freeze the database
after returning or silently replace drafts when a later write arrives; local
write-context validation still protects subsequent saves. It reduces transaction
and queue-entry overhead without adding database queries. Device loading latency
has not been measured.

`make check` passed: 90 Swift files, 177 Core tests, 78 Store tests in five local
suites, and seven query-plan checks. Expanded Release Store verification passed
156 tests in sixteen suites (all fourteen portable test files). Project/scheme
regeneration remained identical. CloudKit-backed interleavings, native app/widget
builds, and actual iPhone loading behavior remain outside these Linux checks.

## Open-workout lookup without scanning completed history

Launch/recovery asks for the newest session with `finishedAt IS NULL`. The old
`startedAt` index satisfied ordering but scanned completed workouts to establish
that none was open. The regression fixture now includes 5,000 finished sessions
and explicitly checks this expected-empty result. Before the fix, the plan gate
failed with `SCAN sessions USING INDEX sessions_on_startedAt`.

Additive migration `v6_openSessionLookup` creates the non-unique partial index
`sessions_on_openStartedAt` on `(finishedAt, startedAt DESC)` for rows where
`finishedAt IS NULL`. SQLite can search the null key and return the newest open
row without sorting. Finished sessions occupy no entries in this index; earlier
migrations and workout rows remain unchanged. Index creation still examines the
existing sessions once during migration, so this does not eliminate upgrade cost.

On the deterministic local fixture, the median of five warm absent-workout reads
changed from 0.481 ms to 0.001 ms, with a `SEARCH` plan. This measures the SQLite
lookup only, not app launch or iPhone latency. The native Store regression traces
and explains the actual generated query and checks newest-open selection,
finishing to reveal an older open workout, no-open results, and a subsequent new
workout. Against the original schema, all four query-plan checks failed while
functional assertions passed; with the migration, all pass. Upgrade tests now
cover v1 through v5 and verify row preservation and non-unique indexes.

`make check` passed: 90 Swift files, 177 Core tests, 79 Store tests in five local
suites, and eight query-plan cases. Expanded Release Store verification passed
157 tests in sixteen suites (all fourteen portable test files). Project/scheme
regeneration was identical.

## Consistent volume reports — 2026-11-07

`VolumeStore.report` previously loaded date-window sets and current exercise
attribution in separate read transactions. A deterministic test with two real
SQLite WAL connections now reproduces the consequence: an independent writer
moves four bench sets outside the window and archives the exercise between the
two reads. The old report showed four unattributed sets, although the complete
older version contained four attributed chest sets and the newer version had
zero sets in the window. Both the report-equality test and a transaction trace
failed before the fix (two reads instead of one).

The report now reads both inputs inside one `database.read` closure using
connection-scoped helpers shared with the existing public input APIs. It builds
the attribution index and computes volume after the read ends. The original SQL,
date boundaries, warm-up handling, and archived/unreadable-attribution policies
are preserved. The regression returns the coherent older report while the writer
commits; its next load sees zero sets, proving the update was actually applied.
There are no sleeps, mocked writer behavior, additional queries, or migrations.

This removes one transaction/queue entry and prevents mixed reports. It does not
measure main-thread responsiveness or phone loading latency; `WeeklyVolumeScreen`
still calls this synchronous API from its load handler. Scheduling and cancellation
need their own measured follow-up. Snapshot consistency also does not freeze data
after the method returns or make attribution historical: later loads still use
current stored attribution.

Verification: `make check` passed (90 Swift files, 177 Core tests, 79 Store tests,
eight query-plan cases). The default Linux Store selection omits VolumeStoreTests,
so these regressions were run explicitly: 90 tests in six suites passed in Debug,
then all fourteen portable Store files passed in Release (159 tests, sixteen
suites). Project/scheme regeneration remained identical. Native app/widget and
CloudKit execution, plus physical-device loading/frame measurements, are pending.

## Consistent progression history — 2026-11-07

`ProgressionStore.history` previously read working sets and machine names in
separate transactions. A test with two file-backed SQLite WAL connections
reproduces an atomic edit of a 100 kg set and its machine name: the old loader
returned 100 kg under the new name although the committed newer version contained
200 kg. The original history-equality check and transaction-count check both
failed; the free-weight variant already used only one transaction.

The loader now fetches samples and names within one read snapshot, using shared
connection-scoped helpers for its existing public input APIs. Machine IDs are
deduplicated from the samples; free-weight/empty history skips the names query.
Chart grouping and machine-change analysis remain outside the read closure. The
SQL filtering/order, 2,000-set limit, per-machine grouping and label fallbacks
remain unchanged. This prevents mixed snapshots and removes one transaction/queue
entry for machine history without adding queries. It does not establish phone
latency or fix the separately tracked chart-limit/tie-order issues.

The regression verifies the independent writer actually committed, the current
load matches the complete earlier history, and a later load sees both the new
200 kg load and renamed station. It uses no sleeps or mocked database writes.
`make check` passed: 90 Swift files, 177 Core tests, 81 Store tests in five suites,
and eight query-plan cases. Expanded Release Store passed all fourteen portable
test files (161 tests in sixteen suites). Project/scheme regeneration remained
identical. Native builds, CloudKit execution and device timings remain pending.

## Suspend screen database waits — 2026-11-07

History, progression, and weekly-volume screens called synchronous Store APIs from
MainActor `.task` and refresh handlers. A portable runtime probe schedules a
MainActor job from a real GRDB query callback. With the synchronous path, that job
cannot execute until the database wait ends; all three cases failed the
availability assertion. This measures executor availability, not iPhone frame
latency. The test uses a bounded semaphore wait only inside the synthetic probe;
production code contains no semaphore or detached task.

The three stores now offer explicitly named async loading APIs backed by GRDB's
cancellable async `read`, sharing the existing connection helpers. Each complete
load still uses one read snapshot and returns the same values as its synchronous
reference. Public stores have compiler-checked Sendable conformance through their
DatabaseWriter field. No unchecked annotations, new dependencies or migrations.
The caller suspends for database work under the project's Swift 6.2 isolation
settings; adding `async` alone to the old synchronous body would not provide this.
Volume/progression analysis after the read still runs on the caller's actor; its
CPU cost needs profiling before a separate executor change.

A shared MainActor `@Observable SnapshotLoader` owns screen results and cancels a
previous read when a newer request begins. It propagates caller cancellation to
the active task, drops stale successes/errors, silently preserves visible content
on cancellation, and surfaces actual failures with the existing retry flow. The
three screens await it from appearance and refresh tasks. History rows are mapped
once per successful load. Initial reads show the native progress indicator before
empty/data content; refresh preserves readable content. No custom animation was
added, so reduced-motion behavior is unchanged. `DESIGN.md` records the existing
tokens and these states because no design document previously existed.

The main-actor availability probe passes on the async path. Tests also verify
async/sync result equality and read counts, already-canceled loads issue no SELECT,
active-query cancellation leaves the connection usable, old successes/failures
cannot replace newer content, and cancellation reaches an operation even when it
ignores cancellation until it returns. Failure/retry and silent CancellationError
behavior are covered. Tests use continuations for overlap control, without sleeps.

Final verification: `make check` passed (92 Swift files, 177 Core tests, 81 default
Store tests and eight query-plan cases). Explicit Debug with SnapshotLoadingTests
passed 87 tests in six suites. Expanded Release Store passed all fifteen portable
test files (167 tests in seventeen suites). Project/scheme regeneration was
identical. The default Linux test selection omits SnapshotLoadingTests, so the
expanded run is required to execute these regressions.

SwiftUI source is syntax-checked on Linux, not compiled or rendered with an Apple
SDK. Native navigation, keyboard/VoiceOver, refresh and dismissal behavior,
responsive appearance, and mid-range-device frame/load measurements remain
unverified. Synchronous app initialization, catalog/recovery and picker paths are
separate remaining loading work; this milestone does not establish launch time.

## App-owned startup resources — 2026-11-07

`HardsetApp.init` opened and migrated SQLite synchronously. Its failure path used
`assertionFailure` and continued without installing the intended default database;
SQLiteData's unconfigured dependency supplies a blank in-memory writer. The app's
actual data APIs already accept explicit writers. A separate RootView task owned
the sync engine and constructed it on each execution, even though the engine's
SQL functions must remain alive for the lifetime of its writer.

`AppStartup<Resources>` now owns one preparation attempt and the successful
resource set at the App level, shared across scenes. Blocking preparation runs on
a dedicated serial queue, with captured dependency context restored there so
preview/test context does not silently change. The app explicitly passes the
prepared writer to its feature environment. `HardsetDatabase.prepareForLaunch`
bundles that writer with its retained SyncEngine, including the existing mandatory
account delegate. The bundle is published only after opening, migrations and
engine construction all succeed. This waits for local resource construction,
not CloudKit network synchronization.

Concurrent start callers share one in-flight task; disappearing/canceled scene
callers do not cancel this process-owned work. A completed resource set cannot be
replaced by another appearance or retry. Failure exposes no resources, stores the
error, and permits another attempt only through explicit retry. Attempt IDs keep
older waiters from disturbing a newer attempt. The app shows native progress or
an explicit retry state before the workout UI, using existing tokens/components
and a native button with the minimum target inside its label. There is no custom
motion; reduced-motion behavior stays immediate. No database is erased or replaced
as a fallback. Sync construction failure now gates the workout UI instead of
asserting and proceeding with potentially incomplete engine setup.

The portable baseline ran the actual migrator from MainActor and failed the
availability probe: a job queued to MainActor could not run while migration
waited. The same migration through AppStartup passes. Tests also cover shared
startup with canceled callers, failure/no-resource/explicit retry behavior,
resource identity and lifetime, and preservation of preview dependencies across
the queue boundary. These validate controller behavior and real SQLite migration,
not Apple sync construction or measured phone launch latency.

Verification: final `make check` passed (94 Swift files, 177 Core tests, 81 default
Store tests, eight query-plan cases). Explicit Debug with AppStartupTests passed
86 tests in six suites. Expanded Release Store passed all sixteen portable files
(172 tests in eighteen suites). Project/scheme regeneration was identical. The
installed default Linux selection omits the new tests, so use the expanded run to
execute them.

The app and Database.swift wiring require a native build and CloudKit integration
run; Linux syntax checks do not compile those files against Apple frameworks.
Permission/entitlement failures, failure injection after partial SyncEngine setup,
scene restoration and actual engine/function lifetime must be verified there.
Synchronous catalog seeding, workout recovery and gym loading after this gate
remain subsequent work. First useful-screen timing still requires Release iPhone
measurements, including migration cost for multi-year databases.

## Root preparation and recovery gate — 2026-11-07

The root's appearance task synchronously seeded the catalog, swallowed recovery
errors with `try?`, and synchronously loaded gym options. In the portable
reproduction of that exact call pattern, an unreadable plan table made recovery
look empty, so the new-start path inserted a second session over an existing
unfinished workout. A real catalog query also blocked a queued MainActor job in
the availability probe. Both assertions failed before the change. This reproduces
the Store call sequence; it is not a native SwiftUI interaction test.

`WorkoutRootModel` now owns readiness, recovered coordinator, gym options and
selection. It awaits GRDB's async seed write, one complete recovery read, and one
combined gym-options/preselection read. Connection helpers and recovery-state
construction are shared with the synchronous APIs; catalog merge, machine
provenance, session exclusion and date semantics are preserved. Database waits
release MainActor; building actor-owned workout state remains on MainActor and
still needs CPU profiling on device.

The UI exposes progress or retry before offering the tabs. Failed required input
loads publish no partial root and cannot be bypassed by calling `startWorkout`:
the model enforces readiness and refuses another workout while it owns a live
coordinator. Retry can recover the same saved session. Only a finished coordinator
can be cleared; later appearances do not replay old recovery or discard drafts.
Initial preparation is model-owned and shared among appearance callers. Canceling
one caller does not cancel that job underneath another appearance. This differs
intentionally from refreshable report snapshots, where superseded reads cancel.
The job handle is released on completion, including failure.

The probe measures three initial transactions (one seed write and two reads),
with no additional reads/writes on another appearance. Tests cover catalog,
recovery and gym-read failures; retry; logged-set and gym recovery; canceled
callers; duplicate appearances; refusing premature/new duplicate starts; finishing
and starting a later workout. The gym list and last-used preselection now share a
single read snapshot. Initial root errors use existing components and tokens;
there is no custom motion. A successful gym save followed by a failed refresh is
reported as a saved gym with a read failure rather than an unsuccessful write.

Verification: `make check` passed (96 Swift files, 177 Core tests, 81 default
Store tests and eight query-plan cases). Explicit Debug with WorkoutRootModelTests
passed 86 tests in six suites. Expanded Release Store passed all seventeen
portable files (177 tests in nineteen suites). Project/scheme regeneration remained
identical. The installed default selection omits this new test file, so the
expanded run is required to execute its regressions.

Readiness is point-in-time. It does not exclude a different writer/device starting
a workout after this load, or solve the separately tracked missing-plan recovery
and retry-identity issues. User-initiated gym writes and follow-up refresh still
use synchronous APIs. Native root rendering, focus/VoiceOver, background/foreground
and scene transitions, plus iPhone load/frame measurements, remain unverified.

## Root integration with the current UI — 2026-11-08

Remote main advanced during the interrupted session. The push guard rejected the
old-base root commit, and the feature branch merged main8422cd3 without rewriting
remote history. The merged RootView retains the current cyan design system,
settings, workout headers/accessory, and last-workout card. Loading/retry uses the
existing HardsetLoadingState and HardsetEmptyState action. The optional last-workout
card now loads asynchronously through SnapshotLoader, retaining its absent-on-error
policy and rejecting stale overlapping refreshes.

CI run [42429147943](https://github.com/FrankieBiz/hardset/actions/runs/42429147943)
passed for code commit924dd1f: macOS HardsetKit build, unsigned iOS Simulator app
and widget build, and14 screen-render tests. Root-start light/dark artifacts were
inspected: both reach loaded Metroflex Gym data and the expected two-set last-workout
card. This proves the fixture reaches loaded UI; the renderer's800ms settling delay
is not a device latency benchmark. Liquid Glass/tab-bar appearance remains limited
by the renderer, as recorded in MAC-VERIFICATION.md.

After integration, make check passed98 syntax files,179 Core tests/23 suites,
81 default Store tests/5 suites,8 query cases and172 palette contrast pairs.
Expanded Release Store passed177 tests/19 suites across17 portable files; Release
Core passed179 tests/23 suites. Project/scheme regeneration stayed identical.
Native signed entitlements, real account transitions, UI interaction/accessibility
and physical-device cold/warm loading/frame measurements still need validation.

Read-only follow-up measurements found that an unchanged catalog seed still issues
50 UPDATE statements (five warm host runs about18–21ms, without CloudKit triggers).
An absent last-used-gym query scans50,000 nil-gym sessions (about4.4ms in SQLite);
a scratch partial covering index avoids that history traversal. These are measured
next targets, not changes in the root-model code. AppSmokeTests also still references
the obsolete private RootView() initializer and is outside the native workflow's
selected screenshot suite; it must be repaired and executed separately.

## Skip unchanged catalogue updates — 2026-11-08

An unchanged launch previously executed50 exercise UPDATEs. A regression installs
an SQLite row-update audit trigger after seeding and editing user-owned fields;
it reproduced50 updates through both synchronous seed and async loadCatalog.
The loader now compares all catalogue-owned fields and the existing three-way
merged name inside its write transaction, skipping UPDATE when they match.
Both paths now record zero updates. No catalog-version flag or persistent cache
can hide later changes or missing rows. Notes, archive state and creation time
remain untouched, and user renames retain the existing conditional assignment.

Seven parameterized correction cases cover every compared field, including the
curated-name merge. Expanded Release Store passes179 tests in19 suites across17
portable files. make check passes98 syntax files,179 Core tests/23 suites,
81 default Store tests/5 suites,8 query cases and172 contrast pairs. These new
catalog regressions are outside the installed checker's default Store selection.

A temporary Release probe ran ten warm loads against the actual CatalogSeeder
and migrator in an in-memory DatabaseQueue, with identical pinned dependencies.
Baseline commit7acda12 ranged7.58–9.62ms; changed code ranged7.55–8.21ms on Linux.
The ranges overlap; this is modest host evidence, not an iPhone launch-time claim.
The probe had no CloudKit tracking triggers and is outside the repository. Logs
are catalog-benchmark-before.log and catalog-benchmark-after.log in the local
hardset-check cache. The regression's audit trigger separately proves50 updates
become zero; it does not measure network or CloudKit traffic.

Native feature verification is run42431360543 for commitc0f9bc4 and remains pending
at this entry. App smoke-target repair is separately under run42431117598. Main's
root-loading integration passed repeat native run42430194445. The user selected
Linux and simulator CI for now; signed account/device checks remain pending.

## Remaining app-wide work

- Capture Release cold/warm launch, first usable workout, resume, picker, history,
  progression, and volume timings on iPhone, with small and multi-year databases.
  Record median/tail latency, main-thread hangs, memory, and device/OS/build details
  before setting defensible loading budgets.
- Audit remaining synchronous picker and user-initiated gym loading, and post-read
  analysis on the main actor. Profile before moving additional CPU work, preserve
  cancellation and consistent snapshot semantics, and validate the new startup
  owner with Apple frameworks and real scene/account transitions.
- Measure first-launch index creation and ongoing set-write/storage overhead.
- Address progression-chart row limits/order, machine provenance,
  and retry/concurrent-command identity from
  `CORE_STORE_ARCHITECTURE_REVIEW.md`; do not trade correctness for smaller reads.
- Verify repaired historical schemas with native CloudKit metadatabases, sync
  triggers, account transitions, and the full app launch/recovery flow.
- Complete native app/widget compilation and physical-device checks, including
  restoration, rest reconciliation, sync ownership, and accessibility behavior.

The goal remains active until app-wide behavior and performance have direct
runtime evidence. Microbenchmark gains must not be described as launch-time gains.
