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

## UI design-system elevation follow-up — 2026-11-07

- Objective: perfect and elevate the entire UI so no screen reads as a stock Apple
  screen. Maintainer: FrankieBiz <frankabisignano@gmail.com>.
- Worktree: `/home/frankbiz/orca/workspaces/hardset/snapper`; branch
  `FrankieBiz/ui-elevation-overhaul`, rebased onto `origin/main` at `33d2b09`. Four
  commits: design system foundation, unit-aware machine-change notes (Core), accent
  and launch wiring (app target), and the screen-by-screen pass. Not pushed.
- Settled decisions (see `DESIGN.md`): "calibrated instrument" direction; readout-cyan
  accent `#00515E`/`#5ED3E6` replacing the asset blue; colour only for meaning; SF Pro
  Condensed tabular figures and SF Expanded screen titles (system fonts only, no
  resource bundle); every control has a fill or 3:1 border, tags never do; dashed
  outline means "nothing here yet"; one spring (the log stamp); Reduce Motion
  honoured everywhere. Tab roots draw their own `ScreenHeader` with the stock bar
  hidden (`hardsetTabRoot()`); sheets use `hardsetNavigationTitle(_:)`.
- Changed paths: all of `HardsetUI`, the Feature screens (root, live session,
  settings, history, volume, progress), `HardsetWidgetBundle.swift`, `Progression.swift`
  and `ProgressionTests.swift`, `AccentColor`/`LaunchBackground` colorsets, `Info.plist`,
  `Tools/generate_project.py` (global accent setting), project file, `Makefile`,
  `Tools/check_contrast.py`, `DESIGN.md`, `docs/MAC-VERIFICATION.md`, the audit doc.
- Defects fixed on the way: a create-movement button that did nothing; `GymOption`
  holding `UUID` while callers passed `GymID` (would not compile); warm-ups counted as
  working sets in exercise progress; record banners and machine chips hard-coded to kg;
  machine-change notes in kg (Core, tested); chart series merged when two machines
  share a name; rest controls hidden from VoiceOver; keypad detent shorter than the
  keypad; set row overflowing 375 pt phones; unreachable pull-to-refresh on error
  states; false empty states before first load; gap copy overclaiming under lower
  bounds; widget timer range able to invert; methodology sheet with no way to close.
- Review: three implementation agents on disjoint files, then two independent
  compile-plausibility reviews. Rejected with evidence: "computed `id` cannot satisfy
  `Identifiable` under default MainActor" and "`.refreshable { load() }` needs await"
  (both patterns compiled in the build recorded at `e5aff33`); hedged the three new
  computed-id types with `nonisolated` anyway. Not adopted: replacing the conditional
  `tabViewBottomAccessory` (pre-existing, documented, and it is what refreshes tabs
  after a workout).
- Verification on Linux: `make check` passed after rebase: 91 files parsed, 179 Core
  tests, 72 Store tests in five suites, query-index gate, palette contrast (172 pairs:
  7:1 text in four appearances, 3:1 control borders, 4.5:1 pressed fills). Project
  regeneration has no drift; `git diff --check` clean. Nothing in HardsetUI,
  HardsetFeature, the widget or the app has been compiled.
- Next concrete step: on the Mac, work through `docs/MAC-VERIFICATION.md` (build
  gates first, then appearance, logger ergonomics at 375 pt, hit regions, glare).
  Open user decision: the app icon set has no image; the final icon is still the
  user's call.
||||||| 33d2b09


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


### 2026-11-07 19:20 UTC — Bound open-workout lookup to open rows

- Objective: eliminate completed-history scans during recovery with no open workout.
  Existing task worktree `/home/frankbiz/orca/workspaces/hardset/mojarra`, branch
  `FrankieBiz/mojarra`; clean at start, no other changes found.
- Owned paths: Store/Migrations.swift, StoreTests/HistoryStoreTests.swift,
  StoreTests/LoggerStoreTests.swift, Tools/check_query_performance.py, this handoff,
  docs/LOADING_PERFORMANCE.md. No changes to LoggerStore query semantics.
- Confirmed absent-workout lookup scans sessions_on_startedAt. Added expected-empty
  5,000-finished-session benchmark; pre-fix --require-indexes failed only for that
  lookup. Native generated-query regression failed eight plan assertions across
  four lookups; all selection/finish/new-workout assertions already passed.
- v6_openSessionLookup adds non-unique partial sessions_on_openStartedAt index
  (finishedAt, startedAt DESC) WHERE finishedAt IS NULL. Earlier migrations untouched.
  Finished rows consume no entries; initial index creation still scans sessions.
  Migration preservation/nonunique tests now cover v1 through v5.
