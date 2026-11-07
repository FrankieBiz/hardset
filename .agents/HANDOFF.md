# Core and Store review handoff

- Date: 2026-10-24
- Maintainer: FrankieBiz <frankabisignano@gmail.com>
- Branch: `FrankieBiz/apex-orchestration-workspace-setup`
- Review baseline: `b5b93df`
- Deliverable: `docs/CORE_STORE_ARCHITECTURE_REVIEW.md`

## Current state

The requested architectural review is documented. No production Swift source or tests were changed. Implementation findings remain open; this task does not authorize treating the review as implemented.

## Settled decisions

- Preserve GRDB/SQLiteData, private CloudKit replication, Foundation-only nonisolated Core, and all three invariants in `CODEX.md`.
- Preserve the explicit account-change delegate and persist-before-claim ordering.
- Use the actual implementation and `DEVICE-CHECKLIST.md` over stale root handoff claims: machine selection/history are wired and a prior simulator build is recorded. Physical-device/real-account verification remains outstanding.
- Competitor documentation does not support labeling every competitor cloud-first. Hevy explicitly recommends duplicate exercises to separate physical-machine history.

## Evidence and next work

- Linux `make check` passed: syntax for 86 Swift files, 162 Core tests, 45 tests in five Store suites. The gate excludes CloudKit wiring and 13 other Store test files.
- A temporary Swift 6 executable reproduced cross-machine next-set prefill, mixed-machine change analysis, and infinite draft load acceptance.
- Project generation succeeded but differs from the committed project in HardsetFeature product IDs/order. The generated file was restored to baseline after inspection; reproducibility drift remains a review finding.
- Prioritize upgrade safety (`v1` was edited in place), stable sync ownership/account gating, durable rest reconciliation, machine provenance, and complete history queries. See the review for source names, examples, and acceptance checks.
- No failed implementation approaches were attempted. No architectural fixes are included in the review commit.

## UI token audit follow-up — 2026-10-24

- Maintainer: FrankieBiz <frankabisignano@gmail.com>.
- Baseline: `0542a22`; deliverable: `docs/UI_TOKEN_ACCESSIBILITY_AUDIT.md`.
- Scope: source-based color/typography/geometry audit and concrete upgrade specification. Production Swift and tests remain unchanged; recommendations are not implemented.
- Exact sRGB calculations find the current accent below 7:1 on every normal background/surface pair. Seven proposed foreground roles exceed 7:1 on both surfaces in each appearance; proposed borders exceed 3:1.
- Keep the normal background/surface values and 44pt/56pt product policy. Apple's current HIG lists 44pt as the iOS default and 28pt as its minimum; the source comment needs correction when tokens are implemented.
- Fix keypad adjusters (36pt), the 380pt minimum content inside a 370pt sheet, targets applied outside button labels, and narrow set/rest layouts together with larger typography. Raising adjusters to 56pt increases minimum keypad content to 400pt before Dynamic Type.
- Add explicit semantic foreground/fill roles and increased-contrast resolution. Keep all changes within HardsetUI; preserve Core/Store and zero database work per render.
- Verification: `make check` passed with 86 Swift files parsed, 167 Core tests, and 45 Store tests across five local suites. CloudKit and native UI behavior are excluded. Contrast candidates were checked numerically; iOS resolved colors, actual hit regions, Dynamic Type layouts, and physical glare testing remain pending.
- Next work: implement the audit's prioritized recommendations as a separate task, with native UI verification. The earlier architectural review findings above remain open.

## App loading follow-up — 2026-11-07

- Objective remains active: improve code and loading throughout the entire app.
- Worktree: `/home/frankbiz/orca/workspaces/hardset/mojarra`; branch `FrankieBiz/mojarra`.
- Implemented `v2_loadingIndexes` without editing v1: date-range, exercise/date,
  exercise/machine/date, session/ordinal, and plan session/position indexes.
- Changed paths: `Migrations.swift`, `HistoryStoreTests.swift`, `Makefile`,
  `Tools/check_query_performance.py`, `docs/LOADING_PERFORMANCE.md`, this handoff.
