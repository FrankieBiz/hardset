# Front-end rebuild, Phase 4: Onboarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (built inline in one checkout; the pieces share a pager, a model and an environment flag, so parallel worktrees would cost more than they save).

**Goal:** A first launch the lifter remembers and can skip: the Welcome bar they load with plates, three live Pitch pages, a guided Tour over staged real screens, and a Setup page, gated once by `hardset.onboardingVersion` and replayable from Settings.

**Architecture:** Stateless visuals live in HardsetUI (`ClankPlayer`, `PlateTray`, `WelcomeBarView`, `PitchPage` and its three demos, `DemoRestTimer`, `SpotlightOverlay`, `CalloutCard`, the `tourTarget` anchor modifier, `TourStaging`). Everything that touches stores lives in HardsetFeature (`OnboardingModel`, `SetupPage`, `TourStage`, `OnboardingFlow`, `HardsetLaunchView`). The Tour renders the real `HardsetRootView` from `TourFixtures` inside `ScaledPhoneFrame` (Phase 3); steps that need a state a lifter reaches by tapping (a tab, the keypad, the machine picker, Settings) get it through a `TourStaging` environment value the real screens read, never a fake screen. The app target stays a thin shell: its `RootView` calls `HardsetLaunchView`.

**Spec:** `docs/superpowers/specs/2026-11-12-frontend-rebuild-design.md` ("First launch", Screens 1 to 6, "Haptics"). **Settled decisions, traps and process:** `.agents/HANDOFF.md` (Phases 1 to 3) and `.agents/handoffs/phase-2.md`; the Phase 2 and 3 plans' Global Constraints all still apply and are not repeated, plus:

## Global Constraints

- Motion in the daily app is unchanged. Onboarding is the one deliberate exception: larger, physical motion is allowed, every sequence is interruptible by a tap or swipe, nothing loops faster than once per three seconds, there is no full-screen parallax, and Reduce Motion gets a still version with cross-fades. Every animation still goes through `Tokens.Motion.adaptive`; any new motion value is a token already in `DESIGN.md` (`fling`, `state`, `reveal`, `stamp`).
- No new colour, type, radius, spacing or motion token. Plate colours are the existing `plateRed`, `plateBlue`, `plateYellow`, `plateGreen` and `chalk` (the 5 kg "white" plate), with the stamp in `canvas` so it clears the plate fill in both appearances.
- `clank` becomes a CoreHaptics pattern (a sharp transient at intensity 1.0 and sharpness 0.6, then a 40 ms low rumble) with the heavy system impact kept as the fallback where CoreHaptics is unavailable. The log stamp plays `clank` then `success` in the Pitch demo only; the daily app's log tap keeps `success` alone until Phase 5 (R13).
- The pitch demos use the real kit components and the engine's own rules; nothing the lifter sees is typed in as a result (Pitch 2's figure and badge come from `StrengthMath`).
- Existing UI journeys keep passing: they launch past onboarding with the `-hardset.onboardingVersion` launch argument; one new journey drives onboarding from a fresh install.
- Accessibility: every page is navigable and completable with VoiceOver, Reduce Motion and the largest Dynamic Type; "Skip" is a visible control from the second page on; the Welcome bar has an equivalent, non-drag way to load a plate (a tap) and a spoken description of what is loaded.

## Rulings