- Benchmark: 0.481 -> 0.001 ms warm median on local fixture, SCAN -> SEARCH without
  sorting. SQLite microbenchmark only; no iPhone launch-time claim. All eight query
  cases preserve results and foreign keys. Only named absent-workout case permits
  an empty result; existing seven queries still require nonempty fixtures.
- Verification: make check passed (90 parsed Swift files, 177 Core tests/23 suites,
  79 Store tests/5 suites, eight plan cases); expanded Release Store passed 157
  tests/16 suites across fourteen portable files via prior runpy wrapper procedure.
  Project and scheme regeneration identical; git diff --check clean.
- No failed fix attempts; expected pre-fix regression failures only. Linux cannot
  validate native app/widget/CloudKit/AlarmKit or physical-device load/frame times.
- Remaining broad goal: async startup/writer-engine ownership, consistent report
  reads, progression limits/order, incomplete-plan recovery, provenance UX, numeric
  validation, retry identity, rest persistence/account gating, native/device checks.
  Next concrete step: reproduce a concurrent volume report mixing countableSets
  with attributionIndex from separate database.read snapshots, then compose the
  report in one snapshot if confirmed. App-wide goal remains active.


### 2026-11-07 19:24 UTC — Read volume-report inputs consistently

- Objective: reproduce and eliminate mixed volume sets/attribution during concurrent
  edits, reducing separate read transactions. Prior turn was verified progress
  (06e48b4 on main). Existing worktree `/home/frankbiz/orca/workspaces/hardset/mojarra`,
  branch `FrankieBiz/mojarra`; clean at start.
- Owned paths: Store/VolumeStore.swift, StoreTests/VolumeStoreTests.swift,
  docs/LOADING_PERFORMANCE.md and this handoff. ProgressionStore in the same source
  file remains unchanged. No migrations or public API changes.
- Two real file-backed DatabaseQueues in WAL reproduce the bug without sleeps:
  after reading four bench sets, an independent writer atomically moves their dates
  outside the window and archives the exercise. Old report mixed four earlier sets
  with later missing attribution (4 unattributed), matching neither complete state.
  Baseline extended Debug command failed exactly report equality and BEGIN count
  (2 vs 1). Catalog decoding and archive rules work in the complete before/after
  fixtures; changing only read composition resolves the defect.
- report now reads both inputs in one database.read, via private connection helpers
  shared with countableSets/attributionIndex. AttributionIndex and VolumeAnalyzer
  arithmetic execute after closing the read. Existing SQL/date bounds/warmup and
  archive/unreadable attribution policies preserved. No nested database reads.
- Test proves the independent write fired and succeeded, coherent older report
  during load, complete newer zero-set report on next load, and one read transaction.
  No phone latency claim; screen load remains synchronous on MainActor.
- Verification: make check passed (90 parsed files, 177 Core tests/23 suites,
  79 Store tests/5 suites, 8 query-plan cases); default checker excludes Volume tests.
  Explicit Debug with STORE_TESTS += ('VolumeStoreTests.swift',) passed 90 tests/6
  suites. Expanded Release all14 portable Store files passed 159 tests/16 suites
  using existing runpy release wrapper procedure. Generated project/scheme identical;
  whitespace/diff review clean. No failed fix attempts beyond expected red baseline.
- Remaining: progression history still reads samples and labels in separate reads;
  next concrete step is reproduce an atomic machine-label/history update with a WAL
  writer and compose that load if confirmed. Also prioritize async screen/startup
  loading with cancellation and process-owned writer/sync engine: HardsetApp.init
  currently opens/migrates synchronously, RootView.task can recreate a view-owned
  engine, and WeeklyVolumeScreen.load runs the sync report on MainActor. Native
  builds, CloudKit/AlarmKit/widget integration and Release iPhone timing/frame/memory
  measurements remain required before any app-wide completion claim. Goal active.


### 2026-11-07 19:27 UTC — Read progression history consistently

- Objective: prevent progression samples and labels from different database versions
  and reduce read boundaries. Prior turn made verified progress (de56a8b). Existing
  worktree `/home/frankbiz/orca/workspaces/hardset/mojarra`, branch FrankieBiz/mojarra;
  clean at start. No subagents used.
- Owned paths: Store/VolumeStore.swift (ProgressionStore section only),
  StoreTests/ProgressionStoreTests.swift, docs/LOADING_PERFORMANCE.md, this handoff.
- Reproduced a real atomic WAL update via two DatabaseQueues. After sample SELECT,
  writer changes weight100->200 and station name Original->Renamed. Original loader
  produced 100 under Renamed, not either committed state. Baseline hardset-check
  store failed exactly history equality plus machine-history BEGIN count2 vs1.
  Free-weight variant already had one read and no labels query.
