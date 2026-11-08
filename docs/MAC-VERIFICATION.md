# Mac verification: design-system pass

Linux can parse Swift and run the Core and Store suites, but it cannot compile SwiftUI, Charts,
WidgetKit, ActivityKit or AlarmKit. The `iOS build and screens` workflow
(`.github/workflows/ios-ui.yml`) now does that on a GitHub macOS runner with Xcode 26.6 for every
push to a `FrankieBiz/**` branch. It also renders every screen to PNG through
`HardsetUISnapshotTests` and uploads the images as the `hardset-ios-ui` artifact. What that run
has proven is ticked below; the rest still needs a Mac, a device, or both.

## 1. Build gates

- [x] The app and widget build for the iOS Simulator (`xcodebuild -project Hardset.xcodeproj
      -scheme Hardset -destination 'generic/platform=iOS Simulator' build`) under Swift 6 strict
      concurrency. Verified by CI run 42421852965, after fixing two errors the first run found
      (a GRDB `Configuration` shadowing `ButtonStyle.Configuration` in HardsetFeature, and a
      non-exhaustive `LoggerStoreError` switch).
- [x] `swift build` of `HardsetKit` for the macOS host succeeds, so iOS-only modifiers are
      correctly guarded. Same run.
- [x] The widget compiles, including `AlarmPresentationState.Mode.Countdown.totalCountdownDuration`.
- [x] The dynamic-colour providers, `onGeometryChange`, and the computed-`id` `Identifiable`
      types compile with no isolation errors.
- [ ] A signed build on a Mac with the real CloudKit and AlarmKit entitlements; CI builds unsigned.
- [x] The app target's own `HardsetTests` builds and executes: run
      [42431117598](https://github.com/FrankieBiz/hardset/actions/runs/42431117598)
      passed one test in one suite, plus14 screen-render tests. The smoke test constructs
      `HardsetApp` on MainActor instead of calling its private RootView. CI now runs
      this target and requires a nonzero passing Swift Testing count. Construction
      verifies app-target build/link behavior; it does not certify signed sync startup.

## 1a. The real app, driven on the simulator

`HardsetUITests` launches the real app in CI (signed to run locally, so the iCloud entitlements
are embedded), walks a lifter's journey and saves system-composited screenshots, Liquid Glass
included. It also runs Apple's `performAccessibilityAudit` on each screen. Verified there:

- [x] The tab bar, the workout accessory, and sheet toolbars render as system glass with the
      readout-cyan tint in both appearances, not stock blue.
- [x] The journey works end to end: add a gym, start a workout, add a movement, type weight and
      reps on one keypad that retargets in place, log the set, finish, and see it on the start
      screen, in history and in the weekly volume.
- [x] A crash found there is fixed: design-token colour providers inherited `MainActor`
      isolation and trapped (SIGTRAP) when UIKit resolved a colour off the main thread, which
      happened as the gym picker presented and as a workout's first exercise appeared.
- [x] Apple's audit reports no contrast, hit-region, element-description or trait issues on any
      audited screen. What it still reports is Dynamic Type scaling of navigation-bar titles and
      the system Done buttons (bars cap their text; titles carry the Large Content Viewer), the
      single-line search field, and the deliberately hidden set-row column header.

The package snapshot suite draws through Core Animation without an app host and cannot render
glass; use the real-app screenshots above for chrome.

## 2. Visual checks, per appearance

Run each in light, dark, light + Increase Contrast and dark + Increase Contrast.

- [ ] Every tab opens on its own expanded-type header; no stock navigation bar title is visible on
      Train, Volume or History, and scrolled content disappears under the status bar rather than
      colliding with the clock.
- [ ] Sheets (gym, movement, machine, settings, methodology, name entry, exercise history) show
      the expanded inline title and accent-coloured toolbar buttons, not system blue.
- [ ] Tab bar selection, toolbar buttons and alerts are readout cyan, not system blue
      (`AccentColor` asset updated, `.tint` applied at the root).
- [ ] Increase Contrast visibly switches backgrounds to pure black/white and strengthens borders
      live, without relaunching.
- [ ] Charts: each machine series has its own colour and point symbol; machine-change rules are
      2 pt dashed in warning orange.

## 3. Logger ergonomics

- [ ] Set row at default size: ordinal, last time, weight, reps and the log control fit on one
      line at 375 pt wide (iPhone SE) in pounds, e.g. "132.28", without truncating. By arithmetic
      the row needs 292 pt of the 319 pt available there; confirm nothing clips at the card edge.
- [ ] The column header ("Set, Last time, kg, Reps") sits over its columns.
- [ ] At accessibility text sizes the row stacks and labels itself; nothing truncates mid-number.
- [ ] Log control states read distinctly: incomplete (dashed, disabled), ready (outlined),
      next up (filled cyan), logged (success stamp with haptic). With Reduce Motion the stamp
      appears without the spring.
- [ ] Keypad sheet height matches its content (no clipped bottom row, no empty band); at large
      text sizes it scrolls. The set row behind it stays tappable.
- [ ] Rest bar: one line on wide phones, two lines on narrow ones; every control 56 pt; VoiceOver
      reads the countdown, then reaches each control separately.
- [ ] Finish workout asks once inline before closing the session.

## 4. Hit regions

With the Accessibility Inspector, tap near the edges of: certainty badges, the exercise-name
history button, machine chip, filter chips, segmented control segments, header icon button, quiet
buttons ("How sets are counted", "Warm-up"). Each must respond across its full 44 pt (56 pt in the
logger) region.

## 5. Physical device

Under bright gym lighting and in daylight, confirm the cyan accent, captions and certainty chips
remain legible at arm's length. The palette passes 7:1 numerically (`make check-contrast`); glare
is not something a ratio certifies.
