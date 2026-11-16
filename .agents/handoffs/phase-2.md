# Front-end rebuild, Phase 2 (component kit): coordinator ledger

Maintainer: FrankieBiz <frankabisignano@gmail.com>. Plan: `docs/superpowers/plans/2026-11-13-frontend-rebuild-phase-2-component-kit.md`
(component map beside it). Integration branch: `FrankieBiz/premium-frontend-design-plan-2`. Task 16 folds this file into one dated
entry in `.agents/HANDOFF.md`.

## Step 0 and Wave 0 (Tasks 1 and 2), 2026-11-15

- Merged: no merges (Wave 0 is committed directly on the integration branch). Step 0 `1b6bb1f` (plan and map), Task 1 `5dff997`,
  Task 2 `e64b529`, minors fix `6199f26`. Coordinator CI commits: `93d9425` early package-test compile step, `ed3a037` timeout 75 to
  120 minutes, `621cee9` named-simulator destination for the early step (an independent reviewer's one finding: a generic destination
  also builds x86_64, which the render step never reuses).
- Baseline at Step 0 (`make check` exit 0): parse 147 files, Core 232 tests in 29 suites, Store 299 tests in 30 suites, 176 contrast pairs
  across 23 swatches. After Wave 0: parse 155, contrast 176, generator diff clean.
- Reviews: Task 1 and Task 2 each approved by a spec reviewer and a compile reviewer in round 0 (no critical or important findings).
  Two minors on Task 2 fixed in `6199f26`.
- macOS run 43763977949 on `621cee9`: green, every step success, about 49 minutes end to end. The early compile step took 2 m 38 s; the
  render step about 5 minutes (40 tests in 4 suites, 66 PNGs, so the per-capture cost is far below the 4.3 s the plan assumed and the
  120 minute timeout is generous). Real-app journey and audit step passed in dark and light.
- PNGs reviewed (`kit-surfaces-*`, 10 files): press section shows the opacity press (dim to 80% with a small sink) and the machined press
  (darker face, edge light dropped, control edge kept, nothing dims) apart, in dark and light; disabled samples keep full contrast;
  cards show the 2 pt `plateBlue` ring on `plateBlueSurface` when selected; `typeWeight` confirms `hardsetText(.caption, weight: .semibold)`
  renders visibly heavier than `hardsetText(.caption)` at the same tracking, and wraps without truncation at accessibility3. R17 stands, no
  fallback needed. Bottom edges are not cropped. The stray end-lines on outlined capsules are the known `layer.render` artefact.
- Noise, not defects: 18 `CHHapticPattern ... Failed to read pattern library data` lines in the snapshot log (simulator host has no haptics
  pattern library; pre-existing `sensoryFeedback` chatter).
- Flakes: none. Fix rounds: 0 (plus the minors commit). Reverts: none.
- Rulings made by the coordinator: the plan's R38 to R40 and the replacement of R17 (a deterministic `hardsetText(_:weight:)` overload instead
  of a font-weight chain), the press architecture (`MachinedPressFace` and `MachinedPressStyle`), knurl as a background only, the capture
  budget and timeout, and the execution protocol were all written into the plan after its adversarial review; see its Rulings table.
  Housekeeping: `Packages/HardsetKit/Package.resolved` is rewritten by Linux Swift tooling and is never staged.
