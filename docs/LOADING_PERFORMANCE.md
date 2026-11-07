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
  machine provenance, and transaction boundaries from
  `CORE_STORE_ARCHITECTURE_REVIEW.md`; do not trade correctness for smaller reads.
- Verify earliest shipped v1 fixtures: this index migration does not repair
  historical edits to v1 columns or debug schema-erasure behavior identified in
  the architectural review.
- Complete native app/widget compilation and physical-device checks, including
  restoration, rest reconciliation, sync ownership, and accessibility behavior.

The goal remains active until app-wide behavior and performance have direct
runtime evidence. Microbenchmark gains must not be described as launch-time gains.
