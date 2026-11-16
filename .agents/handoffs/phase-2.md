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

## Wave 1 (Tasks 3 to 11), 2026-11-15 and 2026-11-16 (recorded after Wave 2 merged)

- Merged `--no-ff` in task order after conflict dry runs, no conflicts: `de8ccfd` (3), `2ad2fd7` (4), `3063a10` (5), `efa9990` (6),
  `9dda653` (7), `92d76f6` (8), `4d0007d` (9), `4cf7b88` (10), `164161f` (11). BASE `6199f26`. Each task was one commit on its own
  scratch branch in `_p2/t<N>`; a spec reviewer and a compile reviewer both approved every task in round 0 (no fix rounds).
- Before merging, the coordinator checked each branch against its owned paths (all nine touched only their own files), authorship
  (FrankieBiz, no trailers) and tip against reported head. One implementer (Task 9) reported a mistyped full SHA (`775f4841ee1d...`
  is not an object); the branch itself was one clean commit (`775f484`), and its reviewers read the real code. Later waves asked for
  `git rev-parse HEAD` verbatim and the coordinator checks tip equals reported head for every task. Task 9 was re-verified by hand:
  no spoken-label or action line removed, `LoggerFormatting.swift` untouched, knurl through `KnurlPattern` in a background.
- Integrated V: parse 172, contrast 184 pairs across 23 swatches (Task 11 added exactly 8), generator diff clean, `make check` exit 0
  (Core 232 in 29 suites, Store 299 in 30 suites unchanged).
- macOS run 43791436878 on `164161f`: green, about 30 minutes. The early package-test compile step passed in about 2 m 40 s, so the whole
  snapshot target compiled for the simulator minutes in. 179 PNGs (the 56 existing plus 123 `kit-*`); real-app journeys and audit passed
  in dark and light, which covers the set-row tap geometry (offsets 0.44, 0.93, 0.08).
- PNG review (coordinator spot checks plus 12 parallel readers): no regression in the existing screens; every difference is an intended
  one (condensed -2% display titles, +1% caption and unit tracking, machined fields, chips and header circle, the knurled ring around the
  logged seal, the chalk countdown on its knurled backing). Findings acted on in the final fix dispatch: capture windows cropped at the
  bottom (messages empty, honesty detail, methodology with a citation, set-row rows at accessibility3, rest bar at 402 pt); sheet roots
  rendered without the app's plate-blue tint, so toolbar Done and Cancel drew near-black on dark (the pre-Phase-2 methodology capture had
  the same artefact; the real app shows them blue); long wrapped tags, assumption chips and certainty capsules at accessibility3 became
  blobs with text crossing the outline. Known renderer artefact, not a defect: stray end-lines on outlined capsules.
- Deferred minors (Wave 1): Task 3 extra live `HeaderIconMenu` in the icons section; Task 4 two extra internal symbols
  (`HardsetSegmentFace` second init, `hardsetSegmentTrack()`) and the `.isSelected` trait stays on the Button; Task 6 extra internal
  `SelectionRowLabel`; Task 7 large-text detail rendered through `CertaintyDetail` not the seam; Task 9 seal glyph capped at xxxLarge;
  Task 10 catalogue does not use `CatalogSection` and has no `height(_:)` switch (one section).

## Wave 2 (Tasks 12 to 15), 2026-11-16

- BASE `164161f`. Merged `--no-ff` after dry runs, no conflicts: `0cf2a00` (12), `b38594d` (13), `befccb5` (14), `601dfd0` (15).
  Both reviewers approved every task in round 0. Owned paths, authorship, trailers and tip equal to reported head all checked.
  Integrated V: parse 176, contrast 184, generator clean; `SelectionTag` survives only at the two `SelectionRow` call sites and the
  typealias; the U+2019 label in `MachinePickerView` is intact.
- Ruling: Wave 2 was merged locally while Wave 1's run was still in flight (its reviews were complete and nothing was pushed while a run was
  in flight), and Wave 2 and Task 16 share the next push so there is one run rather than two; costs: a failure in the combined run is
  attributed by file path.
- Deferred minors (Wave 2): Task 12 default preview has no warm-up row and a capture name with a width suffix
  (`kit-exercise-leg-press-dark-375`); Task 13 the gym loading line is an inline `Text`, not `HardsetLoadingState` (deliberate: that view
  fills its frame); Task 14 sample reused one machine in both lists (fixed in the final dispatch).

## Task 16 and the final review, 2026-11-16

- Task 16 (kit completion) `28081c8` plus a design-notes correction `0cdbee0` after one fix round; `make check` exit 0; `ComponentsHarness` and
  the `SelectionTag` typealias deleted, `MethodologySheet.level(for:)` delegates to `CertaintyLevel(_:)`. Preview shortfalls, deliberate:
  `NumericPad` 12 previews for 11 states with two sharing one; `ExercisePickerView` 12 for 13 with the two "Not attributed" and "Not recognised"
  states sharing one.
- Whole-branch review (four Opus lenses: compile across tasks, spec and accessibility, frozen contracts, tests and CI honesty, each finding
  verified by a skeptic): 9 confirmed, 0 refuted. No public signature was removed or altered; every call site compiles; contrast math for the
  new pairs holds (editing ring 7.43:1, seal 7.40:1, pressed selected chip 7.54:1, chalk on `steelPressed` 14.67:1, `controlEdge` at least
  3.11:1). Important findings, all fixed in `ee7540b`: the machine picker's accessibility3 error capture was 2800 pt tall and could not show
  whether the pinned banner crowds the list (now phone height, so it can fail by design: if the render shows the list unreachable, move the
  banner into the scrolling content at accessibility sizes and record a ruling); the "All" chip hit region was about 40 pt wide (now 44 by 44);
  `DESIGN.md` said every header circle sinks, but `HeaderIconMenu` is a `Menu` and keeps its resting face (device check); three capture windows
  were cropped; this ledger lacked Wave 1 and Wave 2.
- Final fix dispatch: one fixer commit `ee7540b` (21 files: windows, sheet tint in the snapshot roots, rounded-rectangle shape at accessibility sizes
  for `HardsetTag`, `AssumptionChip` and `CertaintyCapsule` with no new `Shape` type, chip minimum width, design and spec notes, stale comments), then
  two scoped re-reviewers approved it with minors only. Coordinator follow-up `HonestyCatalogView` pressed assumption-chip sample now takes the same
  shape rule as the live chip.
- Owner decisions left open (not changed inside Phase 2): under Increase Contrast dark, `steelRaised` and `steel` are pure black, so filled-only tags,
  icon tiles and the static "Not evaluated" fill vanish (word and symbol still carry meaning) and `steelPressed` (`#26262B`) is lighter than `steelRaised`,
  so a pressed face does not sink; the paused rest countdown is chalk like running (chalkDim failed 7:1 on the knurl), distinguished by the word
  "Paused" and the play glyph; dismissible banners squeeze their body at accessibility3; chips truncate in a rail at accessibility3 by design; segments
  hyphenate "Estimated one-rep max" mid-word at accessibility3; `plateBlue` text on `steelPressed` in light is 6.97:1 (not gated; the pressed floor is 4.5:1).
- Physical-device checks the owner still owns: press feel on `HeaderIconMenu` (a `Menu` never reports a press) and on the machined faces, glare, haptics.
