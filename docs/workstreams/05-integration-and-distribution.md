# 05 — Integration, compatibility and distribution architecture

**Preferred owner:** Codex or the primary coordinator. **Stages:** M5–M8; release-readiness inventory can start earlier. **Dependencies:** accepted 01–03 changes and independent review of relevant 04 findings.

## Objective

Turn verified implementation into an identifiable, recoverable release candidate. Source integration, TestFlight distribution and public rollout remain separate decisions.

## Owned paths

After brief 01 releases ownership: `Tools/generate_project.py`, `Tools/install_device.sh`, `.github/workflows/`, proposed release tooling and release documentation. Generated project edits come through the generator. Candidate records belong under `docs/releases/` with private artifacts stored outside the public repository.

Do not patch Core/Store/UI defects in passing; route them to the responsible owner. Shared ownership of generator/CI with 01 is sequential. Until then this assignment is read-only inventory and release-procedure design.

## Work and deliverables

1. Integrate bounded worker commits non-destructively, inspect actual diffs and test the resulting candidate. Preserve dependencies and unrelated work; do not infer readiness from worker summaries.
2. Add deliberate version/build inputs and an archive/validation procedure separate from the local-install helper. Verify actual distribution credentials/capabilities without committing them.
3. Produce the migration/mixed-version compatibility packet, production CloudKit schema diff and candidate manifest specified in `perfect.md`. An older binary is not a safe rollback without demonstrated compatibility.
4. Prepare signed internal TestFlight, external pilot and public release procedures with exact build identity, test evidence, feedback/incident handling and forward-fix recovery.
5. Add later purchase/progression capability gates when those product stages are authorized. Preserve existing free access and actual purchased entitlements.

## Acceptance criteria

- Candidate commit, archive, version/build, dependencies, schema changes and processed distribution build can be traced together.
- Linux, native, device and migration/compatibility evidence matches the candidate, with unresolved gates explicit.
- Internal/external/public distribution stages have separate readiness and approval records; no production schema or release action is hidden in a routine build.
- Incident containment preserves committed records and acknowledges offline clients; no imaginary remote kill switch or destructive reset is relied upon.
- Existing purchases, restore/error states, exports and local logging remain covered wherever the release affects them.

## Verification

Primary integration gate: `make check`, project regeneration/idempotence and `git diff --check`. Native gate: actual package build, `./test.sh`, app/widget compilation and real-app journey in the workflow. Signed-device gate: candidate-specific offline/recovery, account-change, alarm and two-device sync checks.

Archive validation/upload and production environment checks require the actual Apple configuration. Prepare the exact reviewable operation before requesting any missing outward authorization. No placeholder signing configuration or inferred paid account access counts as proof.

## Authority and handoff

When assigned to a worker, return the release procedure, tooling diff and candidate packet to the coordinator via `.agents/handoffs/integration-distribution.md`. The worker does not publish, deploy CloudKit schema, invite testers, change prices, send messages or push main. The coordinator performs only actions already authorized for the specific destination after all applicable checks pass.

If the same primary agent is both implementer and coordinator, it must still inspect the final diff and fresh results before claiming readiness. Record unsupported physical-device and platform claims as open gates.
