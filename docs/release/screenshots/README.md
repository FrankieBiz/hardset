# App Store gallery screenshots

Three screens, two required App Store sizes, six PNG files. The images are renders of
Hardset's real SwiftUI views and real `Tokens` typography, fed a fixed fixture state. They
are not mockups drawn by hand, and they are not screenshots taken from a device. That is
the distinction decision D27 asks for: the interface shown is the interface that ships.

| File | Screen | Caption | Pixels |
| --- | --- | --- | --- |
| `6.9/01-train.png` | Live workout (`SessionView`) | It tells you when it's estimating. | 1320 × 2868 |
| `6.9/02-volume.png` | Volume (`VolumeReportView`) | Shows its math. Refuses to invent targets. | 1320 × 2868 |
| `6.9/03-progress.png` | Progress (`ProgressBoardView`) | Different machines. Never merged. | 1320 × 2868 |
| `6.5/01-train.png` | Live workout (`SessionView`) | It tells you when it's estimating. | 1242 × 2688 |
| `6.5/02-volume.png` | Volume (`VolumeReportView`) | Shows its math. Refuses to invent targets. | 1242 × 2688 |
| `6.5/03-progress.png` | Progress (`ProgressBoardView`) | Different machines. Never merged. | 1242 × 2688 |

The captions are the three chosen in `docs/LAUNCH-PLAN.md` §2. They are set in
`Tokens.Text.display` (the app's 28 pt semibold title role) on `Tokens.Color.canvas`, above
the screen, at 3x. The screen itself is the live view at the width of the target device.

## What state each image shows

- **Train.** A live session for Incline Chest Press on a Plate-Loaded Incline with 10 lb
  steps and a prior-history note, "From another machine · Low confidence". Two 225 lb × 8
  sets are logged; the record panel shows "Best estimated 1RM: About 285 lb" with
  Moderate confidence. The rest timer is running. The logged rows are green seals, the
  record is the yellow trophy, and the rest bar is the running countdown. The app's
  `ExerciseLogState` and `SessionView` decide the layout; the fixture only supplies the
  values.
- **Volume.** 14 working sets in the last 7 days, with Chest 10, Front delts 7.5 and
  Triceps 6 visible. The screen's own disclosure says there is no target line because no
  weekly set target is established, and "Not evaluated" is explained. "Worked from" and
  "How sets are counted" are visible as the inspectable path.
- **Progress.** The most-improved strip shows Leg Press on a 45° Incline Sled at +12% and
  the same movement on a Horizontal Cable Sled with "no 6-week comparison", followed by
  Chest Press on Hammer Strength at +8%. Both Leg Press rows are separate series; the
  second is not merged into the first. Quads follows with the same two rows and their
  sparklines.

## Regenerate

On a Mac with Xcode:

```bash
Tools/render_store_screenshots.sh
```

The script copies `Tools/store-screenshots/StoreScreenshotRenderer.swift` into
`Packages/HardsetKit/Tests/HardsetUISnapshotTests/` for the duration of one `xcodebuild
test` run, renders at 440 × 956 pt and 414 × 896 pt at 3x, verifies the four pixel
dimensions with `sips`, copies the six files here, and removes the temporary source. It
leaves no test target or test file change in the repository.

Toolchain: verified with Xcode 26.6, the version the project's CI uses. Xcode 27.2
currently fails to compile an unrelated existing Store test
(`Conformance of 'Row' to 'Sendable' is unavailable`) before the renderer runs. That is a
project/toolchain mismatch, not a render failure; use the CI toolchain.

Do not upscale, pad, or crop a smaller capture and call it native. If a size cannot be
produced, say so in the PR or release notes instead. `scripts/` verifies the dimensions
on every run and fails loudly if they are wrong.

## Upload

- App Store Connect requires the 6.9-inch iPhone size for a new app. Upload
  `6.9/01-train.png`, `6.9/02-volume.png`, `6.9/03-progress.png` first; they are the
  primary gallery.
- The 6.5-inch set is for the older size slot. Upload it only if App Store Connect asks
  for it or the owner wants the older-device gallery. Both sets show the same three
  screens and captions.
- Do not add a device frame, a marketing background image, or a different caption. The
  gallery's job is to show the app; the caption is the only added element.
- The app is dark-appearance only on the store gallery. The app itself has a light
  appearance; the store set uses the primary appearance (D21's dark palette).
