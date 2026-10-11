# Mac verification ledger

Development happens on Linux, where only HardsetCore and HardsetStore (sync excluded) compile.
Everything else is written blind. Every commit that touches code the Linux harness cannot build
adds an entry here: what to build or run on the Mac, and what must be true. Same rule as
`DEVICE-CHECKLIST.md`: an unchecked box is not "probably fine".

How to run: pull the branch on the Mac, then `./test.sh` (full suite, including sync) and build
the `Hardset` scheme for the iOS 26.4 simulator.

## Phase 0

- [ ] `./test.sh` passes on the Mac. Proves the `#if canImport(CloudKit)` guards and the
      `Configuration.forTesting()` helper changed nothing on Darwin. The sync suites must still
      run there.
- [ ] `Hardset.xcodeproj` opens and the app builds after the manifest became conditional.
      Expected: no change, since `os(Linux)` is false on macOS.
- [ ] After the generator re-baseline, Xcode still resolves the `HardsetFeature` package product
      for the app target. Only its object IDs changed.

## Phase 1

- [ ] (feat(core): one weight formatter, so pounds mode stops reading kilograms) HardsetUI builds
      with ProgressionChartView calling `explanation(in:)`.

## Phase 1

- [ ] (feat(store): remember each exercise's rest…) HardsetFeature and the app build after the
      restAfterSet → restPreferences rename.
- [ ] (fix(ui): a set row shows what it saves, and a logged row stays locked) HardsetUI builds with
      `SetRowView` using `.onChange(of: draft)`, `.accessibilityActions` and `WeightFormatter`.
      In the iOS 26.4 simulator, with a session that has a prefilled row:
  - [ ] Change machine on that row. The field shows the new machine's prefill, and logging saves
        that number (confirm in history), not the old one.
  - [ ] Open the weight pad and type. Digits are never overwritten mid-keystroke.
  - [ ] Log a set. Tapping its weight and reps fields does nothing, and VoiceOver offers no
        "Edit weight" or "Edit reps" action on it. Its values stay legible: a disabled plain
        button may dim them, and if they read too faint, replace `.disabled(isLogged)` with a
        hit-test guard.
  - [ ] Type a weight, leave the pad open, then tap the row's check mark. The pad closes.
  - [ ] VoiceOver on a row says "kilograms" ("pounds" in pounds mode), never "kg" or "lb". The
        "Last time" caption reads "60 kg × 8" in kilograms mode and "132.28 lb × 8" in pounds mode.
        A logged row has no hint. A 62.25 kg set reads 62.25, not 62.3 (the old formatter
        rounded to one decimal).
  - [ ] Known residual: change machine while the pad is still open. The field keeps what was typed
        (reseeding is skipped while editing), so note whether the pad can be left showing a
        value other than the draft that logging will save.
- [ ] (fix(ui): weights and counts read in the chosen unit, and "This week" says "Last 7 days")
      HardsetUI and HardsetFeature build with `MachinePickerView(unit:)` (no default, so the
      `LiveSessionScreen` call site and the preview must both pass it),
      `SessionView.describe(_:unit:)` using `WeightFormatter`, `CountText` and `StrengthMath`, and
      `HistoryView.volumeText`. In the iOS 26.4 simulator with Settings set to lb:
  - [ ] Log a set that earns each record kind. The PR banner reads in lb: "N lb, up from M lb",
        "N reps at W lb, up from P", and for an estimated 1RM "about X lb, up from about Y lb"
        (the new estimate is now stated; lb rounds to a whole pound, kg to 0.5 kg).
  - [ ] Open the machine picker from a machine chip. A machine with a known stack step reads
        "moves in N lb steps" (a 10 kg stack shows as 22.05 lb), and the chip on the session
        screen reads "· N lb steps". Nothing on the session screen says "kg" in lb mode.
  - [ ] The session footer reads "1 set · 1 rep · N lb volume" with the right plurals, and a
        History row reads "1 set · N reps · W lb" (never "1 sets"). Volumes are whole numbers in
        the chosen unit ("20723 lb", "9400 kg"), never "20723.45 lb".
  - [ ] Weekly volume screen: the empty state ("Nothing logged in the last 7 days"), the header
        ("N working sets in the last 7 days") and both captions say "the last 7 days". Known
        residual outside this task's files: the tab's navigation title (`HardsetRootView`) and
        the error label in `WeeklyVolumeScreen` still say "this week".
- [ ] (feat(ui): a rest chip per exercise, with presets, a custom time and Off) HardsetUI builds
      with `ExerciseSectionView(restChoice:onChooseRest:onStartRest:)` and
      `SessionView(restChoices:onChooseRest:onStartRest:)`. The new inputs all default, so
      `LiveSessionScreen` is unchanged and must still compile; nothing passes them until Task 11,
      so on the shipped screen the chip is hidden. New APIs: `Menu`, `ViewThatFits`,
      `accessibilityAddTraits(.isSelected)`, `labelsHidden()`, `sheet(isPresented:)`, and a `Picker`
      with `.pickerStyle(.wheel)` behind `#if os(iOS)`. Also run the macOS host build, because
      `.wheel` does not exist there. Check in the Xcode previews first ("Exercise section" and
      "Live session" both pass the rest inputs), then in the iOS 26.4 simulator once Task 11 is in:
  - [ ] A fresh exercise's chip reads "Rest · Off", in the same font, colour and 44 pt height as
        the machine chip. Open it: 1:00, 1:30, 2:00, 3:00, 4:00, 5:00 and "Custom…", and no check
        mark on any of them. "Off" and "Start rest now" are absent.
  - [ ] Choose 2:00. The chip reads "Rest · 2:00" in the accent colour. Reopen it: 2:00 has a
        check mark and the others do not, and "Off" and "Start rest now" (below a divider) appear.
        The check mark must be drawn by `Label(systemImage: "checkmark")` inside a menu `Button`;
        if the menu draws it oddly or not at all, fall back to a `Picker` with `.pickerStyle(.inline)`
        and tags wrapped in `Optional`, and confirm nothing is selected while the choice is nil.
  - [ ] "Custom…" opens a sheet with minutes and seconds wheels, at 0:00 with "Set" disabled on a
        fresh exercise, and at the current rest otherwise. The two wheels scroll independently
        (known SwiftUI hazard: wheel pickers in an `HStack` can overlap each other's touch area;
        if so, add `.compositingGroup().clipped()` to each). 0:10 and 30:30 leave "Set" disabled;
        0:15, 2:15 and 30:00 enable it. Confirming 2:15 makes the chip read "Rest · 2:15" and no
        preset is checked. Cancel changes nothing. The "Between 0:15 and 30:00." note is always
        visible.
  - [ ] Choose "Off". The chip reads "Rest · Off" again, no preset is checked, and "Start rest now"
        is gone.
  - [ ] VoiceOver on the chip reads "Rest after each set, off" or "..., 2:00" (never "Rest · Off").
        Inside the open menu the checked preset is announced as selected; if it is not, the chip's
        own label still carries the current value, so note it as a known gap.
  - [ ] With a long machine name, or at the largest Dynamic Type size, the machine chip and rest
        chip stack vertically instead of truncating. With no gym (no machine chip) the rest chip
        shows alone. With the custom sheet open, rotating the device does not dismiss it.
  - [ ] Once Task 11 wires it: choosing 2:00 then logging a working set starts a 2:00 rest and the
        bar shows "Exercise · Set N of M" (`RestBarView` already renders `RestMetadata`, so this
        needed no change). A warm-up starts nothing. "Start rest now" starts the chosen rest.
        Relaunching the app keeps the chip at 2:00.
- [ ] (fix(ui): root and screens surface real failures instead of swallowing them) HardsetFeature
      builds with `HardsetRootView` (do/catch resume and seed, `resumeFailedView`, `catalogueNotice`
      via `.safeAreaInset(edge: .top, spacing: 0)`), and `WeeklyVolumeScreen` / `HistoryScreen`
      using `ContentUnavailableView(label:description:actions:)`. In the iOS 26.4 simulator, with
      the database made unreadable (or a forced throw in a debug build):
  - [ ] Resume failure: the Train tab shows "Workout unavailable" with the resume copy and a
        working "Try again". "No workout in progress", the gym row and "Start workout" are all
        absent while it shows. Fixing the cause and tapping Try again shows the workout or, if
        none is open, the normal start screen.
  - [ ] Seed failure: a notice with the catalogue copy and "Try again" sits under the nav bar on
        the start screen AND over a live session, and disappears after a successful retry. With
        no failure it takes no space. Check it does not overlap the nav bar or the set grid.
  - [ ] A failing gym save reads "That gym could not be saved. Try again." with no error text.
  - [ ] Volume and History each show their copy and a Try again button that actually reloads. The
        button must look like a button and be at least 44 pt tall inside the system's
        `ContentUnavailableView` action styling; if not, add `.buttonStyle(.bordered)`.
  - [ ] The Volume tab is titled "Last 7 days". No screen says "this week".
  - [ ] Methodology badge: reads Low when only counted (non-modelled) muscles were trained,
        Moderate when a modelled muscle is credited, and is hidden when nothing is credited.
- [ ] (feat(feature): wire rest choices, alarm state and failure copy into the live workout)
      Build the `Hardset` scheme for the iOS 26.4 simulator, and HardsetFeature for macOS (the
      Settings button is behind `#if canImport(UIKit)`), with no new warnings. None of the three
      Swift files has been compiled. On Linux they passed `swiftc -parse`, and the app's wiring
      type-checked, with `-warnings-as-errors`, against stub modules that copy the real
      signatures. Confirm:
  - [ ] `extension RestTimerStore: @retroactive RestTimerPersistence {}` (end of `HardsetApp.swift`)
        compiles with no warning and no isolation diagnostic. The protocol is `@MainActor`, and the
        store's methods are `nonisolated`.
  - [ ] `HardsetApp.init()` now takes the opened database back from `prepareDependencies` and
        builds `RestTimerController(persistence: RestTimerStore(database:))` from it. If the
        database fails to open, the controller gets no store, so the timer still runs but is not
        written down.
  - [ ] `HardsetTests` builds and passes. It now imports `HardsetFeature`, `HardsetStore` and
        `SQLiteData` (for `DatabaseQueue`), but the target declares only the `HardsetCore` product
        in `project.pbxproj`. That works only if the host app's build leaves those modules where
        the test can find them and `BUNDLE_LOADER` provides the symbols, which is how the app
        target already imports `SQLiteData`. If you get "no such module" or undefined symbols, add
        `HardsetFeature` and `HardsetStore` to the HardsetTests target's package products, then
        check that the test run does not print "Class … is implemented in both" warnings.
  Then in the simulator, and on device for the alarm items:
  - [ ] Choose 2:00 on an exercise and log a working set. The rest bar starts at 2:00 and its
        caption reads "Exercise · Set N of M". "Start rest now" on the chip starts the chosen rest
        with a caption too. A warm-up starts nothing.
  - [ ] Skip clears the bar and its caption. The next rest's caption names the new set, not the
        old one.
  - [ ] Relaunch: the chip still reads 2:00 (`UserDefaultsRestPreferences`). Force-quit during a
        rest, relaunch: the same countdown is back (launch `.task` runs `reconcile()`).
  - [ ] Deny alarm permission, then start a rest. The line "Alarms are off for Hardset, so rest
        won't sound when the phone is locked." and a "Settings" button appear in one panel with the
        rest bar, on the same background. The line sits directly BELOW the bar, not above it as the
        brief said: `SessionView` owns the bar's inset, and an inset added by `LiveSessionScreen`
        is laid out beneath it. If it must go above, that is a `SessionView` input (HardsetUI),
        outside this task. "Settings" is at least 44 pt tall and opens Hardset's page in the
        Settings app. The panel goes when the rest ends or is skipped. With alarms allowed it never
        appears.
  - [ ] An alarm failure (forced throw in a debug build) shows "The rest alarm could not be set.
        The countdown on screen still runs." in that panel, only while the rest runs. With alarms
        denied and a failure at once, both lines show. No error text ever appears.
  - [ ] Alarms denied, notifications allowed, app in front at the deadline: the rest notification
        shows as a banner with sound. That proves `RestNotificationPresenter` is installed in
        time. Apple's `delegate` page asks for it before launch finishes
        (`application(_:willFinishLaunchingWithOptions:)` or `…didFinishLaunching…`), and does not
        say when `App.init()` runs relative to those. If no banner shows, move the assignment into
        an `@UIApplicationDelegateAdaptor` delegate's `application(_:willFinishLaunchingWithOptions:)`.
  - [ ] Force a machine save failure (debug throw in `GymStore.createMachine`). The picker stays
        open and its footer reads "That machine could not be saved. Try again." Closing and
        reopening the picker clears it, and so does a successful add.
  - [ ] Set the clock to before the workout started and tap Finish: "…Check your device's date
        and time, then try again." Any other finish failure (forced) reads "…Your sets are saved.
        Try again." with no clock advice. A failed set reads "That set could not be saved. It has
        not been logged — tap to try again." `LiveSessionScreen` no longer has its own
        `LoggerStoreError` switch (see the Phase 2 Task 6 note below), so all of this copy comes
        from `FailureCopy`.

## Phase 2

- Task 6 (`LiveSessionScreen.errorMessage`): the exhaustive `LoggerStoreError` switch gained
  `.setNotFound, .sessionNotEmpty, .sessionNotOpen` falling to the generic message. HardsetFeature
  does not compile on Linux, so confirm it builds on the Mac.
- [ ] (feat(alarm): reconcile and persist the rest timer; ask at the first rest) Build HardsetAlarm
      for iOS (`Hardset` scheme, iOS 26.4 simulator) with no new warnings. It has never been
      compiled against the SDK. It was written from Apple's documentation and compiled here only
      against stub modules built from that documentation (URLs in the commit body). Confirm:
  - [ ] `AlarmPresentation.Alert(title:)` resolves to the 26.1
        `init(title:secondaryButton:secondaryButtonBehavior:)`, with no deprecation warning.
  - [ ] `for await _ in RestAlarmService.alarmUpdates()` on the main actor raises no Sendable or
        isolation diagnostic (`AlarmManager.AlarmUpdates` is not documented as `Sendable`).
  - [ ] `RestNotificationFallback` raises no "sending … risks causing data races" diagnostic. The
        UserNotifications classes are not documented as `Sendable` either.
  - [ ] The `@unknown default` cases over `Alarm.State` and `AlarmManager.AuthorizationState`
        compile, and so does `if case .fixed(let fireDate)? = alarm.schedule`.
  - [ ] Task 11 conforms the store in the app target as
        `extension RestTimerStore: @retroactive RestTimerPersistence {}`. Without `@retroactive`,
        Swift warns, because the app target is outside the package.
  - [ ] (fix(alarm): stop the old alarm when a rest is cut to zero…) `RestNotificationPresenter`
        compiles with no "nearly matches optional requirement" warning. Its method must be the
        documented `userNotificationCenter(_:willPresent:withCompletionHandler:)` with an
        `@escaping @Sendable` handler; a near-miss signature compiles and is never called. Task 11
        keeps one alive in the app and sets `UNUserNotificationCenter.current().delegate` to it
        before launch finishes (the property is `weak`).
  Then on device:
  - [ ] Start a rest, force-quit, relaunch: the app shows the same countdown.
  - [ ] (fix(alarm): no system pause on the Lock Screen…) The Lock Screen countdown offers no pause
        button. Pausing in the app shows paused on the Lock Screen and resumes correctly. Phase 4.1
        re-adds Lock Screen pause and resume as `LiveActivityIntent`s that run in the app.
  - [ ] Known residual until Phase 4.1: the paused Lock Screen view still has a Resume button,
        because `AlarmPresentation.Paused(title:resumeButton:)` requires one. Pause in the app,
        lock, tap Resume: expected, the rest ends on the next reconcile, because the resume time
        cannot be read (Task 2 ruling). Record what happens.
  - [ ] First rest ever: the permission prompt appears.
  - [ ] Deny it: the on-screen countdown still runs and the denial banner shows (with Task 11).
  - [ ] The alert has no button that does nothing.
  - [ ] Alarms denied: the notification prompt appears once. Allow it. The rest ends with a
        notification at the deadline; +15 s moves it; pause removes it; Skip removes it. Relaunch
        mid-rest: the countdown is still there. With the app open at the deadline, the rest bar
        goes away and the notification still arrives.
  - [ ] Alarms denied, app in front at the deadline: banner and sound appear (needs Task 11's
        delegate).
  - [ ] Start a rest with under 15 s left, tap −15 s: the bar goes away and nothing sounds at the
        old deadline. Check it with alarms allowed and with alarms denied.
  - [ ] Tap +15 s five times fast with the app in front. `AlarmManager.shared.alarms` holds exactly
        one alarm, and the rest never drops to idle.
  - [ ] Note whether `alarmUpdates` emits on pause and resume. The code works either way.
- [ ] (feat(ui): tokens v2 …) HardsetUI builds for iOS 26.4 simulator and, via `./test.sh`, for
      macOS. Then in the simulator:
  - [ ] Light mode: a card on the Volume tab is visibly separate from the background.
  - [ ] Settings › Accessibility › Display & Text Size › Increase Contrast on: the "Low confidence"
        badge text on the methodology sheet darkens (light) / lightens (dark).
  - [ ] The "at least this much" lower-bound note on the Volume tab reads as grey text with a
        glyph, not orange.
  - [ ] The machine-change rule on a progression chart is grey and dashed, not orange.
  - Written without a compiler. If the build fails, look first at `Tokens.adaptive`: it is
    `nonisolated` and calls only the `nonisolated` `Tokens.uiColor`; on macOS it switches over
    `NSAppearance.Name` (unwrapped with `?? .aqua`) using `.accessibilityHighContrastAqua` and
    `.accessibilityHighContrastDarkAqua`. The brief's `PaletteSwatch(light:…)` convenience init
    from `PaletteColor` was not added: a cross-module struct initialiser must delegate to a public
    one, and the only public one takes hex.
  - Increase Contrast is read through the `UIColor` provider's `accessibilityContrast` trait, not
    `@Environment(\.colorSchemeContrast)`. The badge check above is what proves SwiftUI passes the
    setting into the trait collection. If the badge does not change, that assumption is wrong.
  - [ ] Caveat text is legible and still reads as secondary. `Tokens.Color.caveat` is the
        palette's tested grey (`certaintyUnevaluated`), not the system `secondary`. Check the
        lower-bound note on the Volume tab, the no-estimate note and the machine-change rule on a
        progression chart. Do this in light and dark mode, and with Increase Contrast on. Each one
        should be comfortably readable, and should still sit visually below the primary text
        around it.

- [ ] (feat(ui): picker Recent and Cancel; repeat from history) HardsetUI builds. In the
      simulator, with Task 18/19 merged:
  - [ ] Add movement: the picker has Cancel, and with an empty search a "Recent" section listing
        the last movements logged, newest first. Typing hides it.
  - [ ] History: long-press a workout: "Repeat this workout". No row suggests it otherwise.
  - [ ] "Length unknown" in history is grey with its glyph, not orange.
  - [ ] History rows are no longer disabled buttons: with VoiceOver on, a row is not read as
        "dimmed"; with `onRepeat` set, the rotor's Actions lists "Repeat this workout".
  - Written without a compiler. Check first: `.toolbar { if let onCancel { ToolbarItem… } }` in
    `ExercisePickerView` (conditional toolbar content), and `Button(_:systemImage:action:)` and
    `.accessibilityAction(named: Text(…))` in `HistoryView`. The picker still compiles for
    existing callers (new inputs default); Cancel appears only once Task 18 passes `onCancel`.
- [ ] (feat(ui): one rest cluster …) HardsetUI builds (iOS, and macOS 15 via `./test.sh`). With
      Task 19 merged, on the simulator:
  - [ ] During a rest, the countdown appears once: in the tab accessory, never also in the
        Train screen.
  - [ ] Scroll the set list down: the tab bar collapses and the accessory shows only the
        countdown and pause; scroll up: −15 / +15 / skip return.
  - [ ] ±15 plays a selection haptic (device) and the paused remainder rolls (off with Reduce
        Motion).
  - [ ] All accessory buttons are at least 44 pt (Accessibility Inspector).
  - [ ] VoiceOver reaches the countdown, −15, +15, pause/resume and skip as separate elements
        (the old `.combine` hid the buttons). The countdown reads "Resting, m:ss remaining …"
        and, with `onOpen` set, adds the hint "Opens the workout".
  - [ ] Written without a compiler. If it fails, look first at `@Environment(\.tabViewBottomAccessoryPlacement)`
        (inside `#if os(iOS)`), `.background { if !inAccessory { … } }`, and `readout`, which
        is a plain view, not a disabled Button, when `onOpen` is nil (a disabled plain Button
        dims the countdown).
- [ ] (feat(ui): a summary at the end of a workout, and nothing to live up to) HardsetUI builds
      (iOS, and macOS 15 via `./test.sh`); the three `#Preview`s (Summary, Loading, Error) render.
      With Task 19 merged:
  - [ ] Finish a workout with a record: the sheet lists the record, the muscles (with ≥ when a
        custom movement was logged), the machines, and the length.
  - [ ] A workout left open overnight and finished shows "Length unknown" (grey, with its glyph),
        not 20 hours.
  - [ ] Pounds mode: every weight in the sheet is in lb.
  - [ ] VoiceOver reads "Chest, at least 6 sets", not "greater than or equal to"; each record is
        one element with units spelled out.
  - [ ] There is no goal, target or streak anywhere on it. Done is in the toolbar.
  - [ ] Written without a compiler. If it fails, look first at `ContentUnavailableView { } description: { }
        actions: { }` with a conditional `Button`, the `let name` inside `ForEach` in
        `musclesSection`, the `Section { } header: { } footer: { }` with a conditional footer,
        and `Text(_:format: .dateTime…)`. The title is a large title; if it crowds on iPhone,
        add `.navigationBarTitleDisplayMode(.inline)` under `#if os(iOS)`.

- [ ] (fix(ui): secondary text meets 4.5:1) Secondary text (captions, labels, prior-performance
      notes; `Tokens.Color.textSecondary`, now the palette's `secondaryText`) is legible in
      light, dark and with Increase Contrast on, and still reads as secondary, visibly quieter
      than the primary text beside it.
