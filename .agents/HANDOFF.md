# Handoff — Hardset ADA polish branch → the Mac

**Branch:** `FrankieBiz/perfect-app-polish-agents` (local only, **not pushed**). Branch point from
`main`: `1b6f2c8`. Written 2026-10-12 on the Linux box (Fedora, no Xcode).

## What this branch is
Four phases of the spec `docs/superpowers/specs/2026-10-10-hardset-ada-polish-design.md`, planned in
`docs/superpowers/plans/2026-10-1{0,1}-phase{0..4}-*.md` and executed task by task (implementer →
reviewer → fix rounds → merge), then a four-area final review whose findings were fixed:

- **Phase 0** Linux harness: `Tools/linux-test.sh` (podman `swift:6.2`), CloudKit-guarded sync code.
- **Phase 1 Trust:** per-exercise remembered rest (no default), AlarmKit reconcile/persistence,
  notification fallback, failure copy, one weight formatter.
- **Phase 2 Core loop:** bottom keypad, edit/delete/undo of sets, record moments, workout summary,
  Recent movements, one tab identity with the rest in the tab accessory, glass Start, Repeat.
- **Phase 3 Honesty & inclusivity:** certainty as glyph + word, methodology sheet, VoiceOver/Dynamic
  Type, localization seam (DECISIONS §23), first-run screen, past-workout detail, gyms/machines
  rename & archive, root split.
- **Phase 4 System surfaces:** Lock Screen rest with pause/resume/skip intents, Siri/Spotlight/
  Action button start, Control Center controls, history widgets (App Group snapshot file, never the
  DB), Apple Health opt-in write-only, two TipKit tips, launch colour, privacy manifests, icon brief.

## State
- **Linux:** HardsetCore + HardsetStore pass the full suite (`Tools/linux-test.sh`; 680+ tests).
- **Never compiled:** HardsetUI, HardsetFeature, HardsetAlarm, HardsetHealth, the app, the widget,
  HardsetIntents, HardsetTests. Expect a first-build pass of small fixes.
- `Hardset.xcodeproj` is **generated** — never hand-edit; `python3 Tools/generate_project.py`.

## What to do on the Mac, in order
1. `git push -u origin FrankieBiz/perfect-app-polish-agents` (from Linux, when you choose), pull on
   the Mac, run `python3 Tools/generate_project.py`, open the project, build the `Hardset` scheme.
2. Work through `docs/MAC-VERIFICATION.md` top to bottom — every entry names what to check and the
   fallback if it fails. Look-first items (SDK spellings that could not be checked here) are marked.
3. Then `DEVICE-CHECKLIST.md` §B (AlarmKit), §E (system surfaces), §F (Health) on a real iPhone.
4. **Unblock two tasks** once Phase 3 Task 10's String Catalog builds on the Mac (MAC-VERIFICATION
   Phase 3 entry): Phase 3 Task 11 and Phase 4 Task 16 route Core copy through `localized(_:)`
   (DECISIONS §23). Plans and briefs are in `docs/superpowers/plans/` and `.superpowers/sdd/`.

## Decisions owed by the user (blocking shipping, not building)
- Privacy policy URL (App Review requires it with the HealthKit entitlement).
- Paid Apple Developer Program membership (App Group for widgets, HealthKit, iCloud, push).
- Final app icon artwork (brief + SVG layers in `Design/AppIcon/`).
- From HANDOFF.md: catalogue author, founding price.

## Settled — do not re-litigate
Refusals in `HANDOFF.md` §6 (no streaks, feed, default program, default rest, invented targets; no set
logged from outside the app UI). `DECISIONS.md` §22–§27. Every controller ruling is in
`.superpowers/sdd/*/progress.md` (lines starting "Ruling"). Notable: §27 one plate = 5 lb in either
unit when the machine's step is unknown; a workout finished on another device is never exported to
Health from this one; Health "Saved" only after both the HealthKit save and the export record.

## Known residuals (accepted, documented)
`settle()` in-flight schedule race; a failed machine-increment read can make a live record verdict
differ from the replay; a tie exactly at the 1,000th prior set; old alarm not cancelled on permission
revoke (device check); tips/TipKit spellings; alert-after-confirmation-dialog presentation. Each has
a MAC-VERIFICATION or DEVICE-CHECKLIST line.
