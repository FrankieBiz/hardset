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
  - [ ] `HardsetTests` builds and passes. The target now declares the `HardsetCore`,
        `HardsetStore` and `HardsetFeature` products (`Tools/generate_project.py`). `SQLiteData`,
        imported for `DatabaseQueue`, stays implicit, as it is for the app target.
  Then in the simulator, and on device for the alarm items:
  - [ ] Choose 2:00 on an exercise and log a working set. The rest bar starts at 2:00 and its
        caption reads "Exercise · Set N of M". "Start rest now" on the chip starts the chosen rest
        with a caption too. A warm-up starts nothing.
  - [ ] Skip clears the bar and its caption. The next rest's caption names the new set, not the
        old one.
  - [ ] Relaunch: the chip still reads 2:00 (`UserDefaultsRestPreferences`). Force-quit during a
        rest, relaunch: the same countdown is back (launch `.task` runs `reconcile()`).
  - [ ] Deny alarm permission, then start a rest. The line "Alarms are off for Hardset, so rest
        won't sound when the phone is locked." and a "Settings" button appear. On iOS (after Phase
        2 Task 19 moved the bar into the tab accessory) the line sits at the bottom of the workout,
        directly above the accessory's rest bar, and under the keypad when the keypad is open; on
        macOS it sits directly below `SessionView`'s rest bar. Check it reads as belonging to the
        rest on iOS; if not, move it into `LiveSessionAccessory` (Phase 3 Task 16) only if the
        accessory has the height. "Settings" is at least 44 pt tall and opens Hardset's page in the
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
- [ ] (feat(ui): keypad v2 and the active set) HardsetUI builds (iOS 26.4 simulator, and macOS
      via `./test.sh`). In the simulator, kilograms, a prefilled 100 kg row, no machine:
  - [ ] Tap the weight, then +2.5: the row and the pad header read 102.5. Log it; history shows
        102.5 kg. (Two taps.)
  - [ ] Tap the weight, type 1 0 2 . 5: 102.5, with no deletes first. (Five keys after focus.)
  - [ ] On a machine with a 5 kg stack, ± moves 5. In pounds mode it moves 11.02 lb.
  - [ ] On an empty row, ± does nothing and the keys look disabled.
  - [ ] Next moves to reps with reps selected; typing replaces it; Done closes the pad.
  - [ ] Clear empties the field and the log button disables.
  - [ ] The active row's weight is the largest text on screen; logged rows are compact;
        upcoming rows are not dimmed.
  - [ ] iPhone SE, active row: kg 102.5 and lb 132.28 render with no ellipsis. "Last time" sits
        on its own line under the fields, and the reps field is only as wide as its digits.
  - [ ] After logging, the screen scrolls to the next set, which becomes active.
  - [ ] With the pad up, the active row is fully visible on iPhone SE (3rd gen) and 17 Pro Max,
        and at the largest Dynamic Type size.
  - [ ] Pounds mode, 60 kg prefill: change only the reps, log; the chart and history show 60 kg,
        not 60.0013.
  - [ ] Change machine with the pad open: the pad and row both show the new machine's prefill
        (Phase 1 residual closed).
  - [ ] Reduce Motion on: the pad appears without sliding; scrolling to the next set jumps.
  - [ ] Change the unit in Settings with the pad open, then come back: the pad and the row both
        read the new unit's number (the pad is rebuilt on a unit change, as the row's buffers
        used to be reseeded).
  - [ ] In a locale with a decimal comma (e.g. German): the step keys read "+2,5", the row and
        the pad header read "102,5", and VoiceOver reads the step key as "Add 2,5 kilograms",
        with the unit in words.
  - Known gap until Task 19 merges: on iOS the Train tab has no rest controls (±15 s, pause,
    skip). This task stops `SessionView` drawing the rest bar on iOS; Task 19 puts the cluster in
    the tab accessory. The macOS host build still draws the inline bar.
  - Written without a compiler. Settled in review, low risk:
    - `SessionView.keypadBinding`'s `Binding(get:set:)` closures follow a pattern that has
      already built (e5aff33).
    - `.transition(Tokens.Motion.edgeTransition(reduceMotion))` is the iOS 13
      `transition(_: AnyTransition)` overload (`view/transition(_:)-5h5h0`), not deprecated.
    - If the build fails anyway, look at the bottom inset's
      `else { #if !os(iOS) RestBarView(…) #endif }`, which is an empty branch on iOS.
  - Behaviour that could not be reasoned out without running it:
    - [ ] Focus scrolls with `scrollTo(_:anchor: .center)` in the same animated transaction that
          inserts the pad. If the row lands under the pad (the scroll used the viewport from
          before the pad), move the scroll to after the pad is laid out, e.g. into
          `.onChange(of: focus)`, and note which fix held.
    - [ ] Rows are nested inside the `LazyVStack`'s exercise sections. After a log whose next
          set is in another exercise, the screen scrolls to that section first, then to the set.
          Log the last set of an exercise when the next exercise is far off screen: the next set
          is centred. If only the section's top shows, the row scroll ran before the section was
          built; defer it.
    - [ ] At the largest Dynamic Type size the pad's `title2` keys grow. If the pad leaves no room
          for the active row on iPhone SE, cap the pad's Dynamic Type (not done here).
    - [ ] On a 375 pt phone the active row's weight gets about 140 pt, against about 90 for
          "102.5" in the hero size. At large Dynamic Type sizes it can still shrink, by up to
          0.6. Note the first size at which it truncates.
