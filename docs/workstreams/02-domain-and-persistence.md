# 02 — Training domain, persistence and comparison architecture

**Preferred agent:** Codex; Claude may review the product-facing contracts. **Stages:** M2–M4, then gated M7. **Dependencies:** brief 01 and the product/prototype gate from brief 03.

## Objective

Build a durable domain model connecting intended plans, actual sessions, equipment context and reproducible reviews. Preserve Hardset's existing Core/Store architecture and permanent schema invariants.

This is the main architectural assignment. Deliver it in reviewed slices, not one speculative schema-and-app rewrite.

## Owned paths

`Packages/HardsetKit/Sources/HardsetCore/`, `Sources/HardsetStore/` and their matching test directories. New contract/migration notes belong under `docs/architecture/`. Coordinate before touching generated catalogue data or Store files still owned by brief 01.

Do not edit `HardsetUI`, `HardsetFeature`, app shell, native CI or global model/provider settings. The UI implementer consumes public records and commands rather than internal table models.

## Contract before implementation

Publish a concise contract covering identifiers, routine roles, versions, sequence transitions, session intention versus deviation, supported load conventions, unknown context, read snapshots, commands/errors, conflict behavior and comparison selection. Include sample states and transitions in tables or prose; no diagrams.

Have the coordinator and UI implementer accept the relevant contract before writing permanent schema tokens. Use existing public vocabulary and persistence where it works. Explain any necessary addition; do not introduce a second workout engine.

## Implementation slices

1. **Plans and sequence:** reusable routines, one active plan, saved versions, explicit skips, extra sessions and today-only changes. Preserve the starting plan/version when a workout begins.
2. **Equipment and ownership:** gym-specific routine bindings, physical versus confirmed-comparable versus unknown context, substitutions, load convention and source provenance. Integrate with existing import/export rather than flattening new meaning away.
3. **Descriptive review:** deterministic matched-work selection, both reps/load, dates, excluded/unmatched work, exposure totals and explicit insufficient-information states. No cross-machine normalization or invented personal targets.
4. **Later only:** optional blocks, deeper comparisons and user-selected progression proposals with inspectable triggers. Wait for pilot evidence and a separate slice decision before implementing this extension.

## Acceptance criteria

- Missed days, partial finishes, active-plan edits and repeated movement roles preserve the intended sequence and historical facts.
- Plan edits/session starts are atomic; new snapshots do no database work per render; save-before-claim remains enforced.
- Additive migrations preserve supported historical databases, including known legacy-v1 variants and current v10; mixed-client behavior is specified and tested where support is claimed.
- Comparisons use explicit eligibility and source sets, preserve missing context and do not imply hypertrophy or equivalent machine loads.
- New data survives recovery and appropriate export/import round trips; a history correction does not silently replay an accepted future progression decision.

## Verification

Primary: `make check` after each final slice. Use actual Core/Store compilation, focused state-transition/migration/atomicity tests and large-history query-plan fixtures. On macOS run `./test.sh` and real package compilation for Swift 6 isolation checks. A schema change additionally needs the migration/compatibility packet defined in `perfect.md`; tests alone do not authorize CloudKit production deployment.

Brief 04 supplies adversarial cases. The implementer reproduces valid cases and owns production fixes and durable tests. Do not accept an audit conclusion without replaying its evidence.

## Handoff

Return public contract, migration diff, test evidence, unresolved compatibility cases and commit for each slice. Use `.agents/handoffs/domain-persistence.md`. UI requests crossing the ownership boundary go through the coordinator. No additional worker dispatch, production schema deployment or main push.