- Verification: `make check` passed: 90 files parsed, 171 Core tests, 46 Store
  tests, and large-fixture query-plan/result gate. Native migrator upgrade/reopen
  test passed. Project generator produced identical project and scheme files.
- Evidence: 100,000-set fixture originally failed the plan gate for all five
  reads; all now use indexed searches without temporary sorting. Local volume
  read median improved 4.342 to 1.079 ms. These are warm in-memory SQLite results,
  not iPhone or launch measurements. See loading document for all measurements.
- Settled: keep immutable snapshots and machine keys; avoid caches that hide
  incomplete history. Retain existing v1 indexes until write/storage tradeoffs
  are measured. This does not fix historical v1-column upgrades/debug erasure.
- Next concrete step: profile synchronous feature loading and app initialization
  with Release device traces, and continue complete-history/record query fixes
  from the Core/Store review. Linux cannot verify SwiftUI/app/widget builds,
  CloudKit integration, AlarmKit, or physical-device performance.

## Atomic workout-start follow-up — 2026-11-07

- Same objective/worktree/branch as the loading follow-up above; goal stays active.
- `LoggerStore` now saves the session and its whole plan in one write transaction.
  `SessionCoordinator` prepares fallible history/increment reads before creating
  the session. Adding a movement likewise prepares history/state before its save.
- `PlannedExercise` explicitly opts out of default MainActor isolation so immutable
  plan values can be used on database queues; Swift 6 compilation passed.
- Owned changes: `LoggerStore.swift`, `SessionCoordinator.swift`,
  `SessionCoordinatorTests.swift`, loading document, this handoff.
- Four new tests cover partial-plan rollback, failed startup reads, failed add
  reads, and twelve-exercise transaction count/order. Original sources reproduced
  all four regressions, including thirteen transactions; changed sources use one.
- Verification: `make check` passed: 90 syntax checks, 171 Core tests, 50 Store
  tests, and query-plan gate. Project generator output remains identical.
- Test development: throwing fetch calls inside `#expect` in a database closure
  needed hoisting to local values. Baseline-log verification searched for a
  function name absent from test output; inspecting the actual assertion text
  confirmed the expected failures. Sources restored and full gate passed after it.
- Still pending: device measurements/native app compilation; complete and fair
  prior-performance/record queries; numeric/machine provenance correctness;
  recovery snapshot consistency; local-write validation; historical v1 upgrade
  safety; durable rest/sync ownership. Next independent code step: reproduce the
  global 500-row snapshot starvation and replace its incomplete history selection
  with complete latest-session data and complete record benchmarks.

## Complete prior-performance follow-up — 2026-11-07

- Objective/worktree/branch unchanged; full-app goal remains active.
- Replaced `priorPerformanceSnapshot`'s shared 500-row sample with per-exercise
  equipment discovery and complete latest-session sets/all-time heaviest sets per
  equipment key, all within one read transaction. Excludes the live session in SQL
  before every selection; preserves free-weight and machine histories/warm-up filtering.
- Removed the unused `rowLimit` argument; `asOf` remains a capture stamp. Snapshot
  holds no database handle and is still loaded only at explicit session events.
- Added `v3_historyBenchmarks`, a non-unique working-set partial index. Native test
  verifies the actual emitted benchmark SQL uses it without sorting. Large-fixture
  single-query measurement: 0.375 to 0.003 ms; no whole-snapshot/device speed claim.
- Fixed Core fallback recency to use latest-session timestamps rather than the
  all-time-best date; stable machine-ID ties and exact-key precedence preserved.
- Changed paths: Core `PriorPerformance.swift`; Store `LoggerStore.swift` and
  `Migrations.swift`; Core `LoggerInvariantTests.swift`; Store `LoggerStoreTests.swift`
  and `HistoryStoreTests.swift`; query benchmark; loading document; this handoff.
- Five Store semantic regressions were verified red against the original loader,
  then green after restoration. Core recency regression likewise verified red/green.
  Upgrade/reopen test now covers both current v1 and v2 schemas.