| Id | Decision |
| --- | --- |
| R49 | The tour's states come from a `TourStaging` environment value (initial tab, open keypad, open machine picker, show settings) read by the real screens; a step never shows a picture or a lookalike. |
| R50 | Receipt is not staged (R46); the History step shows the History tab and its callout says what a receipt is. |
| R51 | Replay is a full-screen cover hosting the same flow in replay mode, so Settings does not restart the app or touch `hardset.onboardingVersion`; finishing a replay just dismisses it. |
| R52 | The Welcome bar's bend is a spring on `Motion.state` driven by the loaded mass, not a `keyframeAnimator`: a critically damped settle is the spec's intent and the keyframe form adds nothing the spring does not. |
| R53 | No per-task review agents (R48 stands); one whole-branch review of the Phase 4 diff before delivery. |
| R54 | A system sheet presents over the whole window, so the tour's keypad, machine picker and Settings cannot be real sheets inside a scaled phone. `stagedSheet` draws them inline when `TourStaging.presentsSheetsInline` is set; the content is the real content and only the surface is the tour's. The three presenting screens call it in place of `sheet`, which is unchanged outside the tour. |
| R55 | Targets report their window rectangles into a `TourTargets` registry through `onGeometryChange(.global)`, not a preference: a tab view and navigation stack can host their content across a UIKit boundary that a preference does not cross. The stage converts to the phone's space with the phone's own measured frame, so the scale cancels. |
| R56 | Tour step one's line differs from the spec: the start screen has no "repeat last workout" action, so it says what is there ("One tap starts a workout. Your last one is right below it."). |
| R57 | A replay runs the same pages without Setup and ends at the tour's end; skipping a replay ends it. |
| R58 | UI-test onboarding state is set by a DEBUG-only `HARDSET_ONBOARDING` environment variable ("skip" or "reset") read in `HardsetApp.init`, not a launch argument: an argument shadows the stored value, so the app's own write on finishing would never be read back. |

## Review Focus

1. **A lifter who cannot finish onboarding.** Pager swipes versus the bar's drag, Reduce Motion, VoiceOver and the largest type must all reach Setup and "Start logging". Pinned by the UI journey and the model tests.
2. **Existing installs.** A lifter with history and a stored unit sees onboarding once; Setup pre-selects their unit and lists their gyms as selection rows, so nothing is duplicated. Pinned by the model tests against a populated environment.
3. **Skipping loses nothing.** Skip from any page lands on Setup. Pinned by the model tests.
4. **The fixtures lie.** The Pitch demos and tour must not show a result the engine did not produce. Pinned by Pitch 2 reading `StrengthMath` and the tour reading `TourFixtures`.
5. **A tour that wanders.** Non-interactive steps leave the staged phone inert; only step 2 is interactive and "Next" stays hidden until the check is tapped. Pinned by the model tests and the UI journey.

---

### Task 1: Haptic, tray and Welcome bar (HardsetUI)

**Files:** Create `ClankPlayer.swift`, `PlateTray.swift`, `WelcomeBarView.swift`; modify `DESIGN.md` (haptics and the Welcome components); add `WelcomeSnapshotTests.swift`.

**Interfaces:** `ClankPlayer` (`@MainActor`, `play()`, CoreHaptics with fallback). `PlateTray` and a public `Plate` (25, 20, 15, 10, 5 kg with plate colour). `WelcomeBarView(unit:isLoaded:onLoadedChange:)` (loaded plates, total in `hero` with `unit`, auto-load of one 20 per side after four idle seconds, interruptible, Reduce Motion loaded at start, tap and drag both load, a loaded plate returns on tap or drag down, VoiceOver label of the loaded mass).

- [ ] Implement the three files, `DESIGN.md`, and captures: the bar empty, loaded with 20s, loaded with several plates, in dark, light and Reduce-Motion-equivalent still, and the tray at accessibility3. Commit `Add the plate tray and the Welcome bar`.

### Task 2: Pitch pages and the demo rest timer (HardsetUI)

**Files:** Create `PitchPage.swift`, `PitchDemos.swift`, `DemoRestTimer.swift`, `PitchSnapshotTests.swift`.

