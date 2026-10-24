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