- Verification: `make check` passed: 90 files, 172 Core tests, 56 Store tests in
  five local suites, six query-plan checks. Project/scheme generation identical.
- Implementation trap: a multiline `guard let latest = query.order { ... }`
  parsed its trailing closure as a guard body. Hoist the query result into a local
  before `guard let latest`; that compiled and passed. No repeated blind attempts.
- Limits: equipment discovery still walks indexed exercise history; three queries
  per equipment key follow it. Device latency/memory and index-write/storage cost
  remain unmeasured. Native integration and historically edited-v1 upgrades unverified.
- Next code step: replace the coordinator's capped 1,000-row record-detection read
  with compact complete benchmarks (heaviest, reps-at-candidate-load, evaluable e1RM),
  preserving save-before-claim behavior and suppressing claims when history fails.
  Remaining broader work includes machine prefill provenance, recovery consistency,
  local-write validation, rest persistence/reconciliation, sync ownership, and native
  Release performance traces. See loading document and architectural review.

## Complete record comparisons follow-up — 2026-11-07

- Full-app objective stays active, same worktree/branch.
- Production logging no longer calls capped `completedSets`. Store's internal
  log overload selects at most 14 actual all-time comparison sets before insertion
  inside the same write transaction, then returns claims only after commit.
  The public SetID-only API delegates without collecting comparisons.
- Comparisons preserve heaviest weight, highest reps within Core's exact load
  tolerance, and best eligible weight at each estimable rep count. Core retains
  the formula/eligibility constants; shared tolerance prevents divergent filters.
- Added `v4_recordComparisons` with partial non-unique rep/load index; previous
  migrations unchanged. Scalar SQL MAX replaces the per-tap ordinal row array.
- Coordinator clears stale records on each log attempt. Failed saves cannot
  publish comparisons or start rest; a malformed historical date suppresses
  claims while the valid new set can still save.
- Owned paths: Core `PersonalRecords.swift`; Store `LoggerStore.swift`,
  `Migrations.swift`, `SessionCoordinator.swift`; Store tests `LoggerStoreTests`,
  `SessionCoordinatorTests`, `HistoryStoreTests`; query benchmark; loading doc;
  this handoff.
- Red/green: all three record kinds were falsely claimed beyond the 1,000-row cap;
  a failed save retained a stale previous celebration. Fixed and verified.
  Differential checks cover 65 candidates and require genuine records of every
  kind. Native SQL tracing verifies atomicity, warm-up read skipping, and all
  twelve indexed rep queries. Upgrade/reopen tests cover current v1/v2/v3.
- Verification: `make check` passed: 90 files, 172 Core tests, 62 Store tests in
  five local suites, seven SQL-plan checks. Project/scheme generation identical.
  Supplemental Store run including existing `RecordDetectionTests.swift` passed
  72 tests in six suites. Used `runpy.run_path` on installed
  `/home/frankbiz/.local/share/hardset-tooling/checks/hardset_check.py`, appended
  `('RecordDetectionTests.swift',)` in `test.__globals__['STORE_TESTS']`, and invoked
  `main()` with argv `['hardset-check', 'store']`. No installed tooling was edited.
- Test development: the initial emitted-SQL test filter assumed no parentheses
  around the reps column. Two runs (the second with a targeted fixture SQL trace)
  identified the real form `("loggedSets"."reps") = (12)`. Corrected the filter,
  removed `[DEBUG-record-sql]` instrumentation, and passed the full gate.
- Limits: native app/widget, CloudKit, AlarmKit, physical-device timing, whole-tap
  latency, index write/storage costs, and historically different v1 upgrades remain
  unverified. Single indexed rep query measured 0.241 -> 0.003 ms on Linux;
  do not present this as a total logging or launch latency improvement.
- Next concrete code work: validate local writes against closed/missing sessions,
  mismatched plan/exercise/machine references, and missing machine-update rows.
  Continue provenance/next-set prefill fixes, progression completeness, consistent
  recovery reads, durable rest reconciliation, sync ownership, and native profiling.