- history now reads samples and deduplicated machine IDs' names in one database.read,
  sharing connection helpers with public samples/machineNames. Analysis/grouping runs
  after the read ends. No nested reads, extra SQL, migration, or public API change.
  Existing warmup filtering, date order, 2000-set cap and labels remain unchanged;
  chart cap/partial-session and tied-time ordering problems remain separate work.
- Regression asserts writer fired/succeeded, older coherent history during update,
  newer200/Renamed on next load, exactly1 read, and no names query for free weights.
  Deterministic profile callback, no sleeps. Actual iPhone latency not measured.
- Verification: make check passed (90 Swift parse files, 177 Core tests/23 suites,
  81 Store tests/5 suites, 8 query-plan cases); expanded Release all14 portable Store
  files passed161 tests/16 suites via established runpy wrapper. Project and scheme
  regeneration identical; reviewed diff and whitespace clean. Expected red baseline
  only; no failed fix attempts. Native app/widget/CloudKit/AlarmKit not run on Linux.
- Next priority: measure synchronous feature load handlers/main actor occupancy and
  startup opening/migration, then design tested async loading with cancellation and
  durable process ownership for writer/sync engine. Existing screen .task closures
  call synchronous store methods. Do not equate async syntax with off-main execution
  under NonisolatedNonsendingByDefault. Native validation remains necessary. Also
  pending complete chart histories/tie ordering, incomplete-plan recovery, provenance
  UI, validation/retry identity, durable rest/account gating. Full-app goal active.


### 2026-11-07 19:35 UTC — Suspend screen database waits and own refresh results

- Objective: stop History/ExerciseProgress/WeeklyVolume screen database waits from
  occupying MainActor, preserve read snapshots and reject stale/canceled UI results.
  Prior turn was verified progress (a28c301). Existing worktree
  `/home/frankbiz/orca/workspaces/hardset/mojarra`, branch FrankieBiz/mojarra; clean
  at start. No agents delegated.
- Owned paths: Store/VolumeStore.swift, new Store/SnapshotLoader.swift, new
  StoreTests/SnapshotLoadingTests.swift, Feature/{HistoryScreen,ExerciseProgressScreen,
  WeeklyVolumeScreen}.swift, new DESIGN.md, docs/LOADING_PERFORMANCE.md, this handoff.
- Runtime baseline: query callback schedules MainActor job; all three original sync
  loaders block that job until a bounded test wait ends. Baseline test failed each
  availability assertion. Setup first needed await on GRDB write overloads in async
  test (one compile correction, no failed production approach). Probe uses semaphore
  only in fixture, timeout now2s to allow unrelated suite scheduling; no production
  locks, sleeps or detached tasks added.
- New named async Store APIs: loadRollingWeek, loadHistory, loadRecentSessions.
  Use actual GRDB async read with cancellation, shared helpers and one snapshot;
  synchronous public APIs preserved. Sendable conformances compiler-checked through
  DatabaseWriter. Under NonisolatedNonsendingByDefault, async alone is insufficient;
  GRDB read suspends here. Post-read volume/progression CPU remains on caller actor,
  pending profiling; no invented @concurrent or background responsiveness claim.
- SnapshotLoader is MainActor @Observable, cancels superseded active tasks, propagates
  parent cancellation with a cancellation handler, rejects stale successes/errors,
  silently preserves content on cancellation and reports actual failures. Screens
  await it; initial loads use native progress before data/empty states, refresh
  retains content. HistoryRow mapping remains once per success. No new motion;
  existing tokens retained. DESIGN.md records source token values and loading states.
- Portable tests cover main-actor availability, async/sync result equality and1 read
  each, no query when already canceled, cancellation during real query plus connection
  health afterward, latest-request success/error races, cancellation propagation even
  when operation returns late, failure/retry and silent CancellationError. Continuation
  gates control races without sleeps. Extended Debug passed87 tests/6 suites.
- Final make check passed:92 syntax files,177 Core tests/23 suites,81 default Store
  tests/5 suites,8 query-plan cases. Default checker omits the new test file; include
  SnapshotLoadingTests.swift in STORE_TESTS for extended runs. Expanded Release now
  uses15 portable files (prior14 plus SnapshotLoadingTests.swift); see next validation
  line for final result. Generated project/scheme identical; reviewed diff clean.
  Final expanded Release passed167 tests/17 suites (15 portable test files).
