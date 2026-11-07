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

## Remaining app-wide work

- Capture Release cold/warm launch, first usable workout, resume, picker, history,
  progression, and volume timings on iPhone, with small and multi-year databases.
  Record median/tail latency, main-thread hangs, memory, and device/OS/build details
  before setting defensible loading budgets.
- Audit synchronous reads in feature `.task`/refresh handlers and database opening
  in `HardsetApp.init`; profile then move measured blocking work off the main actor
  with cancellation and consistent snapshot semantics.
- Measure first-launch index creation and ongoing set-write/storage overhead.
- Address progression-chart row limits/order, machine provenance, consistent
  consistent progression-history reads, and retry/concurrent-command identity from
  `CORE_STORE_ARCHITECTURE_REVIEW.md`; do not trade correctness for smaller reads.
- Verify repaired historical schemas with native CloudKit metadatabases, sync
  triggers, account transitions, and the full app launch/recovery flow.
- Complete native app/widget compilation and physical-device checks, including
  restoration, rest reconciliation, sync ownership, and accessibility behavior.

The goal remains active until app-wide behavior and performance have direct
runtime evidence. Microbenchmark gains must not be described as launch-time gains.
