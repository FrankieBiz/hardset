# Hardset handoff for a second computer

Use this file as the first context given to Codex after cloning the repository. It is intentionally
shorter than `HANDOFF.md`; the latter contains the full architecture and decision history.

## Start here

```text
You are taking over Hardset, an iPhone strength-training logger. Work from this repository and read
README.md, HANDOFF.md, DECISIONS.md, DEVICE-CHECKLIST.md, APP-STORE-SUBMISSION.md, and
docs/APP-STORE-REVIEW-2026-09-08.md before changing code. Preserve the established product rules and
do not reinterpret missing recommendations, scores, defaults, or targets as unfinished features.

The active integration branch is feat/splits. First run `git status`, `git branch --show-current`,
and `git log --oneline --decorate -10`. Never reset, discard, or rewrite existing work. Keep changes
small and test-first. This Windows machine can edit and review the repository, but it cannot build,
run, sign, or submit an iOS/Xcode application. Do not claim an iOS fix is verified from Windows;
leave a precise Mac verification command and hand the change back to a Mac.

Current priority is App Store readiness and very fast gym use. The September 8 review fixed planner
occurrence settings, empty-day setup routing, completed-history selection, and the warning shown
when redistribution removes plan days. Remaining release gates include physical-device interaction
and haptic testing, AlarmKit background behavior, large-history performance, distribution signing,
public privacy/support URLs, App Store Connect metadata, and a decision about CloudKit storage of
fitness data. Do not enable or remove CloudKit, change privacy promises, or publish externally
without an explicit product decision.
```

## Repository state at handoff

- Remote: `https://github.com/FrankieBiz/hardset.git`
- Working branch: `feat/splits`; it is substantially ahead of `main`.
- Stack: Swift 6.2, SwiftUI, GRDB/SQLiteData, CloudKit/CKSyncEngine, AlarmKit and ActivityKit.
- Minimum deployment: iOS 26.1. Xcode project generation is owned by
  `Tools/generate_project.py`; do not casually hand-edit `project.pbxproj`.
- Supported host verification on macOS: `./test.sh` from the repository root.
- Latest verified package result on September 8, 2026: 769 main tests plus five isolated tests,
  774 total, all passing.
- Latest verified simulator result: planner-to-workout and cold-launch UI tests passed on an
  iPhone 17 Pro / iOS 26.4 simulator. Responsive-first-frame launch averaged about 2.10 seconds
  using the ephemeral UI-test database.
- Latest unsigned generic iOS Simulator Release build passed with Xcode 26.4. This does not prove
  App Store signing, production CloudKit, AlarmKit delivery, haptics, or physical-device speed.

## Product rules that must survive

- Logging is local-first and must work without a network or account.
- A set is shown as completed only after persistence succeeds.
- Weight is stored canonically in kilograms and converted only at UI boundaries.
- History and progress are specific to exercise plus physical machine.
- Drop sets do not add a working set and do not seed history, records, or progression.
- The app does not invent training prescriptions, default programs, set targets, scores, or
  unsupported certainty.
- Existing workout data must never be erased as migration recovery or test setup.
- `HardsetSyncDelegate` must preserve local data across iCloud account changes.

## What Windows can safely do

- Review Swift and documentation, search for inconsistencies, prepare small patches and commits.
- Work on pure algorithms only if the change is later compiled and tested on the Mac.
- Update copy, checklists and GitHub documentation while preserving LF line endings.

Windows cannot run the authoritative tests because the package targets macOS/iOS and the app uses
Apple-only frameworks. A Windows agent must clearly label all code changes **unverified** and provide
the Mac with the relevant command. For normal package changes that command is:

```bash
./test.sh
```

For an app build:

```bash
xcodebuild -quiet -skipMacroValidation \
  -project Hardset.xcodeproj -scheme Hardset -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Current decisions still requiring the owner

1. Ship version 1 local-only, or retain CloudKit after resolving Apple's restriction on storing
   personal health information in iCloud and completing two-device production testing.
2. Supply real public privacy-policy and support URLs. Never invent these URLs.
3. Complete the paid-team signing, App Store Connect privacy/age-rating metadata, screenshots and
   physical-device checklist.

When returning work to the Mac, provide: branch and commit, exact files changed, behavioral reason,
tests that were or were not run, and the exact Mac verification still required.
