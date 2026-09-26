# Hardset video handoff

This folder is ready to open on Windows. The PNGs and MP4 are captures of Hardset running in an iPhone 17 Pro simulator, with fictional training data. The app itself needs a Mac and Xcode; editors do not.

## Start here

1. Read `video-brief.md` for the story, 35-second draft structure, and accurate on-screen copy.
2. Open `contact-sheet.jpg` to scan the available screens.
3. Edit from `footage/workout-walkthrough.mp4`. This is a trimmed, continuous, real UI interaction, not an animation of screenshots.
4. Use `screenshots/` for clean holds, close crops, and transitions. The full-resolution originals are 1206 x 2622 PNG.
5. Use `assets/AppIcon-1024.png` for the end card. `assets/design-tokens-summary.md` has the exact UI colors.

## Suggested delivery

- Primary: vertical 1080 x 1920 MP4 (H.264), 30 to 40 seconds, with editable project files.
- Also export a silent version and a version with captions burned in.
- Keep a safe area for platform captions; do not crop away the set fields or the bottom navigation while they are being demonstrated.
- The footage is silent. Add licensed music/sound in the edit; do not imply the app makes sound on each tap.
- A small “Horizon” return breadcrumb from the simulator's previous app is visible at the top left of the walkthrough. Cover that corner with the video title treatment or crop the very top of the footage in the edit.

## Asset provenance

- The seven PNG captures and app icon came from the existing September 26, 2026 simulator marketing drop.
- The walkthrough MP4 was captured from the existing automated UI test that starts a workout, adds Barbell Bench Press, enters 100 lb and 8 reps, logs the set, finishes, opens History, and starts that workout again.
- No customer data appears in these assets. The names and training data shown are demo data. Equipment names describe what a user recorded, not a brand partnership.

The video brief reflects the current release candidate. It deliberately avoids promising verified iCloud sync or background rest alarms; those physical-device release checks are still open.