- [ ] (feat(ui): row moments …) HardsetUI and HardsetFeature build (iOS 26.4 simulator, and macOS
      15 via `./test.sh`). In the simulator, with history so a record is possible, and on device
      for haptics. Until Task 18 wires `recordsBySlot`, `feedback`, `pendingUndo` and the
      edit/delete/undo callbacks, only the build, the missing banner and the check-mark swap can be
      seen; the rest is checked once Task 18 is merged.
  - [ ] Log a set that beats last week: a trophy appears on that row and bounces once; one
        success haptic, no impact haptic with it. Log the next set: the trophy stays, and does
        not bounce again.
  - [ ] An ordinary log: one crisp impact haptic; the check mark swaps with a symbol transition.
  - [ ] VoiceOver on: a record announces "New record on <movement>. Heaviest weight: …
        kilograms, up from …". No "kg" is spoken.
  - [ ] Long-press a logged row: Edit and Delete. Edit opens the pad with "Not saved yet"; Save
        writes (history shows the new value). Close without saving: the row shows the old value.
  - [ ] Edit a record set down to below last week: its trophy disappears; no haptic.
  - [ ] Delete: the row disappears, the Undo bar slides up (glass), Undo within 5 s restores it
        in place with its trophy. Wait 5 s: the bar goes and Undo is gone.
  - [ ] Reduce Motion on: no bounce, no slide, no number roll; everything still updates.
  - [ ] There is no records banner above the exercises any more.
  - [ ] Long-press an unlogged row: no menu and no lift. The menu's content is empty there, and
        SwiftUI is expected to show nothing for an empty `contextMenu`; if it lifts an empty
        menu, apply the menu only to logged rows without changing the row's identity.
  - [ ] Long-press on a logged row's weight or reps (disabled buttons) opens the menu too, not
        only on the gaps.
  - [ ] Edit: the pad opens on weight with it selected; Next moves to reps; the key on reps
        reads "Save". On weight it reads "Next". On an unlogged row the reps key still reads
        "Done".
  - [ ] Edit, clear the reps, Save: the store refuses, the pad stays open with what was typed,
        the error shows above, and the saved row is unchanged.
  - [ ] Edit, type a new weight, then change the unit in Settings and come back: if the pad is
        still open, it keeps the typed correction (in the new unit) and still says "Not saved
        yet".
  - [ ] VoiceOver: a logged row offers the actions "Edit set" and "Delete set" (and no "Edit
        weight" / "Edit reps"). If SwiftUI also exposes the context menu's own items, there are
        two of each; note it, and drop one pair.
  - [ ] VoiceOver: a trophy row reads "…, logged, record: Heaviest weight: 105 kg, up from
        100 kg". If "kg" is read as letters here, Core needs a public spoken line (RecordCopy's
        `spokenDetail` is internal), which is a follow-up.
  - [ ] VoiceOver: deleting announces "<label>. Undo is available." 5 s is short to swipe to the
        button; note whether it is reachable in time.
  - [ ] Delete, then switch tabs and come back within 5 s: the bar may reappear for a fresh 5 s
        (its wait restarts with the view). Undo after the coordinator's window does nothing.
  - [ ] With the pad open, delete another row: the Undo bar sits above the pad, not under it.
  - [ ] Pounds mode: the record line under the row reads lb.
  - Written without a compiler. If it fails, look first at:
    - `UndoBarBackground`'s `if #available(iOS 26.0, macOS 26.0, *)` inside a `@ViewBuilder`
      `body(content:)`, and `glassEffect(.regular, in: .capsule)`.
    - `import Accessibility` in `SessionView.swift` (for `AccessibilityNotification`; Apple's
      sample imports only SwiftUI, so it can be dropped if it clashes).
    - `.sensoryFeedback(trigger: feedback) { feedback.map { … } }`, which must resolve to the
      `() -> SensoryFeedback?` overload, not the `(old, new)` one.
    - `.task(id: undo.id) { … try await Task.sleep(for: .seconds(5)) … }` calling
      `onExpireUndo` (same pattern as `LiveSessionScreen`'s `.task(id:)`).
  - Behaviour that could not be reasoned out without running it:
    - [ ] The trophy is always in the row, at zero width and invisible until the row has a
          record, so the bounce has a value change to play on. The bounce is triggered one update
          after the trophy appears (from `SessionView`'s `onChange(of: feedback)`). If it does not
          bounce, note it; if a zero-width trophy leaves a gap before the check, note it.
    - [ ] `symbolEffectsRemoved(reduceMotion)` sits inside `.symbolEffect(.bounce …)` because it
          removes inherited effects (Apple's example). Under Reduce Motion the trophy must not
          bounce; if it does, the order is wrong.
    - [ ] With a trophy, the check is no longer centred in its 56 pt column. At the largest
          Dynamic Type sizes the trophy and the check may overflow the column; note the size.
    - [ ] The lifted context-menu preview may have square corners (the row is clipped outside
          the menu). If so, add `.contentShape(.contextMenuPreview, RoundedRectangle(…))`.
    - [ ] A record announcement made while the screen scrolls to the next set is not cut off by
          VoiceOver's focus change. If it is, post it with a high
          `accessibilitySpeechAnnouncementPriority` (Apple's example on the Announcement page).

- [ ] (feat(feature): one tab identity, the rest accessory, glass Start, the summary, repeat)
      HardsetFeature and the app build for the iOS 26.4 simulator, and HardsetFeature for macOS 15
      via `./test.sh`. In the simulator:
  - [ ] Start a workout on Train and start a rest from a chip, then switch to History: the
        accessory shows the countdown with −15 / +15 / pause / skip; tap its countdown: the app
        returns to Train.
  - [ ] Task 13's known gap is closed: during a rest on iOS the Train tab has ±15 s, pause and
        skip, in the accessory, and the countdown is drawn once (not also in the screen).
  - [ ] With no rest running, the accessory reads "1 set logged" (inflected); tapping anywhere on
        the pill, not only its words, returns to Train. VoiceOver reads "Workout in progress, 1
        set logged" with the hint "Opens the workout".
  - [ ] Start and finish a workout: the tabs keep their navigation state (no identity reset),
        and no empty pill shows above the tab bar on the start screen.
  - [ ] After finishing, open History and Volume: the new workout is there. The TabView is no
        longer rebuilt on finish, so this relies on each tab's `.task` re-running when the tab
        reappears. If it does not, reload on `selectedTab` change.
  - [ ] Start workout is a prominent glass button; no set row or card is glass. Note its height:
        the label's 56 pt minimum sits inside the style's own padding. The macOS 15 host build
        keeps the plain button.
  - [ ] Finish a workout: the summary sheet appears over whichever tab is showing; Done
        dismisses it. Force a read failure (debug): "Your workout is saved, but its summary
        could not be read." with Try again.
  - [ ] Finish through the unlogged dialog's "Finish workout" too: the summary still appears. A
        sheet asked for while the confirmation dialog is dismissing can be dropped; if it is,
        set `summaryTarget` once the dialog has gone.
  - [ ] Finish with nothing logged and Discard: no summary, straight back to the start screen.
  - [ ] History › long-press › Repeat this workout: a session starts on Train with the same
        movements and machines, prefilled from the latest history (not the repeated loads).
        With a workout already open, the action is absent.
  - [ ] With "Workout unavailable" showing on Train (force a resume failure), History offers no
        Repeat either: starting one then would put a second workout on top of the unread one.
  - [ ] Force `repeatPlan` to throw (debug): the app goes to Train, which reads "Could not
        start a workout. Nothing has been lost — try again." in the critical colour.
  - [ ] Known limit, from the brief: Repeat on a history workout with no logged sets does
        nothing (an empty plan starts nothing). Note whether such rows exist in real data; if
        they do, the action needs either hiding per row (a HardsetUI change) or a stated reason.
  - [ ] The long-press works anywhere on a History row, including the gaps between its lines.
        If only the text responds, add `.contentShape(Rectangle())` to `HistoryView.content(_:)`
        (HardsetUI, outside this task's files).
  - [ ] Add movement: the picker's Recent section now lists the movements logged most recently
        (Task 18's "Recent stays empty until Task 19" is closed).
  - [ ] The catalogue notice, the start failure and the gym-save failure read in the critical
        colour, legible in light, dark and with Increase Contrast on.
  - [ ] With no workout open, scrolling History or Volume also minimises the tab bar: the
        modifier is now unconditional, so the TabView keeps one identity. Expected.
  - [ ] (fix(feature): the live session's failures read in the critical colour) During a rest,
        force a timer failure (debug `lastErrorMessage`): its line under the rest is the critical
        colour, and the alarms-off line beside it stays grey (a choice, not a failure). Force an
        add-machine failure: the picker's footer is the critical colour. Both legible in light,
        dark and with Increase Contrast on.
  - Written without a compiler. The non-SwiftUI parts (`HardsetEnvironment`, `RootTab`,
    `SummaryTarget`, `canStartWorkout`, `repeatWorkout`, the `onFinished` closure, the
    accessory's `RestBarView` call and `onSkip`, `SummarySheet`'s init and `load`, and
    `HistoryScreen`'s `onRepeat.map`) were type-checked on Linux in a scratch target against the
    real HardsetCore and HardsetStore, with the `LiveSessionScreen`, `RestBarView`,
    `WorkoutSummaryView` and `HistoryView` signatures copied verbatim. That run also showed the
    brief's literal forms do not compile: `coordinator = nil` inside `if let coordinator`, the
    method reference in `coordinator == nil ? repeatWorkout : nil` (ambiguous), and calling a
    memberwise initialiser of a struct with private properties. If the build fails anyway, look
    first at:
    - `TabView(selection:)` with `Tab(_:systemImage:value:content:)`, each given a `RootTab`.
    - `.tabViewBottomAccessory(isEnabled:content:)` (iOS 26.1) and
      `.tabBarMinimizeBehavior(.onScrollDown)`, both inside `#if os(iOS)`.
    - `let restState = hooks.state()` inside `if let coordinator { … }` in the `@ViewBuilder`
      accessory.
    - `startButton`'s `if #available(iOS 26.0, macOS 26.0, *) { … .buttonStyle(.glassProminent) }
      else { … }`.
    - `private nonisolated enum RootTab` and `private nonisolated struct SummaryTarget` at file
      scope, used by `TabView(selection:)` and `.sheet(item:)`.

## Phase 3

- [ ] (feat(core): the chart says what changed on one machine …) HardsetUI and HardsetFeature build
      (iOS, and macOS 15 via `./test.sh`) with `ProgressionMetric` now from HardsetCore and
      `ProgressionChartView.SeriesInput` a typealias of `ProgressionChartSeries`. The chart's
      metric picker still shows "Heaviest load" and "Est. 1RM". With two machines named alike
      (create two unbranded "Leg Press" machines and log on both), the exercise's chart shows two
      lines in the legend, "Leg Press" and "Leg Press (2)".

- [ ] **GATE for Task 11** (feat(core): one door for Core's words, and a String Catalog behind it)
      Core now has a resource bundle, the step that once broke the app build.
  - [ ] `./test.sh` passes on the Mac. `LocalizedTests` there exercise the Apple branch,
        `String(localized:bundle: .module)`, and must return the same English as on Linux.
  - [ ] The `Hardset` scheme builds for the iOS 26.4 simulator **and** archives (Product ›
        Archive), from the checkout's real path. If the checkout is normally opened through a
        symlink, build from that path too: the old actool failure was a write denied under a
        symlinked path.
  - [ ] The widget extension builds (it links HardsetCore).
  - [ ] In the built `Hardset.app`, `HardsetKit_HardsetCore.bundle` exists and contains a compiled
        `en.lproj/Localizable.strings` (or `.stringsdict`) with the "Not evaluated" entry.
  - [ ] Optional: with "Use Compiler to Extract Swift Strings" on, note whether Xcode extracts the
        `localized("…")` literals into the catalog. Record yes or no here; Task 11 adds manual
        entries only for keyed lookups either way.
  - [ ] If any of these fails: apply the fallback in `DECISIONS.md` §23, record the failure and
        the fallback here, and only then unblock Task 11.

- [ ] (feat(ui): a badge says how sure, and opens where from) HardsetUI and HardsetFeature build
      (iOS, and macOS 15 via `./test.sh`) with `CertaintyLevel` and
      `ExercisePickerView.displayName` gone. Then in the simulator:
  - [ ] Volume tab › "How sets are counted": the sheet opens with "In short" first, the three
        credit bars (1, 0.5, 0) with their basis lines, then "How it works". Done closes it.
  - [ ] The Source section shows "Open the paper at doi.org"; it opens
        https://doi.org/10.1007/s40279-025-02344-w (no trailing comma).
  - [ ] The title is inline and reads "Fractional set counting".
  - [ ] SF Symbols render (not blank): `circle.dashed`, `greaterthan.circle`,
        `clock.badge.questionmark`, `checkmark.seal`, `circle.lefthalf.filled`,
        `questionmark.circle`. If one is missing, choose another non-error glyph in the SF Symbols
        app and change it in `CertaintyMark.swift` (Core tests do not pin names).
  - [ ] Increase Contrast on: badge text darkens (light) or lightens (dark).
  - [ ] VoiceOver on a badge: "Moderate confidence. Shows how this was calculated", and double tap
        opens the sheet. The credit rows each read as one element.
  - [ ] Muscle names in the picker, the Volume tab and the summary are unchanged ("Quads", …).
  - [ ] The 0 credit row draws an empty track, and the whole 44 pt "Open the paper" row is
        tappable, not only its words (the frame is on the link's label).
  - [ ] VoiceOver's Headings rotor steps through "In short", "How it works", "Where it holds, and
        where it does not" and "Source"; the sheet's certainty line reads as its word alone.
  - Written without a compiler. If the build fails, look first at:
    - `MethodologySheet.section`'s `let bodyFont: Font = if … else if … else …` (an if
      expression, Swift 5.9).
    - `CertaintyBadge.Style` is main-actor isolated by the target's default isolation, and
      `style == .full` runs in `body`. An isolated-conformance diagnostic there is fixed by
      declaring it `nonisolated public enum Style`.
    - The `#if os(iOS) .navigationBarTitleDisplayMode(.inline) #endif` between
      `.navigationTitle` and `.toolbar` (the API is unavailable on macOS).

- [ ] (feat(ui): every volume figure says how sure it is) HardsetUI and HardsetFeature build. In
      the simulator:
  - [ ] Volume tab: each muscle row has a compact badge. Chest, quads and the other modelled sites
        read "Moderate"; forearms, abs and other counted muscles read "Low" beside "counted, not
        modelled". A muscle over 25 sets reads "Low".
  - [ ] "How sets are counted" opens the sheet with no certainty line at the top.
  - [ ] Tapping a row's badge opens the sheet with that row's certainty.
  - [ ] With a custom (unattributed) movement logged: counts read "≥ 12", the note's glyph is the
        grey ">" circle, not an exclamation mark, and VoiceOver reads "at least 12 sets".
  - [ ] Settings › General › Language & Region › German (or region Germany): a fractional count
        reads "6,5", not "6.5".
  - [ ] Summary sheet: each muscle line has its badge; an estimated-1RM record shows its
        certainty, and VoiceOver offers "How this estimate is calculated".
  - [ ] History, VoiceOver: a row reads "... 9400 kilograms ...", never "kg"; pounds mode reads
        "pounds". Rows are not dimmed.
  - [ ] Summary muscle rows (combined element): VoiceOver reads name, count and the badge's word
        without garbling "≥"; if it does, set `.accessibilityLabel("\(line.muscle.displayName),
        \(line.spokenSetsText())")` on the row.
  - [ ] Volume rows: VoiceOver reads the certainty word once, not twice (the row label includes it
        explicitly); if doubled, drop it from the label in `VolumeReportView.bar(for:)`.
  - Written without a compiler. If the build fails, look first at the `[String, String?] array
    .compactMap { $0 }.joined` label arrays in `VolumeReportView.bar(for:)` and
    `WorkoutSummaryView.recordsSection`, and the `.accessibilityActions { if … { Button … } }`.

- [ ] (feat(ui): the chart says what changed on one machine, and VoiceOver hears it) HardsetUI and
      HardsetFeature build (iOS, and macOS 15 via `./test.sh`). With two machines for one movement,
      in the simulator:
  - [ ] Over the chart: "Cybex Leg Press: +5 kg over 2 sessions" for the machine used last, never a
        delta across machines. In pounds the number is the difference of the two displayed loads.
  - [ ] Each machine has its own colour and its own point shape (circle, square, ...); with colour
        filters on (Settings > Accessibility > Display > Color Filters > Grayscale) the lines are
        still told apart.
  - [ ] Est. 1RM: lines are dashed, the headline says "about" and carries a badge.
  - [ ] Drag across the chart: a rule and a label follow the nearest logged session, named by its
        machine.
  - [ ] A movement done only with 15-rep sets: Est. 1RM shows "Not evaluated" and the reason.
  - [ ] VoiceOver: focus the chart, swipe up to "Chart details" / "Play audio graph". The title is
        "<movement>, heaviest load", there is one series per machine, and values read "102.5
        kilograms".
  - [ ] At the largest accessibility text size the chart is taller than at the default size.
  - Written without a compiler. If it fails, look first at:
    - the `.symbol(by:)` and `.lineStyle` modifiers on `LineMark`;
    - `chartXSelection(value:)` with a `Date?` binding;
    - Settled in review, not expected to fail: `ProgressionAudioGraph` is `nonisolated` so its
      witness satisfies `AXChartDescriptorRepresentable` under the target's main-actor default;
      `@ScaledMetric` has a default value; `if let` in chart builders uses
      `ChartContentBuilder.buildIf` (iOS 16, macOS 13).

- [ ] (feat(ui): the logger with VoiceOver and large text) HardsetUI builds (iOS, and macOS 15). In
      the simulator, VoiceOver on:
  - [ ] A prefilled row reads "Set 2, 100 kilograms, 8 reps, Last time …, button. Double tap to
        log this set." Double tap logs it, and VoiceOver then says "Set 2 logged, 100 kilograms, 8
        reps." once. A record set says the log and the record in one announcement.
  - [ ] A logged row reads "…, logged, selected" with no hint; double tap does nothing.
  - [ ] A half-typed row reads "60 kilograms, reps not entered".
  - [ ] On the reps pad, swiping never lands on an invisible decimal key. Typing on the weight pad
        speaks "Weight, 62.5 kilograms"; the step keys say "Add 2.5 kilograms" / "One more rep".
  - [ ] Scroll so the tab bar collapses during a rest: the accessory's countdown offers the
        actions "Subtract 15 seconds", "Add 15 seconds", "Skip rest".
  - [ ] Pounds mode: every weight is spoken "pounds", including a row's record ("New record on
        Leg Press. Heaviest weight: 231 pounds, up from …"), never "lb".
  - [ ] Settings › Accessibility › Display & Text Size › Larger Text, the largest size: set rows
        stack (number and "Last time" above, fields and check below), nothing truncates the weight,
        and every control is at least 44 pt (Accessibility Inspector). The keypad's keys grow but
        stop growing at 88 pt, and the row being edited stays visible above the pad.
  - [ ] AX5 on iPhone SE (375 pt): the active row's weight renders without ellipsis, and the
        check mark sits on its own line beneath the weight and reps.
  - [ ] Pad: the `.onChange(of: keypad.focused.text)` announcement may also fire on a reseed or a
        field switch (Next). Watch for spurious or doubled announcements.
  - [ ] An estimated-1RM record on a row shows its certainty glyph and word, and the action "How
        this estimate is calculated" opens the Epley sheet.
  - [ ] Loads borrowed from another machine show the "From another machine" chip; tapping it opens
        the machine picker.
  - [ ] The correction mode (Edit on a logged row) still keeps the pad open on the logged row, and
        its row reads "…, logged, not saved yet" until Save.
  - [ ] Written without a compiler. If it fails, look first at `.accessibilityAction { }` (the
        default-action overload), `.accessibilityAddTraits` with a ternary of `AccessibilityTraits`,
        `@ScaledMetric(relativeTo:)` with `Tokens.…` initial values, the `if`-inside
        `.accessibilityActions { }` builders, and `.sheet` after `.accessibilityActions` in
        `SetRowView.body`.
- [ ] (feat(feature): wire corrections, the finish flow and Recent into the live session)
      HardsetFeature and the app build. In the simulator:
  - [ ] Finish is the prominent (glass) action at the top right; there is no Finish at the
        bottom of the list.
  - [ ] Log 1 of 3 prefilled sets, tap Finish: "2 sets weren't logged and won't be saved", with
        Finish workout / Keep logging.
  - [ ] Start a workout, log nothing, tap Finish: "Nothing was logged" with Discard workout;
        discarding returns to the start screen and nothing appears in history.
  - [ ] A failed edit shows "That change could not be saved…", not the log-set copy.
  - [ ] The picker's Cancel closes it and clears the search.
  - [ ] Keep logging closes either dialog and changes nothing. Its title does not blank or change
        while it animates away. "Finish workout" in the unlogged dialog finishes: history shows
        only the logged set.
  - [ ] Both dialogs present. They are two `.confirmationDialog`s on one view; if only one ever
        appears, merge them into one keyed on the decision.
  - [ ] With a rest running and nothing logged (start it from the chip), Discard workout ends the
        rest too.
  - [ ] Task 14's moments are now wired: re-run that entry's trophy, haptic, Edit, Delete and Undo
        checks here.
  - [ ] Settings (gear) and Finish both sit at the trailing edge of the Train tab. Note their
        order. The macOS 15 host build shows a plain Finish (no `.confirm` role).
  - [ ] Force a finish failure (debug throw), then log a set: the finish copy goes and the screen
        is quiet. A finish failure is retired by the next write the lifter attempts, so it never
        stands in front of a later failure's copy.
  - Recent stays empty until Task 19 passes `shortcuts:` from `HardsetRootView`. This task only
    adds the input; the root's call site changed in its `onFinished` closure alone.
  - Known limit, Undo timing: `PendingUndo` takes no expiry, so the bar counts its own 5 s from
    when it appears (moments after the delete), and restarts after a tab switch. The
    coordinator's `DeletedSet.expiresAt` stays the authority: an Undo after it does nothing and
    shows no error. Passing the expiry needs a HardsetUI change (`PendingUndo(expiresAt:)`).
  - [ ] Force an Undo failure (debug throw in `LoggerStore.restoreSet`): "That set could not be
        put back. Tap Undo to try again." shows while the bar is up. When the bar times out, the
        copy goes with it; the set stays deleted.
  - [ ] Force an add-movement failure (debug throw in `LoggerStore.addExercise`): "That movement
        could not be added. Try again." Force a machine-change failure (debug throw in
        `LoggerStore.setSessionExerciseMachine`): "The machine could not be changed. Your logged
        sets are safe. Try again." Neither reads as a failed set.
  - Written without a compiler. The non-SwiftUI parts (every `SessionView` callback, the picker
    call, `attempt(_:_:)`, `requestFinish`, `discard`, `refreshRecent`, `SessionExit`) were
    type-checked on Linux in a scratch target against the real HardsetCore and HardsetStore, with
    `SessionView`/`ExercisePickerView`/`PendingUndo` signatures copied verbatim and SwiftUI
    stand-ins using the SDK's `Binding(get:set:)` and `Button(_:role:action:)` declarations.
    Swift 6.2 also showed `if #available(iOS 26.0, macOS 26.0, *)` raises no "unnecessary
    check" warning at an iOS 26.1 deployment target (it does only under an enclosing
    `@available`), which settles the Task 14 worry about `UndoBarBackground` too. If the build
    fails anyway, look first at:
    - `ToolbarItem(placement: .confirmationAction) { if #available(…) { Button(…, role: .confirm,
      …) } else { … } }`.
    - The two `.confirmationDialog(_:isPresented:titleVisibility:actions:)` calls with `String`
      titles, which must resolve to the `StringProtocol` overloads (iOS 15).
    - The single-expression `attempt(.x) { … }` callbacks, which return `Bool` into the
      `Void`-typed `onLogSet`/`onDeleteSet`/`onUndoDelete`.
  - If Finish is not visibly prominent, the `.confirm` role alone did not style it on iOS 26: add
    `.buttonStyle(.glassProminent)` inside the `#available` branch.

- [ ] (refactor(feature): the root composes three views instead of drawing them) HardsetFeature
      and the app build (iOS, and macOS 15 via `./test.sh`); `AppSmokeTests` passes. In the
      simulator, nothing looks or behaves differently: start screen, gym row and sheet (including
      "Add a gym" inside it), glass Start, the accessory during a workout and a rest, Finish →
      summary, Repeat from history.

- [ ] (feat(ui): a past workout opens from history) HardsetUI and HardsetFeature build (iOS, and
      macOS 15 via `./test.sh`). New SF Symbol names: `chart.xyaxis.line` (section header),
      `trophy` (a set's record; already used in the summary). In the simulator:
  - [ ] Tap a History row: the session opens, with its date and length ("Length unknown", grey with
        its glyph, for one left open overnight), its totals, and one section per movement and
        machine. A leg press done on two machines shows two sections.
  - [ ] Records sit on the sets that earned them; an estimated 1RM shows its badge.
  - [ ] Tap a section's header: that movement's load history opens, outside any workout. Its
        header keeps the caption style (grey, not uppercase) and VoiceOver finds it as a heading.
        Coming back from the load history keeps the detail's scroll position.
  - [ ] Back returns to History with its scroll position; Repeat (context menu) still works.
  - [ ] VoiceOver: a History row is a button, not dimmed; a set reads "Set 2, 100 kilograms, 8
        reps, logged". A set with an estimated 1RM offers "How this estimate is calculated".
  - Compiler watch: `navigationDestination(item:)` twice (History, and inside the detail screen);
    the `#if os(iOS)` inside the modifier chain in `HistoryScreen.detailScreen`.

- [ ] (feat(ui): one honest first screen; a new lifter is told three promises and the privacy
      line and asked for nothing, and an existing lifter never sees it) HardsetUI and
      HardsetFeature build; `AppSmokeTests` passes. New SF Symbols: `lock`,
      `exclamationmark.circle` (the three promise symbols come from `FirstRunCopy`). In the
      simulator:
  - [ ] Erase the simulator, install, launch: one screen with three promises, the unit, an
        optional gym field, "No account. Your data stays on your devices and in your iCloud.", and
        Start. Nothing asks for a goal, a target, a program or experience.
  - [ ] Region United States: the unit reads lb with the chip "Weights in pounds, from your
        region"; tapping the chip switches to kg and the chip disappears. Region UK: kg.
  - [ ] A unit chosen earlier wins: set kg in Settings under a US region, delete only
        `hardset.firstRunComplete`, relaunch: the first screen opens on kg with no region chip at all (a chosen unit is not a guess).
  - [ ] Start with the gym field empty: the Train tab, no gym selected. Relaunch: the first screen
        does not return.
  - [ ] Erase, type "  Iron   Temple ", Start: the start screen's gym row reads "Iron Temple".
  - [ ] Install over a build that has history (or log a workout, then delete the
        `hardset.firstRunComplete` default): the first screen never appears.
  - [ ] Leave a workout open, delete the default, relaunch: the workout is offered back; no first
        screen.
  - [ ] No alarm permission prompt appears until the first rest.
  - [ ] VoiceOver reads each promise as one element, then the unit, the chip, the field, the
        privacy line and Start. Largest text size: everything scrolls, nothing truncates.
  - Compiler watch: `Group { if … FirstRunView else tabs }` carrying `.sheet`/`.task`;
    `#if os(iOS)` inside the TextField modifier chain; `useImperial` self-write via a local.

- [ ] (feat(feature): rename or archive a gym or a machine) HardsetFeature builds (iOS, and
      macOS 15 via `./test.sh`). In the simulator:
  - [ ] Settings > Gyms and machines lists each gym with its machines.
  - [ ] Rename a machine to "Leg Press 45°" with brand "Hammer Strength": the list, a past
        session's detail and the movement's chart all read "Hammer Strength Leg Press 45°".
  - [ ] Rename to spaces: Save stays disabled.
  - [ ] Archive the selected gym, close Settings: the start screen no longer shows it; its sessions
        are still in History with their machines named.
  - [ ] Every action is reachable by swipe, by long press, and as a VoiceOver action.
  - Compiler watch: `GymsScreen`'s private nested `Target` used by the file-private `RenameSheet`;
    `confirmationDialog` title built from optional state; `.sheet(item:)` on `Target`.
  - No new SF Symbols.

## Phase 4

- [ ] (feat(app): launch in the app's own colour; a manifest for the widget) The `Hardset` scheme
      builds and archives. In the built `Hardset.app`, `PlugIns/HardsetWidget.appex/PrivacyInfo.xcprivacy`
      exists, and `PrivacyInfo.xcprivacy` is at the app bundle's root (DEVICE-CHECKLIST §D).
  - [ ] Cold-launch in light and in dark mode (kill the app first): the launch screen is the
        same grey as the first screen, with no white or black flash before it.
  - [ ] Xcode › Product › Archive › Generate Privacy Report: the app lists UserDefaults CA92.1
        only; the widget lists nothing.
- [ ] (docs(design): an icon brief and two layer drafts) **Needs the user's design judgement.**
      In Icon Composer (Xcode › Open Developer Tool › Icon Composer): import `01-stack.svg` and
      `02-pin.svg` from `Design/AppIcon/layers/`, set the background, check the default, dark,
      tinted and clear appearances and the smallest size, and save as `AppIcon.icon`.
  - [ ] Then, in a scratch copy of the project, add `AppIcon.icon` to the Hardset target in Xcode
        once and read the `lastKnownFileType` Xcode writes for it. Add
        `("AppIcon.icon", "Hardset", APP)` to `RESOURCES` in `Tools/generate_project.py`, teach
        its file-type switch that extension, add the file to `group_children["Hardset"]`, keep
        `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, remove `AppIcon.appiconset`, regenerate
        twice, and build. Never hand-edit the pbxproj.
- [ ] (fix(ui,feature): what a cross-file review of the never-compiled code found) Build the
      `Hardset` scheme and `./test.sh` (macOS 15 host build) with **no new warnings**:
  - [ ] No "unnecessary check for 'iOS'" warnings: the three `#available` checks
        (`LiveSessionScreen` Finish, `SessionView` Undo bar, `HardsetRootView` Start) now name
        macOS 26 only, because the iOS floor (26.1) already guarantees the iOS 26.0 APIs.
  - [ ] `LiveSessionScreen.body` type-checks in reasonable time: the `SessionView` call no longer
        holds conditional closures (they are the named `addExerciseAction`, `selectMachineAction`,
        `showHistoryAction` and `pendingUndo`). If "unable to type-check" still appears, move
        `attempt` closures into named methods the same way.
  - [ ] VoiceOver on the rest bar (accessory, during a rest): it says "Resting until <time>"
        (the rest's end, in the device's time format), then "after <movement>, <set>". Paused:
        "Rest paused, 1:20 remaining". Wait a minute and re-focus: the end time is still right.
  - [ ] `NumericPad` builds with its new `import Accessibility`; its spoken-value announcement still
        speaks. `Tokens.Haptic.feedback(for:)` is `nonisolated`; the log haptic still plays.
  - [ ] **Test bundle linking.** `HardsetTests` links HardsetCore, HardsetStore and HardsetFeature
        statically while its host app links them too. If Xcode reports "Swift package product …
        is linked as a static library by 'HardsetTests' and 'Hardset'" as an **error**, or the
        smoke tests misbehave because two copies of a package global exist (for example
        `prepareDependencies` not reaching the app's code), set `TESTS` to `[]` in
        `Tools/generate_project.py` (`BUNDLE_LOADER` resolves the symbols from the host), regenerate
        twice, and rebuild. If that instead gives "No such module", restore the list and accept the
        warning. Record which one held here.
  - [ ] `HardsetKit_HardsetCore.bundle` (Phase 3 Task 10's String Catalog) is embedded in the app,
        the widget extension and the test bundle, and builds from the symlinked package path. If it
        breaks the build, Phase 3 Task 11 is blocked on it; nothing calls `localized(_:)` yet, so
        removing `resources:` from HardsetCore unblocks the build until it is fixed.
- [ ] (feat(widget): the rest on the Lock Screen, with pause, resume and skip that run in the app)
      The `Hardset` scheme builds (app and widget) with no new warnings, and HardsetAlarm builds
      for iOS. Written without a compiler; look first at:
  - [ ] `@AppDependency private var restTimer: RestTimerController` resolves. If not, use the
        spelling in Apple's samples, `@Dependency`; neither file imports SQLiteData, so there is
        no clash there.
  - [ ] `AppDependencyManager.shared.add(dependency: restTimer)` resolves to the autoclosure
        overload with `key` defaulted; if `key:` has no default, pass `key: nil`.
  - [ ] `@Parameter(title:defaultUnit:supportsNegativeNumbers:requestValueDialog:)` on
        `Measurement<UnitDuration>` resolves; if not, drop `supportsNegativeNumbers:` (Core refuses
        negatives anyway) and note the overload that did.
  - [ ] `@MainActor func perform()` satisfies `AppIntent` in a target whose default isolation is
        MainActor, in both the app and the widget, with no isolated-conformance diagnostic.
  - [ ] `RestControls.button(for:)`: three `Button(intent:)` branches in a `switch` inside
        `@ViewBuilder` build. `ProgressView(timerInterval:…)` with `.progressViewStyle(.circular)`
        animates in a Live Activity; if it is drawn static or linear, drop the circular style.
  - [ ] SF Symbols exist: `pause.fill`, `play.fill`, `forward.end.fill`, `checkmark.circle.fill`.
  - [ ] Shortcuts shows the descriptions of "Start a rest" and "Skip the rest", and lists neither
        "Pause the rest" nor "Resume the rest". (`static let description = IntentDescription(…)`
        is Apple's documented form, but a non-optional `static let` does not witness the
        `IntentDescription?` requirement at runtime, so the text reaches Shortcuts only through
        the build's App Intents metadata. If it is missing, type it `IntentDescription?`.)
  - [ ] "Start a rest" from Shortcuts before any rest has been started in the app, so alarm
        permission was never asked: record whether the prompt appears over Shortcuts, or the
        rest falls back to the notification. Either way the shortcut finishes with a sentence
        and does not hang.
  - Already checked on Linux (swift:6.2, `-default-isolation MainActor`, `-warnings-as-errors`):
    `RestTimerController.swift` as changed, against stubs of `RestAlarmService` and
    `RestNotificationFallback`; and `RestIntents.swift` and `IntentDependencies.swift` against a
    mock of the documented AppIntents signatures. That rules out Swift-level isolation errors,
    not SDK differences. The mock showed an intent struct is inferred nonisolated (AppIntent
    inherits `Sendable`), so only `perform()` is main-actor.
  Then on device (DEVICE-CHECKLIST §B):
  - [ ] Every Lock Screen and Dynamic Island check added to §B there.
  - Known residual: after ±15 s or a resume the ring starts again from the new alarm's length
    (reading 3). Record whether it reads as wrong in use.
  - Known residual: if a background launch cannot read AlarmKit's alarms, a Lock Screen button
    or Siri changes nothing and says "The rest timer could not be checked. Open Hardset and try
    again." rather than "No rest is running." while an alarm may still count down. Opening the
    app reconciles. Record it if it is ever seen.
- [ ] (fix(ui): VoiceOver offers "Log set" only on a row that can still be logged) With VoiceOver
      on, swipe up/down on an unlogged row's actions: "Log set", "Edit weight", "Edit reps". On a
      logged row: "Edit set", "Delete set" and no "Log set". Double-tap on an unlogged, complete
      row still logs it.
- [ ] (fix(alarm): a rest that would not pause does not ring under a paused screen) HardsetAlarm
      builds. Normal pause/resume is unchanged: pause shows the paused card on the Lock Screen,
      resume replaces the alarm. Failure path (hard to force; read the code if it cannot be
      forced): when `RestAlarmService.pause` throws, the alarm is cancelled (`pauseFailed`), the
      rest stays paused in the app with the error shown, no alarm rings at the old deadline, and
      Resume schedules a fresh one. Two quick adjusts in a row (±15 twice within the debounce)
      still end with exactly one alarm (`schedulingID` is now cleared only by its own commit).
- [ ] (feat(app): start a workout or a rest by voice, from Spotlight or the Action button) The
      `Hardset` scheme builds (app and widget), HardsetFeature builds for macOS 15 via `./test.sh`,
      and `AppSmokeTests` passes. Written without a compiler; look first at
      `static let supportedModes: IntentModes = .foreground` (if `IntentModes` wants a call, use
      `.foreground(.immediate)`), `AppShortcut(intent:phrases:shortTitle:systemImageName:)`, and
      `.onChange(of: systemRequests.pending)` (zero-argument closure form, iOS 17).
  - [ ] Shortcuts app › Hardset lists Start workout, Start rest and Skip rest, and no Pause, Resume
        or Open Hardset. No action anywhere takes a weight or reps.
  - [ ] Settings › Action Button › Shortcut › Hardset offers the same three.
  - [ ] Spotlight: typing "Hardset" shows Start workout.
  - [ ] Every check added to DEVICE-CHECKLIST §E.
  - [ ] The widget extension builds with `WorkoutIntents.swift` in it (`supportedModes =
        .foreground` in an extension target), and its App Intents metadata step reports nothing
        about the two intents. Neither intent is used by the widget until Task 11.
  - [ ] `HardsetRootView(…, systemRequests: SystemRequestInbox = SystemRequestInbox())` builds: a
        main-actor default argument on the main-actor init. If it does not, make the parameter
        `SystemRequestInbox? = nil` and build the inbox in the init body.
  - [ ] During a rest started in the app, the bar (accessory on iOS, `SessionView` on macOS) still
        captions the set that started it; a rest started from Siri shows no caption. The caption
        now comes from `RestTimerController.metadata`, not the coordinator.
  - SF Symbols: none new. `figure.strengthtraining.traditional`, `timer` and `forward.end` are
    already used in HardsetFeature and HardsetUI.
  - Already checked on Linux (swift:6.2, `-default-isolation MainActor`,
    `InferIsolatedConformances`, `-warnings-as-errors`): the four `HardsetIntents` files as
    committed, against Task 9's mock `AppIntents` extended with the documented `IntentModes`,
    `AppShortcutsProvider`, `AppShortcut`, `AppShortcutPhrase` and `result()`; the widget's two
    shared files on their own; and `handleSystemRequest()` pasted verbatim into a non-SwiftUI
    stand-in. That rules out Swift-level isolation and Core API mismatches, not SDK differences.

- [ ] (feat(widget): Start workout and Rest in Control Center) The widget extension builds.
      Written without a compiler; look first at `promptsForUserConfiguration()` (name and
      placement) and `StaticControlConfiguration(kind:)`. Each control is a single
      `ControlWidgetButton` over one intent type, because `ControlWidgetTemplateBuilder` has no
      `buildEither` or `buildOptional`.
  - [ ] `@Parameter(title: "Length", defaultUnit: .minutes, supportsNegativeNumbers: false) var
        length: Measurement<UnitDuration>?` on `RestControlConfiguration` resolves to an
        `IntentParameter` initialiser. If not, make it a non-optional `Measurement` with a
        sentinel of 0 seconds, mapped to `needsChoice` by `RestControlState`, never to a default
        rest.
  - [ ] `RestControlIntent` (`@Parameter var seconds: Double?`, built with `init(seconds:)`)
        builds, and a tap with a configured length starts the rest without opening the app. With
        no length a tap does nothing; Apple documents `supportedModes = [.background,
        .foreground(.dynamic)]` plus `continueInForeground(_:alwaysConfirm:)` for opening
        conditionally, not used because it can throw and ask for confirmation.
  - [ ] `StartWorkoutControlIntent: OpenIntent` (`target: HardsetScreen`, a one-case `AppEnum`)
        builds, and the Start workout control opens Hardset on Train and starts the workout.
  - [ ] Every check added to DEVICE-CHECKLIST §E for controls.
  - SF Symbols: none new (`figure.strengthtraining.traditional`, `timer` are already used).

- [ ] (feat(widget): last time on a machine, and the last workout, from a file) The `Hardset`
      scheme builds; HardsetFeature builds for macOS 15. Written without a compiler; look first at
      the `TimelineProvider` methods (if the SDK declares `@Sendable` completions, match them
      exactly, or they are near-misses that are never called) and `.containerBackground(_:for:)`.
      The doc JSON declares both completions `@escaping @Sendable`, and `HistoryWidgets.swift`
      matches them.
  - [ ] The app's and the widget's entitlements both carry `group.com.hardset.app`, and signing
        succeeds with the group registered for the team. **Needs the paid Apple Developer Program
        membership, a decision the user still owes (`HANDOFF.md` §11.2).** It adds no new barrier:
        the app's iCloud and push entitlements already need it. If a signed build ever lacks the
        group, `containerURL(forSecurityApplicationGroupIdentifier:)` is nil ("In iOS, the value
        is nil when the group identifier is invalid"), the app writes nothing, and both widgets
        say "nothing yet".
  - [ ] `SnapshotEntry` and `SnapshotProvider` are `nonisolated`, so the provider's conformance is
        not main-actor in a target whose default isolation is. Build with no isolated-conformance
        diagnostic, and with the widget on the Home Screen nothing traps when WidgetKit asks for a
        timeline.
  - [ ] `HardsetRootView.refreshWidgets()` runs at the end of the launch `.task`, in
        `onFinished` (finished and discarded) and on `.onChange(of: useImperial)`; never in
        `body`. It reads the finished workouts on the main actor, as every screen's store read
        does (bounded: `WidgetSnapshotStore.sessionWindow`, 30 sessions). Finishing a long
        workout shows its summary with no visible hitch.
  - [ ] A failed read or write is kept in `widgetSnapshotError`, not shown, logged once with
        `Logger(subsystem: "com.hardset.app", category: "widget")` (the error's type public, its
        description private), and a debug build stops on `assertionFailure("The widget snapshot
        was not written: …")`. If a debug run ever stops there, record the error here: it means
        the widgets are a workout behind. WidgetKit is asked to reload only after a write
        succeeds. `import OSLog` in HardsetFeature builds for iOS and for macOS 15 (`Logger`:
        iOS 14, macOS 11).
  - [ ] `ForEach(lines.indices, id: \.self)` in `LastTimeColumn`: three identical sets ("100 kg ×
        8" three times) draw three lines, with no "ID occurs multiple times" log.
  - [ ] `accessoryRectangular` (Lock Screen) has its own three-line layout in both widgets; the
        system families are unchanged. Last time: the name in semibold caption; the machine
        (`.truncationMode(.middle)`) then `UncutSuffix` "· date" at `.layoutPriority(1)`; one set
        in a `ViewThatFits(in: .horizontal)` that drops "· +N more sets" when it does not fit.
        Last workout: title then "· date", the totals, the length. Check the date is never cut,
        including at the largest Dynamic Type size, and that `ViewThatFits` falls back.
  - [ ] The Lock Screen draws vibrant ("desaturates the widget, making a monochrome version"),
        so in `accessoryRectangular` the container background is `Color.clear`
        (`SnapshotBackground`); the Home Screen keeps `Tokens.Color.surface`. The Lock Screen
        views use only the default and `.secondary` styles, no fixed colour, so no
        `widgetAccentable` is needed (it acts only in `.accented` mode, which the iPhone Lock
        Screen does not use).
  - [ ] Every check added to DEVICE-CHECKLIST §E for widgets.
  - SF Symbols: none new. The widgets draw text only.
  - Already checked on Linux (swift:6.2, `-default-isolation MainActor`,
    `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `-warnings-as-errors`):
    `SnapshotEntry` and `SnapshotProvider` exactly as committed, against a mock of the documented
    WidgetKit declarations (the mock built in Swift 5 mode, as an SDK module is), and passed to a
    `@MainActor` `StaticConfiguration` stand-in from a main-actor `Widget.body`. Without
    `nonisolated` the same provider is inferred main-actor, and the compiler refuses that
    conformance to a nonisolated caller (the stand-in for WidgetKit's). Also
    `WidgetSnapshotWriter.swift` (its `os(iOS)` branch, against a mock `WidgetCenter`) and
    `refreshWidgets()` pasted verbatim into a non-SwiftUI stand-in, against the real HardsetStore.
    That rules out Swift-level isolation and Core/Store API mismatches, not SDK differences.
    After fix round 1, the same again with `WidgetSnapshotWriter.log(_:)`, against a mock of the
    documented `Logger`/`OSLogMessage` String interpolation. The SwiftUI layouts cannot be
    checked here.

- [ ] (feat(health): a finished workout can go to Apple Health, opt-in and write-only)
      **Do not ship without the privacy policy URL** (spec §12.1, DEVICE-CHECKLIST §D): that is a
      decision the user still owes. The `Hardset` scheme builds; `./test.sh` builds HardsetHealth
      for macOS as an empty module (`#if os(iOS)` throughout; `HKWorkoutBuilder` is "macOS –").
      Written without a compiler; look first at the async `HKWorkoutBuilder` calls inside one
      `nonisolated static` function (no "sending … risks causing data races"), `device: .local()`
      (`HKDevice.local()` through an `HKDevice?` parameter), the async closure properties of
      `HealthExportHooks`, and the `Binding(get:set:)` built in `HardsetRootView` (the same shape
      as `SetRowView`'s at e5aff33, which built).
  - [ ] Signing with `com.apple.developer.healthkit` needs the HealthKit capability on the App ID,
        so the paid Apple Developer Program membership, **a decision the user still owes**
        (`HANDOFF.md` §11.2). If Xcode's Signing & Capabilities editor is used to add it, it may
        add `healthkit` to `UIRequiredDeviceCapabilities` in `Hardset/Info.plist`: remove it
        (Health is optional here, and that key hides the app from devices without it; Apple:
        "If HealthKit isn't required for the correct operation of your app, delete the healthkit
        entry"). An empty `com.apple.developer.healthkit.access` array it may add is harmless.
  - [ ] Requesting access with `read: []` and only `NSHealthUpdateUsageDescription` does not raise
        "NSHealthShareUsageDescription must be set". The docs make the share key "required if
        your app uses APIs that access the someone's health data", which Hardset does not; if
        HealthKit refuses anyway, add that key with "Hardset does not read your Health data." and
        record it here and in `AppResourcesTests`. A thrown request reads, to the lifter, as a
        refusal (`try?` in `HardsetApp.swift`), so the symptom would be the toggle snapping off
        with the "Turn it on in Settings" line.
  - [ ] Health's permission sheet appears over the Settings sheet when the toggle is turned on, and
        the toggle reads on only after Allow (it stays off while the sheet is up).
  - [ ] The finish is never held up or failed by Health: the summary sheet opens at once, and the
        Health line appears under the date when Health answers. "Saved to Apple Health as strength
        training." only after `finishWorkout()` returned a workout and
        `HealthExportStore.recordExport` succeeded. A nil workout (saved while locked) or a
        recording failure says nothing (a debug build stops on the latter: record it here).
  - [ ] SF Symbols exist: `heart.text.square`, `info.circle`.
  - Fixed before review (was a residual): `LiveSessionScreen.finish()` reports
    `SessionTimelineError.alreadyFinished` as `SessionExit.finishedElsewhere`, not `.finished`.
    That covers a double tap here and a finish synced from another device. The root shows the
    summary for both and refreshes the widgets for every exit, but sends to Health only for
    `.finished`, so a workout this device did not finish is never sent from it. The root's
    `switch` over `SessionExit` is exhaustive, so a new case must be handled. The Health line is
    kept per workout (`healthLines[id]`), so such a summary never shows an earlier workout's line.
  - [ ] Every check in DEVICE-CHECKLIST §F, including "Finished on another device first".
  - Already checked on Linux (swift:6.2, `-swift-version 6 -default-isolation MainActor`,
    `NonisolatedNonsendingByDefault`, `-warnings-as-errors`, `-c -wmo`):
    `HealthWorkoutWriter.swift` (its `#if` stripped) against a mock of the documented HealthKit
    declarations, three ways: as documented (store and builder `Sendable`), with neither
    `Sendable`, and with the mock itself in `NonisolatedNonsendingByDefault`. All compiled. A
    control that builds the configuration in a main-actor helper is refused ("non-Sendable
    'HKWorkoutConfiguration'-typed result can not be returned from main actor-isolated …",
    "sending 'builder' risks causing data races"), as `DECISIONS.md` §3 describes. Also
    `HealthExportHooks.swift`, `HardsetEnvironment.swift`, `HealthSettingInput` and the root's
    Health functions pasted verbatim into a `View`-conforming stand-in, against the real
    HardsetStore and a SwiftUI mock (`State`, `Binding(get:set:)`), and `HardsetApp.swift`'s
    three closures against the probe HardsetHealth: compiled. The mock `Binding` needs
    `@_inheritActorContext`, which the doc JSON cannot show; without it the same mock also refuses
    `SetRowView`'s Binding that built at e5aff33. That rules out Swift-level isolation and
    Core/Store API mismatches, not SDK differences or the SwiftUI layouts.
- [ ] (feat(ui): two tips that point at the machine chip and a movement's history) HardsetUI
      builds for iOS and macOS 15. Written without a compiler; look first at
      `@Parameter static var isEligible` and `#Rule(Self.$isEligible)` (TipKit's macro spelling),
      the `nonisolated struct ...: Tip` conformances (`Tip` is `Sendable` with non-isolated
      requirements, against HardsetUI's MainActor default), and `.onChange(of:initial:_:)`.
  - [ ] Fresh install, a workout at a gym, one movement: the machine tip appears over the chip.
        Tap the chip: the tip goes for good. Next day, with a movement that has history, the
        history tip appears over its name; tapping the name ends it.
  - [ ] No tip appears while the keypad is up, nor without a gym (no chip), nor on a movement with
        no history. Never two tips on screen; never two in a day.
  - [ ] VoiceOver reads each tip; dismissing it with its close button works.
  - [ ] The chip row's `ViewThatFits` (side by side, or stacked at large type) still anchors the
        machine tip to the one chip that is shown, and never shows it twice.
  - [ ] Only the first movement anchors tips. With history on the second movement only, no history
        tip appears.
  - [ ] `AppSmokeTests` and any preview that taps the chip or name still run with TipKit not
        configured (`Tip.invalidate(reason:)` before `Tips.configure` must not crash).
- [ ] (fix(ui): tap targets keep their floors at the small text sizes) HardsetUI builds for iOS
      and macOS 15. Written without a compiler; look first at `Tokens.tapTarget(_:floor:)` (a
      MainActor static func, called only from view computed properties) and the renamed
      `@ScaledMetric` stores (`scaledCloseTarget`, `scaledAccessoryTarget`, `scaledLoggerTarget`).
  - [ ] xSmall: a set row's fields and check mark are 56 pt high (a logged row's 44), the keypad's
        keys 56 pt, its close button 44 pt high and 56 pt wide, the macOS rest bar's buttons
        56 pt. Before, `@ScaledMetric` scaled them down to about 46 and 36.
  - [ ] Large: unchanged (56 and 44).
  - [ ] AX5: none grows past 88 pt; the keypad does not cover the row being edited, and the
        stacked set row still shows the whole hero weight.
- [ ] (fix(ui): the rest bar's buttons fit the tab accessory at every text size) HardsetUI builds
      for iOS and macOS 15. Written without a compiler: `RestBarView.tapTarget` is a fixed
      `Tokens.minimumTapTarget` in the accessory and `Tokens.tapTarget(_:floor:)` in the logger.
  - [ ] AX5, a rest running, tab bar expanded: −15, +15, pause and skip are 44 pt and the
        countdown stays inside the accessory. Before, each button grew to about 137 pt.
  - [ ] AX5: the button *labels* still scale ("−15" in subheadline, the countdown in title2), and
        nothing caps Dynamic Type in the accessory. If the countdown or "−15" is clipped or pushed
        out at AX3–AX5, the remaining fix is a Dynamic Type cap with the Large Content Viewer on
        the accessory; record what you see.
  - [ ] xSmall and Large: the accessory buttons are 44 pt; macOS's inline rest bar keeps 56–88 pt.
  - [ ] Tab bar collapsed (inline): VoiceOver's actions on the countdown still offer Subtract 15
        seconds, Add 15 seconds and Skip rest.
- [ ] (fix(ui): the assumption chip is tappable across its whole 44 pt) HardsetUI builds for iOS
      and macOS 15. `AssumptionChip`'s frame and `contentShape` moved inside the plain button's
      label; `UnevaluatedReadout` reads `Certainty.unevaluated.mark.word`.
  - [ ] First run, the unit chip ("Weights in kilograms, from your region"): a tap just above or
        below the grey capsule, inside the 44 pt row, still toggles the unit. Before, only the
        roughly 24 pt capsule responded.
  - [ ] Logger, a movement with borrowed history and a gym: the "From another machine" chip
        opens the machine picker from anywhere in its 44 pt row.
  - [ ] Accessibility Inspector: the chip's frame is at least 44 pt high at xSmall, Large and AX5.
  - [ ] Progress screen, Estimated 1RM with only high-rep sets: the readout still says "Not
        evaluated".
- [ ] (fix(ui): a paused rest offers no ±15) HardsetUI builds for iOS and macOS 15.
      `RestBarView.canAdjust` (`state.isRunning`) gates the −15 and +15 buttons and their
      VoiceOver actions; the nested `if` inside `.accessibilityActions` is the thing to compile.
  - [ ] Device, a rest running, tab bar expanded: pause it. −15 and +15 go; pause (now resume)
        and skip stay. Resume: they come back, and ±15 moves both the bar and the Lock Screen.
  - [ ] Tab bar collapsed, paused: VoiceOver's actions on the countdown offer only Skip rest;
        running, they offer Subtract 15 seconds, Add 15 seconds and Skip rest.
  - [ ] Together with the timer's own refusal of a paused adjust (the other final-review branch):
        no path left adjusts a paused rest, so the bar and the Lock Screen never disagree.
- [ ] (fix(ui): the summary sheet speaks its totals and muscle counts in full) HardsetUI builds
      for iOS and macOS 15. `WorkoutSummaryView`'s totals are `SessionVolumeText.written` with
      `.spoken` as the label; each muscle row's combined element is labelled with
      `MuscleLine.spokenSetsText()` and the certainty word.
  - [ ] Finish a workout with warm-ups and a lower-bound muscle count. Totals read one line, the
        same text as that workout's History row ("14 sets · 118 reps · 9840 kg · 3 warm-up").
  - [ ] VoiceOver on the totals: "14 sets, 118 reps, 9840 kilograms, 3 warm-up sets".
  - [ ] VoiceOver on a muscle row: "Chest, at least 6 sets, Moderate confidence" (or the row's
        level), never "greater than or equal to 6 sets"; the row's actions still open the
        source.
  - [ ] xSmall, Large and AX5: the totals line wraps rather than truncating.
- [ ] (fix(ui): the live totals are History's line, spoken in full) HardsetUI builds for iOS and
      macOS 15. `SessionView.volumeDescription` is `SessionVolumeText.written`; the new
      `spokenVolumeDescription` (`.spoken`) labels it.
  - [ ] Live workout with a warm-up and two working sets: the line under the list reads like the
        History row ("2 sets · 16 reps · 1600 kg · 1 warm-up"), no longer "… kg volume".
  - [ ] VoiceOver on it: "2 sets, 16 reps, 1600 kilograms, 1 warm-up set"; with nothing logged,
        "No sets logged yet". Pounds: "… pounds".
  - [ ] The numeric roll still animates on a log, and is instant under Reduce Motion.
- [ ] (fix(ui): the unit segments say kilograms and pounds to VoiceOver) HardsetUI and
      HardsetFeature build for iOS and macOS 15. Each segment is
      `Text("kg").accessibilityLabel("Kilograms").tag(false)` (and "lb"/"Pounds"/`true`).
  - [ ] Settings and the first-run screen still show "kg" and "lb", and tapping each still
        switches the unit (the tag is outermost, after the label).
  - [ ] VoiceOver on each segment: "Kilograms" / "Pounds", with the selected state; not "k g"
        or "l b". If iOS's segmented picker ignores the label, say so here.
