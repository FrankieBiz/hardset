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