## Local-write validation follow-up — 2026-11-07

- Full-app goal remains active; same worktree and `FrankieBiz/mojarra` branch.
- Store rejects mutations of missing/closed workouts, missing exercise/gym/machine
  references, supplied set-plan IDs that mismatch session/exercise/equipment, and
  machines outside a known workout gym. Nil-gym legacy sessions retain equipment
  provenance; archives do not invalidate already-existing references.
- Equipment updates accept optional expected session/exercise IDs; coordinator
  supplies them to detect plan reparenting by another writer. Missing/reparented
  plan rows and ignored writes leave exercise state unchanged. Rejected logging
  leaves drafts unlogged with no record claims/rest requests.
- Every session/plan/set insert and equipment/finish update requires exactly one
  affected row, catching silent `RAISE(IGNORE)` operations. Atomic plan startup
  also rolls back when its second plan insert is ignored rather than thrown.
- Validation is inside existing write transactions before record queries. Session
  lookup selects only gym and `finishedAt IS NULL`; exercise/machine lookups select
  IDs. Avoid notes/date decoding per tap. Initial plan references are deduplicated.
- Owned paths: Store `LoggerStore.swift`, `SessionCoordinator.swift`; Store tests
  `LoggerStoreTests.swift`, `SessionCoordinatorTests.swift`; loading doc; handoff.
- Seventeen initial failure scenarios verified red against baseline, then green
  with typed errors. Added stale-coordinator and missing-reference checks and
  extended startup rollback injection to both ABORT and IGNORE. All pass.
- Final verification: `make check` passed: 90 Swift files, 172 Core tests, 70 Store
  tests in five local suites, seven query-plan checks. Project generation matched
  committed project/scheme. Expanded Store run passed 120 tests in twelve suites.
- Expanded run used the installed checker via `runpy.run_path` as in the previous
  handoff, adding `RecordDetectionTests.swift`, `MachineChangeTests.swift`,
  `MachineStatePersistenceTests.swift`, `GymSelectionTests.swift`, `GymStoreTests.swift`,
  and `SessionDivergenceTests.swift` to `test.__globals__['STORE_TESTS']`. No installed
  tooling edits. Its default printed scope still says five suites; actual Swift
  Testing output confirms twelve. Default `make check` still covers five.
- No failed implementation attempts. Review tightened session validation from
  full-row decoding to a minimal projection, followed by fresh full/expanded gates.
- No new schema constraints or migrations; replication's direct SQL remains
  tolerant. Offline multi-device logging/finish conflicts still need a policy.
- Remaining work: machine provenance and cross-machine next-set prefill, progression
  history limits, consistent recovery reads, numeric/import validation and command
  retry identity, historical v1 upgrades/debug erasure, durable rest and sync
  ownership, native app/widget builds, and Release iPhone loading/hitch measurements.
  Next concrete code step: reproduce the Core next-set prefill taking a logged
  load from machine A after switching to machine B, then preserve per-set machine
  provenance through live logging and recovery.

## Next-set provenance follow-up — 2026-11-07

- Full-app objective remains active; same worktree/branch.
- Actual baseline already guarded normal live appends by logged machine ID. Do
  not redo that fix. The broken path was recovery: coordinator omitted saved
  machine IDs, and Core's `logged.machineID ?? currentMachine` invented provenance.
- Recovery now forwards saved machine IDs/timestamps and preserves nil IDs. Core
  captures each equipment key's latest successfully saved working-set values,
  updated by initialization, ordered reconstruction, and successful mark events.
  Appends use that keyed value, respecting save order rather than display order.
  Warm-ups skip it; later draft edits cannot change the captured values.
- Duplicate mark callbacks preserve the saved ID/machine. `loggedMachineID` is
  publicly readable with a file-confined setter. Existing constructor access remains.
- Coordinator captures `now()` once per save and forwards the same timestamp to
  Store/Core. Recovery order has ordinal/time/ID tie-breaking, with UUID string
  formatting only for ties. No new SQL or migrations.
