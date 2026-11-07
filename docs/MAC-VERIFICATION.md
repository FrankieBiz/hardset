# Mac verification: design-system pass

Linux can parse Swift and run the Core and Store suites, but it cannot compile SwiftUI, Charts,
WidgetKit, ActivityKit or AlarmKit, resolve dynamic colours, or measure hit regions. Everything in
this list is therefore unverified until it passes on a Mac with Xcode 26 and an iOS 26.1 simulator
or device. Nothing here has been compiled.

## 1. Build gates

- [ ] `xcodebuild -scheme Hardset -destination 'platform=iOS Simulator,name=iPhone 17' build`
      succeeds with zero errors and zero new warnings under Swift 6 strict concurrency.
- [ ] `swift build` of `HardsetKit` for macOS succeeds (HardsetUI and HardsetFeature must still
      build on the host; iOS-only modifiers are behind `#if os(iOS)`).
- [ ] The widget extension builds. `HardsetWidgetBundle.swift` reads
      `AlarmPresentationState.Mode.Countdown.totalCountdownDuration`; confirm that property exists
      on `Countdown` (it is already used on `Paused`). If it does not, drop the progress bar rather
      than computing the interval from `Date()`.
- [ ] `DesignTokens.swift`: the `UIColor` and `NSColor` dynamic providers call a `nonisolated`
      helper because HardsetUI defaults to `MainActor`; confirm no isolation diagnostics.
- [ ] `SetRowView.swift`: `onGeometryChange(for:of:action:)` measuring the keypad compiles in the
      Swift 6 language mode.
- [ ] Watch item, expected to pass: several HardsetUI value types satisfy `Identifiable` with a
      computed `id` under default `MainActor` isolation (`HardsetSegment`, `StatLedger.Item`,
      `SetRowField`, `NumericPad.Key`, `ExercisePickerView.MuscleSection`, `HistoryView.MonthGroup`,
      `ProgressionChartView.SeriesInput` and `PlottedSeries`). The same pattern compiled in the
      build recorded at `e5aff33`. If Xcode instead reports "main actor-isolated property 'id'
      cannot be used to satisfy nonisolated requirement", mark the type `nonisolated` (as
      `SettingsSheet`'s `Disclosure` already is); do not change the identities.

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
