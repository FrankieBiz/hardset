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

## Remaining app-wide work

- Capture Release cold/warm launch, first usable workout, resume, picker, history,
  progression, and volume timings on iPhone, with small and multi-year databases.
  Record median/tail latency, main-thread hangs, memory, and device/OS/build details
  before setting defensible loading budgets.
- Audit synchronous reads in feature `.task`/refresh handlers and database opening
  in `HardsetApp.init`; profile then move measured blocking work off the main actor
  with cancellation and consistent snapshot semantics.
- Measure first-launch index creation and ongoing set-write/storage overhead.
- Address complete prior-performance/record queries, global history row limits,
  machine provenance, consistent recovery reads, and write validation from
  `CORE_STORE_ARCHITECTURE_REVIEW.md`; do not trade correctness for smaller reads.
- Verify earliest shipped v1 fixtures: this index migration does not repair
  historical edits to v1 columns or debug schema-erasure behavior identified in
  the architectural review.
- Complete native app/widget compilation and physical-device checks, including
  restoration, rest reconciliation, sync ownership, and accessibility behavior.

The goal remains active until app-wide behavior and performance have direct
runtime evidence. Microbenchmark gains must not be described as launch-time gains.