- Core's direct legacy call defaults still use the prior epoch timestamp when
  no instant is supplied; production Store paths pass the actual saved instant.
  Captured per-key values are session-local prefill data, never an all-time PR source.
  Future edit/undo persistence commands must refresh this data explicitly.
- Owned paths: Core `ExerciseLogState.swift`; Store `SessionCoordinator.swift`;
  Core tests `ExerciseLogStateTests.swift`/`ResumeTests.swift`; Store
  `SessionRecoveryTests.swift`; loading doc; handoff.
- Red/green verified against original Core/Coordinator sources: nil equipment
  reassignment, named/nil equipment drift after recovery, out-of-display-order
  saves, repeated mark relabelling, mutable draft prefill, and lost timestamps.
  Return-to-equipment/warm-up behavior also tested. Original sources temporarily
  restored only from snapshots of owned files; fixed sources restored in `finally`
  and full verification rerun. No failed implementation attempts.
- Verification: `make check` passed: 90 files, 177 Core tests, 72 Store tests in
  five suites, seven query-plan checks. Expanded run (same six extra test files
  as previous handoff) passed 122 Store tests in twelve suites. Project/scheme
  regeneration identical; diff whitespace check passed. Native app/device tests
  and actual loading/frame-time measurements remain unverified on Linux.
- Labelled other-machine borrowing policy and history-based remaining planned
  rows are unchanged. Default borrowing still needs the broader provenance/UX audit.
- Inspected current `ProgressionAnalyzer.machineChanges`: session/machine grouping
  is already implemented; older review wording about grouping only by session is
  stale. Ordering ties and same-session revisits still warrant explicit requirements
  and tests before changing its semantics.
- Next high-priority independent step: verify historical v1 schema fixtures and
  implement additive repair migrations without debug schema erasure. Remaining
  work includes progression limits/order, consistent recovery reads, numeric/import
  validation and command retry identity, durable rest/sync ownership, native
  app/widget compilation, and Release iPhone launch/loading/hitch measurements.

## Legacy-schema repair follow-up — 2026-11-07

- Full-app goal stays active, same worktree and `FrankieBiz/mojarra` branch.
- Verified historical diff: `33c1038` edited v1 to add `curatedName` and
  `sessionExerciseID`; original `c1677fb` databases already marked v1 missed both.
  Debug erasure discarded records; release-style upgrades left columns missing.
- Removed automatic erasure in all configurations. Added conditional additive
  `v5_legacyV1Columns`; prior migration bodies remain unchanged. Preserves existing
  column values, skips columns already present, and leaves old plan hints null.
- Seeder now preserves nonempty names with unknown previous-curated-name metadata.
  Known-provenance catalogue corrections still use normal three-way merging;
  unknown historical spellings are conservatively preserved along with user edits.
- Owned paths: Store `Migrations.swift`, `CatalogSeeder.swift`; Store
  `HistoryStoreTests.swift`; `Tools/check_query_performance.py`; loading doc; handoff.
- Frozen original SQL fixture embeds thirteen statements from `c1677fb`, independent
  of current migrations. Verified normalized SQL equality against git history;
  SHA256 `b681497419b5997112503cb59f121c573a248d5c4b3b9e2e3dad26af13f8680c`.
- Sixteen file-backed variants cover missing/either/both columns, v1/v4 markers,
  default/release-style policies. Compare every old value in all ten app tables,
  close/reopen/migrate again, read history, resume coordinator (load/equipment/step/
  plan count), log a new linked set, check FKs, and seed twice preserving names,
  notes, and archives. Unsupported missing-table repair rolls back its first
  column addition and migration marker while preserving unrelated rows.
- Baseline regressions verified: debug data loss, missing columns, and unknown-name
  clobbering. First baseline test run hit an unchecked array access after expected
  fixture erasure; replaced it with required-row assertions. Rerun reported the
  expected data-loss/missing-column/name failures cleanly; fixed code passed.
