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
