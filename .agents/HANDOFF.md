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
