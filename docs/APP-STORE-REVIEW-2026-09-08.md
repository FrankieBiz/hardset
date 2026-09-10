# Hardset release review — September 8, 2026

Verdict: not yet submission-ready. This is a source/configuration review with a fresh package test run, not an Apple approval or a physical-device certification. Existing application edits and training data were preserved.

## Release blockers and risks

1. **Public policy and support are unresolved.** `LegalLinks.live` in `AppMetadata.swift` still contains nil URLs. The offline policy exists, but public policy hosting and App Store Connect metadata are not verified. Apple guideline 5.1.1(i) requires accessible policy links in the app and store metadata. Configure real, maintained pages; do not invent URLs.
2. **Distribution sync configuration is absent.** The checked project has no `CODE_SIGN_ENTITLEMENTS` setting. The database deliberately tolerates absent CloudKit capability and continues locally, while the policy and listing describe synchronization. Produce and validate the paid-team distribution archive and production CloudKit behavior, or explicitly choose a local-only release and align its promises. Do not silently enable sync or change existing data handling during a review.
3. **Health-data scope needs a release decision.** Bodyweight is excluded from explicit CloudKit synchronization, but sessions, logged sets and free-text notes are included. Guideline 5.1.3(ii) prohibits personal health information in iCloud. Determine whether the actual stored fields and intended note use meet this restriction; private CloudKit alone is not proof of compliance. This is a policy risk, not a definitive finding that every strength log violates the rule.

## Concrete gym-workflow findings

- **Fixed: repeated exercise settings shifted during redistribution.** The replacement queue now preserves one authored-settings position for every occurrence, including an unconfigured one, so a later occurrence's machine and set count cannot jump forward.
- **Fixed: an empty day hid history-based setup.** Builder routing now uses the number of movements. Existing empty days remain editable while the history-start controls stay visible; the no-op redistribution action is not offered.
- **Fixed: history-derived plans omitted valid exercises.** The completed-movement query now filters completed sessions and groups distinct exercises in SQL before applying the requested limit.
- **Disclosed: reducing days discards historical plan associations.** Completed weights and reps are retained, but the confirmation now states that sessions tied to removed days no longer contribute to that plan's rotation history.
- **Potential UI blocking needs measurement.** `SplitPlannerScreen.redistribute` and `startFromHistory` perform attribution reads, plan calculation and writes through a synchronous UI callback. App initialization also opens/migrates the database synchronously. These are profiling targets, not measured latency claims.

## Fresh verification

- `./test.sh` after the repairs: exit 0; 769 tests in the main run plus five isolated tests, **774 total**, all passed. Log: `/tmp/hardset-plan-tests-20260908.log`.
- Installed toolchain: Xcode 26.4. Apple's current upload minimum is Xcode 26 with an iOS 26 SDK or later.
- App/widget Info.plist, entitlements and privacy manifest pass `plutil -lint`; `git diff --check` passes. These checks validate syntax/whitespace, not privacy accuracy or signing.
- An unsigned generic iOS Simulator Release build completed successfully with Xcode 26.4. Log: `/tmp/hardset-plan-release-build-20260908.log`. This does not validate distribution signing, entitlements, production CloudKit or App Store upload.
- The planner-to-workout UI flow and cold-launch measurement both passed on the iPhone 17 Pro / iOS 26.4 simulator. The five responsive-first-frame launch samples were 2.18, 2.51, 1.89, 2.21 and 1.71 seconds (about 2.10 seconds average). This used the UI-test ephemeral database and is not a large-history or physical-device performance result. Result bundle: `/tmp/HardsetPlanVerification/Logs/Test/Test-Hardset-2026.09.08_21-57-53--0400.xcresult`.
- Package tests do not prove touch responsiveness, haptic feel, AlarmKit background delivery, production sync or App Store acceptance.
- The existing launch UI test uses an ephemeral test database. It is not a representative benchmark of years of retained training history.

## Required acceptance pass

Before submission: validate a signed Release archive; run the UI suite; profile launch, exercise search, set logging/undo and history scrolling with a large synthetic history on supported hardware; test offline and Low Power Mode; check VoiceOver, large Dynamic Type and Reduce Motion; physically verify alarm denial/background/lock-screen behavior and haptic feedback; verify production sync and deletion across devices if sync ships.

Proposed product targets (not Apple rules or measured results): common taps visibly respond within 100 ms, no duplicate sets on rapid taps, no dependency on network availability for logging, and no lost completed sets after interruption. Establish device-specific launch and scrolling budgets with Instruments.

App Store Connect account status, public links, metadata, screenshots, age-rating answers, privacy answers, distribution territories and review contact information remain unverified. Only Apple can decide approval.

## Current official references

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/news/upcoming-requirements/