- Native SwiftUI compilation/rendering, keyboard/VoiceOver, refresh/dismissal, screen
  resizing and mid-range-device load/frame timings remain unverified on Linux. Never
  turn the executor-availability test into an iPhone latency claim. New screens were
  syntax checked only; Store and loader were fully compiled/executed.
- Next: inspect/test startup ownership and failure path. HardsetApp.init still opens
  and migrates synchronously via prepareDependencies, RootView.task owns/recreates
  syncEngine; current assertionFailure can continue with an unintended default
  database. Also catalog/recovery/pickers remain synchronous. Native startup/CloudKit
  environment is needed before release-quality whole-app validation. Other pending
  work: chart limits/tie order, incomplete-plan recovery, provenance, numeric/retry
  identity, durable rest and account gating. Goal remains active.


### 2026-11-07 19:43 UTC — Own and gate process startup resources

- Objective: move blocking opening/migrations off MainActor, retain exactly one live
  writer/engine bundle across scenes and surface startup failure without a fallback.
  Prior turn was verified progress (de26319). Existing worktree
  `/home/frankbiz/orca/workspaces/hardset/mojarra`, branch FrankieBiz/mojarra; clean at
  start. No subagents used. No migration/schema/path or account-policy change.
- Owned paths: new Store/AppStartup.swift and StoreTests/AppStartupTests.swift,
  Store/Database.swift, Hardset/HardsetApp.swift, DESIGN.md, docs/LOADING_PERFORMANCE.md,
  this handoff. Generated Xcode project is untouched.
- Baseline: actual migrator invoked from MainActor prevented a queued MainActor job
  from running inside a bounded test callback; extended Debug failed exactly that
  availability assertion. New controller executes blocking preparation on a private
  serial DispatchQueue and passes. Only test probes use semaphores; production does
  not block the actor or cooperative executor waiting on a semaphore.
- AppStartup<Resources> is MainActor @Observable, owns one in-flight task and the
  completed resource set. Concurrent callers share it, caller/scene cancellation
  doesn't cancel app-owned initialization, successful resources stay retained, failed
  attempts expose no resources and require explicit retry. Attempt IDs prevent late
  old waiters from changing new state. Escaped dependency context is restored on
  queue (tested with preview context) to avoid accidentally opening a live store.
- HardsetDatabase.prepareForLaunch returns a Sendable Resources value retaining both
  database and SyncEngine; existing mandatory delegate stays installed and retained
  by engine. App owns controller in @State above WindowGroup. No view task recreates
  a live engine. Explicit writer injection replaces App's only defaultDatabase usage;
  rg confirms no @Fetch/argumentless fetch/execute/defaultDatabase consumers elsewhere
  in app sources. Pinned SQLiteData source confirms unconfigured dependency supplies
  blank in-memory writer; earlier assertionFailure could leave that path active.
- App now shows progress and a token-based explicit retry UI before exposing root.
  Engine-construction failure also gates readiness rather than running a partially
  prepared writer. This waits for construction, not network sync. No custom motion;
  reduced-motion behavior immediate. Retry label has44pt minimum target token.
- Controller tests: real migration/main-actor availability; overlapping callers with
  one canceled; error/no-resources/explicit retry; resource identity and weak-reference
  lifetime; preview dependency propagation. Extended Debug passed86 tests/6 suites.
  Expected red baseline only, no failed implementation attempts.
- Final make check passed:94 parsed files,177 Core tests/23 suites,81 default Store
  tests/5 suites,8 query-plan cases. Project/scheme regeneration identical and diff
  clean. Default checker omits AppStartupTests; expanded suite now adds it to prior
  15 portable files. Final expanded Release passed172 tests/18 suites (16 portable
  test files), via established runpy wrapper with AppStartupTests.swift appended.
- Linux fully compiles/runs AppStartup and migrator/controller tests; Database.swift,
  SyncSetup.swift and the App are Apple-dependent and only syntax checked. Native
  app/widget build, actual CloudKit construction/entitlements, partial-engine failure
  retry, scene restoration/function lifetime, accessibility/responsiveness and Release
  device launch/frame measurements remain unverified. Do not claim native build or
  phone launch improvement. SyncEngine's Sendable conformance and initializer shape
  were checked against pinned source, not an Apple compilation.
- Next concrete step: measure post-gate HardsetRootView .task work, which still uses
  synchronous CatalogSeeder.seed, SessionCoordinator.resume and refreshGyms, swallowing
  seed/recovery errors with try?. Establish safe async/bootstrap state before allowing
  a new workout if recovery failed. Other broad-goal work remains chart limits/order,
  incomplete-plan recovery/provenance, numeric/retry identity, durable rest/account
  gating, and native/device validation. Goal remains active.