- Verification: `make check` passed (90 Swift files, 177 Core tests, 76 Store tests
  in five suites, seven query-plan checks). Release Core passed 177 tests;
  expanded Release Store passed 154 tests across sixteen suites. Project/scheme
  regeneration identical; frozen fixture comparison and whitespace checks passed.
- Release commands used the installed checker's `runpy` entry as before, wrapping
  `run_logged` to add `--configuration release` after `swift test` and write
  `core-release.log`/`store-release.log` in the existing workspace cache. Expanded
  Store adds prior six files plus `CatalogSeederTests.swift`, `CatalogRenameTests.swift`,
  `VolumeStoreTests.swift` (all fourteen portable test files). No installed tooling
  edits. Its fixed printed "five suites" scope is stale for expanded runs; actual
  Swift Testing output confirms sixteen. Initial Release dependency build took
  242 seconds; final incremental run 21 seconds. Logs are under
  `/home/frankbiz/.cache/hardset-check/workspaces/0cbdfb12da0f/`.
- SQL performance harness now mirrors conditional ADD COLUMN guards; actual native
  migrator tests remain the upgrade authority. No data-table rebuilds or resets.
- Remaining: native CloudKit-metadatabase/trigger upgrades, app/widget/AlarmKit/UI
  builds and behavior, actual iPhone loading/frame timings, async startup ownership,
  consistent recovery reads, progression limits/order, numeric/import validation,
  command retry identity, durable rest and sync ownership/account gating.
  Next independent code step: make recovery's session/plan/sets/history reads one
  consistent database snapshot and reproduce a concurrent-update interleaving.

## Consistent recovery snapshot follow-up — 2026-11-07

- Full-app objective remains active; same worktree/branch.
- Reproduced recovery using four read transactions and combining an old movement-A
  plan with a new 900 kg set and 200 kg prior history. Test uses two real SQLite
  connections in WAL mode; a profile callback commits a deterministic external
  update after plan-machine metadata is fetched. No sleeps or probabilistic race.
- Store now exposes an internal immutable `SessionRecoverySnapshot`, collecting
  session, plan metadata, sets, and prior performance in one database.read.
  Private connection-scoped helpers share logic with unchanged public read APIs.
  Coordinator builds state from the value bundle after the connection is released.
  Corrected stale nearby wording about grouping repeated exercise blocks.
- Concurrency regression now sees coherent A/100/80 despite the writer commit;
  the next load sees B/900/300. Explicit fired/error checks ensure writer execution;
  later-load assertions ensure no application cache hides it. Trace proves 4 -> 1
  read transactions. Both regressions verified red before implementation, then green.
- Owned paths: Store `LoggerStore.swift`, `SessionCoordinator.swift`; Store
  `SessionRecoveryTests.swift`; loading doc; handoff. No migrations or new queries.
- Verification: `make check` passed: 90 Swift files, 177 Core tests, 78 Store tests
  in five suites, seven query-plan checks. Expanded Release Store passed 156 tests
  in sixteen suites (same fourteen portable files/runpy release procedure as the
  previous handoff). Project/scheme regeneration identical; whitespace check clean.
- No failed implementation attempts. Do not nest database.read calls to compose
  recovery; use the connection helpers within the owning read closure.
- Snapshot consistency is point-in-time, not a lock against later updates or
  offline devices. Subsequent local writes still validate current context. No
  iPhone latency/CloudKit integration claim. Existing reconstruction behavior for
  missing/unassigned plan hints is unchanged and deserves a separate completeness audit.
- Remaining: async startup/engine ownership, partial/absent open-session lookup
  indexing, coherent multi-read volume/progression reports, progression limits/order,
  numeric/import validation, retry identity, durable rest and account/sync gating,
  native app/widget/CloudKit/AlarmKit checks, Release iPhone loading/hitch traces.
  Next concrete performance step: measure open-session lookup with years of
  completed sessions and no active workout; add an appropriate index if the query
  plan confirms it scans finished history. Also audit report reads for the same
  interleaving pattern now fixed in recovery.