**Interfaces:** `PitchPage(title:lines:element:)`. `PitchSetRowDemo` (the real `SetRowView` for "Chest press" prefilled 60 kg for 10; logging plays `clank` then `success`, settles on `plateGreenSurface`, and shows a second row with the next prefill). `PitchEstimateDemo(unit:)` (a `readout` figure from `StrengthMath.estimatedOneRepMax(weightKg: 60, reps:)`, a live `CertaintyBadge`, a four-segment `HardsetSegmentedControl` of 3, 8, 12 and 15 reps walking high, moderate, low, unevaluated, and the engine's own provenance line). `PitchRestDemo` (the real `RestBarView` counting down from 90 seconds with live -15, +15, pause and skip giving `selection` haptics) over `DemoRestTimer` (`@Observable`, idle, running and paused states through `RestTimerState`, no AlarmKit).

- [ ] Implement, with captures of each page in dark and light and at accessibility3 for the copy, and a test (unwrapped Swift Testing) that the four Pitch 2 segments produce the four certainty levels from `StrengthMath`. Commit `Add the pitch pages and their live demos`.

### Task 3: Model, Setup, pager and launch gating (HardsetFeature, app target)

**Files:** Create `OnboardingModel.swift`, `SetupPage.swift`, `OnboardingFlow.swift`, `HardsetLaunchView.swift`, `OnboardingModelTests.swift`; modify `HardsetRootView.swift` (an optional `onShowTour` closure forwarded to Settings), `SettingsSheet.swift` ("Show the tour again"), `Hardset/HardsetApp.swift` (call `HardsetLaunchView`), `HardsetUITests/AppScreensUITests.swift` (launch past onboarding).

**Interfaces:** `OnboardingModel` (`@Observable`): `Page` (welcome, pitch one to three, tour, setup), `index`, `next()`, `skip()` (always to setup, never from welcome), `canSkip`, tour step and its interaction gate, `finish(...)` saving the unit and the gym through the existing stores. `HardsetLaunchView(environment:unit:hooks:restAfterSet:)` gates on `@AppStorage("hardset.onboardingVersion")` against `OnboardingVersion.current` and cross-fades to the root. `SetupPage`: unit `SelectionRow`s preselected from the locale guess or the stored value, existing gyms as selection rows, otherwise a name field from `hardsetNameInput()`, "Start logging".

- [ ] Write `OnboardingModelTests` first (skip lands on setup from every page but welcome; welcome has no skip; the tour's step 2 hides Next until the check is tapped; an existing install's setup lists its gyms and stored unit and creates no duplicate; finishing sets the version and saves choices). Implement, then commit `Add the onboarding model, Setup and launch gating`.

### Task 4: Tour (HardsetUI, HardsetFeature)

**Files:** Create `SpotlightOverlay.swift`, `CalloutCard.swift`, `TourTarget.swift`, `TourStaging.swift` (HardsetUI), `TourStage.swift` (HardsetFeature); modify `HardsetRootView.swift`, `LiveSessionScreen.swift`, `SetRowView.swift` (anchor tags and staging reads, no behaviour change outside the tour).

**Interfaces:** `View.tourTarget(_:)` publishing an anchor; `TourStaging` environment value; `SpotlightOverlay` (a `canvas` scrim at 70% with a rounded hole moving on `Motion.state`); `CalloutCard` on glass (`#if os(iOS)`); `TourStage` with the eight steps from the spec, the "n of 8" counter in `caption`, "Next" and "Skip tour", the staged phone inert except step 2.

- [ ] Implement and capture each step framed (the renderer cannot draw glass; the callout is verified from the real-app screenshots). Commit `Add the guided tour over the staged screens`.

### Task 5: Onboarding UI journey and delivery

- [ ] Add `testOnboardingJourney` to `AppScreensUITests` (fresh install, load a plate, Start, through the pitches, the tour including logging the step-2 check, Setup, Start logging, the root appears) with the system-composited screenshots saved; run `make check`; push once; fix compile errors from the early step; review every new PNG and screenshot; one whole-branch review; fix in one commit; append the `.agents/HANDOFF.md` entry (`[skip ci]`); update the project memory.
