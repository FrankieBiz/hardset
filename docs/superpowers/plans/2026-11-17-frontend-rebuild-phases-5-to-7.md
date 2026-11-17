# Front-end rebuild, Phases 5 to 7: live session, the other screens, and the end of the aliases

> Written after Phase 4 was built, and kept short on purpose. Phases 2 to 4 rebuilt every kit component, staged the real app for the tour and wrote the first launch, so what is left is the behaviour the spec asks of the daily screens and the removal of the old names. The rulings continue from Phase 4 (R49 to R58). Spec: `docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md` ("The app").

## Rulings

| Id | Decision |
| --- | --- |
| R59 | Auto rest lives in `LiveSessionScreen`, not the coordinator: the length is per movement and only the screen holds `RestPreferences`. A working set that is saved starts the rest last chosen for its movement; a warm-up starts nothing; a movement with no remembered rest is not given one and asks once through the card's rest control. The app never starts a rest of a length nobody chose. |
| R60 | The rest bar's chooser is a "Next rest" row under the controls plus a drag up (open) and down (close). The choices arrive by an insertion-only opacity reveal with no animated layout, as every message does, instead of `Motion.fling`: the spec's fling would animate a height, which DESIGN forbids. It sets the movement's next rest and never the one running. |
| R61 | Saving a set plays `clank` under `success`. The row does both when it is marked logged, so a failed write plays neither. Pitch 1 relies on the row and no longer plays its own. |
| R62 | The old colour aliases are deleted, 218 uses in 20 files renamed one for one to the plate tokens, so the build failing on a missed one is the proof. |
| R63 | The Volume screen's report-level "Moderate confidence" badge is removed, as the spec says: the engine asserts nothing for a report. Each muscle shows the certainty `VolumeAnalyzer.doseResponse` gives its count (moderate, low beyond the studied range, not evaluated for a counted-only muscle). |
| R64 | The Train tab's last-workout card opens its receipt, and a successful read with no history shows "No sessions yet" in an empty state. Both receipts present as sheets, as History's does: the spec's zoom transition is not built, because a transition cannot be checked from CI and a sheet is already the receipt's established presentation. It stays an owner decision. |
| R65 | "Repeat last workout" stays omitted until the engine has an entry point for it (spec, "Engine asks"). |

## Delivered

- **Phase 5.** Auto rest on save, the next-rest chooser on the rest bar, the clank under the success haptic, and the live-session files on plate tokens.
- **Phase 6.** Volume certainty per muscle, the last-workout card as a receipt link, the empty history state, and every remaining screen on plate tokens.
- **Phase 7.** Aliases deleted, `DESIGN.md` brought level with the code, handoff entries and the owner's device checklist in `docs/OWNER-DEVICE-CHECKLIST.md`.

## Verification

Linux `make check` and `hardset-check parse` on every change; macOS CI compiles it, renders every component and screen to PNG and drives the real app, which is where the PNGs of the changed screens (rest bar chooser, Volume, Train start) are read.
