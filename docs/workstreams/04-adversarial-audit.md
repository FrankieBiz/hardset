# 04 — Taxonomy, data and adversarial scenario audit

**Preferred agent:** DeepSeek through existing free OpenCode configuration. **Stages:** evidence alongside M0/M1, then regression challenges throughout M2–M8.

## Objective

Find reproducible errors and missing cases cheaply and independently. Produce evidence the implementers can replay. This workstream does not own production architecture or scientific truth by assertion.

## Owned paths

Reports, fixture proposals and standalone reproducibility material only under `docs/audits/deepseek/`. Production source, package tests, migrations, CI, generated catalogue, global config and shared handoff are read-only. Use `.agents/handoffs/adversarial-audit.md` for task-specific state.

Before running executable audit material, inspect it and use disposable synthetic databases/files. No user databases, secrets or private histories. Do not modify another worker's live checkout.

## Audit batches

1. **Existing baseline:** identify catalogue/taxonomy inconsistencies, unknown attribution, direct/indirect/stabilizer counting and machine-separated history edge cases. Read the taxonomy specification and generator source; do not hand-edit generated catalogue output.
2. **Plan transitions:** build a finite case matrix for missed days, skips, partial sessions, duplicate movement roles, active-plan edits and concurrent versions. Report ambiguity as a specification question, not a fabricated failing test.
3. **Equipment/import:** kg/lb round trips, decimal increments, assistance, per-side conventions, archived/unknown stations, same-brand distinct machines, imports lacking identity, duplicate replay and correction provenance.
4. **Reviews:** changed setups, unmatched set counts, different set roles, warm-ups, sparse history, imported uncertainty and candidate-selection bias. Show where a proposed result overstates the available evidence.
5. **Later progression/commerce:** rule thresholds, unavailable load steps, corrected old data, override/reset and missing purchase states. Wait for actual contracts before treating these as implementation defects.

## Required finding format

For each finding provide:

- Unique ID, affected commit, relevant file/function or contract section and severity rationale.
- Minimal synthetic input and deterministic seed if generation is random.
- Expected result, why it follows from an accepted specification/source, and observed result.
- Exact reproduction command, exit code/output and environment; distinguish a proposed case from an executed reproduction.
- Suggested regression location, without patching production or rewriting the specification yourself.

Scientific claims need a primary source and the precise inference being made. Preserve the distinction between population findings, counting conventions and individual prescriptions. Do not “fix” unevaluated targets by supplying uncited numbers.

## Acceptance criteria

- Every claimed defect has a minimal replayable case; unreproduced suspicions are labeled.
- Source-based taxonomy findings cite the governing spec or research and identify uncertainty.
- Generated inputs are synthetic, deterministic and bounded; no live training records are touched.
- Findings are deduplicated and prioritized by consequence, including evidence of correct behavior where useful.
- The coordinator/implementer can independently reproduce accepted findings before any production change.

## Verification

Primary baseline: `make check`, recording the actual candidate and output. For each delivered reproducer, include its exact runnable command and captured result; audit scripts must execute only against disposable fixtures. Structured fixture syntax checks do not prove semantic correctness. A proposed regression that has not been run must not be reported as red/green.

This agent writes no package test or production fix in this assignment. The appropriate Core/Store or UI owner converts accepted findings into durable tests and repairs. The coordinator reruns them on the integrated tree.

## Cost and completion boundary

Use configured `opencode/deepseek-v4.1-flash-free`. Do not enable the paid DeepSeek API, install another provider or run paid probes. No worker delegation, direct main push or publication.

Stop a batch after covering its finite matrix or identifying a blocking specification gap. Do not generate unlimited random cases or turn one ambiguous statement into repeated speculative findings. Deliver the report and the next highest-value missing case.
