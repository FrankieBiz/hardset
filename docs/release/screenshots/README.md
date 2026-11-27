# App Store gallery screenshots

Four screens, two required App Store sizes, eight PNG files. The images are renders of
Hardset's real SwiftUI views and real `Tokens` typography, fed a fixed fixture state. They
are not mockups drawn by hand, and they are not screenshots taken from a device. That is
the distinction decision D27 asks for: the interface shown is the interface that ships.

| File | Screen | Caption | Pixels |
| --- | --- | --- | --- |
| `6.9/01-train.png` | Live workout (`SessionView`) | It tells you when it's estimating. | 1320 × 2868 |
| `6.9/02-volume.png` | Volume (`VolumeReportView`) | Shows its math. Refuses to invent targets. | 1320 × 2868 |
| `6.9/03-progress.png` | Progress (`ProgressBoardView`) | Different machines. Never merged. | 1320 × 2868 |
| `6.9/04-muscle-history.png` | Muscle history (`MuscleHistoryView`) | Muscle history. One purchase, no subscription. | 1320 × 2868 |
| `6.5/01-train.png` | Live workout (`SessionView`) | It tells you when it's estimating. | 1242 × 2688 |
| `6.5/02-volume.png` | Volume (`VolumeReportView`) | Shows its math. Refuses to invent targets. | 1242 × 2688 |
| `6.5/03-progress.png` | Progress (`ProgressBoardView`) | Different machines. Never merged. | 1242 × 2688 |
| `6.5/04-muscle-history.png` | Muscle history (`MuscleHistoryView`) | Muscle history. One purchase, no subscription. | 1242 × 2688 |

The first three captions are the ones chosen in `docs/LAUNCH-PLAN.md` §2; the fourth reuses the words of the Lifetime in-app purchase description, so the gallery says that this screen is paid. They are set in
`Tokens.Text.display` (the app's 28 pt semibold title role) on `Tokens.Color.canvas`, above
the screen, at 3x. The screen itself is the live view at the width of the target device.

## What state each image shows

- **Train.** A live session for Incline Chest Press on a Plate-Loaded Incline with 10 lb
  steps and same-machine history of 215 lb × 8. Two 225 lb × 8 sets are logged, each with a
  "+10 lb" beat mark, and the third row is next up. The record panel is whatever
  `PersonalRecordDetector.records` returns for 225 lb × 8 against that history; nothing in it is
  typed. The rest timer is running. There is no "From another machine" note: this is a
  same-machine state, which is the only state in which the app can announce a record. The
  two-record notice and the rest bar cover most of the list at phone height, so the card hosts
  the live screen taller than itself and shows its lower part: the title and gym line are
  cropped away, and the three rows, the notice and the rest bar stay on screen.
- **Volume.** 14 working sets in the last 7 days, with Chest 10, Front delts 7.5 and
  Triceps 6 visible. The screen's own disclosure says there is no target line because no
  weekly set target is established, and "Not evaluated" is explained. "Worked from" and
  "How sets are counted" are visible as the inspectable path.
- **Progress.** The most-improved strip shows Leg Press on a 45° Incline Sled at +12% and
  the same movement on a Horizontal Cable Sled with "no 6-week comparison", followed by
  Chest Press on Hammer Strength at +8%. Both Leg Press rows are separate series; the
  second is not merged into the first. Quads follows with the same two rows and their
  sparklines.

- **Muscle history.** The paid screen. Incline Chest Press credits Chest directly and Front
  delts indirectly, so those two rows carry figures and "Worked from" controls; every other
  muscle, Side delts included, reads "No credited sets". Twelve weeks of sets include one zero
  week, and the last four weeks sit above the four before. There is no imported history. The
  figures come from `MuscleHistoryAnalyzer.history` over counts and weekly reports derived from
  one attribution. The card shows the sheet below its title and explanatory text, cropped the
  same way, so the Side delts "No credited sets" row is on screen.

## Regenerate

On a Mac with Xcode:

```bash
Tools/render_store_screenshots.sh
```

The script copies `Tools/store-screenshots/StoreScreenshotRenderer.swift` into
`Packages/HardsetKit/Tests/HardsetUISnapshotTests/` for the duration of one `xcodebuild
test` run, renders at 440 × 956 pt and 414 × 896 pt at 3x, verifies the four pixel
dimensions with `sips`, copies the eight files here, and removes the temporary source. It
leaves no test target or test file change in the repository.

Toolchain: the renderer and the images were verified on Xcode 27.2 by running the same
`xcodebuild` invocation in a throwaway copy that excluded two unrelated existing test
targets. Xcode 27.2 currently fails to compile an unrelated existing Store test
(`Conformance of 'Row' to 'Sendable' is unavailable`) before the renderer runs. The
script as committed therefore expects the project's CI toolchain (26.6), which compiles
the whole package. Nothing in the committed package or test target is changed; the
temporary copy was a local verification aid, not a deliverable.

Do not upscale, pad, or crop a smaller capture and call it native. If a size cannot be
produced, say so in the PR or release notes instead. `scripts/` verifies the dimensions
on every run and fails loudly if they are wrong.

## Upload

- App Store Connect requires the 6.9-inch iPhone size for a new app. Upload
  `6.9/01-train.png`, `6.9/02-volume.png`, `6.9/03-progress.png`, `6.9/04-muscle-history.png` first; they are the
  primary gallery.
- The 6.5-inch set is for the older size slot. Upload it only if App Store Connect asks
  for it or the owner wants the older-device gallery. Both sets show the same four
  screens and captions.
- Do not add a device frame, a marketing background image, or a different caption. The
  gallery's job is to show the app; the caption is the only added element.
- The app is dark-appearance only on the store gallery. The app itself has a light
  appearance; the store set uses the primary appearance (D21's dark palette).
