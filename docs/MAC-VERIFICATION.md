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

## Phase 2

- Task 6 (`LiveSessionScreen.errorMessage`): the exhaustive `LoggerStoreError` switch gained
  `.setNotFound, .sessionNotEmpty, .sessionNotOpen` falling to the generic message. HardsetFeature
  does not compile on Linux, so confirm it builds on the Mac.
