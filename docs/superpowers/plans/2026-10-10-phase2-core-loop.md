# Phase 2 — The Core Loop, Crafted Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** one workout, opened cold, logged, corrected and finished, done fast and honestly:
- the keypad's first key replaces the prefill, and ± moves by the machine's real step
- the current set leads the screen
- a logged set can be edited or deleted, written first and shown second, with an Undo
- a record is marked on the row that earned it
- finishing ends in a summary read from the database
- motion and haptics are calm, glass sits only on the functional layer, and the palette is legible
- getting into a workout is shorter: Recent movements, Cancel, and "Repeat this workout"

**Architecture:** every decision lands in `HardsetCore` (pure values) or `HardsetStore` (GRDB), test-first,
verified by `Tools/linux-test.sh`:
- *Core:* keypad, load step, finish decision, active set, feedback events, record copy, record
  replay, palette contrast, the summary value
- *Store:* set corrections, records read back from storage, the summary reader, the shortcuts, and
  the coordinator

`HardsetUI` and `HardsetFeature` tasks only render those values and wire callbacks. They cannot
compile on Linux, so each adds `docs/MAC-VERIFICATION.md` entries. There is no schema change.

**Tech Stack:** Swift 6.2 (Swift 6 language mode, `NonisolatedNonsendingByDefault`), Swift Testing,
GRDB 7 / SQLiteData 1.x (StructuredQueries), SwiftUI for iOS 26.1. The Mac's `./test.sh` also builds
HardsetUI and HardsetFeature for macOS 15.

**Spec:** `docs/superpowers/specs/2026-10-10-hardset-ada-polish-design.md` §8 (Phase 2, items
2.1–2.9), under the §3 direction, the §4 non-negotiables and the §5 verification strategy. This plan
builds on `docs/superpowers/plans/2026-10-10-phase1-trust.md`; its Produces blocks are treated as
existing code.

## Global Constraints

- **No default rest, program, streak, target or goal comparison.** A rest exists only after the
  lifter picks one. "Start workout" starts empty. "Repeat this workout" is started by the lifter, and
  is never preselected or recommended (`HANDOFF.md` §6; spec §8 2.4, 2.9).
- **Persist before claiming.** Nothing is marked logged, edited, deleted, restored, discarded or
  announced until the write it depends on has succeeded (`HANDOFF.md` §5.4; spec 2.3 "The store
  writes first, then the UI updates").
- **A set that is not complete cannot be written, and there is no `?? 0` anywhere.** A correction
  goes through `SetEntryDraft.resolved()` exactly as a log does (`HANDOFF.md` §5.1).
- **Records must beat something by a real margin:** the greater of 2.5% and one plate increment.
  Only `PersonalRecordDetector` decides this, and edits never announce records. The summary
  recomputes them from the database (`HANDOFF.md` §5.5; spec 2.3).
- **Kilograms are canonical.** Conversion goes through `WeightUnit` only, and display through
  `WeightFormatter` only (Phase 1 Task 3, plus `total(kilograms:)`).
- **Machine series are never merged** (`HANDOFF.md` §5.10).
- **The logger does zero database work per render** (`HANDOFF.md` §5.3). Every new read runs from
  a lifter's action, at resume, or in a `.task`, never from a `body`:
  - `recordsBySet`
  - `recentExercises`
  - the summary
  - the repeat plan
- **No schema change.**
  - Deletes rely on the existing `ON DELETE CASCADE` of `sessionExercises.sessionID` and
    `loggedSets.sessionID` (`Packages/HardsetKit/Sources/HardsetStore/Migrations.swift:197, 215`).
  - Nothing references `loggedSets.id`.
  - The schema is permanent and additive-only (`DECISIONS.md` §4). A task that finds it needs a
    schema change stops and asks for a `DECISIONS.md` entry first.
- **Never edit these:** `ExerciseCatalog.swift`, and methodology text pinned by tests.
  `HardsetApp.swift` stays wiring only; no task in this phase touches it.
- **No set is ever logged from outside the app UI.**
- **Liquid Glass is for the functional layer only:** the Start button, the Finish toolbar action,
  the rest cluster in the tab accessory, and the Undo bar. It never goes on set rows or cards.
- **Motion honours Reduce Motion, always.** Every animation, transition and symbol effect is gated
  on `accessibilityReduceMotion`. Frequent actions (a keypress, a log) get minimal motion.
- **Certainty is never colour alone.** Text colours meet 4.5:1, and 7:1 under Increase Contrast.
- **Isolation:**
  - Core types are `nonisolated` by module default.
  - Store types that touch the database are explicitly `nonisolated`.
  - `SessionCoordinator` is `@MainActor @Observable`.
  - `PlannedExercise` is MainActor-isolated by module default, so only MainActor code constructs
    it (`DECISIONS.md` §11).
- **Store tests build databases with `Configuration.forTesting()`**, never `Configuration()`, with
  `foreignKeysEnabled = true`.
- **Verification:**
  - Core and Store tasks: `Tools/linux-test.sh` (optionally `--filter '<Suite>|<Suite>'`) must
    pass, in full, before commit.
  - UI and Feature tasks: add `docs/MAC-VERIFICATION.md` entries under `## Phase 2`. The ledger
    merges by union (`.gitattributes`), so parallel tasks may all append.
- **API discipline for Mac-only code:**
  - Every Apple API not already used in this codebase is confirmed against developer.apple.com.
    Fetch `https://developer.apple.com/tutorials/data/documentation/<path>.json`, because the HTML
    pages render client-side. Put the human URL in the commit body.
  - Anything newer than iOS 26.1 needs `#available`.
  - The package is also built for macOS 15, so any API first available in macOS 26 needs
    `if #available(iOS 26.0, macOS 26.0, *)` or `#if os(iOS)`. That covers `glassEffect`,
    `.glassProminent`, `ButtonRole.confirm`, `tabBarMinimizeBehavior` and
    `tabViewBottomAccessoryPlacement`.
- **Commits:** messages explain *why*, and end with `Co-Authored-By: <your model's trailer>`.
  Never `git push`.

## Review Focus

- **Pounds mode, changing only the reps.** Re-deriving the weight from the rounded display buffer
  ("132.28 lb") would rewrite a 60 kg set as 60.0013 kg the moment the reps were touched. A field
  the lifter did not edit must keep its canonical value. Pinned in Task 1
  (`untouchedWeightKeepsCanonicalValue`).
- **A typo'd record, corrected.** The lifter logs 1000 kg by mistake and edits it to 100. The
  trophy and the summary's record must both go. Editing a set upward must announce nothing, though
  the summary may then list it. Pinned in Task 10 (`typoRecordRetracted`, `editNeverAnnounces`)
  and Task 7 (`correctedSetRejudged`).
- **A stale Undo.** An Undo tapped after the 5-second window, after the toast expired, or after
  Finish must not bring a set back. Pinned in Task 10 (`undoExpires`, `expiredUndoIsGone`,
  `finishEndsUndo`).
- **Discard when the screen and the database disagree.** A set that reached the database through a
  path the screen never saw must still block "Discard". So must a warm-up. Pinned in Task 6
  (`discardRefusesLoggedWork`) and Task 10 (`discardRefusedWhenDatabaseDisagrees`).
- **Repeating a workout that is not the latest on its machine, or whose machine or gym has since
  been archived.** Prefill must come from the latest history, never from the repeated workout, and
  removed equipment must not come back. Pinned in Task 11 (`prefillComesFromLatestHistory`,
  `archivedMachineNotRevived`, `archivedGymNotRevived`).

## How this plan reads the spec

The spec leaves these points open. Each resolution below is binding for the tasks and pinned by a
test where it is behaviour.

1. **`SessionSummary` already exists.** It is the history-row type in `VolumeStore.swift:147`, used
   by `HistoryScreen`. The finish summary is therefore named `WorkoutSummary`: a Core value that
   HardsetUI can render, read by a new Store `WorkoutSummaryStore`. Renaming the existing type would
   be a drive-by.
2. **"Undo re-inserts the row" means its contents go back under a new `SetID`.** On delete,
   SQLiteData sets `_isDeleted` in the row's sync metadata, and the insert trigger's upsert
   (`onConflictDoUpdate: { _ in }`) does not clear it. That is a reading of
   `.build-linux/checkouts/sqlite-data/Sources/SQLiteData/CloudKit/Internal/Triggers.swift`, and it
   cannot be exercised here. So re-inserting the same primary key before the deletion syncs risks
   iCloud deleting a set the device shows. Nothing references `loggedSets.id`. Task 6 records this
   as `DECISIONS.md` §22.
3. **"Kept for the session" also covers a crash.**
   - Trophies are rebuilt from the database on resume.
   - After an edit, a trophy stays only if the database still supports it. An edit never adds one.
   - The summary lists whatever the database supports.
4. **Delete removes the row.** It does not leave an unlogged ghost that the finish dialog would then
   count. Undo puts the row back where it was.
5. **What counts as unlogged** for "2 sets weren't logged and won't be saved": a row holding a
   complete, loggable value that was never logged, warm-ups included. Empty or half-typed rows are
   not sets. Zero logged sets means Discard is offered, never Finish.
6. **The rest cluster lives in the tab bar's bottom accessory on iOS,** where it is already glass.
   `SessionView` stops drawing its own rest bar on iOS. That frees the bottom inset for the keypad,
   and the countdown is drawn once.
7. **The summary sheet is presented by `HardsetRootView`,** because `LiveSessionScreen` is torn
   down the moment the session ends.
8. **"Repeat this workout":**
   - It copies the plan rows that had at least one logged set, in order. Sets with no plan row are
     attributed exactly as `resume` attributes them.
   - It copies the machine the exercise *ended* on, and only if that machine is not archived and
     belongs to the past session's gym. A gym that is now archived is not copied.
   - `plannedSets` is nil, so row counts and prefills come from the latest history, as for any
     start.
9. **± on the reps field moves by one rep and never below one.** On weight it moves by `LoadStep`.
   The spec's tap counts ("2 taps (±) or 5 taps (typed)") start from a closed pad: focus is one
   tap, then one ± or five keys.
10. **The 4.5:1 palette claim moves into Core** (`Palette`), so it is tested on Linux instead of
    trusted to a view.

## Scheduling (for the controller)

**Precondition:** Phase 1 is fully merged (Tasks 1–12). This phase edits files that Phase 1
Tasks 8, 10, 11 and 12 rewrite, and assumes these from them:
- `FailureCopy`, and the removal of the exhaustive `LoggerStoreError` switch in
  `LiveSessionScreen.errorMessage`
- `restChoices` and `activeRest`
- the rest chip inputs
- `WeightFormatter.total(kilograms:)`

Line numbers below were read at commit `30f82f9`. They are anchors; the symbol names are
authoritative.

Tasks with disjoint files may run in parallel, each in its own worktree branched from the current
tip of `FrankieBiz/perfect-app-polish-agents`. They merge back one at a time, rebased on the tip,
with `Tools/linux-test.sh` rerun after each merge. `docs/MAC-VERIFICATION.md` is union-merged, so
it is not an ownership conflict. Paths are relative to `Packages/HardsetKit/Sources/` (sources)
and `Packages/HardsetKit/Tests/` (tests).

| Task | Files owned | Depends on |
|---|---|---|
| 1 Keypad semantics (Core) | HardsetCore/NumericEntryBuffer.swift, HardsetCore/LoadStep.swift, HardsetCore/SetEntryKeypad.swift, HardsetCoreTests/SetEntryKeypadTests.swift | — |
| 2 Session flow: finish decision, active set (Core) | HardsetCore/SessionFlow.swift, HardsetCoreTests/SessionFlowTests.swift | — |
| 3 Record moment: feedback events, record copy (Core) | HardsetCore/FeedbackEvent.swift, HardsetCore/RecordCopy.swift, HardsetCoreTests/RecordMomentCopyTests.swift | — |
| 4 Session record replay (Core) | HardsetCore/SessionRecordReplay.swift, HardsetCoreTests/SessionRecordReplayTests.swift | — |
| 5 Palette with tested contrast (Core) | HardsetCore/Palette.swift, HardsetCoreTests/PaletteTests.swift | — |
| 6 Set corrections (Store) | HardsetStore/LoggerStore.swift, HardsetStore/FailureCopy.swift, HardsetStoreTests/SetCorrectionTests.swift, HardsetStoreTests/FailureCopyTests.swift, DECISIONS.md | — |
| 11 Workout shortcuts (Store) | HardsetStore/WorkoutShortcuts.swift, HardsetStoreTests/WorkoutShortcutsTests.swift | — |
| 7 Records read back from storage (Store) | HardsetStore/LoggerStore.swift, HardsetStoreTests/SessionRecordsReadTests.swift | 4, 6 |
| 12 Tokens v2 (Mac-only) | HardsetUI/DesignTokens.swift, HardsetUI/VolumeReportView.swift, HardsetUI/ProgressionChartView.swift | 3, 5 |
| 8 Workout summary (Core value, Store reader) | HardsetCore/WorkoutSummary.swift, HardsetStore/WorkoutSummaryStore.swift, HardsetStore/VolumeStore.swift (one keyword), HardsetStore/FailureCopy.swift, HardsetCoreTests/WorkoutSummaryTests.swift, HardsetStoreTests/WorkoutSummaryStoreTests.swift, HardsetStoreTests/FailureCopyTests.swift | 6, 7 |
| 9 Coordinator: trophies per row, feedback (Store) | HardsetStore/SessionCoordinator.swift, HardsetStoreTests/RecordMomentTests.swift | 3, 7 |
| 13 Keypad v2 and the active set (Mac-only) | HardsetUI/NumericPad.swift, HardsetUI/SetRowView.swift, HardsetUI/ExerciseSectionView.swift, HardsetUI/SessionView.swift | 1, 2, 12 |
| 15 One rest cluster (Mac-only) | HardsetUI/RestBarView.swift | 12 |
| 17 Picker Recent and Cancel; Repeat in history (Mac-only) | HardsetUI/ExercisePickerView.swift, HardsetUI/HistoryView.swift | 12 |
| 10 Coordinator: edit, delete, undo, finish, discard (Store) | HardsetStore/SessionCoordinator.swift, HardsetStoreTests/SetCorrectionCoordinatorTests.swift | 2, 6, 9 |
| 14 Row moments (Mac-only) | HardsetUI/SetRowView.swift, HardsetUI/ExerciseSectionView.swift, HardsetUI/SessionView.swift, plus the one-line `records:` removal in HardsetFeature/LiveSessionScreen.swift | 3, 12, 13 |
| 16 Summary sheet (Mac-only) | HardsetUI/WorkoutSummaryView.swift | 3, 8, 12 |
| 18 Live session wiring (Mac-only) | HardsetFeature/LiveSessionScreen.swift, plus the one-line `onFinished` closure change in HardsetFeature/HardsetRootView.swift | 6, 10, 11, 14, 17 |
| 19 Root: tabs, rest accessory, glass Start, summary, repeat (Mac-only) | HardsetFeature/HardsetRootView.swift, HardsetFeature/HistoryScreen.swift | 8, 11, 15, 16, 17, 18 |

**Waves:**
- Wave 1: 1, 2, 3, 4, 5, 6 and 11, in parallel.
- Wave 2: 7 and 12.
- Wave 3: 8, 9, 13, 15 and 17, in parallel.
- Wave 4: 10, 14 and 16, in parallel.
- Wave 5: 18.
- Wave 6: 19.

Merge 13 and 19 close together if possible. Between them, the iOS build shows the countdown in the
accessory but has no rest controls on the Train tab, because 13 moves the rest bar out of
`SessionView` and 19 moves it into the accessory.

**Rule:** no task may leave a caller of an API it changed uncompiled. A task that changes a
signature updates every call site in the same task, even in files another task owns later. Those
edits are mechanical, nothing more, and each is named in its task.

---

### Task 1: Keypad semantics (Core)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetCore/NumericEntryBuffer.swift:13-117`
- Create: `Packages/HardsetKit/Sources/HardsetCore/LoadStep.swift`
- Create: `Packages/HardsetKit/Sources/HardsetCore/SetEntryKeypad.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/SetEntryKeypadTests.swift` (three suites)

**Interfaces:**
- Consumes:
  - `WeightUnit.fromKilograms`, `toKilograms`, `plateIncrement` and `abbreviation`
  - `SetEntryDraft(weightKg:reps:suggestion:)`, `.suggestion` and `.isLoggable`
- Produces:
  - On `NumericEntryBuffer`:
    - `public private(set) var replacesOnNextInput: Bool`
    - `public mutating func selectForReplacement()`
    - `init(value:...)` sets the flag for a non-empty seed
  - `public struct LoadStep: Hashable, Sendable`, with:
    - `init(machineIncrementKg: Double?, unit: WeightUnit)`
    - `let amount: Double` (in display units)
    - `let source: LoadStep.Source` (`.machine` or `.unitDefault`)
    - `func moved(_ value: Double?, by steps: Int) -> Double?`
  - `public struct SetEntryKeypad: Hashable, Sendable`, with:
    - nested `Field` (`.weight`, `.reps`) and `Direction` (`.down`, `.up`)
    - `init(draft: SetEntryDraft, unit: WeightUnit, machineIncrementKg: Double?, field: Field = .weight)`
    - read-only `weight`, `reps` (both `NumericEntryBuffer`), `field`, `unit` and `loadStep`
    - `var focused: NumericEntryBuffer`
    - `type(digit:)`, `typeDecimalSeparator()`, `deleteBackward()`, `clear()` and `step(_:)`
    - `@discardableResult advance() -> Bool`
    - `focus(_:)`
    - `var draft: SetEntryDraft`
    - `func composedText(locale: Locale = .current) -> String`

Rules (each a test below):
- **Replace on first input.** The first digit or decimal point after seeding replaces the prefill.
  Delete edits it instead. The inert decimal key on reps does not clear it.
- **Focusing a field selects it.** `focus` and `advance` set replacement on the newly focused field.
- **± adjusts an existing value.**
  - It never creates one from an empty field, never goes below zero, and never exceeds the field's
    four integer digits.
  - Weight moves by `LoadStep`, which is the machine's `stackIncrementKg` when it is finite and
    positive, and the unit default (2.5 kg or 5 lb) otherwise. Reps move by 1, within `1...999`.
  - A stepped value is selected again, so the next digit replaces it.
- **A field the lifter did not change keeps the draft's canonical value.**
- **Next and Clear:**
  - Next moves weight → reps. On reps, `advance()` returns `false`, which is the pad's cue to
    close.
  - Clear empties only the focused field.

- [ ] **Step 1: Write the failing tests**

`SetEntryKeypadTests.swift`:

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The first key replaces a prefill; deleting edits it")
struct ReplaceOnFirstInputTests {
  @Test("A digit typed over a prefill replaces it")
  func digitReplaces() {
    var buffer = NumericEntryBuffer(value: 100)
    #expect(buffer.replacesOnNextInput)
    buffer.append(digit: 9)
    #expect(buffer.displayText == "9")
    #expect(!buffer.replacesOnNextInput)
  }

  @Test("102.5 over a 100 prefill takes five presses, not ten")
  func fivePresses() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.append(digit: 1)
    buffer.append(digit: 0)
    buffer.append(digit: 2)
    buffer.appendDecimalSeparator()
    buffer.append(digit: 5)
    #expect(buffer.value == 102.5)
  }

  @Test("A decimal point over a prefill starts a fresh 0.")
  func separatorReplaces() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.appendDecimalSeparator()
    #expect(buffer.displayText == "0.")
  }

  @Test("Delete edits the prefill instead of replacing it")
  func deleteEdits() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.deleteBackward()
    #expect(buffer.displayText == "10")
    buffer.append(digit: 5)
    #expect(buffer.displayText == "105")
  }

  @Test("The inert decimal key on reps does not clear the prefill")
  func inertDecimalKeepsPrefill() {
    var reps = NumericEntryBuffer(
      value: 8, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
    )
    reps.appendDecimalSeparator()
    #expect(reps.displayText == "8")
    reps.append(digit: 1)
    reps.append(digit: 0)
    #expect(reps.displayText == "10")
  }

  @Test("Only a prefill is replaced: an empty field and typed text append")
  func onlyPrefillsAreReplaced() {
    var empty = NumericEntryBuffer(value: nil)
    #expect(!empty.replacesOnNextInput)
    empty.append(digit: 6)
    empty.append(digit: 0)
    #expect(empty.displayText == "60")

    var typed = NumericEntryBuffer(text: "6")
    typed.append(digit: 2)
    #expect(typed.displayText == "62")
  }

  @Test("Selecting an empty field selects nothing")
  func selectingEmpty() {
    var buffer = NumericEntryBuffer()
    buffer.selectForReplacement()
    #expect(!buffer.replacesOnNextInput)
  }

  @Test("Clearing leaves no value and nothing to replace")
  func clearing() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.clear()
    #expect(buffer.value == nil)
    #expect(!buffer.replacesOnNextInput)
    buffer.append(digit: 7)
    #expect(buffer.displayText == "7")
  }
}

@Suite("± moves by what the equipment moves by")
struct LoadStepTests {
  @Test("A machine's stack increment wins")
  func machineWins() {
    let step = LoadStep(machineIncrementKg: 5, unit: .kilograms)
    #expect(step.amount == 5)
    #expect(step.source == .machine)
  }

  @Test("With no machine increment: 2.5 kg, or 5 lb")
  func unitDefault() {
    #expect(LoadStep(machineIncrementKg: nil, unit: .kilograms).amount == 2.5)
    #expect(LoadStep(machineIncrementKg: nil, unit: .pounds).amount == 5)
    #expect(LoadStep(machineIncrementKg: nil, unit: .pounds).source == .unitDefault)
  }

  @Test("A kilogram stack read in pounds steps by its real size")
  func machineStepInPounds() {
    let step = LoadStep(machineIncrementKg: 5, unit: .pounds)
    #expect(abs(step.amount - 11.023_113_1) < 1e-6)
  }

  @Test(
    "A nonsense increment falls back to the unit's step",
    arguments: [0.0, -2.5, Double.nan, Double.infinity]
  )
  func nonsenseIncrement(increment: Double) {
    let step = LoadStep(machineIncrementKg: increment, unit: .kilograms)
    #expect(step.amount == 2.5)
    #expect(step.source == .unitDefault)
  }

  @Test("A step never creates a value from nothing")
  func nilStaysNil() {
    #expect(LoadStep(machineIncrementKg: nil, unit: .kilograms).moved(nil, by: 1) == nil)
  }

  @Test("Below zero is refused; down to exactly zero is allowed")
  func floorAtZero() {
    let step = LoadStep(machineIncrementKg: nil, unit: .kilograms)
    #expect(step.moved(1, by: -1) == nil)
    #expect(step.moved(2.5, by: -1) == 0)
  }
}

@Suite("The keypad edits a set the way a lifter expects")
struct SetEntryKeypadTests {
  let posix = Locale(identifier: "en_US_POSIX")

  private func keypad(
    _ weightKg: Double?, _ reps: Int?, unit: WeightUnit = .kilograms, increment: Double? = nil
  ) -> SetEntryKeypad {
    SetEntryKeypad(
      draft: SetEntryDraft(weightKg: weightKg, reps: reps), unit: unit,
      machineIncrementKg: increment
    )
  }

  @Test("100 to 102.5 is one ± press on plates")
  func onePress() {
    var pad = keypad(100, 8)
    pad.step(.up)
    #expect(pad.draft.weightKg == 102.5)
    #expect(pad.draft.reps == 8)
  }

  @Test("On a 5 kg stack, ± moves 5 kg")
  func stackStep() {
    var pad = keypad(100, 8, increment: 5)
    pad.step(.up)
    #expect(pad.draft.weightKg == 105)
    pad.step(.down)
    pad.step(.down)
    #expect(pad.draft.weightKg == 95)
  }

  @Test("± never invents a weight for an empty field")
  func noValueFromNil() {
    var pad = keypad(nil, 8)
    pad.step(.up)
    #expect(pad.draft.weightKg == nil)
    #expect(!pad.draft.isLoggable)
  }

  @Test("Typing replaces the prefill: 102.5 in five presses")
  func typed() {
    var pad = keypad(100, 8)
    pad.type(digit: 1)
    pad.type(digit: 0)
    pad.type(digit: 2)
    pad.typeDecimalSeparator()
    pad.type(digit: 5)
    #expect(pad.draft.weightKg == 102.5)
  }

  @Test("A stepped value is replaced by the next digit, like a prefill")
  func stepResultIsSelected() {
    var pad = keypad(100, 8)
    pad.step(.up)
    pad.type(digit: 9)
    pad.type(digit: 0)
    #expect(pad.draft.weightKg == 90)
  }

  @Test("Next moves weight to reps and selects it; from reps there is nothing next")
  func next() {
    var pad = keypad(100, 8)
    #expect(pad.field == .weight)
    #expect(pad.advance())
    #expect(pad.field == .reps)
    pad.type(digit: 1)
    pad.type(digit: 0)
    #expect(pad.draft.reps == 10)
    #expect(!pad.advance())
    #expect(pad.field == .reps)
  }

  @Test("Clear empties only the focused field and leaves no zero behind")
  func clearFocusedOnly() {
    var pad = keypad(100, 8)
    pad.clear()
    #expect(pad.draft.weightKg == nil)
    #expect(pad.draft.reps == 8)
    #expect(!pad.draft.isLoggable)
  }

  @Test("Reps step by one, never below one")
  func repsStep() {
    var pad = keypad(100, 1)
    pad.advance()
    pad.step(.down)
    #expect(pad.draft.reps == 1)
    pad.step(.up)
    pad.step(.up)
    #expect(pad.draft.reps == 3)
  }

  @Test("A weight past what the field can hold is refused")
  func ceiling() {
    var pad = keypad(9_998, 5)
    pad.step(.up)
    #expect(pad.draft.weightKg == 9_998)
  }

  /// Review Focus: the display holds 132.28 lb; storage holds 60 kg. Touching only the reps must
  /// not rewrite the weight from the rounded display.
  @Test("Changing only the reps in pounds leaves the stored kilograms exactly as they were")
  func untouchedWeightKeepsCanonicalValue() {
    var pad = keypad(60, 8, unit: .pounds)
    #expect(pad.weight.displayText == "132.28")
    pad.advance()
    pad.type(digit: 9)
    #expect(pad.draft.weightKg == 60)
    #expect(pad.draft.reps == 9)
  }

  @Test("A key that changes nothing, and moving between fields, are not edits")
  func noOpIsNotAnEdit() {
    var pad = keypad(60, 8, unit: .pounds)
    pad.advance()
    pad.typeDecimalSeparator()  // inert on reps
    pad.focus(.weight)  // focusing selects; it does not edit
    #expect(pad.draft.weightKg == 60)
    #expect(pad.draft.reps == 8)
  }

  @Test("Typed pounds are stored as kilograms")
  func poundsToKilograms() throws {
    var pad = keypad(nil, nil, unit: .pounds)
    pad.type(digit: 2)
    pad.type(digit: 2)
    pad.type(digit: 5)
    let kilograms = try #require(pad.draft.weightKg)
    #expect(abs(kilograms - 102.058_283_25) < 1e-6)
  }

  @Test("The header shows what is being composed, in the locale's notation")
  func header() {
    var pad = keypad(100, 8)
    #expect(pad.composedText(locale: posix) == "100 kg × 8")
    pad.step(.up)
    #expect(pad.composedText(locale: posix) == "102.5 kg × 8")
    #expect(pad.composedText(locale: Locale(identifier: "de_DE")) == "102,5 kg × 8")
    #expect(keypad(nil, nil).composedText(locale: posix) == "— kg × —")
  }

  @Test("The draft's suggestion survives editing")
  func suggestionKept() {
    let last = PriorSetRecord(weightKg: 100, reps: 8, completedAt: .distantPast)
    var pad = SetEntryKeypad(
      draft: SetEntryDraft(suggestion: last), unit: .kilograms, machineIncrementKg: nil
    )
    pad.step(.up)
    #expect(pad.draft.suggestion == last)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'ReplaceOnFirstInputTests|LoadStepTests|SetEntryKeypadTests'`
Expected: compile failure, `value of type 'NumericEntryBuffer' has no member
'replacesOnNextInput'` and `cannot find 'LoadStep' in scope`.

- [ ] **Step 3: Implement**

In `NumericEntryBuffer.swift`, add the stored property under `text` (line 16):

```swift
  /// True while the text is a value the lifter did not type: a prefill, or the result of a ± step.
  ///
  /// The next digit or decimal point then replaces it instead of appending, the way a selected
  /// field behaves. Typing "105" over a "100" prefill used to mean three deletes first; now it is
  /// three keys. Deleting edits the value instead, because "fix the last digit" is the other
  /// thing a lifter means.
  public private(set) var replacesOnNextInput: Bool
```

In `init(text:...)` (lines 21–31) add `self.replacesOnNextInput = false`. At the end of
`init(value:...)` (after the `self.init(...)` call at lines 56–61) add:

```swift
    // A prefill is shown as a value, but nobody typed it: the first key replaces it.
    self.replacesOnNextInput = !seed.isEmpty
```

Replace the four mutators (lines 91–116) with:

```swift
  public mutating func append(digit: Int) {
    guard (0...9).contains(digit) else { return }
    takeOverSelection()
    // A single leading zero is meaningful ("0.5"); a second one is not.
    if text == "0" { text = String(digit); return }

    if let separatorIndex = text.firstIndex(of: ".") {
      let fraction = text.distance(from: text.index(after: separatorIndex), to: text.endIndex)
      guard fraction < maximumFractionDigits else { return }
    } else {
      guard text.count < maximumIntegerDigits else { return }
    }
    text.append(String(digit))
  }

  public mutating func appendDecimalSeparator() {
    // Checked before replacing: the reps pad's inert decimal key must not wipe a prefill.
    guard allowsDecimal else { return }
    takeOverSelection()
    guard !text.contains(".") else { return }
    // Leading "." is ambiguous to read on a dense row; make it explicit.
    text = text.isEmpty ? "0." : text + "."
  }

  public mutating func deleteBackward() {
    replacesOnNextInput = false
    guard !text.isEmpty else { return }
    text.removeLast()
  }

  public mutating func clear() {
    text = ""
    replacesOnNextInput = false
  }

  /// Selects the whole value, so the next key replaces it. Focusing a field calls this. An empty
  /// field has nothing to select.
  public mutating func selectForReplacement() {
    replacesOnNextInput = !text.isEmpty
  }

  private mutating func takeOverSelection() {
    guard replacesOnNextInput else { return }
    text = ""
    replacesOnNextInput = false
  }
```

`LoadStep.swift`:

```swift
import Foundation

/// How far one ± press moves a load, in the unit the lifter reads.
///
/// The machine's own stack increment when it is known, because a +2.5 kg press on a stack that
/// moves in 5 kg jumps proposes a weight the machine cannot be set to. Otherwise the unit's plate
/// step. Steps only adjust a value that exists: an empty field stays empty, since a ± that
/// invented a load would be a `?? 0` with extra steps.
public struct LoadStep: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    /// The machine's `stackIncrementKg`.
    case machine
    /// No usable increment is known, so 2.5 kg or 5 lb.
    case unitDefault
  }

  /// The step in display units. A 5 kg stack read in pounds steps by 11.02 lb, which is what the
  /// pin really moves.
  public let amount: Double
  public let source: Source

  public init(machineIncrementKg: Double?, unit: WeightUnit) {
    if let increment = machineIncrementKg, increment.isFinite, increment > 0 {
      amount = unit.fromKilograms(increment)
      source = .machine
    } else {
      amount = unit.plateIncrement
      source = .unitDefault
    }
  }

  /// `value` moved by `steps` increments, or nil when nothing should change: there is no value
  /// to move, or the result would be negative.
  public func moved(_ value: Double?, by steps: Int) -> Double? {
    guard let value else { return nil }
    let result = value + amount * Double(steps)
    // The tolerance absorbs binary noise, so 2.5 − 2.5 lands on zero rather than a hair below it.
    guard result > -1e-9 else { return nil }
    return max(0, result)
  }
}
```

`SetEntryKeypad.swift`:

```swift
import Foundation

/// The logger's keypad, as a value: two fields, which one is focused, and what each key does.
///
/// It lives here, not in a view, because every rule in it is a way the number on screen and the
/// number saved could part company, and those rules have to be tested where a compiler can run
/// them. The view renders `weight`, `reps` and `composedText`, and writes `draft` back.
public struct SetEntryKeypad: Hashable, Sendable {
  public enum Field: Hashable, Sendable { case weight, reps }
  public enum Direction: Hashable, Sendable { case down, up }

  public private(set) var weight: NumericEntryBuffer
  public private(set) var reps: NumericEntryBuffer
  public private(set) var field: Field
  public let unit: WeightUnit
  public let loadStep: LoadStep

  private let base: SetEntryDraft
  private var weightEdited = false
  private var repsEdited = false

  public init(
    draft: SetEntryDraft, unit: WeightUnit, machineIncrementKg: Double?, field: Field = .weight
  ) {
    self.base = draft
    self.unit = unit
    self.loadStep = LoadStep(machineIncrementKg: machineIncrementKg, unit: unit)
    self.weight = Self.weightBuffer(draft.weightKg.map(unit.fromKilograms))
    self.reps = Self.repsBuffer(draft.reps.map(Double.init))
    self.field = field
  }

  public var focused: NumericEntryBuffer { field == .weight ? weight : reps }

  public mutating func type(digit: Int) { edit { $0.append(digit: digit) } }
  public mutating func typeDecimalSeparator() { edit { $0.appendDecimalSeparator() } }
  public mutating func deleteBackward() { edit { $0.deleteBackward() } }
  /// Empties the focused field only. The draft then has no value there, not zero.
  public mutating func clear() { edit { $0.clear() } }

  /// ± on the focused field: `loadStep` for weight, one rep for reps. Refused, leaving everything
  /// as it was, when there is no value to move or the result would not be a valid entry.
  public mutating func step(_ direction: Direction) {
    let steps = direction == .up ? 1 : -1
    switch field {
    case .weight:
      // Four integer digits is what the field displays; a step past it would show a number the
      // keypad itself could never have produced.
      guard let moved = loadStep.moved(weight.value, by: steps), moved < 10_000 else { return }
      weight = Self.weightBuffer(moved)
      weightEdited = true
    case .reps:
      guard let current = reps.value else { return }
      let next = Int(current) + steps
      guard (1...999).contains(next) else { return }
      reps = Self.repsBuffer(Double(next))
      repsEdited = true
    }
  }

  /// Weight → reps. Returns false when there is no next field: the pad's cue to close.
  @discardableResult
  public mutating func advance() -> Bool {
    guard field == .weight else { return false }
    focus(.reps)
    return true
  }

  /// Focusing a field selects it, so the first key replaces what it shows.
  public mutating func focus(_ field: Field) {
    self.field = field
    switch field {
    case .weight: weight.selectForReplacement()
    case .reps: reps.selectForReplacement()
    }
  }

  /// What the fields describe, in canonical kilograms.
  ///
  /// A field the lifter did not change keeps the draft's own value. Re-deriving it from the
  /// rounded display would turn a 60 kg set into 60.0013 kg the moment a pounds user changed
  /// only the reps, and the row would then save a weight nobody entered.
  public var draft: SetEntryDraft {
    SetEntryDraft(
      weightKg: weightEdited ? weight.value.map(unit.toKilograms) : base.weightKg,
      reps: repsEdited ? reps.value.map { Int($0) } : base.reps,
      suggestion: base.suggestion
    )
  }

  /// The value being composed, for the pad's header: "102.5 kg × 8". An empty field shows "—",
  /// never "0". The stored text always uses ".", so the locale's separator is substituted here.
  public func composedText(locale: Locale = .current) -> String {
    let separator = locale.decimalSeparator ?? "."
    let weightText =
      weight.isEmpty ? "—" : weight.displayText.replacingOccurrences(of: ".", with: separator)
    let repsText = reps.isEmpty ? "—" : reps.displayText
    return "\(weightText) \(unit.abbreviation) × \(repsText)"
  }

  /// Applies a key to the focused field. A key that changes no text (the inert decimal on reps,
  /// delete on an empty field) is not an edit, so it cannot trigger a re-derivation.
  private mutating func edit(_ change: (inout NumericEntryBuffer) -> Void) {
    switch field {
    case .weight:
      let before = weight.text
      change(&weight)
      if weight.text != before { weightEdited = true }
    case .reps:
      let before = reps.text
      change(&reps)
      if reps.text != before { repsEdited = true }
    }
  }

  private static func weightBuffer(_ value: Double?) -> NumericEntryBuffer {
    NumericEntryBuffer(value: value, maximumIntegerDigits: 4, maximumFractionDigits: 2)
  }

  private static func repsBuffer(_ value: Double?) -> NumericEntryBuffer {
    NumericEntryBuffer(
      value: value, allowsDecimal: false, maximumIntegerDigits: 3, maximumFractionDigits: 0
    )
  }
}
```

The buffer limits match `SetRowView`'s (4 integer and 2 fraction digits for weight; 3 and 0 for
reps), so a keypad seeds exactly what the row shows.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'ReplaceOnFirstInputTests|LoadStepTests|SetEntryKeypadTests'`
Expected: all three suites pass.

Then run `Tools/linux-test.sh` in full. It must pass. `EntryTests.swift`'s `deleteToEmpty` and
`clearing` still hold: deleting a seeded "60" edits it to "6" and then to "", and `clear` empties
it.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/NumericEntryBuffer.swift \
  Packages/HardsetKit/Sources/HardsetCore/LoadStep.swift \
  Packages/HardsetKit/Sources/HardsetCore/SetEntryKeypad.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/SetEntryKeypadTests.swift
git commit -m "feat(core): a keypad whose first key replaces the prefill

Changing a 100 kg prefill to 102.5 took ten presses: three deletes, then the
digits. The first key now replaces a prefill, and ± moves by the machine's real
stack increment, or 2.5 kg / 5 lb without one. That makes it two presses, or five
typed.

± never creates a value from an empty field. A field the lifter did not touch
keeps its canonical kilograms, so a pounds user changing only the reps no longer
rewrites 60 kg as 60.0013 kg from the rounded display.

Co-Authored-By: <your model's trailer>"
```

---

### Task 2: Session flow — the finish decision and the active set (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/SessionFlow.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/SessionFlowTests.swift`

**Interfaces:**
- Consumes: `ExerciseLogState` (`.id`, `.slots`), and `SetSlot` (`.id`, `.isLogged`,
  `.draft.isLoggable`).
- Produces:
  - `public enum FinishDecision: Hashable, Sendable`, with the cases `finish`,
    `confirmUnlogged(count: Int)` and `discardEmpty`.
  - `public enum FinishFlow`, with:
    - `static func decision(for: [ExerciseLogState]) -> FinishDecision`
    - `static func unloggedTitle(count: Int) -> String`
    - `static let discardTitle: String`
    - `static let discardMessage: String`
  - `public struct ActiveSet: Hashable, Sendable`, with:
    - `let exerciseID: UUID` (an `ExerciseLogState.id`)
    - `let slotID: UUID`
    - `init(exerciseID:slotID:)`
    - `static func next(in: [ExerciseLogState], after lastLogged: UUID?) -> ActiveSet?`

The copy, verbatim:
- `unloggedTitle(count: 1)` is "1 set wasn't logged and won't be saved".
- `unloggedTitle(count: n)` is "n sets weren't logged and won't be saved".
- `discardTitle` is "Nothing was logged".
- `discardMessage` is "There's nothing to save, so this workout will be discarded."

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Finishing asks only when something would be lost")
struct FinishFlowTests {
  private func exercise(_ slots: [SetSlot]) -> ExerciseLogState {
    ExerciseLogState(exerciseID: ExerciseID(), exerciseName: "Leg Press", prior: nil, slots: slots)
  }
  private func logged(_ weight: Double = 100, warmup: Bool = false) -> SetSlot {
    SetSlot(draft: SetEntryDraft(weightKg: weight, reps: 8), isWarmup: warmup, loggedSetID: SetID())
  }
  private func prefilled(warmup: Bool = false) -> SetSlot {
    SetSlot(draft: SetEntryDraft(weightKg: 100, reps: 8), isWarmup: warmup)
  }
  private func empty() -> SetSlot { SetSlot(draft: SetEntryDraft(weightKg: nil, reps: nil)) }
  private func halfTyped() -> SetSlot { SetSlot(draft: SetEntryDraft(weightKg: 100, reps: nil)) }

  @Test("Everything with values was logged: finish without asking")
  func finishes() {
    #expect(FinishFlow.decision(for: [exercise([logged(), logged(), empty()])]) == .finish)
  }

  @Test("Prefilled rows never logged are counted, warm-ups included")
  func countsUnlogged() {
    let decision = FinishFlow.decision(for: [
      exercise([logged(), prefilled(), prefilled(warmup: true)]),
      exercise([prefilled(), empty(), halfTyped()]),
    ])
    #expect(decision == .confirmUnlogged(count: 3))
  }

  @Test("Nothing logged: the only thing to offer is discarding")
  func nothingLogged() {
    #expect(FinishFlow.decision(for: [exercise([prefilled(), prefilled()])]) == .discardEmpty)
    #expect(FinishFlow.decision(for: []) == .discardEmpty)
  }

  @Test("A logged warm-up is logged work: the workout is not empty")
  func warmupCounts() {
    #expect(FinishFlow.decision(for: [exercise([logged(warmup: true)])]) == .finish)
  }

  @Test("The warning names the count, with the noun agreeing")
  func copy() {
    #expect(FinishFlow.unloggedTitle(count: 1) == "1 set wasn't logged and won't be saved")
    #expect(FinishFlow.unloggedTitle(count: 2) == "2 sets weren't logged and won't be saved")
    #expect(FinishFlow.discardTitle == "Nothing was logged")
    #expect(
      FinishFlow.discardMessage == "There's nothing to save, so this workout will be discarded.")
  }
}

@Suite("The current set is the one the lifter is about to do")
struct ActiveSetTests {
  private func slot(logged: Bool) -> SetSlot {
    SetSlot(
      draft: SetEntryDraft(weightKg: 100, reps: 8), loggedSetID: logged ? SetID() : nil)
  }
  private func exercise(_ logged: [Bool]) -> ExerciseLogState {
    ExerciseLogState(
      exerciseID: ExerciseID(), exerciseName: "Lift", prior: nil,
      slots: logged.map { slot(logged: $0) })
  }

  @Test("Nothing logged yet: the first row")
  func first() {
    let session = [exercise([false, false]), exercise([false])]
    #expect(
      ActiveSet.next(in: session, after: nil)
        == ActiveSet(exerciseID: session[0].id, slotID: session[0].slots[0].id))
  }

  @Test("After a log, the next row of the same exercise")
  func nextInExercise() {
    let session = [exercise([true, false, false])]
    #expect(
      ActiveSet.next(in: session, after: session[0].slots[0].id)?.slotID
        == session[0].slots[1].id)
  }

  @Test("After an exercise's last row, the next exercise")
  func nextExercise() {
    let session = [exercise([true, true]), exercise([false])]
    #expect(
      ActiveSet.next(in: session, after: session[0].slots[1].id)?.slotID
        == session[1].slots[0].id)
  }

  @Test("Logging out of order follows the lifter, then wraps to what was skipped")
  func followsTheLifter() {
    let session = [exercise([true, false]), exercise([true, false])]
    #expect(
      ActiveSet.next(in: session, after: session[1].slots[0].id)?.slotID
        == session[1].slots[1].id)
    let done = [exercise([true, false]), exercise([true, true])]
    #expect(
      ActiveSet.next(in: done, after: done[1].slots[1].id)?.slotID == done[0].slots[1].id)
  }

  @Test("A last-logged row that no longer exists falls back to the first open row")
  func unknownLastLogged() {
    let session = [exercise([true, false])]
    #expect(ActiveSet.next(in: session, after: UUID())?.slotID == session[0].slots[1].id)
  }

  @Test("Everything logged: there is no current set")
  func allDone() {
    let session = [exercise([true, true])]
    #expect(ActiveSet.next(in: session, after: session[0].slots[1].id) == nil)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'FinishFlowTests|ActiveSetTests'`
Expected: compile failure, `cannot find 'FinishFlow' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// What Finish should do, decided from the rows rather than from a view's guess.
public enum FinishDecision: Hashable, Sendable {
  /// Every row holding a set was logged. Finish without asking.
  case finish
  /// Rows hold complete values that were never logged. Ask, and say how many will be lost.
  case confirmUnlogged(count: Int)
  /// Nothing was logged at all. There is nothing to save, so the choice is to discard.
  case discardEmpty
}

public enum FinishFlow {
  /// Counts rows that look like sets, meaning complete and loggable, that were never logged.
  /// Empty and half-typed rows are not sets and are not counted. Zero logged sets is never a
  /// "finish": an empty workout in history is noise that looks like a session that happened.
  public static func decision(for exercises: [ExerciseLogState]) -> FinishDecision {
    let slots = exercises.flatMap(\.slots)
    guard slots.contains(where: \.isLogged) else { return .discardEmpty }
    let unlogged = slots.count { !$0.isLogged && $0.draft.isLoggable }
    return unlogged == 0 ? .finish : .confirmUnlogged(count: unlogged)
  }

  public static func unloggedTitle(count: Int) -> String {
    count == 1
      ? "1 set wasn't logged and won't be saved"
      : "\(count) sets weren't logged and won't be saved"
  }

  public static let discardTitle = "Nothing was logged"
  public static let discardMessage = "There's nothing to save, so this workout will be discarded."
}

/// The set the lifter is about to do: the one the screen emphasises and scrolls to.
public struct ActiveSet: Hashable, Sendable {
  /// `ExerciseLogState.id`.
  public let exerciseID: UUID
  /// `SetSlot.id`.
  public let slotID: UUID

  public init(exerciseID: UUID, slotID: UUID) {
    self.exerciseID = exerciseID
    self.slotID = slotID
  }

  /// The first unlogged row after `lastLogged` in session order, wrapping to the first unlogged
  /// row from the top.
  ///
  /// It follows the lifter rather than the plan: someone who jumps to a free machine is doing
  /// that set now. With nothing logged yet, or a `lastLogged` that was since deleted, it is the
  /// first open row. Nil when everything is logged.
  public static func next(in exercises: [ExerciseLogState], after lastLogged: UUID?) -> ActiveSet? {
    let rows = exercises.flatMap { exercise in
      exercise.slots.map { (exercise: exercise.id, slot: $0) }
    }
    let start = lastLogged.flatMap { id in rows.firstIndex { $0.slot.id == id } }.map { $0 + 1 } ?? 0
    let ordered = rows[start...] + rows[..<start]
    return ordered.first { !$0.slot.isLogged }.map {
      ActiveSet(exerciseID: $0.exercise, slotID: $0.slot.id)
    }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'FinishFlowTests|ActiveSetTests'`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/SessionFlow.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/SessionFlowTests.swift
git commit -m "feat(core): decide what Finish does, and which set is current

Finishing silently dropped prefilled rows that were never logged, and saved empty
workouts into history. The decision is now made from the rows: finish, warn with
the exact count of sets that won't be saved, or offer discard when nothing was
logged. The current set follows the lifter rather than the plan, so the screen
can lead with the one they are about to do.

Co-Authored-By: <your model's trailer>"
```

---

### Task 3: The record moment in Core — feedback events and record copy

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/FeedbackEvent.swift`
- Create: `Packages/HardsetKit/Sources/HardsetCore/RecordCopy.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/RecordMomentCopyTests.swift`

**Interfaces:**
- Consumes:
  - `PersonalRecord` and `PersonalRecordKind.label`
  - `WeightFormatter`: `load`, `estimate`, `spoken` and `unit`
  - `CountText.reps`
  - `StrengthMath.estimatedOneRepMax` and `StrengthMath.displayRounded(_:in:)`
- Produces:
  - `public enum FeedbackEvent: Hashable, Sendable`, with the cases `log`, `record`, `error` and
    `restAdjust`, and
    `static func afterLogging(records: [PersonalRecord]) -> FeedbackEvent`.
  - `public struct FeedbackPulse: Hashable, Sendable`, with:
    - `let event: FeedbackEvent`, `let sequence: Int` and `let slotID: UUID?`
    - `init(event:sequence:slotID:)`
    - `static func following(_ previous: FeedbackPulse?, event: FeedbackEvent, slotID: UUID? = nil) -> FeedbackPulse`
  - `public enum RecordCopy`, with:
    - `static func detail(for: PersonalRecord, formatter: WeightFormatter) -> String`
    - `static func line(for: PersonalRecord, formatter: WeightFormatter) -> String`
    - `static func announcement(for: [PersonalRecord], exerciseName: String, formatter: WeightFormatter) -> String?`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("One haptic per thing that happened")
struct FeedbackEventTests {
  @Test("A record outranks an ordinary log")
  func recordOutranksLog() {
    #expect(FeedbackEvent.afterLogging(records: []) == .log)
    let record = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)
    #expect(FeedbackEvent.afterLogging(records: [record]) == .record)
  }

  @Test("Two identical events in a row are still two pulses")
  func pulsesAreDistinct() {
    let row = UUID()
    let first = FeedbackPulse.following(nil, event: .log, slotID: row)
    let second = FeedbackPulse.following(first, event: .log, slotID: row)
    #expect(first.sequence == 1)
    #expect(second.sequence == 2)
    #expect(first != second)
    #expect(second.slotID == row)
  }
}

@Suite("A record states what it beat, in the lifter's unit")
struct RecordCopyTests {
  let posix = Locale(identifier: "en_US_POSIX")
  var kilograms: WeightFormatter { WeightFormatter(unit: .kilograms, locale: posix) }
  var pounds: WeightFormatter { WeightFormatter(unit: .pounds, locale: posix) }

  let heaviest = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)
  let reps = PersonalRecord(
    kind: .repsAtLoad, weightKg: 100, reps: 9, previousWeightKg: 100, previousReps: 8)
  // 100 × 5 estimates 116.67 kg; the best before was 110 kg.
  let estimate = PersonalRecord(
    kind: .estimatedOneRepMax, weightKg: 100, reps: 5, previousWeightKg: 110)

  @Test("Heaviest weight names the new load and the old one")
  func heaviestCopy() {
    #expect(RecordCopy.detail(for: heaviest, formatter: kilograms) == "105 kg, up from 100 kg")
    #expect(
      RecordCopy.line(for: heaviest, formatter: kilograms)
        == "Heaviest weight: 105 kg, up from 100 kg")
    #expect(
      RecordCopy.detail(for: heaviest, formatter: pounds) == "231.49 lb, up from 220.46 lb")
  }

  @Test("Reps at a load names the load and the old count")
  func repsCopy() {
    #expect(RecordCopy.detail(for: reps, formatter: kilograms) == "9 reps at 100 kg, up from 8")
  }

  @Test("An estimate states the new estimate, called an estimate, never in kilograms in pounds mode")
  func estimateCopy() {
    #expect(
      RecordCopy.detail(for: estimate, formatter: kilograms)
        == "about 116.5 kg, up from about 110 kg")
    let inPounds = RecordCopy.detail(for: estimate, formatter: pounds)
    #expect(inPounds == "about 257 lb, up from about 243 lb")
    #expect(!inPounds.contains("kg"))
  }

  @Test("VoiceOver hears the movement and the units in full")
  func announcement() {
    #expect(
      RecordCopy.announcement(for: [heaviest], exerciseName: "Leg Press", formatter: kilograms)
        == "New record on Leg Press. Heaviest weight: 105 kilograms, up from 100 kilograms.")
    let both = RecordCopy.announcement(
      for: [heaviest, estimate], exerciseName: "Leg Press", formatter: pounds)
    #expect(both?.hasPrefix("New records on Leg Press.") == true)
    #expect(both?.contains("Best estimated 1RM: about 257 pounds") == true)
    #expect(both?.contains("lb") == false)
  }

  @Test("Nothing to announce is nil, not an empty string")
  func nothing() {
    #expect(RecordCopy.announcement(for: [], exerciseName: "Leg Press", formatter: kilograms) == nil)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'FeedbackEventTests|RecordCopyTests'`
Expected: compile failure, `cannot find 'FeedbackEvent' in scope`.

- [ ] **Step 3: Implement**

`FeedbackEvent.swift`:

```swift
import Foundation

/// The things worth a haptic, named here so the UI only maps them and decides nothing.
///
/// Four, on purpose. The HIG asks for restraint on frequent actions, and the spec gives the app
/// exactly one celebratory moment: a record (spec §3, items 4, 5 and 7).
public enum FeedbackEvent: Hashable, Sendable {
  case log
  case record
  case error
  case restAdjust

  /// The single event a successful log produces. A record set plays only the record haptic, so
  /// the moment is distinct rather than a log haptic with something added.
  public static func afterLogging(records: [PersonalRecord]) -> FeedbackEvent {
    records.isEmpty ? .log : .record
  }
}

/// One occurrence of an event.
///
/// The sequence number makes two identical events in a row two different values, which is what
/// a `sensoryFeedback(trigger:)` needs to fire twice. `slotID` names the row it is about, so the
/// screen can bounce that row's trophy and find what to announce.
public struct FeedbackPulse: Hashable, Sendable {
  public let event: FeedbackEvent
  public let sequence: Int
  public let slotID: UUID?

  public init(event: FeedbackEvent, sequence: Int, slotID: UUID? = nil) {
    self.event = event
    self.sequence = sequence
    self.slotID = slotID
  }

  public static func following(
    _ previous: FeedbackPulse?, event: FeedbackEvent, slotID: UUID? = nil
  ) -> FeedbackPulse {
    FeedbackPulse(event: event, sequence: (previous?.sequence ?? 0) + 1, slotID: slotID)
  }
}
```

`RecordCopy.swift`:

```swift
import Foundation

/// What a record says, on the row, in the summary and to VoiceOver.
///
/// Every line names what was beaten, so the claim can be checked rather than taken on trust. An
/// estimate is called "about" and is rounded like every derived number (guideline 1.4.1). It is
/// always in the lifter's unit: the PR banner was one of the places pounds mode read kilograms.
public enum RecordCopy {
  /// "105 kg, up from 100 kg".
  public static func detail(for record: PersonalRecord, formatter f: WeightFormatter) -> String {
    switch record.kind {
    case .heaviestLoad:
      let new = f.load(kilograms: record.weightKg)
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(f.load(kilograms: previous))"
    case .repsAtLoad:
      let new = "\(CountText.reps(record.reps)) at \(f.load(kilograms: record.weightKg))"
      guard let previousReps = record.previousReps else { return new }
      return "\(new), up from \(previousReps)"
    case .estimatedOneRepMax:
      let new = newEstimate(of: record).map { f.estimate(kilograms: $0) } ?? "estimated"
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(f.estimate(kilograms: previous))"
    }
  }

  /// "Heaviest weight: 105 kg, up from 100 kg".
  public static func line(for record: PersonalRecord, formatter: WeightFormatter) -> String {
    "\(record.kind.label): \(detail(for: record, formatter: formatter))"
  }

  /// Spoken when a set earns records, with units in full. Nil when there is nothing to say.
  public static func announcement(
    for records: [PersonalRecord], exerciseName: String, formatter: WeightFormatter
  ) -> String? {
    guard !records.isEmpty else { return nil }
    let lead =
      records.count == 1 ? "New record on \(exerciseName)." : "New records on \(exerciseName)."
    let parts = records.map { "\($0.kind.label): \(spokenDetail(for: $0, formatter: formatter))." }
    return ([lead] + parts).joined(separator: " ")
  }

  static func spokenDetail(for record: PersonalRecord, formatter f: WeightFormatter) -> String {
    switch record.kind {
    case .heaviestLoad:
      let new = f.spoken(kilograms: record.weightKg)
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(f.spoken(kilograms: previous))"
    case .repsAtLoad:
      let new = "\(CountText.reps(record.reps)) at \(f.spoken(kilograms: record.weightKg))"
      guard let previousReps = record.previousReps else { return new }
      return "\(new), up from \(previousReps)"
    case .estimatedOneRepMax:
      let new = newEstimate(of: record).map { spokenEstimate($0, f) } ?? "estimated"
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(spokenEstimate(previous, f))"
    }
  }

  /// The record set's own estimate. `PersonalRecord` stores the set, not the estimate, so it is
  /// derived here the one way the detector derived it.
  private static func newEstimate(of record: PersonalRecord) -> Double? {
    StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps).value
  }

  /// Rounded exactly as the written estimate is, then spoken.
  private static func spokenEstimate(_ kilograms: Double, _ f: WeightFormatter) -> String {
    let rounded = StrengthMath.displayRounded(kilograms, in: f.unit)
    return "about \(f.spoken(kilograms: f.unit.toKilograms(rounded)))"
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'FeedbackEventTests|RecordCopyTests'`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/FeedbackEvent.swift \
  Packages/HardsetKit/Sources/HardsetCore/RecordCopy.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/RecordMomentCopyTests.swift
git commit -m "feat(core): name the haptic moments and the words a record uses

The record moment needs a distinct haptic, a row trophy, a summary line and a
VoiceOver announcement. They have to agree, and none of them can be tested in a
view. Four feedback events, with a record outranking a log, and one copy table
that states the new value, what it beat, and calls an estimate an estimate in
the lifter's unit.

Co-Authored-By: <your model's trailer>"
```

---

### Task 4: Session record replay (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/SessionRecordReplay.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/SessionRecordReplayTests.swift`

**Interfaces:**
- Consumes: `PersonalRecordDetector.records(for:history:increment:)`, `PriorSetRecord`,
  `ProgressionKey`, `SetID` and `MachineID`.
- Produces: `public enum SessionRecordReplay`, with:
  - nested `public struct Entry: Hashable, Sendable`, holding `setID`, `key`, `weightKg`, `reps`,
    `isWarmup` and `completedAt`, with a memberwise `public init`
  - `static func records(session: [Entry], priorHistory: [ProgressionKey: [PriorSetRecord]], increments: [MachineID: Double]) -> [SetID: [PersonalRecord]]`

The function replays a session's sets in performed order. Each is judged as `logSet` judged it:
against `priorHistory` for its key, plus this session's earlier working sets on the same key.
Warm-ups are never records and never become history. A key's increment comes from `increments`
for its machine; with none, the detector's default applies.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("A session's records, replayed exactly as they were judged live")
struct SessionRecordReplayTests {
  let day = Date(timeIntervalSince1970: 1_000_000)
  let press = ProgressionKey(exerciseID: ExerciseID())

  private func entry(
    _ weight: Double, _ reps: Int, key: ProgressionKey? = nil, warmup: Bool = false
  ) -> SessionRecordReplay.Entry {
    SessionRecordReplay.Entry(
      setID: SetID(), key: key ?? press, weightKg: weight, reps: reps, isWarmup: warmup,
      completedAt: day)
  }
  private func history(_ sets: [(Double, Int)]) -> [PriorSetRecord] {
    sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: .distantPast) }
  }

  @Test("The first set ever on a lift is never a record")
  func firstEver() {
    let only = entry(100, 8)
    #expect(SessionRecordReplay.records(session: [only], priorHistory: [:], increments: [:]).isEmpty)
  }

  @Test("A later set is judged against this session's earlier sets too")
  func earlierSetsCount() {
    let first = entry(100, 8)
    let second = entry(105, 8)
    let result = SessionRecordReplay.records(
      session: [first, second], priorHistory: [:], increments: [:])
    #expect(result[first.setID] == nil)
    #expect(result[second.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("Repeating the best is not a record")
  func repeatIsNot() {
    let same = entry(100, 8)
    let result = SessionRecordReplay.records(
      session: [same], priorHistory: [press: history([(100, 8)])], increments: [:])
    #expect(result.isEmpty)
  }

  @Test("A heavy warm-up is never a record and never raises the bar")
  func warmupsAreInvisible() {
    let warmup = entry(140, 3, warmup: true)
    let working = entry(110, 8)
    let result = SessionRecordReplay.records(
      session: [warmup, working], priorHistory: [press: history([(100, 8)])], increments: [:])
    #expect(result[warmup.setID] == nil)
    #expect(result[working.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("A machine's increment sets the margin")
  func machineIncrementMargin() {
    let machine = MachineID()
    let stack = ProgressionKey(exerciseID: press.exerciseID, machineID: machine)
    let set = entry(104, 1, key: stack)
    let onStack = SessionRecordReplay.records(
      session: [set], priorHistory: [stack: history([(100, 1)])], increments: [machine: 5])
    #expect(onStack[set.setID]?.contains { $0.kind == .heaviestLoad } != true)
    let onPlates = SessionRecordReplay.records(
      session: [set], priorHistory: [stack: history([(100, 1)])], increments: [:])
    #expect(onPlates[set.setID]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("Another machine's history is not this machine's")
  func seriesNeverMerge() {
    let other = ProgressionKey(exerciseID: press.exerciseID, machineID: MachineID())
    let set = entry(100, 8)
    let result = SessionRecordReplay.records(
      session: [set], priorHistory: [other: history([(60, 8)])], increments: [:])
    #expect(result.isEmpty)
  }
}
```

In `machineIncrementMargin`, 104 × 1 on a 5 kg stack needs 100 + max(2.5, 5) = 105, so it is not a
record. On plates it needs 102.5, so it is. Singles compare estimated 1RM as the load itself, by the
same 2.5% rule, so only the heaviest-load kind is asserted.

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter SessionRecordReplayTests`
Expected: compile failure, `cannot find 'SessionRecordReplay' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Re-judges a session's sets for records after the fact, by the same rules as the moment.
///
/// `SessionCoordinator.logSet` reads history *before* each write and judges the set against it
/// (`DECISIONS.md` §12). Replaying a session's sets in order against the history that preceded
/// it gives the same verdicts. A summary, a resumed workout and a corrected set can then all be
/// judged from storage, and none of them trusts what a screen happened to remember.
public enum SessionRecordReplay {
  public struct Entry: Hashable, Sendable {
    public let setID: SetID
    public let key: ProgressionKey
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let completedAt: Date

    public init(
      setID: SetID, key: ProgressionKey, weightKg: Double, reps: Int, isWarmup: Bool,
      completedAt: Date
    ) {
      self.setID = setID
      self.key = key
      self.weightKg = weightKg
      self.reps = reps
      self.isWarmup = isWarmup
      self.completedAt = completedAt
    }
  }

  /// - Parameters:
  ///   - session: This session's sets, in the order they were performed.
  ///   - priorHistory: Working sets from before this session, per exercise and machine.
  ///   - increments: Stack increments for the machines involved.
  /// - Returns: The records each set earned. Sets that earned none are absent.
  public static func records(
    session: [Entry],
    priorHistory: [ProgressionKey: [PriorSetRecord]],
    increments: [MachineID: Double]
  ) -> [SetID: [PersonalRecord]] {
    var history = priorHistory
    var result: [SetID: [PersonalRecord]] = [:]
    for entry in session {
      let found = PersonalRecordDetector.records(
        for: .init(weightKg: entry.weightKg, reps: entry.reps, isWarmup: entry.isWarmup),
        history: history[entry.key] ?? [],
        increment: entry.key.machineID.flatMap { increments[$0] }
      )
      if !found.isEmpty { result[entry.setID] = found }
      // Warm-ups are not benchmarks, exactly as `completedSets(for:)` excludes them in SQL.
      if !entry.isWarmup {
        history[entry.key, default: []].append(
          PriorSetRecord(weightKg: entry.weightKg, reps: entry.reps, completedAt: entry.completedAt)
        )
      }
    }
    return result
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter SessionRecordReplayTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/SessionRecordReplay.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/SessionRecordReplayTests.swift
git commit -m "feat(core): replay a session's records by the rules of the moment

The summary must list every record from the database, a resumed workout must get
its trophies back, and an edited set must be judged on what it says now. All
three need the verdicts logSet reached live. Replaying the sets in order against
the history before each one reproduces them through the same detector, with the
same margin, warm-up and per-machine rules.

Co-Authored-By: <your model's trailer>"
```

---

### Task 5: A palette whose contrast is tested (Core)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/Palette.swift`
- Test: `Packages/HardsetKit/Tests/HardsetCoreTests/PaletteTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `public struct PaletteColor: Hashable, Sendable`, with:
    - `red`, `green` and `blue`
    - `init(red:green:blue:)` and `init(hex: UInt32)`
    - `var relativeLuminance: Double`
    - `func contrast(with: PaletteColor) -> Double`
  - `public struct PaletteSwatch: Hashable, Sendable`, with:
    - `light`, `lightIncreasedContrast`, `dark` and `darkIncreasedContrast`
    - `init(light:lightIncreasedContrast:dark:darkIncreasedContrast:)`, taking `UInt32` hex
  - `public enum Palette`, with:
    - nested `Role: String, CaseIterable, Sendable`, with the cases `certaintyHigh`,
      `certaintyModerate`, `certaintyLow`, `certaintyUnevaluated`, `success`, `record`,
      `caution` and `critical`
    - `static func swatch(_ role: Role) -> PaletteSwatch`
    - `backgroundLight`, `backgroundDark`, `surfaceLight` and `surfaceDark`
    - `minimumTextContrast = 4.5` and `increasedTextContrast = 7.0`

The values were checked with the WCAG 2 formula. The smallest standard ratio is 4.62 (`success` on
the light background). The smallest Increase Contrast ratio is 7.41 (`success` on the light
background). The light background moves from (0.976, 0.976, 0.980) to `#F2F2F7`, which takes
light-mode card separation from 1.05:1 to 1.12:1 (spec 2.8, "visible card separation").

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("Every colour that carries text is readable, and Increase Contrast reads better")
struct PaletteTests {
  @Test("WCAG contrast: black on white is 21:1, a colour on itself is 1:1")
  func formula() {
    let black = PaletteColor(hex: 0x000000)
    let white = PaletteColor(hex: 0xFFFFFF)
    #expect(abs(black.contrast(with: white) - 21) < 1e-9)
    #expect(abs(white.contrast(with: black) - 21) < 1e-9)
    let grey = PaletteColor(hex: 0x777777)
    #expect(abs(grey.contrast(with: grey) - 1) < 1e-9)
  }

  @Test("Hex decodes in RGB order")
  func hex() {
    let colour = PaletteColor(hex: 0xFF8000)
    #expect(colour.red == 1)
    #expect(abs(colour.green - 128.0 / 255) < 1e-12)
    #expect(colour.blue == 0)
  }

  @Test("Text colours meet 4.5:1 on cards and backgrounds, light and dark", arguments: Palette.Role.allCases)
  func standardContrast(role: Palette.Role) {
    let swatch = Palette.swatch(role)
    for ground in [Palette.surfaceLight, Palette.backgroundLight] {
      #expect(swatch.light.contrast(with: ground) >= Palette.minimumTextContrast)
    }
    for ground in [Palette.surfaceDark, Palette.backgroundDark] {
      #expect(swatch.dark.contrast(with: ground) >= Palette.minimumTextContrast)
    }
  }

  @Test("Increase Contrast variants meet 7:1", arguments: Palette.Role.allCases)
  func increasedContrast(role: Palette.Role) {
    let swatch = Palette.swatch(role)
    for ground in [Palette.surfaceLight, Palette.backgroundLight] {
      #expect(swatch.lightIncreasedContrast.contrast(with: ground) >= Palette.increasedTextContrast)
    }
    for ground in [Palette.surfaceDark, Palette.backgroundDark] {
      #expect(swatch.darkIncreasedContrast.contrast(with: ground) >= Palette.increasedTextContrast)
    }
  }

  @Test("Increase Contrast never reads worse than standard", arguments: Palette.Role.allCases)
  func increasedIsStronger(role: Palette.Role) {
    let swatch = Palette.swatch(role)
    #expect(
      swatch.lightIncreasedContrast.contrast(with: Palette.surfaceLight)
        > swatch.light.contrast(with: Palette.surfaceLight))
    #expect(
      swatch.darkIncreasedContrast.contrast(with: Palette.surfaceDark)
        > swatch.dark.contrast(with: Palette.surfaceDark))
  }

  @Test("Cards stand apart from the background in both modes")
  func cardSeparation() {
    #expect(Palette.surfaceLight.contrast(with: Palette.backgroundLight) >= 1.1)
    #expect(Palette.surfaceDark.contrast(with: Palette.backgroundDark) >= 1.1)
  }

  @Test("Semantic colours are their own tokens, not certainty under another name")
  func semanticsSeparate() {
    #expect(Palette.swatch(.success) != Palette.swatch(.certaintyHigh))
    #expect(Palette.swatch(.record) != Palette.swatch(.certaintyModerate))
    #expect(Palette.swatch(.caution) != Palette.swatch(.certaintyLow))
    #expect(Palette.swatch(.critical) != Palette.swatch(.certaintyLow))
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter PaletteTests`
Expected: compile failure, `cannot find 'PaletteColor' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// An sRGB colour as three 0...1 components.
///
/// The palette's numbers live in Core, not in `Tokens`, so the claim that text meets 4.5:1 is
/// tested on every run instead of eyeballed. `HardsetUI` turns these into SwiftUI colours and
/// adds nothing.
public struct PaletteColor: Hashable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  /// WCAG 2 relative luminance.
  public var relativeLuminance: Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// WCAG 2 contrast ratio, from 1 to 21.
  public func contrast(with other: PaletteColor) -> Double {
    let a = relativeLuminance
    let b = other.relativeLuminance
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}

/// One role's colour in light and dark appearance, each with an Increase Contrast variant.
public struct PaletteSwatch: Hashable, Sendable {
  public let light: PaletteColor
  public let lightIncreasedContrast: PaletteColor
  public let dark: PaletteColor
  public let darkIncreasedContrast: PaletteColor

  public init(light: UInt32, lightIncreasedContrast: UInt32, dark: UInt32, darkIncreasedContrast: UInt32) {
    self.light = PaletteColor(hex: light)
    self.lightIncreasedContrast = PaletteColor(hex: lightIncreasedContrast)
    self.dark = PaletteColor(hex: dark)
    self.darkIncreasedContrast = PaletteColor(hex: darkIncreasedContrast)
  }
}

/// The app's colours that carry meaning.
///
/// Certainty colours and semantic colours are separate roles (spec 2.8). A record is not "high
/// confidence", and an error is not "low confidence". Using one for the other made a lower bound
/// look like a failure. Every role is legible as text on cards and on the background.
public enum Palette {
  public enum Role: String, CaseIterable, Sendable {
    case certaintyHigh, certaintyModerate, certaintyLow, certaintyUnevaluated
    case success, record, caution, critical
  }

  /// WCAG 1.4.3 (AA) for body text.
  public static let minimumTextContrast = 4.5
  /// WCAG 1.4.6 (AAA), what Increase Contrast should reach.
  public static let increasedTextContrast = 7.0

  /// `#F2F2F7`, darker than before so a white card is visible on it in light mode.
  public static let backgroundLight = PaletteColor(hex: 0xF2F2F7)
  public static let backgroundDark = PaletteColor(red: 0.055, green: 0.055, blue: 0.063)
  public static let surfaceLight = PaletteColor(hex: 0xFFFFFF)
  public static let surfaceDark = PaletteColor(red: 0.110, green: 0.110, blue: 0.122)

  public static func swatch(_ role: Role) -> PaletteSwatch {
    switch role {
    case .certaintyHigh:
      PaletteSwatch(light: 0x1F7A3A, lightIncreasedContrast: 0x14592A, dark: 0x4FD17A, darkIncreasedContrast: 0x8BE8A8)
    case .certaintyModerate:
      PaletteSwatch(light: 0x7A5C00, lightIncreasedContrast: 0x5C4500, dark: 0xE6C229, darkIncreasedContrast: 0xF5DC6E)
    case .certaintyLow:
      PaletteSwatch(light: 0xA84300, lightIncreasedContrast: 0x7D3200, dark: 0xFF9F45, darkIncreasedContrast: 0xFFC48A)
    case .certaintyUnevaluated:
      PaletteSwatch(light: 0x5E5E66, lightIncreasedContrast: 0x46464D, dark: 0xA3A3AB, darkIncreasedContrast: 0xC8C8CF)
    case .success:
      PaletteSwatch(light: 0x1E7D46, lightIncreasedContrast: 0x155A32, dark: 0x5BD68E, darkIncreasedContrast: 0x98EBBB)
    case .record:
      PaletteSwatch(light: 0x4B3FD1, lightIncreasedContrast: 0x3A2FA8, dark: 0xA39BFF, darkIncreasedContrast: 0xC4BEFF)
    case .caution:
      PaletteSwatch(light: 0x8A4B00, lightIncreasedContrast: 0x683800, dark: 0xFFB357, darkIncreasedContrast: 0xFFD199)
    case .critical:
      PaletteSwatch(light: 0xC0262D, lightIncreasedContrast: 0x931C22, dark: 0xFF6B6B, darkIncreasedContrast: 0xFF9C9C)
    }
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter PaletteTests`, then `Tools/linux-test.sh`.
Expected: PASS. If a ratio fails, adjust that hex value, darker in light mode and lighter in dark
mode, until it passes. Never lower the thresholds.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/Palette.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/PaletteTests.swift
git commit -m "feat(core): a palette whose contrast is tested, not trusted

The certainty colours were system green, yellow and orange, and the yellow fails
4.5:1 on white. The same orange marked low certainty, errors and caveats alike,
so a lower bound read as a failure. Colours are now named roles with
light/dark and Increase Contrast variants, and a test holds every role to 4.5:1
and 7:1 on cards and backgrounds. The light background darkens to #F2F2F7 so
white cards are visible on it.

Co-Authored-By: <your model's trailer>"
```

---

### Task 6: Set corrections (Store)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/LoggerStore.swift`. Add a
  `// MARK: - Corrections` section after `finishSession` (lines 173–190), and three cases to
  `LoggerStoreError` (lines 444–449).
- Modify: `Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift`. Add four actions to
  `Action` (lines 12–22), extend the `.logSet` switch (lines 31–36), and add four new action
  branches.
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift`. Change the
  `neverLeaks` arguments (lines 37–43) and add rows to the `copyMatchesTable` arguments (lines
  57–102).
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/SetCorrectionTests.swift`
- Modify: `DECISIONS.md` (append §22)

**Interfaces:**
- Consumes:
  - `SetEntryDraft.resolved()`
  - `LoggedSetRecord(row:)`, internal
  - the `Session`, `LoggedSet` and `SessionExercise` tables
- Produces, on `LoggerStore`:
  - `public func loggedSet(_ id: SetID) throws -> LoggedSetRecord?`
  - `@discardableResult public func updateSet(_ id: SetID, to draft: SetEntryDraft) throws -> LoggedSetRecord`
  - `@discardableResult public func deleteSet(_ id: SetID) throws -> LoggedSetRecord`
  - `@discardableResult public func restoreSet(_ deleted: LoggedSetRecord) throws -> SetID`, which
    restores under a **new** id
  - `public func discardEmptySession(_ sessionID: SessionID) throws`
- Also produces:
  - `LoggerStoreError` gains `.setNotFound`, `.sessionNotEmpty` and `.sessionNotOpen`.
  - `FailureCopy.Action` gains `editSet`, `deleteSet`, `undoDelete` and `discardWorkout`.

The copy, verbatim:

| Action | Error | Message |
|---|---|---|
| `editSet` | `.incompleteSet` | "Enter a weight and reps to save this change." |
| `editSet` | `.setNotFound` | "That set is no longer in this workout." |
| `editSet` | anything else | "That change could not be saved. The set still shows what was saved — try again." |
| `deleteSet` | `.setNotFound` | "That set is no longer in this workout." |
| `deleteSet` | anything else | "That set could not be deleted. It is still saved — try again." |
| `undoDelete` | anything | "That set could not be put back. Tap Undo to try again." |
| `discardWorkout` | `.sessionNotEmpty` | "This workout has logged sets, so it was not discarded. Finish it to keep them." |
| `discardWorkout` | anything else | "This workout could not be discarded. It is still open — try again." |

- [ ] **Step 1: Write the failing tests**

`SetCorrectionTests.swift`:

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A written set can be corrected, removed and put back, and nothing else changes")
struct SetCorrectionTests {
  let start = Date(timeIntervalSince1970: 20_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    return (database, LoggerStore(database: database), exercise)
  }

  @Test("A correction changes weight and reps and nothing else")
  func updateChangesOnlyTheLoad() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let planRow = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, sessionExerciseID: planRow,
      draft: SetEntryDraft(weightKg: 1000, reps: 8), at: start.addingTimeInterval(60)
    )
    let fetched = try store.loggedSet(id)
    let before = try #require(fetched)

    let after = try store.updateSet(id, to: SetEntryDraft(weightKg: 100, reps: 9))

    #expect(after.weightKg == 100)
    #expect(after.reps == 9)
    #expect(after.id == before.id)
    #expect(after.completedAt == before.completedAt)
    #expect(after.setOrdinal == before.setOrdinal)
    #expect(after.sessionExerciseID == planRow)
    #expect(after.isWarmup == before.isWarmup)
    #expect(try store.loggedSet(id) == after)
  }

  @Test(
    "A correction the logger could not have written is refused, and the set is untouched",
    arguments: [
      SetEntryDraft(weightKg: nil, reps: 8),
      SetEntryDraft(weightKg: 100, reps: 0),
      SetEntryDraft(weightKg: -5, reps: 8),
    ]
  )
  func incompleteRefused(draft: SetEntryDraft) throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)
    #expect(throws: LoggerStoreError.incompleteSet) { try store.updateSet(id, to: draft) }
    let fetched = try store.loggedSet(id)
    #expect(fetched?.weightKg == 100)
    #expect(fetched?.reps == 8)
  }

  @Test("Correcting or deleting a set that is not stored says so")
  func missingSet() throws {
    let (_, store, _) = try fixture()
    #expect(throws: LoggerStoreError.setNotFound) {
      try store.updateSet(SetID(), to: SetEntryDraft(weightKg: 100, reps: 8))
    }
    #expect(throws: LoggerStoreError.setNotFound) { try store.deleteSet(SetID()) }
  }

  @Test("Deleting removes the set and returns it as it was")
  func deleteReturnsTheRow() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)

    let removed = try store.deleteSet(id)

    #expect(removed.id == id)
    #expect(removed.weightKg == 100)
    #expect(try store.loggedSet(id) == nil)
    #expect(try store.sets(in: session).isEmpty)
  }

  @Test("Undo puts the set back exactly, under a new id")
  func restoreUnderANewID() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let planRow = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, sessionExerciseID: planRow,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
    let second = try store.logSet(
      sessionID: session, exerciseID: exercise, sessionExerciseID: planRow,
      draft: SetEntryDraft(weightKg: 105, reps: 6), at: start.addingTimeInterval(120))
    let removed = try store.deleteSet(second)

    let restoredID = try store.restoreSet(removed)

    #expect(restoredID != second)
    let fetched = try store.loggedSet(restoredID)
    let restored = try #require(fetched)
    #expect(restored.weightKg == 105)
    #expect(restored.reps == 6)
    #expect(restored.setOrdinal == removed.setOrdinal)
    #expect(restored.completedAt == removed.completedAt)
    #expect(restored.sessionExerciseID == planRow)
    #expect(!restored.isWarmup)
    // History sees it again, so anything judged against it is judged as before.
    #expect(try store.completedSets(for: ProgressionKey(exerciseID: exercise)).count == 2)
  }

  @Test("Undo into a workout that no longer exists is refused")
  func restoreNeedsTheSession() throws {
    let (database, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)
    let removed = try store.deleteSet(id)
    try database.write { db in
      try Session.where { $0.id.eq(session.rawValue) }.delete().execute(db)
    }
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.restoreSet(removed) }
  }

  @Test("An empty open workout is discarded with its plan rows")
  func discardEmpty() throws {
    let (database, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    _ = try store.addExercise(to: session, exerciseID: exercise, position: 0)

    try store.discardEmptySession(session)

    #expect(try store.openSession() == nil)
    let planRows = try database.read { db in
      try SessionExercise.where { $0.sessionID.eq(session.rawValue) }.fetchAll(db)
    }
    #expect(planRows.isEmpty)
  }

  /// Review Focus: the check is against storage, so a set the screen never saw still stops it.
  @Test("A workout with any logged set is never discarded, and a warm-up counts")
  func discardRefusesLoggedWork() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 40, reps: 10),
      isWarmup: true, at: start)

    #expect(throws: LoggerStoreError.sessionNotEmpty) { try store.discardEmptySession(session) }
    #expect(try store.openSession()?.id == session)
    #expect(try store.sets(in: session).count == 1)
  }

  @Test("A finished workout is history and is never discarded")
  func discardRefusesFinished() throws {
    let (database, store, _) = try fixture()
    let session = try store.startSession(at: start)
    try store.finishSession(session, at: start.addingTimeInterval(3_600))

    #expect(throws: LoggerStoreError.sessionNotOpen) { try store.discardEmptySession(session) }
    #expect(try HistoryStore(database: database).recentSessions().count == 1)
  }

  @Test("Discarding a workout that does not exist says so")
  func discardUnknown() throws {
    let (_, store, _) = try fixture()
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.discardEmptySession(SessionID()) }
  }
}
```

In `FailureCopyTests.swift`, change the `neverLeaks` parameterisation (lines 37–43) to cover every
action, present and future:

```swift
  @Test("No action ever leaks the raw error", arguments: FailureCopy.Action.allCases)
```

Append these rows to the `copyMatchesTable` arguments array, after the `.scheduleRest` row:

```swift
      CopyRow(
        error: LoggerStoreError.incompleteSet, action: .editSet,
        expected: "Enter a weight and reps to save this change."),
      CopyRow(
        error: LoggerStoreError.setNotFound, action: .editSet,
        expected: "That set is no longer in this workout."),
      CopyRow(
        error: Opaque(), action: .editSet,
        expected: "That change could not be saved. The set still shows what was saved — try again."),
      CopyRow(
        error: LoggerStoreError.setNotFound, action: .deleteSet,
        expected: "That set is no longer in this workout."),
      CopyRow(
        error: Opaque(), action: .deleteSet,
        expected: "That set could not be deleted. It is still saved — try again."),
      CopyRow(
        error: Opaque(), action: .undoDelete,
        expected: "That set could not be put back. Tap Undo to try again."),
      CopyRow(
        error: LoggerStoreError.sessionNotEmpty, action: .discardWorkout,
        expected: "This workout has logged sets, so it was not discarded. Finish it to keep them."),
      CopyRow(
        error: Opaque(), action: .discardWorkout,
        expected: "This workout could not be discarded. It is still open — try again."),
      CopyRow(
        error: LoggerStoreError.setNotFound, action: .logSet,
        expected: "That set could not be saved. It has not been logged — tap to try again."),
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'SetCorrectionTests|FailureCopyTests'`
Expected: compile failure, `value of type 'LoggerStore' has no member 'updateSet'` and
`type 'LoggerStoreError' has no member 'setNotFound'`.

- [ ] **Step 3: Implement**

Add to `LoggerStoreError` (lines 444–449):

```swift
  /// The set is not, or is no longer, stored.
  case setNotFound
  /// Discard was refused: the workout holds logged sets.
  case sessionNotEmpty
  /// Discard was refused: the workout is already finished, which makes it history.
  case sessionNotOpen
```

Add to `LoggerStore`, after `finishSession`:

```swift
  // MARK: - Corrections

  /// One written set, or nil if it is not (or no longer) stored.
  public func loggedSet(_ id: SetID) throws -> LoggedSetRecord? {
    try database.read { db in
      try LoggedSet.where { $0.id.eq(id.rawValue) }.fetchOne(db).map(LoggedSetRecord.init(row:))
    }
  }

  /// Corrects the weight and reps of a written set.
  ///
  /// Goes through `resolved()` exactly as `logSet` does, so a correction cannot write what a log
  /// could not. Everything else about the set is a fact about the performance and is left alone:
  /// when it was done, on which machine, its place in the exercise, whether it was a warm-up.
  @discardableResult
  public func updateSet(_ id: SetID, to draft: SetEntryDraft) throws -> LoggedSetRecord {
    guard let resolved = draft.resolved() else { throw LoggerStoreError.incompleteSet }
    return try database.write { db in
      guard try LoggedSet.where({ $0.id.eq(id.rawValue) }).fetchOne(db) != nil else {
        throw LoggerStoreError.setNotFound
      }
      try LoggedSet
        .where { $0.id.eq(id.rawValue) }
        .update {
          $0.weightKg = #bind(resolved.weightKg)
          $0.reps = #bind(resolved.reps)
        }
        .execute(db)
      guard let row = try LoggedSet.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.setNotFound
      }
      return LoggedSetRecord(row: row)
    }
  }

  /// Deletes a written set and returns it as it was, so an undo can put it back.
  @discardableResult
  public func deleteSet(_ id: SetID) throws -> LoggedSetRecord {
    try database.write { db in
      guard let row = try LoggedSet.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.setNotFound
      }
      try LoggedSet.where { $0.id.eq(id.rawValue) }.delete().execute(db)
      return LoggedSetRecord(row: row)
    }
  }

  /// Writes a deleted set back, exactly as it was, under a new id.
  ///
  /// A new id, not the old one. SQLiteData marks a deleted row's sync metadata as deleted, and
  /// its insert trigger's upsert does not clear that flag. Re-inserting the same primary key
  /// before the deletion reaches iCloud therefore risks the server deleting a set this device
  /// shows (`DECISIONS.md` §22). Nothing references a set's id, so a new one costs nothing.
  @discardableResult
  public func restoreSet(_ deleted: LoggedSetRecord) throws -> SetID {
    let id = SetID()
    try database.write { db in
      guard try Session.where({ $0.id.eq(deleted.sessionID.rawValue) }).fetchOne(db) != nil else {
        throw LoggerStoreError.sessionNotFound
      }
      try LoggedSet.insert {
        LoggedSet.Draft(
          id: id.rawValue,
          sessionID: deleted.sessionID.rawValue,
          exerciseID: deleted.exerciseID.rawValue,
          machineID: deleted.machineID?.rawValue,
          sessionExerciseID: deleted.sessionExerciseID,
          setOrdinal: deleted.setOrdinal,
          weightKg: deleted.weightKg,
          reps: deleted.reps,
          rpe: deleted.rpe,
          isWarmup: deleted.isWarmup,
          completedAt: deleted.completedAt
        )
      }
      .execute(db)
    }
    return id
  }

  /// Deletes an open workout in which nothing was logged, along with its plan rows.
  ///
  /// It refuses, rather than deletes, whenever there is anything to lose. A finished session is
  /// history. A session with even one written set, a warm-up included, holds training. The check
  /// runs inside the write and against the database, not against what a screen believes, so a set
  /// written by a path the screen never saw still stops it. Plan rows go by
  /// `ON DELETE CASCADE` (`Migrations.swift`, `sessionExercises.sessionID`).
  public func discardEmptySession(_ sessionID: SessionID) throws {
    try database.write { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      guard session.finishedAt == nil else { throw LoggerStoreError.sessionNotOpen }
      let written = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchAll(db)
      guard written.isEmpty else { throw LoggerStoreError.sessionNotEmpty }
      try Session.where { $0.id.eq(sessionID.rawValue) }.delete().execute(db)
    }
  }
```

In `FailureCopy.swift`, add the cases to `Action`:

```swift
    case editSet
    case deleteSet
    case undoDelete
    case discardWorkout
```

In the `.logSet` branch's inner switch, add the new cases. They cannot occur while logging, so they
fall through to the generic copy:

```swift
        case .setNotFound, .sessionNotEmpty, .sessionNotOpen:
          break
```

Add the new branches before the closing brace of the outer switch:

```swift
    case .editSet:
      if let storeError = error as? LoggerStoreError {
        if storeError == .incompleteSet { return "Enter a weight and reps to save this change." }
        if storeError == .setNotFound { return "That set is no longer in this workout." }
      }
      return "That change could not be saved. The set still shows what was saved — try again."

    case .deleteSet:
      if let storeError = error as? LoggerStoreError, storeError == .setNotFound {
        return "That set is no longer in this workout."
      }
      return "That set could not be deleted. It is still saved — try again."

    case .undoDelete:
      return "That set could not be put back. Tap Undo to try again."

    case .discardWorkout:
      if let storeError = error as? LoggerStoreError, storeError == .sessionNotEmpty {
        return "This workout has logged sets, so it was not discarded. Finish it to keep them."
      }
      return "This workout could not be discarded. It is still open — try again."
```

Append to `DECISIONS.md`:

```markdown
### 22. Undo puts a deleted set back under a new id

Deleting a logged set and undoing it re-inserts the set's values: weight, reps, ordinal,
completion time, machine and plan row. It does so under a fresh `SetID`, not the original.
SQLiteData marks a deleted row's sync metadata `_isDeleted`, and its insert trigger upserts that
metadata with an empty update (`onConflictDoUpdate: { _ in }`), which leaves the flag set. Read in
`sqlite-data` `Sources/SQLiteData/CloudKit/Internal/Triggers.swift` (`afterDeleteFromUser`,
`SyncMetadata.insert`). This cannot be exercised on Linux, where CloudKit is excluded.

Re-inserting the same primary key before the deletion syncs could therefore leave iCloud deleting a
set the device shows. Nothing references `loggedSets.id`, so a new id loses nothing, and the
restored set is judged for records exactly as before. Verify on device when sync is tested.
```

- [ ] **Step 4: Check every exhaustive switch over `LoggerStoreError`**

Run: `rg -n 'case \.sessionNotFound|case \.incompleteSet' Packages/HardsetKit/Sources Hardset`
Expected: hits only in `FailureCopy.swift`. Phase 1 Task 11 replaced `LiveSessionScreen.errorMessage`
with `FailureCopy`.

If any other `switch` over `LoggerStoreError` remains, add
`case .setNotFound, .sessionNotEmpty, .sessionNotOpen:` to it, falling to its generic message. If
that file is Mac-only, add a ledger entry.

- [ ] **Step 5: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'SetCorrectionTests|FailureCopyTests'`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/LoggerStore.swift \
  Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/SetCorrectionTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift DECISIONS.md
git commit -m "feat(store): correct, delete and restore a logged set; discard an empty workout

Logged rows were locked in Phase 1 because editing one changed only memory. The
store can now correct a set through the same resolved() gate as logging, delete
it and hand back what it was, and restore it under a new id, because reusing the
old one risks a pending iCloud deletion winning (DECISIONS §22).

An open workout with nothing logged can be discarded, relying on the existing
cascade. The empty check runs inside the write against the database, so a set
the screen never saw still prevents it.

Co-Authored-By: <your model's trailer>"
```

---

### Task 7: Records read back from storage (Store)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/LoggerStore.swift`. Add `recordsBySet(in:)`
  and `key(of:)` after `completedSets(for:limit:)`, which ends around line 294 before Task 6's
  insertion.
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/SessionRecordsReadTests.swift`

**Interfaces:**
- Consumes:
  - `SessionRecordReplay.records(session:priorHistory:increments:)` and `SessionRecordReplay.Entry`
    (Task 4)
  - `LoggerStore.updateSet` and `deleteSet` (Task 6), in tests
- Produces:
  `public func recordsBySet(in sessionID: SessionID) throws -> [SetID: [PersonalRecord]]` on
  `LoggerStore`. It throws `LoggerStoreError.sessionNotFound` for an unknown session.

Rules:
- The session's own sets are taken in performed order, by `completedAt` then `setOrdinal`.
- Prior history is every working set on the same exercises, from other sessions, completed before
  this session's `startedAt`.
- Increments come from the `machines` table.

This is "history before this workout", so a later workout never un-earns a record.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Records read back from the database agree with the moment they were announced")
@MainActor
struct SessionRecordsReadTests {
  let start = Date(timeIntervalSince1970: 21_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(_ database: any DatabaseWriter) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: "Leg Press") }.execute(db)
    }
    return id
  }

  /// A finished workout `daysAgo` before `start`, its sets logged a minute apart.
  @discardableResult
  private func workout(
    _ store: LoggerStore, _ exercise: ExerciseID, machine: MachineID? = nil,
    sets: [(Double, Int)], daysAgo: Double
  ) throws -> SessionID {
    let date = start.addingTimeInterval(-daysAgo * 86_400)
    let session = try store.startSession(at: date)
    for (index, set) in sets.enumerated() {
      _ = try store.logSet(
        sessionID: session, exerciseID: exercise, machineID: machine,
        draft: SetEntryDraft(weightKg: set.0, reps: set.1),
        at: date.addingTimeInterval(Double(index) * 60))
    }
    try store.finishSession(session, at: date.addingTimeInterval(3_600))
    return session
  }

  @Test("What the coordinator announced is what the database says")
  func agreesWithLiveDetection() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: start)
    let machine = try gyms.createMachine(
      at: gym, name: "Leg Press", stackIncrementKg: 5, now: start)
    try workout(store, exercise, machine: machine, sets: [(100, 8), (100, 8)], daysAgo: 7)

    let coordinator = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", plannedSets: 3)
      ],
      now: { self.start }
    )
    let state = coordinator.exercises[0]
    var announced: [SetID: Set<PersonalRecordKind>] = [:]
    for (index, set) in [(101.0, 8), (106.0, 8), (106.0, 9)].enumerated() {
      coordinator.exercises[0].slots[index].draft = SetEntryDraft(weightKg: set.0, reps: set.1)
      #expect(coordinator.logSet(slotID: state.slots[index].id, inExercise: state.id))
      let setID = try #require(coordinator.exercises[0].slots[index].loggedSetID)
      let kinds = Set(coordinator.lastRecords.map(\.kind))
      if !kinds.isEmpty { announced[setID] = kinds }
    }

    let read = try store.recordsBySet(in: coordinator.sessionID).mapValues { Set($0.map(\.kind)) }
    #expect(!read.isEmpty)
    #expect(read == announced)
  }

  @Test("A workout is judged against what came before it, never after")
  func laterWorkoutsDoNotCount() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let judged = try workout(store, exercise, sets: [(110, 8)], daysAgo: 3)
    try workout(store, exercise, sets: [(120, 8)], daysAgo: 1)

    let records = try store.recordsBySet(in: judged)
    #expect(records.values.contains { $0.contains { $0.kind == .heaviestLoad } })
  }

  @Test("A corrected set is judged on what it says now")
  func correctedSetRejudged() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let session = try store.startSession(at: start)
    let typo = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 1000, reps: 8),
      at: start)
    #expect(try store.recordsBySet(in: session)[typo] != nil)

    try store.updateSet(typo, to: SetEntryDraft(weightKg: 100, reps: 8))

    #expect(try store.recordsBySet(in: session).isEmpty)
  }

  @Test("A deleted set is not judged, and no longer raises the bar for the sets after it")
  func deletedSetIsGone() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let session = try store.startSession(at: start)
    let first = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 110, reps: 8),
      at: start)
    let second = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 112, reps: 8),
      at: start.addingTimeInterval(60))
    // 112 does not beat 110 by max(2.75, 2.5) kg, nor its estimate by 2.5%.
    #expect(try store.recordsBySet(in: session)[second] == nil)

    try store.deleteSet(first)

    let records = try store.recordsBySet(in: session)
    #expect(records[first] == nil)
    #expect(records[second]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("A workout with no sets has no records, and an unknown one is reported")
  func emptyAndUnknown() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)
    #expect(try store.recordsBySet(in: session).isEmpty)
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.recordsBySet(in: SessionID()) }
  }
}
```

In `agreesWithLiveDetection`, 101 × 8 beats nothing. 106 × 8 beats 101 by the 5 kg stack margin
and beats the best estimate. 106 × 9 is reps-at-load and estimated 1RM. The test compares only the
two sides' verdicts and asserts the fixture produced at least one record. If the 5 kg margin changes
which kinds fire, the comparison still holds.

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter SessionRecordsReadTests`
Expected: compile failure, `value of type 'LoggerStore' has no member 'recordsBySet'`.

- [ ] **Step 3: Implement**

Add to `LoggerStore`, after `completedSets(for:limit:)`:

```swift
  // MARK: - Records, as judged at the time

  /// Which sets in a session earned records, judged as `SessionCoordinator.logSet` judged each one
  /// when it was logged. That means against every earlier working set on the same exercise and
  /// machine: workouts before this one, plus this workout's own earlier sets.
  ///
  /// Read from the database, never from memory. An edited set is judged on its corrected values,
  /// and a deleted one is not judged at all. The summary, a resumed workout and a correction all
  /// rely on that. This is not on the tap path: it runs at resume, after a correction, and for the
  /// summary.
  public func recordsBySet(in sessionID: SessionID) throws -> [SetID: [PersonalRecord]] {
    try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let own = try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { ($0.completedAt, $0.setOrdinal) }
        .fetchAll(db)
      guard !own.isEmpty else { return [:] }

      // History before this workout. A later workout cannot un-earn a record.
      let exerciseIDs = Array(Set(own.map(\.exerciseID)))
      let startedAt = session.startedAt
      let earlier = try LoggedSet
        .where { $0.exerciseID.in(exerciseIDs) }
        .where { !$0.isWarmup }
        .where { $0.completedAt < startedAt }
        .fetchAll(db)
      var prior: [ProgressionKey: [PriorSetRecord]] = [:]
      for row in earlier where row.sessionID != sessionID.rawValue {
        prior[Self.key(of: row), default: []].append(Self.record(from: row))
      }

      let machineIDs = Array(Set(own.compactMap(\.machineID)))
      let increments =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [MachineID: Double]()) { result, row in
            if let increment = row.stackIncrementKg { result[MachineID(rawValue: row.id)] = increment }
          }

      return SessionRecordReplay.records(
        session: own.map { row in
          SessionRecordReplay.Entry(
            setID: SetID(rawValue: row.id), key: Self.key(of: row), weightKg: row.weightKg,
            reps: row.reps, isWarmup: row.isWarmup, completedAt: row.completedAt)
        },
        priorHistory: prior,
        increments: increments
      )
    }
  }

  private static func key(of row: LoggedSet) -> ProgressionKey {
    ProgressionKey(
      exerciseID: ExerciseID(rawValue: row.exerciseID),
      machineID: row.machineID.map(MachineID.init(rawValue:))
    )
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter SessionRecordsReadTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/LoggerStore.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/SessionRecordsReadTests.swift
git commit -m "feat(store): read a session's records back from the database

Records lived only in a field the next log overwrote, so the summary had nothing
to list and a crash lost every trophy. Replaying the session's stored sets
against the history before the workout reaches the verdicts logSet reached
live. A corrected set is judged on its new values, a deleted one not at all,
and a later workout cannot un-earn a record.

Co-Authored-By: <your model's trailer>"
```

---

### Task 8: Workout summary (Core value, Store reader)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetCore/WorkoutSummary.swift`
- Create: `Packages/HardsetKit/Sources/HardsetStore/WorkoutSummaryStore.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetStore/VolumeStore.swift:232`. Change
  `private static func volume(of:)` to `static func volume(of:)`, so the summary and history share
  one count.
- Modify: `Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift`, adding `.loadSummary`
- Modify: `Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift`, adding one row
- Create: `Packages/HardsetKit/Tests/HardsetCoreTests/WorkoutSummaryTests.swift`
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/WorkoutSummaryStoreTests.swift`

**Interfaces:**
- Consumes:
  - `LoggerStore.recordsBySet(in:)` (Task 7)
  - `VolumeStore.attributionIndex()`, `VolumeAnalyzer.report` and `MuscleVolumeReport`
  - `HistoryStore.volume(of:)` (made internal here)
  - `MachineRecord(row:).displayName`
  - `SessionTimeline`, `Duration.clockString` and `WeightFormatter.text` (internal to Core)
- Produces:
  - In Core, `public struct WorkoutSummary: Hashable, Sendable`, with:
    - `sessionID`, `timeline`, `volume: SessionVolume` and `records: [RecordLine]`
    - `muscles: [MuscleLine]`, `unattributedSets: Int` and `machinesUsed: [String]`
    - a public memberwise `init`
    - `var length: Duration?`, nil when open, negative or implausible
    - `var lengthText: String`, either `clockString` or "Length unknown"
    - `var isEmpty: Bool`
    - `static func muscleLines(from: MuscleVolumeReport) -> [MuscleLine]`
  - `WorkoutSummary.RecordLine: Hashable, Sendable, Identifiable`, holding `setID`,
    `exerciseName`, `machineName` and `record`.
  - `WorkoutSummary.MuscleLine: Hashable, Sendable, Identifiable`, with:
    - `muscle: MuscleKey`, `fractionalSets: Double` and `isLowerBound: Bool`
    - `func setsText(locale:) -> String`, e.g. "≥ 2.5 sets"
    - `func spokenSetsText(locale:) -> String`, e.g. "at least 2.5 sets"
  - In Store, `public nonisolated struct WorkoutSummaryStore`, with `init(database:)` and
    `func summary(for sessionID: SessionID) throws -> WorkoutSummary`. It throws
    `LoggerStoreError.sessionNotFound`.
  - `FailureCopy.Action.loadSummary`, whose copy is "Your workout is saved, but its summary could
    not be read. Try again."

`WorkoutSummary` holds no target, goal, streak or comparison field (spec 2.4). The muscle lines
are ordered by credit, then by vocabulary order. Records are listed in performed order. Machines
are listed once each, in first-used order, by display name.

- [ ] **Step 1: Write the failing tests**

`WorkoutSummaryTests.swift` (Core):

```swift
import Foundation
import Testing

@testable import HardsetCore

@Suite("The summary states what was done, and withholds what it cannot know")
struct WorkoutSummaryTests {
  let posix = Locale(identifier: "en_US_POSIX")
  let start = Date(timeIntervalSince1970: 2_000_000)

  private func summary(finishedAfter seconds: Double?) -> WorkoutSummary {
    WorkoutSummary(
      sessionID: SessionID(),
      timeline: SessionTimeline(
        startedAt: start, finishedAt: seconds.map { start.addingTimeInterval($0) }),
      volume: SessionVolume(workingSets: 0, warmupSets: 0, volumeKg: 0, reps: 0),
      records: [], muscles: [], unattributedSets: 0, machinesUsed: []
    )
  }

  @Test("A closed workout's length comes from its timeline")
  func closedLength() {
    #expect(summary(finishedAfter: 2_700).lengthText == "45:00")
    #expect(summary(finishedAfter: 3_900).length == .seconds(3_900))
  }

  @Test(
    "Open, backwards or implausibly long: the length is unknown, not a number",
    arguments: [nil, -60, 7 * 3_600] as [Double?]
  )
  func unknownLength(seconds: Double?) {
    let result = summary(finishedAfter: seconds)
    #expect(result.length == nil)
    #expect(result.lengthText == "Length unknown")
  }

  @Test("Muscle lines: most credited first, then vocabulary order; nothing at zero")
  func muscleOrder() {
    let report = MuscleVolumeReport(
      fractionalSets: [
        MuscleKey(.triceps): 2, MuscleKey(.chest): 4, MuscleKey(.frontDelts): 2,
        MuscleKey(.biceps): 0,
      ],
      hardSets: 4, unattributedHardSets: 0, setsTouchingGroup: [:])
    let lines = WorkoutSummary.muscleLines(from: report)
    #expect(lines.map(\.muscle) == [MuscleKey(.chest), MuscleKey(.frontDelts), MuscleKey(.triceps)])
    #expect(lines.allSatisfy { !$0.isLowerBound })
  }

  @Test("Any unattributed set makes every line a lower bound")
  func lowerBound() {
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(.chest): 2.5], hardSets: 5, unattributedHardSets: 2,
      setsTouchingGroup: [:])
    let line = WorkoutSummary.muscleLines(from: report)[0]
    #expect(line.isLowerBound)
    #expect(line.setsText(locale: posix) == "≥ 2.5 sets")
    #expect(line.spokenSetsText(locale: posix) == "at least 2.5 sets")
    #expect(line.setsText(locale: Locale(identifier: "de_DE")) == "≥ 2,5 sets")
  }

  @Test("Set counts agree with their noun")
  func nouns() {
    let one = WorkoutSummary.MuscleLine(muscle: MuscleKey(.chest), fractionalSets: 1, isLowerBound: false)
    let half = WorkoutSummary.MuscleLine(muscle: MuscleKey(.chest), fractionalSets: 0.5, isLowerBound: false)
    let four = WorkoutSummary.MuscleLine(muscle: MuscleKey(.chest), fractionalSets: 4, isLowerBound: false)
    #expect(one.setsText(locale: posix) == "1 set")
    #expect(half.setsText(locale: posix) == "0.5 sets")
    #expect(four.setsText(locale: posix) == "4 sets")
  }
}
```

`WorkoutSummaryStoreTests.swift` (Store):

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The summary is read from the database, and says only what it can stand behind")
struct WorkoutSummaryStoreTests {
  let now = Date(timeIntervalSince1970: 22_000_000)
  let posix = Locale(identifier: "en_US_POSIX")

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// The real catalogue, so muscle credit is the shipped attribution, not a fixture's.
  private func seeded() throws -> (any DatabaseWriter, LoggerStore, WorkoutSummaryStore) {
    let database = try migratedDatabase()
    try CatalogSeeder(database: database).seed(now: now)
    return (database, LoggerStore(database: database), WorkoutSummaryStore(database: database))
  }

  private func exercise(_ database: any DatabaseWriter, slug: String) throws -> (ExerciseID, String) {
    let row = try database.read { db in
      try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(db)
    }
    let found = try #require(row)
    return (ExerciseID(rawValue: found.id), found.name)
  }

  private func log(
    _ store: LoggerStore, _ session: SessionID, _ exercise: ExerciseID, machine: MachineID? = nil,
    _ weight: Double, _ reps: Int, warmup: Bool = false, at offset: Double
  ) throws -> SetID {
    try store.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: reps), isWarmup: warmup,
      at: now.addingTimeInterval(offset))
  }

  @Test("Length, sets, reps and volume come from what was written")
  func totals() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now)
    _ = try log(logger, session, bench, 60, 10, warmup: true, at: 60)
    for index in 1...3 { _ = try log(logger, session, bench, 100, 8, at: Double(index) * 120) }
    try logger.finishSession(session, at: now.addingTimeInterval(3_900))

    let summary = try summaries.summary(for: session)

    #expect(summary.volume.workingSets == 3)
    #expect(summary.volume.warmupSets == 1)
    #expect(summary.volume.reps == 24)
    #expect(summary.volume.volumeKg == 2_400)
    #expect(summary.lengthText == "1:05:00")
    #expect(!summary.isEmpty)
  }

  @Test("The summary and the history row cannot disagree about a session")
  func agreesWithHistory() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now)
    _ = try log(logger, session, bench, 60, 10, warmup: true, at: 30)
    _ = try log(logger, session, bench, 100, 8, at: 60)
    _ = try log(logger, session, bench, 102.5, 6, at: 120)
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let history = try HistoryStore(database: database).recentSessions()
    #expect(try summaries.summary(for: session).volume == history.first?.volume)
  }

  @Test("Every record this session is listed, with its movement and machine")
  func records() throws {
    let (database, logger, summaries) = try seeded()
    let (press, name) = try exercise(database, slug: "leg-press")
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: now)
    let hammer = try gyms.createMachine(
      at: gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let before = try logger.startSession(gymID: gym, at: now.addingTimeInterval(-7 * 86_400))
    _ = try logger.logSet(
      sessionID: before, exerciseID: press, machineID: hammer,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(-7 * 86_400))
    try logger.finishSession(before, at: now.addingTimeInterval(-7 * 86_400 + 3_600))

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try log(logger, session, press, machine: hammer, 110, 8, at: 60)
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let summary = try summaries.summary(for: session)
    #expect(summary.records.contains { $0.record.kind == .heaviestLoad })
    #expect(summary.records.allSatisfy { $0.exerciseName == name })
    #expect(summary.records.allSatisfy { $0.machineName == "Hammer Strength Leg Press" })
  }

  @Test("A corrected typo's record is gone from the summary")
  func correctedRecordGone() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let before = try logger.startSession(at: now.addingTimeInterval(-86_400))
    _ = try log(logger, before, bench, 100, 8, at: -86_400)
    try logger.finishSession(before, at: now.addingTimeInterval(-82_800))
    let session = try logger.startSession(at: now)
    let typo = try log(logger, session, bench, 1_000, 8, at: 60)
    #expect(try summaries.summary(for: session).records.isEmpty == false)

    try logger.updateSet(typo, to: SetEntryDraft(weightKg: 100, reps: 8))

    #expect(try summaries.summary(for: session).records.isEmpty)
  }

  @Test("Muscles touched follow the set-counting rules")
  func muscles() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now)
    for index in 0..<4 { _ = try log(logger, session, bench, 100, 8, at: Double(index) * 60) }
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let summary = try summaries.summary(for: session)
    #expect(summary.muscles.first?.muscle == MuscleKey(.chest))
    #expect(summary.muscles.first?.fractionalSets == 4)
    #expect(summary.muscles.first { $0.muscle == MuscleKey(.triceps) }?.fractionalSets == 2)
    #expect(summary.muscles.allSatisfy { !$0.isLowerBound })
    #expect(summary.unattributedSets == 0)
  }

  @Test("A movement with no muscles recorded makes every muscle line a lower bound")
  func lowerBound() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let custom = ExerciseID()
    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: custom.rawValue, name: "Gym-specific contraption", isCurated: false)
      }
      .execute(db)
    }
    let session = try logger.startSession(at: now)
    for index in 0..<6 { _ = try log(logger, session, bench, 100, 8, at: Double(index) * 60) }
    for index in 0..<2 { _ = try log(logger, session, custom, 50, 10, at: 600 + Double(index) * 60) }
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let summary = try summaries.summary(for: session)
    #expect(summary.unattributedSets == 2)
    #expect(summary.muscles.allSatisfy(\.isLowerBound))
    #expect(summary.muscles.first { $0.muscle == MuscleKey(.chest) }?.setsText(locale: posix) == "≥ 6 sets")
  }

  @Test("Machines are listed once each, in the order they were first used")
  func machinesUsed() throws {
    let (database, logger, summaries) = try seeded()
    let (press, _) = try exercise(database, slug: "leg-press")
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: now)
    let hammer = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try log(logger, session, press, machine: hammer, 100, 8, at: 60)
    _ = try log(logger, session, bench, 80, 8, at: 120)
    _ = try log(logger, session, press, machine: cybex, 90, 8, at: 180)
    _ = try log(logger, session, press, machine: hammer, 100, 8, at: 240)
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    #expect(
      try summaries.summary(for: session).machinesUsed
        == ["Hammer Strength Leg Press", "Cybex Leg Press"])
  }

  @Test("An open or implausibly long workout has no length")
  func unknownLength() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let open = try logger.startSession(at: now)
    _ = try log(logger, open, bench, 100, 8, at: 60)
    #expect(try summaries.summary(for: open).lengthText == "Length unknown")

    let forgotten = try logger.startSession(at: now.addingTimeInterval(-86_400))
    try logger.finishSession(forgotten, at: now.addingTimeInterval(-86_400 + 7 * 3_600))
    #expect(try summaries.summary(for: forgotten).length == nil)
  }

  @Test("An unknown workout is reported, not summarised as empty")
  func unknownSession() throws {
    let (_, _, summaries) = try seeded()
    #expect(throws: LoggerStoreError.sessionNotFound) { try summaries.summary(for: SessionID()) }
  }
}
```

Append to `FailureCopyTests.copyMatchesTable`'s arguments:

```swift
      CopyRow(
        error: Opaque(), action: .loadSummary,
        expected: "Your workout is saved, but its summary could not be read. Try again."),
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter 'WorkoutSummaryTests|WorkoutSummaryStoreTests|FailureCopyTests'`
Expected: compile failure, `cannot find 'WorkoutSummary' in scope`.

- [ ] **Step 3: Implement**

`WorkoutSummary.swift` (Core):

```swift
import Foundation

/// What a finished workout contained, as the summary sheet shows it.
///
/// A value with no database handle, so the sheet can only render what `WorkoutSummaryStore` read
/// from storage. Named `WorkoutSummary` because `SessionSummary` is already the history row.
/// Deliberately absent: any target, goal, streak or comparison with a plan. The summary states
/// what was done and does not grade it (`HANDOFF.md` §6).
public struct WorkoutSummary: Hashable, Sendable {
  public struct RecordLine: Hashable, Sendable, Identifiable {
    public let setID: SetID
    public let exerciseName: String
    public let machineName: String?
    public let record: PersonalRecord

    public init(setID: SetID, exerciseName: String, machineName: String?, record: PersonalRecord) {
      self.setID = setID
      self.exerciseName = exerciseName
      self.machineName = machineName
      self.record = record
    }

    public var id: String { "\(setID)-\(record.kind.rawValue)" }
  }

  public struct MuscleLine: Hashable, Sendable, Identifiable {
    public let muscle: MuscleKey
    public let fractionalSets: Double
    /// True when some sets could not be attributed, so this figure is a floor, not a total.
    public let isLowerBound: Bool

    public init(muscle: MuscleKey, fractionalSets: Double, isLowerBound: Bool) {
      self.muscle = muscle
      self.fractionalSets = fractionalSets
      self.isLowerBound = isLowerBound
    }

    public var id: String { muscle.storedValue }

    /// "4 sets", "1 set", "0.5 sets", or "≥ 2.5 sets" for a lower bound. The "≥" is the caveat:
    /// it is said in the number itself, not in a warning colour (spec §3, item 2).
    public func setsText(locale: Locale = .current) -> String {
      "\(isLowerBound ? "≥ " : "")\(count(locale)) \(noun)"
    }

    /// For VoiceOver, which reads "≥" badly: "at least 2.5 sets".
    public func spokenSetsText(locale: Locale = .current) -> String {
      "\(isLowerBound ? "at least " : "")\(count(locale)) \(noun)"
    }

    private func count(_ locale: Locale) -> String {
      WeightFormatter.text(fractionalSets, fractionDigits: 1, locale: locale)
    }

    private var noun: String { fractionalSets == 1 ? "set" : "sets" }
  }

  public let sessionID: SessionID
  public let timeline: SessionTimeline
  public let volume: SessionVolume
  public let records: [RecordLine]
  public let muscles: [MuscleLine]
  public let unattributedSets: Int
  public let machinesUsed: [String]

  public init(
    sessionID: SessionID,
    timeline: SessionTimeline,
    volume: SessionVolume,
    records: [RecordLine],
    muscles: [MuscleLine],
    unattributedSets: Int,
    machinesUsed: [String]
  ) {
    self.sessionID = sessionID
    self.timeline = timeline
    self.volume = volume
    self.records = records
    self.muscles = muscles
    self.unattributedSets = unattributedSets
    self.machinesUsed = machinesUsed
  }

  /// The workout's length, or nil when it cannot be known. That covers a session still open, one
  /// whose clock ran backwards, and one longer than any real workout (`DECISIONS.md` §21).
  public var length: Duration? {
    timeline.isImplausible ? nil : timeline.duration
  }

  public var lengthText: String { length?.clockString ?? "Length unknown" }

  public var isEmpty: Bool { volume.isEmpty }

  /// Muscles credited this session, most first, then in vocabulary order.
  public static func muscleLines(from report: MuscleVolumeReport) -> [MuscleLine] {
    let order = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
    return report.fractionalSets
      .filter { $0.value > 0 }
      .map { MuscleLine(muscle: $0.key, fractionalSets: $0.value, isLowerBound: report.isLowerBound) }
      .sorted { lhs, rhs in
        if lhs.fractionalSets != rhs.fractionalSets { return lhs.fractionalSets > rhs.fractionalSets }
        let l = lhs.muscle.muscle.flatMap { order[$0] } ?? Int.max
        let r = rhs.muscle.muscle.flatMap { order[$0] } ?? Int.max
        if l != r { return l < r }
        return lhs.muscle.storedValue < rhs.muscle.storedValue
      }
  }
}
```

`WorkoutSummaryStore.swift` (Store):

```swift
import Foundation
import HardsetCore
import SQLiteData

/// Reads the summary of one workout, from storage only.
///
/// Nothing here comes from the live screen. Totals reuse the history screen's count, records are
/// re-judged by `recordsBySet`, and muscles are counted by `VolumeAnalyzer` against the same
/// attribution as the volume screen. So no screen can disagree with another about the same
/// session.
public nonisolated struct WorkoutSummaryStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func summary(for sessionID: SessionID) throws -> WorkoutSummary {
    let records = try LoggerStore(database: database).recordsBySet(in: sessionID)
    let attribution = try VolumeStore(database: database).attributionIndex()
    return try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let sets = try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { ($0.completedAt, $0.setOrdinal) }
        .fetchAll(db)

      let exerciseIDs = Array(Set(sets.map(\.exerciseID)))
      let names =
        exerciseIDs.isEmpty
        ? [:]
        : try Exercise
          .where { $0.id.in(exerciseIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
      let machineIDs = Array(Set(sets.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = MachineRecord(row: $1).displayName }

      var lines: [WorkoutSummary.RecordLine] = []
      var used: [String] = []
      var seenMachines = Set<UUID>()
      for set in sets {
        if let machineID = set.machineID, seenMachines.insert(machineID).inserted,
          let name = machines[machineID]
        {
          used.append(name)
        }
        let setID = SetID(rawValue: set.id)
        for record in records[setID] ?? [] {
          lines.append(
            WorkoutSummary.RecordLine(
              setID: setID,
              exerciseName: names[set.exerciseID] ?? "Unknown movement",
              machineName: set.machineID.flatMap { machines[$0] },
              record: record
            )
          )
        }
      }

      let report = VolumeAnalyzer.report(
        sets: sets.map {
          CountableSet(exerciseID: ExerciseID(rawValue: $0.exerciseID), isWarmup: $0.isWarmup)
        },
        attribution: attribution
      )
      return WorkoutSummary(
        sessionID: sessionID,
        timeline: SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt),
        volume: HistoryStore.volume(of: sets),
        records: lines,
        muscles: WorkoutSummary.muscleLines(from: report),
        unattributedSets: report.unattributedHardSets,
        machinesUsed: used
      )
    }
  }
}
```

In `VolumeStore.swift:232`, change `private static func volume(of sets: [LoggedSet])` to
`static func volume(of sets: [LoggedSet])`. Add one line to its doc comment: "Internal, not
private: `WorkoutSummaryStore` uses the same count."

In `FailureCopy.swift`, add `case loadSummary` to `Action`, and this branch:

```swift
    case .loadSummary:
      return "Your workout is saved, but its summary could not be read. Try again."
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'WorkoutSummaryTests|WorkoutSummaryStoreTests|FailureCopyTests'`,
then `Tools/linux-test.sh`.
Expected: PASS. `neverLeaks` now covers `.loadSummary` through `allCases`.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetCore/WorkoutSummary.swift \
  Packages/HardsetKit/Sources/HardsetStore/WorkoutSummaryStore.swift \
  Packages/HardsetKit/Sources/HardsetStore/VolumeStore.swift \
  Packages/HardsetKit/Sources/HardsetStore/FailureCopy.swift \
  Packages/HardsetKit/Tests/HardsetCoreTests/WorkoutSummaryTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/WorkoutSummaryStoreTests.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/FailureCopyTests.swift
git commit -m "feat(store): a workout summary read from the database

Finishing went straight back to the start screen, with no account of what was
done. The summary is read from storage after the finish is written:
- the length from the closed timeline, or 'Length unknown'
- totals by the history screen's own count
- every record, re-judged from the stored sets
- muscles touched, with ≥ where unattributed sets make them a floor
- machines used

It carries no target, goal or streak.

Co-Authored-By: <your model's trailer>"
```

---

### Task 9: Coordinator — trophies per row, and feedback (Store)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift`:
  - new properties after `activeRest` (line 70)
  - `logSet` (lines 327–388)
  - `resume`, before `return coordinator` (lines 249–250)
  - a private `emit` in the `// MARK: - Rest` neighbourhood
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/RecordMomentTests.swift`

**Interfaces:**
- Consumes:
  - `FeedbackEvent`, `FeedbackEvent.afterLogging(records:)` and
    `FeedbackPulse.following(_:event:slotID:)` (Task 3)
  - `LoggerStore.recordsBySet(in:)` (Task 7)
- Produces, on `SessionCoordinator`:
  - `public private(set) var recordsBySlot: [UUID: [PersonalRecord]]`, keyed by `SetSlot.id`
  - `public private(set) var feedback: FeedbackPulse?`
  - `private func emit(_ event: FeedbackEvent, slotID: UUID?)`, which Task 10 uses

Rules:
- A successful log sets `lastRecords` as before. When records were found it also sets
  `recordsBySlot[slotID]`, and it emits `.afterLogging(records:)` with the row's slot id.
- A failed log, including an unknown slot, emits `.error`.
- Logging an already-logged row emits nothing.
- `resume` rebuilds `recordsBySlot` from `recordsBySet` by matching `loggedSetID`, and emits
  nothing. A failed read loses only the trophies, never the workout.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A record stays on the row that earned it, and each moment is told once")
@MainActor
struct RecordMomentTests {
  let start = Date(timeIntervalSince1970: 23_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// A store with one exercise and a week-old 100 × 8, so there is something to beat.
  private func fixture() throws -> (LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let store = LoggerStore(database: database)
    let past = start.addingTimeInterval(-7 * 86_400)
    let session = try store.startSession(at: past)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: past)
    try store.finishSession(session, at: past.addingTimeInterval(3_600))
    return (store, exercise)
  }

  private func session(_ store: LoggerStore, _ exercise: ExerciseID) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)],
      now: { self.start }
    )
  }

  @discardableResult
  private func log(_ coordinator: SessionCoordinator, row: Int, _ weight: Double?, _ reps: Int) -> Bool {
    coordinator.exercises[0].slots[row].draft = SetEntryDraft(weightKg: weight, reps: reps)
    return coordinator.logSet(
      slotID: coordinator.exercises[0].slots[row].id, inExercise: coordinator.exercises[0].id)
  }

  @Test("A record is kept on its row after later sets are logged")
  func keptOnTheRow() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    #expect(log(coordinator, row: 0, 110, 8))
    let earned = coordinator.exercises[0].slots[0].id
    #expect(coordinator.recordsBySlot[earned]?.contains { $0.kind == .heaviestLoad } == true)

    #expect(log(coordinator, row: 1, 100, 8))

    #expect(coordinator.lastRecords.isEmpty)
    #expect(coordinator.recordsBySlot[earned]?.isEmpty == false)
    #expect(coordinator.recordsBySlot[coordinator.exercises[0].slots[1].id] == nil)
  }

  @Test("A record plays the record haptic and an ordinary set the log haptic, each once")
  func feedbackPerLog() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    log(coordinator, row: 0, 110, 8)
    let first = try #require(coordinator.feedback)
    #expect(first.event == .record)
    #expect(first.slotID == coordinator.exercises[0].slots[0].id)

    log(coordinator, row: 1, 100, 8)
    let second = try #require(coordinator.feedback)
    #expect(second.event == .log)
    #expect(second.slotID == coordinator.exercises[0].slots[1].id)
    #expect(second.sequence == first.sequence + 1)
  }

  @Test("A refused write plays the error haptic and claims nothing")
  func failureClaimsNothing() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    #expect(!log(coordinator, row: 0, nil, 8))
    #expect(coordinator.feedback?.event == .error)
    #expect(coordinator.recordsBySlot.isEmpty)
    #expect(!coordinator.exercises[0].slots[0].isLogged)
  }

  @Test("Logging a row twice plays nothing the second time")
  func noDoubleFeedback() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    log(coordinator, row: 0, 100, 8)
    let pulse = coordinator.feedback
    #expect(
      coordinator.logSet(
        slotID: coordinator.exercises[0].slots[0].id, inExercise: coordinator.exercises[0].id))
    #expect(coordinator.feedback == pulse)
  }

  @Test("A resumed workout gets its trophies back on the same rows, silently")
  func resumeRestoresTrophies() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    log(coordinator, row: 0, 110, 8)
    log(coordinator, row: 1, 100, 8)
    let recordSet = coordinator.exercises[0].slots[0].loggedSetID
    let plainSet = coordinator.exercises[0].slots[1].loggedSetID

    let resumed = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))

    let recordRow = try #require(resumed.exercises[0].slots.first { $0.loggedSetID == recordSet })
    let plainRow = try #require(resumed.exercises[0].slots.first { $0.loggedSetID == plainSet })
    #expect(resumed.recordsBySlot[recordRow.id]?.contains { $0.kind == .heaviestLoad } == true)
    #expect(resumed.recordsBySlot[plainRow.id] == nil)
    #expect(resumed.feedback == nil)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter RecordMomentTests`
Expected: compile failure, `value of type 'SessionCoordinator' has no member 'recordsBySlot'`.

- [ ] **Step 3: Implement**

Add after `activeRest`:

```swift
  /// Records each row earned, kept for the whole workout, keyed by `SetSlot.id`.
  ///
  /// `lastRecords` is the moment and is cleared by the next log. This is the trophy that stays on
  /// the row that earned it (spec 2.5). It is rebuilt from storage on resume, so a crash does not
  /// take it away.
  public private(set) var recordsBySlot: [UUID: [PersonalRecord]] = [:]

  /// The latest thing worth a haptic. A new value per occurrence, so two identical events in a row
  /// still play twice. Set only after the write it describes has succeeded or failed.
  public private(set) var feedback: FeedbackPulse?
```

In `logSet`:
- In the unknown-slot `else` branch, after `lastError = SessionCoordinatorError.unknownSlot`, add
  `emit(.error, slotID: slotID)`.
- Leave `guard !slot.isLogged else { return true }` emitting nothing, and comment it: "Already
  written: nothing new happened, so nothing plays."
- Replace the records block (the `if let resolved = slot.draft.resolved() { lastRecords = … } else
  { lastRecords = [] }` block) with:

```swift
      let found: [PersonalRecord]
      if let resolved = slot.draft.resolved() {
        found = PersonalRecordDetector.records(
          for: .init(weightKg: resolved.weightKg, reps: resolved.reps, isWarmup: slot.isWarmup),
          history: priorHistory,
          increment: exercise.machineIncrementKg
        )
      } else {
        found = []
      }
      lastRecords = found
      if !found.isEmpty { recordsBySlot[slotID] = found }
      // One haptic per log, after the write. A record outranks an ordinary log.
      emit(.afterLogging(records: found), slotID: slotID)
```

- In the `catch` block, after `lastError = error`, add `emit(.error, slotID: slotID)`.

In `resume`, immediately before `return coordinator`:

```swift
    // Trophies come back with the workout, and nothing is announced again. A failed read loses
    // only the trophies, never the workout, which is why this does not throw.
    if let earned = try? store.recordsBySet(in: session.id) {
      for exercise in states {
        for slot in exercise.slots {
          if let setID = slot.loggedSetID, let records = earned[setID], !records.isEmpty {
            coordinator.recordsBySlot[slot.id] = records
          }
        }
      }
    }
```

Add, near the other private helpers:

```swift
  /// The only writer of `feedback`.
  private func emit(_ event: FeedbackEvent, slotID: UUID?) {
    feedback = FeedbackPulse.following(feedback, event: event, slotID: slotID)
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'RecordMomentTests|SessionCoordinatorTests|RecordDetectionTests'`,
then `Tools/linux-test.sh`.
Expected: PASS. The existing coordinator and record suites are unchanged.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/RecordMomentTests.swift
git commit -m "feat(store): keep each record on the row that earned it

lastRecords was overwritten by the next log, so a record vanished one set later
and could never be marked on its row. The coordinator now keeps records per row
for the whole workout, rebuilt from the database on resume. It also publishes
one feedback pulse per log: record, log or error. The haptic is decided once,
after the write, instead of guessed by a view.

Co-Authored-By: <your model's trailer>"
```

---

### Task 10: Coordinator — edit, delete, undo, the finish decision, discard (Store)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift`:
  - a new `// MARK: - Corrections` section before `// MARK: - Finishing` (line 509)
  - `finish()` (lines 512–517)
  - `SessionCoordinatorError` (lines 554–561)
  - a new `DeletedSet` type at the end of the file
- Create: `Packages/HardsetKit/Tests/HardsetStoreTests/SetCorrectionCoordinatorTests.swift`

**Interfaces:**
- Consumes:
  - `FinishFlow.decision(for:)` and `FinishDecision` (Task 2)
  - `updateSet`, `deleteSet`, `restoreSet` and `discardEmptySession` (Task 6)
  - `recordsBySet(in:)` (Task 7)
  - `recordsBySlot` and `emit` (Task 9)
- Produces, on `SessionCoordinator`:
  - `public static let undoWindow: Duration`, which is `.seconds(5)`
  - `public private(set) var undoableDeletion: DeletedSet?`
  - `public private(set) var isDiscarded: Bool`
  - `public var finishDecision: FinishDecision`
  - `@discardableResult public func editSet(slotID: UUID, inExercise: UUID, to draft: SetEntryDraft) -> Bool`
  - `@discardableResult public func deleteSet(slotID: UUID, inExercise: UUID) -> Bool`
  - `@discardableResult public func undoDelete() -> Bool`
  - `public func expireUndo()`
  - `@discardableResult public func discard() -> Bool`
- Also produces:
  - `public struct DeletedSet: Sendable`, with public `exerciseStateID: UUID`, `slot: SetSlot`,
    `index: Int` and `expiresAt: Date`
  - `SessionCoordinatorError.slotNotLogged`

Rules:
- **Write first.** The store is written first, and memory changes only on success. On failure:
  `lastError` is set, `.error` is emitted, and the row and database are left as they were.
- **Edits are quiet.** An edit emits nothing on success and clears `lastRecords`. It keeps a row's
  trophy only if `recordsBySet` still supports that record kind, and it never adds one. If that
  read fails, the edited row's trophy goes.
- **Delete** removes the row, drops its trophy and holds a `DeletedSet` until
  `now() + undoWindow`.
- **Undo** within the window restores the set under its new id, at the same index, with the same
  slot id and trophy. Undo at or after `expiresAt`, after `expireUndo()`, or after `finish()` or
  `discard()` does nothing. A failed undo keeps the pending deletion, so it can be retried until it
  expires.
- **Discard** refuses in memory when `loggedSetCount > 0`, and the store refuses again when the
  database disagrees. On success it sets `isDiscarded` and ends rest.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Corrections are written first, shown second, and never celebrated")
@MainActor
struct SetCorrectionCoordinatorTests {
  let start = Date(timeIntervalSince1970: 24_000_000)

  /// A clock the test can move, for the undo window.
  private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// One exercise with a week-old 100 × 8, so there is something to beat.
  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let store = LoggerStore(database: database)
    let past = start.addingTimeInterval(-7 * 86_400)
    let session = try store.startSession(at: past)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: past)
    try store.finishSession(session, at: past.addingTimeInterval(3_600))
    return (database, store, exercise)
  }

  private func session(
    _ store: LoggerStore, _ exercise: ExerciseID, clock: Clock
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)],
      now: { clock.now }
    )
  }

  @discardableResult
  private func log(_ c: SessionCoordinator, row: Int, _ weight: Double, _ reps: Int) -> Bool {
    c.exercises[0].slots[row].draft = SetEntryDraft(weightKg: weight, reps: reps)
    return c.logSet(slotID: c.exercises[0].slots[row].id, inExercise: c.exercises[0].id)
  }

  private func edit(_ c: SessionCoordinator, row: Int, _ weight: Double?, _ reps: Int) -> Bool {
    c.editSet(
      slotID: c.exercises[0].slots[row].id, inExercise: c.exercises[0].id,
      to: SetEntryDraft(weightKg: weight, reps: reps))
  }

  // MARK: Edit

  @Test("An edit is written, then shown")
  func editWritesFirst() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)

    #expect(edit(c, row: 0, 102.5, 8))

    #expect(c.exercises[0].slots[0].draft.weightKg == 102.5)
    #expect(c.exercises[0].slots[0].isLogged)
    #expect(try store.sets(in: c.sessionID).first?.weightKg == 102.5)
    #expect(c.lastError == nil)
  }

  @Test("A refused edit changes nothing, on screen or on disk, and says why")
  func refusedEditChangesNothing() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)

    #expect(!edit(c, row: 0, nil, 8))

    #expect((c.lastError as? LoggerStoreError) == .incompleteSet)
    #expect(c.feedback?.event == .error)
    #expect(c.exercises[0].slots[0].draft.weightKg == 100)
    #expect(try store.sets(in: c.sessionID).first?.weightKg == 100)
  }

  @Test("An unlogged row is not edited through the store; it is typed into")
  func unloggedRowIsNotEdited() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    #expect(!edit(c, row: 1, 100, 8))
    #expect((c.lastError as? SessionCoordinatorError) == .slotNotLogged)
  }

  /// Review Focus: an edit is not a moment, though the summary may list what it now supports.
  @Test("Editing a set past the record announces nothing; the summary recomputes")
  func editNeverAnnounces() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    let beforeEdit = c.feedback

    #expect(edit(c, row: 0, 120, 8))

    #expect(c.recordsBySlot.isEmpty)
    #expect(c.lastRecords.isEmpty)
    #expect(c.feedback == beforeEdit)
    let setID = try #require(c.exercises[0].slots[0].loggedSetID)
    #expect(try store.recordsBySet(in: c.sessionID)[setID]?.isEmpty == false)
  }

  /// Review Focus: the typo that earned a trophy loses it when corrected.
  @Test("Correcting a typo'd record takes its trophy away")
  func typoRecordRetracted() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 1_000, 8)
    let row = c.exercises[0].slots[0].id
    #expect(c.recordsBySlot[row] != nil)

    #expect(edit(c, row: 0, 100, 8))

    #expect(c.recordsBySlot[row] == nil)
    #expect(try store.recordsBySet(in: c.sessionID).isEmpty)
  }

  @Test("A trophy the corrected set still earns stays")
  func earnedTrophySurvivesEdit() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 110, 8)
    let row = c.exercises[0].slots[0].id

    #expect(edit(c, row: 0, 110, 9))

    #expect(c.recordsBySlot[row]?.contains { $0.kind == .heaviestLoad } == true)
    #expect(c.recordsBySlot[row]?.first { $0.kind == .heaviestLoad }?.reps == 9)
  }

  // MARK: Delete and undo

  @Test("Delete is written first; Undo inside the window puts the row back where it was")
  func deleteThenUndo() throws {
    let (_, store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try session(store, exercise, clock: clock)
    log(c, row: 0, 100, 8)
    log(c, row: 1, 110, 8)
    let deleted = c.exercises[0].slots[1]
    #expect(c.recordsBySlot[deleted.id] != nil)

    #expect(c.deleteSet(slotID: deleted.id, inExercise: c.exercises[0].id))

    #expect(c.exercises[0].slots.count == 2)
    #expect(!c.exercises[0].slots.contains { $0.id == deleted.id })
    #expect(try store.sets(in: c.sessionID).count == 1)
    #expect(c.recordsBySlot[deleted.id] == nil)
    #expect(c.undoableDeletion?.slot.id == deleted.id)

    clock.now = start.addingTimeInterval(4)
    #expect(c.undoDelete())

    #expect(c.exercises[0].slots.count == 3)
    let restored = c.exercises[0].slots[1]
    #expect(restored.id == deleted.id)
    #expect(restored.isLogged)
    #expect(restored.loggedSetID != deleted.loggedSetID)
    #expect(try store.sets(in: c.sessionID).count == 2)
    #expect(c.recordsBySlot[deleted.id] != nil)
    #expect(c.undoableDeletion == nil)
  }

  /// Review Focus: a stale Undo button must not resurrect a set.
  @Test("Undo at or after five seconds does nothing, and the set stays deleted")
  func undoExpires() throws {
    let (_, store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try session(store, exercise, clock: clock)
    log(c, row: 0, 100, 8)
    #expect(c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))

    clock.now = start.addingTimeInterval(5)

    #expect(!c.undoDelete())
    #expect(c.undoableDeletion == nil)
    #expect(try store.sets(in: c.sessionID).isEmpty)
  }

  @Test("Once the toast has expired, Undo does nothing")
  func expiredUndoIsGone() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id)

    c.expireUndo()

    #expect(!c.undoDelete())
    #expect(try store.sets(in: c.sessionID).isEmpty)
  }

  @Test("Finishing ends the chance to undo")
  func finishEndsUndo() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    log(c, row: 1, 100, 8)
    c.deleteSet(slotID: c.exercises[0].slots[1].id, inExercise: c.exercises[0].id)

    try c.finish()

    #expect(c.undoableDeletion == nil)
    #expect(!c.undoDelete())
    #expect(try store.sets(in: c.sessionID).count == 1)
  }

  @Test("A delete the store refuses leaves the row on screen")
  func failedDeleteKeepsTheRow() throws {
    let (database, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    let setID = try #require(c.exercises[0].slots[0].loggedSetID)
    try database.write { db in
      try LoggedSet.where { $0.id.eq(setID.rawValue) }.delete().execute(db)
    }

    #expect(!c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))

    #expect(c.exercises[0].slots.count == 3)
    #expect((c.lastError as? LoggerStoreError) == .setNotFound)
    #expect(c.undoableDeletion == nil)
  }

  // MARK: Finish and discard

  @Test("Finishing with prefilled rows never logged asks, with the count")
  func finishDecisionCountsUnlogged() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    // Three rows, all prefilled at 100 × 8 from last week.
    log(c, row: 0, 100, 8)
    #expect(c.finishDecision == .confirmUnlogged(count: 2))
  }

  @Test("A workout with nothing logged is discarded, plan rows and all")
  func discardEmpty() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    #expect(c.finishDecision == .discardEmpty)

    #expect(c.discard())

    #expect(c.isDiscarded)
    #expect(try store.openSession() == nil)
  }

  @Test("A workout with a logged set is never discarded")
  func discardRefusedWithLoggedSet() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)

    #expect(!c.discard())

    #expect(!c.isDiscarded)
    #expect((c.lastError as? LoggerStoreError) == .sessionNotEmpty)
    #expect(try store.openSession()?.id == c.sessionID)
  }

  /// Review Focus: memory says empty; the database knows better, and wins.
  @Test("Discard is refused when the database holds a set the screen never saw")
  func discardRefusedWhenDatabaseDisagrees() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    _ = try store.logSet(
      sessionID: c.sessionID, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)
    #expect(c.loggedSetCount == 0)

    #expect(!c.discard())

    #expect((c.lastError as? LoggerStoreError) == .sessionNotEmpty)
    #expect(try store.sets(in: c.sessionID).count == 1)
    #expect(try store.openSession()?.id == c.sessionID)
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter SetCorrectionCoordinatorTests`
Expected: compile failure, `value of type 'SessionCoordinator' has no member 'editSet'`.

- [ ] **Step 3: Implement**

Add `case slotNotLogged` to `SessionCoordinatorError`, with the doc comment "A correction was asked
of a row that was never written. Unlogged rows are corrected by typing into them."

Add before `// MARK: - Finishing`:

```swift
  // MARK: - Corrections

  /// How long a deleted set can be put back (spec 2.3).
  public static let undoWindow: Duration = .seconds(5)

  /// The most recent deletion, while it can still be undone.
  public private(set) var undoableDeletion: DeletedSet?

  /// True once an empty workout has been discarded. The screen leaves the session.
  public private(set) var isDiscarded = false

  /// What Finish should do, decided from the rows (`FinishFlow`).
  public var finishDecision: FinishDecision { FinishFlow.decision(for: exercises) }

  /// Corrects a logged set: the store first, then the row.
  ///
  /// Never announces. An edit is a correction, not a moment, so it plays no record haptic and
  /// adds no trophy. A trophy stays only if the database still supports it (spec 2.3).
  @discardableResult
  public func editSet(
    slotID: UUID, inExercise exerciseStateID: UUID, to draft: SetEntryDraft
  ) -> Bool {
    guard let found = indices(slot: slotID, exercise: exerciseStateID) else {
      return fail(SessionCoordinatorError.unknownSlot, slotID: slotID)
    }
    let slot = exercises[found.exercise].slots[found.slot]
    guard let setID = slot.loggedSetID else {
      return fail(SessionCoordinatorError.slotNotLogged, slotID: slotID)
    }
    do {
      let saved = try store.updateSet(setID, to: draft)
      // What the row shows is what the store now holds.
      exercises[found.exercise].slots[found.slot].draft = SetEntryDraft(
        weightKg: saved.weightKg, reps: saved.reps, suggestion: slot.draft.suggestion)
      lastError = nil
      lastRecords = []
      keepOnlyRecordsStillEarned(editedSlotID: slotID)
      return true
    } catch {
      return fail(error, slotID: slotID)
    }
  }

  /// Deletes a logged set: the store first, then the row. It can be undone for `undoWindow`.
  @discardableResult
  public func deleteSet(slotID: UUID, inExercise exerciseStateID: UUID) -> Bool {
    guard let found = indices(slot: slotID, exercise: exerciseStateID) else {
      return fail(SessionCoordinatorError.unknownSlot, slotID: slotID)
    }
    let slot = exercises[found.exercise].slots[found.slot]
    guard let setID = slot.loggedSetID else {
      return fail(SessionCoordinatorError.slotNotLogged, slotID: slotID)
    }
    do {
      let removed = try store.deleteSet(setID)
      exercises[found.exercise].slots.remove(at: found.slot)
      undoableDeletion = DeletedSet(
        exerciseStateID: exerciseStateID,
        slot: slot,
        index: found.slot,
        expiresAt: now().addingTimeInterval(Self.undoWindow.seconds),
        removed: removed,
        records: recordsBySlot[slotID] ?? []
      )
      recordsBySlot[slotID] = nil
      lastRecords = []
      lastError = nil
      return true
    } catch {
      return fail(error, slotID: slotID)
    }
  }

  /// Puts the most recently deleted set back, inside the window: in the database under a new id,
  /// and on screen at its old position with its trophy. Outside the window it does nothing, so a
  /// stale Undo button cannot resurrect a set.
  @discardableResult
  public func undoDelete() -> Bool {
    guard let pending = undoableDeletion else { return false }
    guard now() < pending.expiresAt,
      let exerciseIndex = exercises.firstIndex(where: { $0.id == pending.exerciseStateID })
    else {
      undoableDeletion = nil
      return false
    }
    do {
      let newID = try store.restoreSet(pending.removed)
      var slot = pending.slot
      slot.loggedSetID = newID
      exercises[exerciseIndex].slots.insert(
        slot, at: min(pending.index, exercises[exerciseIndex].slots.count))
      if !pending.records.isEmpty { recordsBySlot[slot.id] = pending.records }
      undoableDeletion = nil
      lastError = nil
      return true
    } catch {
      // Kept, so Undo can be tried again until the window closes.
      return fail(error, slotID: pending.slot.id)
    }
  }

  /// The Undo toast timed out.
  public func expireUndo() { undoableDeletion = nil }

  /// Deletes this workout when nothing was logged.
  ///
  /// Refused in memory when a set is logged, and refused again by the store when the database
  /// holds one this screen never saw.
  @discardableResult
  public func discard() -> Bool {
    guard loggedSetCount == 0 else { return fail(LoggerStoreError.sessionNotEmpty, slotID: nil) }
    do {
      try store.discardEmptySession(sessionID)
      isDiscarded = true
      undoableDeletion = nil
      lastError = nil
      endRest()
      return true
    } catch {
      return fail(error, slotID: nil)
    }
  }

  /// After a correction, keeps each trophy only while the database still supports it. It never
  /// adds one.
  private func keepOnlyRecordsStillEarned(editedSlotID: UUID) {
    guard !recordsBySlot.isEmpty else { return }
    guard let fresh = try? store.recordsBySet(in: sessionID) else {
      // Unverifiable, so the edited row's trophy goes. A trophy the data may no longer support
      // is the worse error.
      recordsBySlot[editedSlotID] = nil
      return
    }
    var kept: [UUID: [PersonalRecord]] = [:]
    for exercise in exercises {
      for slot in exercise.slots {
        guard let shown = recordsBySlot[slot.id], let setID = slot.loggedSetID else { continue }
        let kinds = Set(shown.map(\.kind))
        let still = (fresh[setID] ?? []).filter { kinds.contains($0.kind) }
        if !still.isEmpty { kept[slot.id] = still }
      }
    }
    recordsBySlot = kept
  }

  private func indices(slot slotID: UUID, exercise exerciseStateID: UUID) -> (exercise: Int, slot: Int)? {
    guard let e = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let s = exercises[e].slots.firstIndex(where: { $0.id == slotID })
    else { return nil }
    return (e, s)
  }

  /// Every correction fails the same way: the error, for the screen's copy, and one error haptic.
  @discardableResult
  private func fail(_ error: any Error, slotID: UUID?) -> Bool {
    lastError = error
    emit(.error, slotID: slotID)
    return false
  }
```

In `finish()`, after `isFinished = true`, add:

```swift
    // A set deleted seconds before finishing stays deleted: the workout it belonged to is closed.
    undoableDeletion = nil
```

At the end of the file:

```swift
/// A set deleted from the live workout, held for `SessionCoordinator.undoWindow` so it can be put
/// back where it was.
public struct DeletedSet: Sendable {
  public let exerciseStateID: UUID
  public let slot: SetSlot
  public let index: Int
  public let expiresAt: Date
  let removed: LoggedSetRecord
  let records: [PersonalRecord]
}
```

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter 'SetCorrectionCoordinatorTests|RecordMomentTests|SessionCoordinatorTests'`,
then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/SessionCoordinator.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/SetCorrectionCoordinatorTests.swift
git commit -m "feat(store): edit, delete and undo a logged set; discard an empty workout

Corrections follow the same order as logging: the store is written, then the
row changes, and a refusal leaves both as they were.
- An edit announces nothing, and keeps a trophy only while the database still
  supports it, so a corrected typo loses its record.
- Delete holds the set for five seconds and Undo puts it back where it was;
  after that, after Finish, or after the toast expires, Undo does nothing.
- Discard is refused whenever any set exists, in memory or on disk.

Co-Authored-By: <your model's trailer>"
```

---

### Task 11: Workout shortcuts — recent movements, and "repeat this workout" (Store)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetStore/WorkoutShortcuts.swift`
- Test: `Packages/HardsetKit/Tests/HardsetStoreTests/WorkoutShortcutsTests.swift`

**Interfaces:**
- Consumes:
  - `CatalogEntry(row:)`, `MachineRecord(row:)` and `PlannedExercise` (existing)
  - the `Session`, `SessionExercise`, `LoggedSet`, `Exercise`, `Machine` and `Gym` tables
- Produces:
  - `public nonisolated struct WorkoutShortcutsStore`, with `init(database:)`, and:
    - `func recentExercises(limit: Int = 8) throws -> [CatalogEntry]`, newest first, distinct,
      not archived
    - `func repeatPlan(of sessionID: SessionID) throws -> RepeatPlan`, which throws
      `LoggerStoreError.sessionNotFound`
  - `public nonisolated struct RepeatPlan: Hashable, Sendable`, with:
    - `sourceSessionID`, `gymID: GymID?` and `items: [RepeatPlan.Item]`
    - `var isEmpty: Bool`
    - `@MainActor var plannedExercises: [PlannedExercise]`, with `plannedSets: nil` throughout
  - `RepeatPlan.Item`, holding `exerciseID`, `exerciseName`, `machineID: MachineID?`,
    `machineName: String?` and `machineIncrementKg: Double?`

There are no loads anywhere in a `RepeatPlan`. Prefill comes from history when the session starts.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Shortcuts the lifter starts: recent movements, and repeating a past workout")
@MainActor
struct WorkoutShortcutsTests {
  let now = Date(timeIntervalSince1970: 25_000_000)

  private struct Fixture {
    let database: any DatabaseWriter
    let logger: LoggerStore
    let gyms: GymStore
    let shortcuts: WorkoutShortcutsStore
    let press: ExerciseID
    let curl: ExerciseID
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    let press = ExerciseID()
    let curl = ExerciseID()
    try queue.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Leg Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: curl.rawValue, name: "Leg Curl") }.execute(db)
    }
    return Fixture(
      database: queue, logger: LoggerStore(database: queue), gyms: GymStore(database: queue),
      shortcuts: WorkoutShortcutsStore(database: queue), press: press, curl: curl)
  }

  private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }

  /// One finished workout. Each entry is a plan row, with the sets logged against it.
  @discardableResult
  private func workout(
    _ f: Fixture, gym: GymID?, at date: Date,
    _ rows: [(exercise: ExerciseID, machine: MachineID?, sets: [(Double, Int)])]
  ) throws -> SessionID {
    let session = try f.logger.startSession(gymID: gym, at: date)
    for (position, row) in rows.enumerated() {
      let rowID = try f.logger.addExercise(
        to: session, exerciseID: row.exercise, machineID: row.machine, position: position)
      for (index, set) in row.sets.enumerated() {
        _ = try f.logger.logSet(
          sessionID: session, exerciseID: row.exercise, machineID: row.machine,
          sessionExerciseID: rowID, draft: SetEntryDraft(weightKg: set.0, reps: set.1),
          at: date.addingTimeInterval(Double(position * 600 + index * 60)))
      }
    }
    try f.logger.finishSession(session, at: date.addingTimeInterval(3_600))
    return session
  }

  // MARK: Recent

  @Test("Recent movements: newest first, each once, archived ones left out, bounded")
  func recent() throws {
    let f = try fixture()
    let retired = ExerciseID()
    try f.database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: retired.rawValue, name: "Old Row", isArchived: true)
      }
      .execute(db)
    }
    let session = try f.logger.startSession(at: day(-3))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-3))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.curl, draft: SetEntryDraft(weightKg: 40, reps: 10),
      at: day(-2))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-1))
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: retired, draft: SetEntryDraft(weightKg: 50, reps: 10),
      at: day(0))

    #expect(try f.shortcuts.recentExercises().map(\.id) == [f.press, f.curl])
    #expect(try f.shortcuts.recentExercises(limit: 1).map(\.id) == [f.press])
  }

  @Test("No history, no recent movements")
  func noneYet() throws {
    let f = try fixture()
    #expect(try f.shortcuts.recentExercises().isEmpty)
  }

  // MARK: Repeat

  @Test("Repeat copies the movements and machines in order, and no loads or set counts")
  func copiesMovementsAndMachines() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(
      at: gym, name: "Leg Press", brand: "Hammer Strength", stackIncrementKg: 5, now: now)
    let past = try workout(
      f, gym: gym, at: day(-8),
      [(f.press, hammer, [(100, 8), (100, 8)]), (f.curl, nil, [(40, 10)])])

    let plan = try f.shortcuts.repeatPlan(of: past)

    #expect(plan.sourceSessionID == past)
    #expect(plan.gymID == gym)
    #expect(plan.items.map(\.exerciseID) == [f.press, f.curl])
    #expect(plan.items.map(\.machineID) == [hammer, nil])
    #expect(plan.items[0].machineName == "Hammer Strength Leg Press")
    #expect(plan.items[0].machineIncrementKg == 5)
    #expect(plan.items[0].exerciseName == "Leg Press")
    #expect(plan.plannedExercises.allSatisfy { $0.plannedSets == nil })
  }

  /// Review Focus: repeating an older workout must not bring back its loads.
  @Test("A repeated workout prefills from the latest history, not from the workout repeated")
  func prefillComesFromLatestHistory() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let past = try workout(f, gym: gym, at: day(-8), [(f.press, hammer, [(100, 8), (100, 8)])])
    try workout(f, gym: gym, at: day(-2), [(f.press, hammer, [(110, 6)])])

    let plan = try f.shortcuts.repeatPlan(of: past)
    let coordinator = try SessionCoordinator.start(
      store: f.logger, gymID: plan.gymID, plan: plan.plannedExercises, now: { self.now })

    #expect(coordinator.exercises[0].machineID == hammer)
    #expect(coordinator.exercises[0].slots.count == 1)
    #expect(coordinator.exercises[0].slots[0].draft.weightKg == 110)
    #expect(coordinator.exercises[0].slots[0].draft.reps == 6)
  }

  @Test("Two blocks of one movement both repeat; a movement never logged does not")
  func onlyWhatWasDone() throws {
    let f = try fixture()
    let past = try workout(
      f, gym: nil, at: day(-3),
      [(f.press, nil, [(100, 8)]), (f.curl, nil, []), (f.press, nil, [(80, 12)])])
    #expect(try f.shortcuts.repeatPlan(of: past).items.map(\.exerciseID) == [f.press, f.press])
  }

  @Test("Sets with no plan row count toward the first row for their movement, as in resume")
  func orphanSetsAttributedLikeResume() throws {
    let f = try fixture()
    let session = try f.logger.startSession(at: day(-3))
    _ = try f.logger.addExercise(to: session, exerciseID: f.press, position: 0)
    _ = try f.logger.addExercise(to: session, exerciseID: f.press, position: 1)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: day(-3))
    try f.logger.finishSession(session, at: day(-3).addingTimeInterval(3_600))

    #expect(try f.shortcuts.repeatPlan(of: session).items.count == 1)
  }

  @Test("A machine changed mid-exercise repeats the machine it ended on")
  func endedOnMachine() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", brand: "Hammer", now: now)
    let cybex = try f.gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try f.logger.startSession(gymID: gym, at: day(-3))
    let row = try f.logger.addExercise(
      to: session, exerciseID: f.press, machineID: hammer, position: 0)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, machineID: hammer, sessionExerciseID: row,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: day(-3))
    try f.logger.setSessionExerciseMachine(rowID: row, machineID: cybex)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.press, machineID: cybex, sessionExerciseID: row,
      draft: SetEntryDraft(weightKg: 80, reps: 8), at: day(-3).addingTimeInterval(300))
    try f.logger.finishSession(session, at: day(-3).addingTimeInterval(3_600))

    #expect(try f.shortcuts.repeatPlan(of: session).items.map(\.machineID) == [cybex])
  }

  /// Review Focus: removed equipment stays removed.
  @Test("An archived machine is not revived; the movement stays and asks for one")
  func archivedMachineNotRevived() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Home", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let past = try workout(f, gym: gym, at: day(-8), [(f.press, hammer, [(100, 8)])])
    try f.gyms.archiveMachine(hammer)

    let plan = try f.shortcuts.repeatPlan(of: past)

    #expect(plan.items.map(\.exerciseID) == [f.press])
    #expect(plan.items[0].machineID == nil)
    #expect(plan.items[0].machineName == nil)
    #expect(plan.gymID == gym)
  }

  @Test("An archived gym is not revived, nor its machines")
  func archivedGymNotRevived() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Old Gym", now: now)
    let hammer = try f.gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let past = try workout(f, gym: gym, at: day(-8), [(f.press, hammer, [(100, 8)])])
    try f.gyms.archiveGym(gym)

    let plan = try f.shortcuts.repeatPlan(of: past)

    #expect(plan.gymID == nil)
    #expect(plan.items[0].machineID == nil)
  }

  @Test("Repeating a workout that does not exist is reported")
  func unknownSession() throws {
    let f = try fixture()
    #expect(throws: LoggerStoreError.sessionNotFound) {
      try f.shortcuts.repeatPlan(of: SessionID())
    }
  }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `Tools/linux-test.sh --filter WorkoutShortcutsTests`
Expected: compile failure, `cannot find 'WorkoutShortcutsStore' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import HardsetCore
import SQLiteData

/// Two shortcuts into a workout, both started by the lifter: the movements they did most recently,
/// and "repeat this workout".
///
/// Neither is a recommendation. Nothing here is preselected or offered unasked, and nothing
/// invents a plan the lifter did not perform (`HANDOFF.md` §6, no default program).
public nonisolated struct WorkoutShortcutsStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Movements most recently logged, newest first, each once. Archived movements are left out,
  /// because that is what archiving is for.
  public func recentExercises(limit: Int = 8) throws -> [CatalogEntry] {
    guard limit > 0 else { return [] }
    return try database.read { db in
      let sets = try LoggedSet.order { $0.completedAt.desc() }.limit(500).fetchAll(db)
      var ordered: [UUID] = []
      for set in sets where !ordered.contains(set.exerciseID) { ordered.append(set.exerciseID) }
      guard !ordered.isEmpty else { return [] }
      let rows = try Exercise.where { $0.id.in(ordered) }.where { !$0.isArchived }.fetchAll(db)
      let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
      return ordered.compactMap { byID[$0] }.prefix(limit).map(CatalogEntry.init(row:))
    }
  }

  /// What "repeat this workout" starts: the movements that were done, in order, on the machines
  /// they ended on. No loads and no set counts. Rows and prefills come from history at start, as
  /// they do for any workout.
  ///
  /// A machine comes along only if it is not archived and belongs to the past session's gym, and
  /// that gym only if it is not archived. Anything else would revive equipment the lifter removed.
  /// The movement still comes, and its chip asks for a machine.
  public func repeatPlan(of sessionID: SessionID) throws -> RepeatPlan {
    try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let rows = try SessionExercise
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { $0.position }
        .fetchAll(db)
      let sets = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchAll(db)

      // Which rows were performed, attributed exactly as `SessionCoordinator.resume` attributes
      // sets: by plan row where the set records one, and otherwise to the first row for the
      // movement.
      let rowsWithSets = Set(sets.compactMap(\.sessionExerciseID))
      let orphanExercises = Set(sets.filter { $0.sessionExerciseID == nil }.map(\.exerciseID))
      var claimed = Set<UUID>()
      let performed = rows.filter { row in
        var isPerformed = rowsWithSets.contains(row.id)
        if orphanExercises.contains(row.exerciseID), claimed.insert(row.exerciseID).inserted {
          isPerformed = true
        }
        return isPerformed
      }

      let gym = try session.gymID.flatMap { id in
        try Gym.where({ $0.id.eq(id) }).where({ !$0.isArchived }).fetchOne(db)
      }
      let machineIDs = Array(Set(performed.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: Machine]()) { $0[$1.id] = $1 }
      let exerciseIDs = Array(Set(performed.map(\.exerciseID)))
      let names =
        exerciseIDs.isEmpty
        ? [:]
        : try Exercise
          .where { $0.id.in(exerciseIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

      let items = performed.map { row -> RepeatPlan.Item in
        let machine = row.machineID
          .flatMap { machines[$0] }
          .flatMap { candidate -> Machine? in
            guard !candidate.isArchived, let gym, candidate.gymID == gym.id else { return nil }
            return candidate
          }
        return RepeatPlan.Item(
          exerciseID: ExerciseID(rawValue: row.exerciseID),
          exerciseName: names[row.exerciseID] ?? "Unknown movement",
          machineID: machine.map { MachineID(rawValue: $0.id) },
          machineName: machine.map { MachineRecord(row: $0).displayName },
          machineIncrementKg: machine?.stackIncrementKg
        )
      }
      return RepeatPlan(
        sourceSessionID: sessionID, gymID: gym.map { GymID(rawValue: $0.id) }, items: items)
    }
  }
}

/// A past workout's movements and machines, ready to start again. It holds no loads, by
/// construction.
public nonisolated struct RepeatPlan: Hashable, Sendable {
  public nonisolated struct Item: Hashable, Sendable {
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public let machineID: MachineID?
    public let machineName: String?
    public let machineIncrementKg: Double?
  }

  public let sourceSessionID: SessionID
  public let gymID: GymID?
  public let items: [Item]

  public var isEmpty: Bool { items.isEmpty }
}

extension RepeatPlan {
  /// The plan `SessionCoordinator.start` takes. `plannedSets` is nil, so row counts come from
  /// history like any other start. MainActor, because `PlannedExercise` is (`DECISIONS.md` §11).
  @MainActor
  public var plannedExercises: [PlannedExercise] {
    items.map {
      PlannedExercise(
        exerciseID: $0.exerciseID, machineID: $0.machineID, exerciseName: $0.exerciseName,
        machineName: $0.machineName, machineIncrementKg: $0.machineIncrementKg, plannedSets: nil)
    }
  }
}
```

If the compiler rejects `try` inside `Optional.flatMap` within the read closure, unwrap with
`if let id = session.gymID { … }` instead. The behaviour is the same.

- [ ] **Step 4: Run to verify pass**

Run: `Tools/linux-test.sh --filter WorkoutShortcutsTests`, then `Tools/linux-test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/HardsetKit/Sources/HardsetStore/WorkoutShortcuts.swift \
  Packages/HardsetKit/Tests/HardsetStoreTests/WorkoutShortcutsTests.swift
git commit -m "feat(store): recent movements, and repeating a past workout

Getting into a workout meant searching the whole catalogue every time. The picker
can now lead with what was done most recently, and a past workout can be started
again by the lifter. Repeat copies the movements done, in order, and the
machines they ended on. Archived machines and gyms are not revived, and there
are no loads or set counts: prefill still comes from the latest history, so
repeating an old workout never brings back old numbers.

Co-Authored-By: <your model's trailer>"
```

---

## Mac-only tasks (12–19): how each one runs

None of these can compile on Linux. Each follows these steps in place of red/green:

1. **Cite.** Fetch the documentation JSON for every API listed under "Read and cite first". Confirm
   the declaration and availability, and put the human URL in the commit body. Each URL was
   checked on 2026-10-10.
2. **Change.** Make exactly the listed changes. Every animation, transition and symbol effect reads
   `@Environment(\.accessibilityReduceMotion)` and goes through `Tokens.Motion` (Task 12).
3. **Check.** Run the task's `rg` checks, and `Tools/linux-test.sh`, which must stay green and
   proves no Core or Store file was touched by accident.
4. **Ledger.** Append the given entries to `docs/MAC-VERIFICATION.md` under `## Phase 2`.
5. **Commit** with a why-message.

---

### Task 12: Tokens v2 — palette, semantic colours, hero type, motion, haptics (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/VolumeReportView.swift`, around line 70 (the
  lower-bound caveat colour)
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift`, around lines 78, 127
  and 132 (caveat colours)
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `Palette`, `PaletteSwatch` and `PaletteColor` (Task 5); `FeedbackEvent` (Task 3).
- Produces, used by Tasks 13–19:
  - `Tokens.Color.background` and `Tokens.Color.surface`, now from `Palette`
  - `Tokens.Color.cardStroke`, a hairline that separates cards in light mode
  - `Tokens.Color.success`, `.record`, `.caution` and `.critical`
  - `Tokens.Color.caveat`, which is `textSecondary`: an honest caveat is plain text with a glyph,
    never a warning colour
  - `Tokens.Color.certainty(_ level: CertaintyLevel)`, with the signature unchanged, the Palette
    values, and Increase Contrast variants
  - `Tokens.Text.hero`, the active set's weight and the largest type on screen
  - `Tokens.Motion.quick(_ reduceMotion: Bool) -> Animation?`
  - `Tokens.Motion.emphasis(_ reduceMotion: Bool) -> Animation?`
  - `Tokens.Motion.edgeTransition(_ reduceMotion: Bool) -> AnyTransition`
  - `Tokens.Haptic.feedback(for: FeedbackEvent) -> SensoryFeedback`

**Read and cite first:**
- https://developer.apple.com/documentation/uikit/uitraitcollection/accessibilitycontrast (iOS 13)
- https://developer.apple.com/documentation/appkit/nsappearance/name-swift.struct/accessibilityhighcontrastaqua (macOS 10.14)
- https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion (iOS 13)
- https://developer.apple.com/documentation/swiftui/sensoryfeedback, plus `impact(weight:intensity:)`,
  `success`, `error` and `selection` (iOS 17, macOS 14)

Changes:

1. **Colours from the palette.** Replace `background`, `surface` and `certainty(_:)` with:

   ```swift
   public static let background = adaptive(light: Palette.backgroundLight, dark: Palette.backgroundDark)
   public static let surface = adaptive(light: Palette.surfaceLight, dark: Palette.surfaceDark)
   /// Separates a card from the background in light mode, where white on #F2F2F7 is quiet.
   public static let cardStroke = SwiftUI.Color.primary.opacity(0.08)

   public static let success = adaptive(Palette.swatch(.success))
   public static let record = adaptive(Palette.swatch(.record))
   public static let caution = adaptive(Palette.swatch(.caution))
   public static let critical = adaptive(Palette.swatch(.critical))
   /// An honest caveat ("≥", "from another machine", "length unknown") is plain secondary text
   /// with a glyph. Orange made a lower bound read as a failure (spec §3, item 2).
   public static let caveat = textSecondary

   public static func certainty(_ level: CertaintyLevel) -> SwiftUI.Color {
     switch level {
     case .high: adaptive(Palette.swatch(.certaintyHigh))
     case .moderate: adaptive(Palette.swatch(.certaintyModerate))
     case .low: adaptive(Palette.swatch(.certaintyLow))
     case .unevaluated: adaptive(Palette.swatch(.certaintyUnevaluated))
     }
   }
   ```

   Replace `dynamic(light:dark:)` with two helpers. Keep the existing UIKit/AppKit split and its
   comment:

   ```swift
   private static func adaptive(_ swatch: PaletteSwatch) -> SwiftUI.Color {
     #if canImport(UIKit)
       return SwiftUI.Color(
         UIColor { traits in
           let dark = traits.userInterfaceStyle == .dark
           let high = traits.accessibilityContrast == .high
           return uiColor(
             dark
               ? (high ? swatch.darkIncreasedContrast : swatch.dark)
               : (high ? swatch.lightIncreasedContrast : swatch.light))
         })
     #elseif canImport(AppKit)
       return SwiftUI.Color(
         NSColor(name: nil) { appearance in
           let match = appearance.bestMatch(from: [
             .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
           ])
           let colour: PaletteColor =
             switch match {
             case .darkAqua: swatch.dark
             case .accessibilityHighContrastDarkAqua: swatch.darkIncreasedContrast
             case .accessibilityHighContrastAqua: swatch.lightIncreasedContrast
             default: swatch.light
             }
           return NSColor(srgbRed: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
         })
     #else
       return SwiftUI.Color(.sRGB, red: swatch.light.red, green: swatch.light.green, blue: swatch.light.blue)
     #endif
   }

   private static func adaptive(light: PaletteColor, dark: PaletteColor) -> SwiftUI.Color {
     // Backgrounds carry no text contrast requirement of their own, so one value serves both
     // contrast settings.
     adaptive(PaletteSwatch(light: light, lightIncreasedContrast: light, dark: dark, darkIncreasedContrast: dark))
   }
   ```

   `PaletteSwatch`'s public initialiser takes hex values. Add an internal convenience
   `init(light:lightIncreasedContrast:dark:darkIncreasedContrast:)` taking `PaletteColor`, here in
   an extension in `DesignTokens.swift`. Do not change the Core file. A `uiColor(_ c: PaletteColor)`
   helper returns `UIColor(red:green:blue:alpha: 1)`.

2. **Hero type.** Add
   `public static let hero = Font.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit()`
   to `Tokens.Text`. It is a text style, so it scales with Dynamic Type.

3. **Motion.** Add:

   ```swift
   /// Spring presets that collapse under Reduce Motion (spec 2.6).
   ///
   /// `nil` means no animation, so `withAnimation(Tokens.Motion.quick(reduceMotion))` and
   /// `.animation(Tokens.Motion.quick(reduceMotion), value:)` both become instant. Frequent actions
   /// (a log, a step) use `quick`: settled, no bounce (HIG, quiet on repetition).
   public enum Motion {
     public static func quick(_ reduceMotion: Bool) -> Animation? {
       reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)
     }
     public static func emphasis(_ reduceMotion: Bool) -> Animation? {
       reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2)
     }
     /// A pad or bar arriving from the bottom edge slides; under Reduce Motion it fades instead.
     public static func edgeTransition(_ reduceMotion: Bool) -> AnyTransition {
       reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
     }
   }
   ```

4. **Haptics.** Add:

   ```swift
   /// Core decides what happened; this only says how it feels. One crisp impact per log, and a
   /// distinct success for a record, which is the app's one earned moment (spec §3, items 4–5).
   public enum Haptic {
     public static func feedback(for event: FeedbackEvent) -> SensoryFeedback {
       switch event {
       case .log: .impact(weight: .medium)
       case .record: .success
       case .error: .error
       case .restAdjust: .selection
       }
     }
   }
   ```

5. **Caveats stop looking like errors.**
   - `VolumeReportView` around line 70, the lower-bound note: `Tokens.Color.certainty(.low)`
     becomes `Tokens.Color.caveat`. Keep the `exclamationmark.circle` glyph.
   - `ProgressionChartView` around line 78 (the no-estimate explanation), and lines 127 and 132
     (the machine-change rule and its glyph): `Tokens.Color.caveat`.
   - Every other `certainty(` call site is migrated by the task that owns its file:
     `SessionView`, `SetRowView` and `ExerciseSectionView` by Tasks 13 and 14, `HistoryView` by
     Task 17, and `HardsetRootView` by Task 19. `MethodologySheet` and `CertaintyBadge` keep
     `certainty(_:)`, because there it means certainty.

Check:
- `rg -n 'certainty\(\.low\)' Packages/HardsetKit/Sources/HardsetUI/VolumeReportView.swift Packages/HardsetKit/Sources/HardsetUI/ProgressionChartView.swift`
  returns nothing.
- `rg -n '\.yellow|\.orange|\.green' Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift`
  returns nothing.

Ledger:

```markdown
- [ ] (feat(ui): tokens v2 …) HardsetUI builds for iOS 26.4 simulator and, via `./test.sh`, for
      macOS. Then in the simulator:
  - [ ] Light mode: a card on the Volume tab is visibly separate from the background.
  - [ ] Settings › Accessibility › Display & Text Size › Increase Contrast on: the "Low confidence"
        badge text on the methodology sheet darkens (light) / lightens (dark).
  - [ ] The "at least this much" lower-bound note on the Volume tab reads as grey text with a
        glyph, not orange.
  - [ ] The machine-change rule on a progression chart is grey and dashed, not orange.
```

Commit, citing the URLs above.

---

### Task 13: Keypad v2 and the active set (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/NumericPad.swift` (rewrite)
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes:
  - `SetEntryKeypad` and `LoadStep` (Task 1)
  - `ActiveSet.next(in:after:)` (Task 2)
  - `Tokens.Text.hero`, `Tokens.Motion`, `Tokens.Color.success`, `.critical` and `.caveat`
    (Task 12)
  - `WeightFormatter.number(kilograms:)`
- Produces, for Tasks 14 and 18:
  - `NumericPad(keypad: Binding<SetEntryKeypad>, commit: NumericPad.Commit, onCommit: @escaping () -> Void, onDismiss: @escaping () -> Void)`,
    with `NumericPad.Commit` being `.next`, `.done` or `.save`.
  - `public enum SetRowEmphasis: Hashable, Sendable { case active, upcoming, logged }`
  - A `SetRowView` initialiser whose draft is a plain value:
    ```swift
    SetRowView(
      draft: SetEntryDraft, ordinal: Int, isWarmup: Bool = false, isLogged: Bool = false,
      unit: WeightUnit, previous: PriorSetRecord? = nil, priorNote: String? = nil,
      emphasis: SetRowEmphasis = .upcoming, keypad: SetEntryKeypad? = nil,
      onFocus: @escaping (SetRowField) -> Void, onLog: @escaping () -> Void)
    ```
  - `ExerciseSectionView` gains `activeSlotID: UUID? = nil`, `focusedSlotID: UUID? = nil`,
    `keypad: SetEntryKeypad? = nil` and `onFocus: ((SetSlot, SetRowField) -> Void)? = nil`.
    A nil `onFocus` makes the fields inert.
  - The `SessionView` public initialiser is **unchanged**. Focus and keypad state are private to
    it.

**Read and cite first:**
- https://developer.apple.com/documentation/swiftui/scrollviewreader (iOS 14)
- https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto(_:anchor:) (iOS 14)
- https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-6gwby
  (iOS 15; already used, and it now hosts the pad)

Changes:

1. **`NumericPad`, rewritten as the bottom inset.** It is no longer a 360 pt sheet.
   - **Header:**
     - a caption naming the focused field ("Weight" or "Reps")
     - `Text(keypad.composedText())` in `Tokens.Text.readout`, one line, scaling down to 0.6
     - a trailing `chevron.down` button labelled "Close keypad" that calls `onDismiss`
   - **Grid,** four by four, with `Tokens.loggerTapTarget` keys and the order fixed so keys never
     move under the thumb:
     ```
     1   2   3   −step
     4   5   6   +step
     7   8   9   Clear
     ,/. 0   ⌫   Next|Done|Save
     ```
   - **Step keys.** The weight label is `"−\(stepText)"` / `"+\(stepText)"`, where `stepText` is
     `keypad.loadStep.amount.formatted(.number.precision(.fractionLength(0...2)))`. The reps label
     is "−1" / "+1".
     - Accessibility labels: "Subtract 2.5 kilograms" / "Add 2.5 kilograms", "pounds" in pounds
       mode, and "One fewer rep" / "One more rep".
     - Step keys are `.disabled(keypad.focused.value == nil)`: ± never creates a value.
   - **Keys map to the keypad:** `type(digit:)`, `typeDecimalSeparator()`, `deleteBackward()`,
     `clear()` and `step(.down|.up)`. The commit key calls `onCommit`, and the caller decides
     between advancing and closing.
   - **Decimal key.** Keep the existing inert decimal key for reps, its locale separator, and the
     opaque `Tokens.Color.surface` background with its comment (glass cannot sample glass).
   - **No haptics on keys.** Frequent actions stay quiet.
   - Delete the old `init(buffer:onDone:)`. Its only caller was `SetRowView.padSheet`, which this
     task removes.

2. **`SetRowView` renders, and holds no editable state.**
   - **Remove** `@State weightBuffer`, `repsBuffer` and `editing`, plus `.sheet(item:)` and
     `padSheet`, `pushToDraft`, `reseedBuffers`, and the three `.onChange` modifiers (lines
     126–141).
     - This keeps Phase 1's fixes (spec 1.5, 1.6). An unfocused row renders the draft directly, so
       there is no cached buffer to go stale. A focused row renders the keypad, which `SessionView`
       rebuilds when the draft changes from outside (change 4).
     - Say this in a comment where the buffers were.
   - **`draft` becomes a plain `SetEntryDraft`.** The row never writes it.
   - **Values.**
     - Focused: `keypad.weight.displayText` / `keypad.reps.displayText`, with "." replaced by the
       locale separator.
     - Otherwise: `WeightFormatter(unit: unit).number(kilograms:)` of `draft.weightKg`, and
       `String(reps)`.
     - Empty shows "—".
   - **Field tap.** A field tap calls `onFocus(.weight)` / `onFocus(.reps)`, `.disabled(isLogged)`.
     The focused field gets the existing accent `strokeBorder`.
   - **Accessibility.** The actions become `Button("Edit weight") { onFocus(.weight) }` and
     `Button("Edit reps") { onFocus(.reps) }`, inside the existing `if !isLogged`.
   - **Emphasis** (spec 2.2, "the current set is the hero"):
     - `.active`: the weight in `Tokens.Text.hero`, with a 2 pt `Tokens.Color.accent`
       `strokeBorder` on the row's rounded rectangle.
     - `.upcoming`: the existing `Tokens.Text.setEntry`.
     - `.logged`: values in `Tokens.Text.label`, and vertical padding `Tokens.Spacing.tight`.
     - Never reduce opacity, so text keeps its contrast.
   - **Colours.** The logged check goes from `certainty(.high)` to `Tokens.Color.success`, and
     `priorNote` from `certainty(.low)` to `Tokens.Color.caveat`.
   - Leave `.sensoryFeedback(.success, trigger: isLogged)` for now. Task 14 replaces it.

3. **`ExerciseSectionView`.**
   - Change `ForEach($state.slots) { $slot in` (line 58) to `ForEach(state.slots) { slot in`.
   - Pass `draft: slot.draft`, plus:
     - `emphasis`: `.logged` if logged, `.active` if `slot.id == activeSlotID`, else `.upcoming`
     - `keypad`: `slot.id == focusedSlotID ? keypad : nil`
     - `onFocus: { field in onFocus?(slot, field) }`
   - Add `.id(slot.id)` to each row, for `scrollTo`.
   - The "From another machine" note (around line 120): `Tokens.Color.caveat`.

4. **`SessionView` owns focus, the keypad and scrolling.**
   - **New state:**

     ```swift
     @State private var focus: (exercise: UUID, slot: UUID)?
     @State private var keypad: SetEntryKeypad?
     @State private var lastLoggedSlotID: UUID?
     @Environment(\.accessibilityReduceMotion) private var reduceMotion
     ```

     If a tuple is rejected for `@State`, use a private `Hashable` struct `KeypadFocus`.
   - **Scrolling.** Wrap the `ScrollView` in `ScrollViewReader { proxy in … }`.
   - **Active set.** Compute `let active = ActiveSet.next(in: exercises, after: lastLoggedSlotID)`
     and pass `activeSlotID: active?.slotID`. Pass `focusedSlotID` and `keypad` only to the focused
     exercise.
   - **Focus.** `onFocus(slot, field)` runs:

     ```swift
     // `SetRowField` is the UI's name for a field; the keypad has its own.
     let keypadField: SetEntryKeypad.Field = field == .weight ? .weight : .reps
     var pad = SetEntryKeypad(
       draft: slot.draft, unit: unit,
       machineIncrementKg: exercises[e].machineIncrementKg, field: keypadField)
     pad.focus(keypadField)
     keypad = pad
     focus = (exercises[e].id, slot.id)
     withAnimation(Tokens.Motion.quick(reduceMotion)) { proxy.scrollTo(slot.id, anchor: .center) }
     ```
   - **The keypad binding** writes every change into the focused row's draft:
     `exercises[e].slots[s].draft = newValue.draft`. Unlogged rows take each keystroke, as before,
     and logged rows cannot be focused in this task.
   - **Commit.**
     - When `keypad.field == .weight`, call `keypad.advance()`.
     - Otherwise, close: `keypad = nil; focus = nil`, inside
       `withAnimation(Tokens.Motion.quick(reduceMotion))`.
   - **Outside changes reseed the pad.** Add `.onChange(of: focusedDraft)`, where `focusedDraft`
     looks up the focused slot's draft. When `new != keypad?.draft`, rebuild the keypad from `new`
     on the same field. This closes the Phase 1 residual where a machine change with the pad open
     left the pad showing one value and the row saving another.
   - **Logging.** In the row's `onLog`, after `onLogSet(exercise.id, slot)`, check the bound
     `exercises` for that slot. `logSet` is synchronous on the main actor, so the result is
     already there. If the slot is now logged:
     - set `lastLoggedSlotID = slot.id`
     - close the pad if it was focused on that slot
     - scroll, with `withAnimation(Tokens.Motion.quick(reduceMotion))`, to
       `ActiveSet.next(in: exercises, after: slot.id)?.slotID` with `anchor: .center` (spec 2.2)
   - **Bottom inset.** Replace the `.safeAreaInset(edge: .bottom)` (around line 171) with:

     ```swift
     .safeAreaInset(edge: .bottom, spacing: 0) {
       if let binding = keypadBinding {
         NumericPad(
           keypad: binding, commit: keypad?.field == .weight ? .next : .done,
           onCommit: commitKey, onDismiss: closeKeypad
         )
         .transition(Tokens.Motion.edgeTransition(reduceMotion))
       } else {
         #if !os(iOS)
           // On iOS the rest cluster lives in the tab bar's accessory (Task 19), so the countdown
           // is drawn once. The host build keeps the inline bar for previews.
           RestBarView(
             state: restState, metadata: restMetadata, onAdjust: onAdjustRest,
             onPauseResume: onPauseResumeRest, onSkip: onSkipRest)
         #endif
       }
     }
     ```

     Wrap the `safeAreaPadding(.bottom, …)` (around line 168) in `#if !os(iOS)` for the same
     reason. The pad's inset keeps the active row visible, because `scrollTo(…, anchor: .center)`
     runs after it appears.
   - **Error colour.** The error label (around line 82) goes from `certainty(.low)` to
     `Tokens.Color.critical`.

5. **Previews.** Update the `#Preview` harnesses in `SetRowView`, `ExerciseSectionView` and
   `SessionView` to the new initialisers: pass `draft: suggested`, not `$suggested`, and add
   `onFocus: { _ in }`. The previews compile in the Mac's host build, so a stale one breaks
   `./test.sh`.

Check:
- `rg -n 'presentationDetents|padSheet|weightBuffer|repsBuffer' Packages/HardsetKit/Sources/HardsetUI`
  returns nothing.
- `rg -n 'NumericPad\(' Packages/HardsetKit/Sources` lists only `SessionView.swift`.

Ledger:

```markdown
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
  - [ ] After logging, the screen scrolls to the next set, which becomes active.
  - [ ] With the pad up, the active row is fully visible on iPhone SE (3rd gen) and 17 Pro Max,
        and at the largest Dynamic Type size.
  - [ ] Pounds mode, 60 kg prefill: change only the reps, log; the chart and history show 60 kg,
        not 60.0013.
  - [ ] Change machine with the pad open: the pad and row both show the new machine's prefill
        (Phase 1 residual closed).
  - [ ] Reduce Motion on: the pad appears without sliding; scrolling to the next set jumps.
```

Commit:

```text
feat(ui): a keypad at the bottom of the screen, and the current set leads

The pad was a 360 pt sheet over the row it edited, and the first key appended
to the prefill. It is now a bottom inset that keeps the active row in view. It
shows the value being composed, steps by the machine's real increment, and
moves weight → reps on Next. The next unlogged set is the hero, and logging
scrolls to the one after.

Rows no longer cache editable buffers, which closes the "pad open during a
machine change" residual.

Docs: <the URLs above>

Co-Authored-By: <your model's trailer>
```

---

### Task 14: Row moments — edit, delete, undo, trophy, motion and haptics (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SetRowView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExerciseSectionView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/SessionView.swift`
- Modify, mechanically:
  `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift`. Delete the
  `records: coordinator.lastRecords,` argument (around line 107), because `SessionView` loses
  `records:`.
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes:
  - `FeedbackPulse`, `FeedbackEvent` and `RecordCopy` (Task 3)
  - `Tokens.Haptic`, `Tokens.Motion` and `Tokens.Color.record` (Task 12)
  - Task 13's `SessionView` focus machinery and the `NumericPad.Commit.save` label
- Produces new `SessionView` inputs, all defaulted, for Task 18:

  ```swift
  recordsBySlot: [UUID: [PersonalRecord]] = [:],
  feedback: FeedbackPulse? = nil,
  pendingUndo: PendingUndo? = nil,
  onEditSet: ((UUID, UUID, SetEntryDraft) -> Bool)? = nil,  // (exercise state id, slot id, draft) -> saved
  onDeleteSet: ((UUID, UUID) -> Void)? = nil,
  onUndoDelete: (() -> Void)? = nil,
  onExpireUndo: (() -> Void)? = nil,
  onFinish: (() -> Void)? = nil   // was non-optional; nil hides the in-list button
  ```

  Also:
  - `records: [PersonalRecord]` is **removed**.
  - New, in `SessionView.swift`:
    `public struct PendingUndo: Hashable, Sendable { public let id: UUID; public let label: String; public init(id:label:) }`
  - `SetRowView` gains `records: [PersonalRecord] = []`, `recordPulse: Int = 0`,
    `isEditingSaved: Bool = false`, `onEdit: (() -> Void)? = nil` and
    `onDelete: (() -> Void)? = nil`.
  - `ExerciseSectionView` passes those through, adding `recordsBySlot`, `recordPulse` (the pulse
    sequence for the slot it names), `editingSlotID`, `onEdit` and `onDelete`.

**Read and cite first:**
- https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(trigger:_:) (iOS 17,
  macOS 14). Use the `() -> SensoryFeedback?` closure form.
- https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:) and
  https://developer.apple.com/documentation/symbols/bouncesymboleffect (iOS 17)
- https://developer.apple.com/documentation/swiftui/view/symboleffectsremoved(_:) (iOS 17)
- https://developer.apple.com/documentation/swiftui/contenttransition/symboleffect(_:options:) (iOS 17)
- https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:) (iOS 17)
  and https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(countsdown:) (iOS 16)
- https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement (iOS 17)
- https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:) (iOS 13)
- https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:) (iOS 26, **macOS 26**,
  so guard it)

Changes:

1. **One haptic per log, from the coordinator's pulse** (spec 2.6).
   - Delete `SetRowView`'s `.sensoryFeedback(.success, trigger: isLogged)` (around line 224).
   - On `SessionView`'s outermost view, add:
     ```swift
     .sensoryFeedback(trigger: feedback) { feedback.map { Tokens.Haptic.feedback(for: $0.event) } }
     ```
     A record set therefore plays only `.success`, an ordinary log `.impact(weight: .medium)`, and
     a failure `.error`.

2. **The trophy on the row** (spec 2.5).
   - When `records` is non-empty, `SetRowView` shows `Image(systemName: "trophy.fill")` in
     `Tokens.Color.record` beside the check:

     ```swift
     Image(systemName: "trophy.fill")
       .foregroundStyle(Tokens.Color.record)
       .symbolEffect(.bounce, value: recordPulse)
       .symbolEffectsRemoved(reduceMotion)
       .accessibilityHidden(true)
     ```

   - Under the row's values, add one `Tokens.Text.caption` line:
     `records.map { RecordCopy.line(for: $0, formatter: WeightFormatter(unit: unit)) }.joined(separator: " · ")`,
     limited to two lines.
   - Append `"record: " + that text` to `spokenLabel`.
   - `ExerciseSectionView` passes `recordPulse: feedback?.slotID == slot.id && feedback?.event == .record ? feedback!.sequence : 0`.
     The bounce fires once, on the earning log, and never on resume, because resume emits no pulse.

3. **The VoiceOver announcement** (spec 2.5). On `SessionView`:

   ```swift
   .onChange(of: feedback) { _, pulse in
     guard let pulse, pulse.event == .record, let slotID = pulse.slotID,
       let exercise = exercises.first(where: { $0.slots.contains { $0.id == slotID } }),
       let records = recordsBySlot[slotID],
       let text = RecordCopy.announcement(
         for: records, exerciseName: exercise.exerciseName, formatter: WeightFormatter(unit: unit))
     else { return }
     AccessibilityNotification.Announcement(text).post()
   }
   ```

4. **Remove the second celebration.**
   - Delete the records banner (`if !records.isEmpty { … }`, around lines 91–114), `describe`,
     and any helper only it used.
   - Delete the `records` property and init parameter.
   - Remove the argument at the one call site in `LiveSessionScreen.swift`.
   - The trophy on the row is now the only celebration (spec §3, item 5: "Nothing else
     celebrates").

5. **The log check, symbol replace** (spec 2.6):

   ```swift
   Image(systemName: isLogged ? "checkmark.circle.fill" : "circle")
     .contentTransition(.symbolEffect(.replace))
     .animation(Tokens.Motion.quick(reduceMotion), value: isLogged)
   ```

6. **Counts that roll** (spec 2.6).
   - `ExerciseSectionView`'s "x of y logged":
     `.contentTransition(.numericText(value: Double(state.loggedCount)))` plus
     `.animation(Tokens.Motion.quick(reduceMotion), value: state.loggedCount)`.
   - `SessionView`'s volume line: `.contentTransition(.numericText())` plus
     `.animation(Tokens.Motion.quick(reduceMotion), value: volumeDescription)`.

7. **Edit and Delete on a logged row** (spec 2.3).
   - `SetRowView`, when `isLogged` and the callbacks are non-nil:

     ```swift
     .contextMenu {
       if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
       if let onDelete { Button("Delete", systemImage: "trash", role: .destructive, action: onDelete) }
     }
     ```

   - Mirror both inside `.accessibilityActions` as "Edit set" and "Delete set", when logged.
   - **Edit.** `SessionView` focuses the row with a flag `editingSaved = true`. Then:
     - The keypad binding does **not** write the draft while `editingSaved`. A saved set changes
       only after the store accepts it, so the draft is untouched while the lifter types.
     - The commit label is `.save` when on reps, and `.next` on weight.
     - Save calls `if onEditSet?(exerciseID, slotID, keypad.draft) == true { closeKeypad() }`. On
       `false` the pad stays open with what was typed, and the coordinator's error shows above.
     - Closing the pad any other way discards the edit.
   - `SessionView` passes `editingSlotID` (the focused slot while `editingSaved`, else nil) to
     `ExerciseSectionView`. That view sets `isEditingSaved: slot.id == editingSlotID` on the row.
     While `isEditingSaved`, the row shows a `Tokens.Text.caption` line "Not saved yet" in
     `Tokens.Color.caution`, so an unsaved correction is never mistaken for the record.
   - **Delete.** It calls `onDeleteSet(exerciseID, slotID)`, and the coordinator removes the row.

8. **The Undo bar** (spec 2.3, 5 seconds). When `pendingUndo` is non-nil, show an overlay at the
   bottom, above the pad inset:

   ```swift
   HStack {
     Text(undo.label).font(Tokens.Text.label)
     Spacer()
     Button("Undo") { onUndoDelete?() }.font(Tokens.Text.label.weight(.semibold))
   }
   .padding(Tokens.Spacing.regular)
   .modifier(UndoBarBackground())   // glass on iOS 26 / macOS 26, opaque surface otherwise
   .transition(Tokens.Motion.edgeTransition(reduceMotion))
   .task(id: undo.id) {
     do {
       try await Task.sleep(for: .seconds(5))
       onExpireUndo?()
     } catch {
       // Cancelled because a newer deletion replaced this one: do not expire the newer one.
     }
   }
   ```

   `UndoBarBackground` is a private `ViewModifier`:
   - `if #available(iOS 26.0, macOS 26.0, *) { content.glassEffect(.regular, in: .capsule) }`
   - `else { content.background(Tokens.Color.surface, in: Capsule()) }`

   The Undo bar is the functional layer, so glass is allowed. Post
   `AccessibilityNotification.Announcement("\(undo.label). Undo is available.")` when it appears.
   The coordinator enforces the window itself, so a late tap does nothing.

9. **`onFinish` becomes optional.** Show the in-list "Finish workout" button only when non-nil.
   Task 18 moves Finish to the toolbar.

Check:
- `rg -n 'records:' Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift` returns
  nothing.
- `rg -n 'sensoryFeedback' Packages/HardsetKit/Sources/HardsetUI` lists only `SessionView.swift`.
  Task 15 adds the rest bar's.
- Every `.animation(`, `.transition(`, `withAnimation(` and `.symbolEffect(` in these three files
  reads `reduceMotion`. Check with `rg -n 'animation\(|transition\(|withAnimation|symbolEffect\(' …`.

Ledger:

```markdown
- [ ] (feat(ui): row moments …) HardsetUI and HardsetFeature build. In the simulator, with
      history so a record is possible, and on device for haptics:
  - [ ] Log a set that beats last week: a trophy appears on that row and bounces once; one
        success haptic, no impact haptic with it. Log the next set: the trophy stays.
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
```

Commit, citing the URLs above.

---

### Task 15: One rest cluster (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/RestBarView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `Tokens.Haptic` and `Tokens.Motion` (Task 12).
- Produces: `RestBarView` gains `onOpen: (() -> Void)? = nil`, which taps on the countdown and
  caption call. Every existing parameter keeps its default, so existing callers compile. Task 19
  hosts it in the tab accessory.

**Read and cite first:**
- https://developer.apple.com/documentation/swiftui/environmentvalues/tabviewbottomaccessoryplacement
  (iOS 26.0, macOS 26.0)
- https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement
- https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:) (iOS 17)

Changes:

1. **Adapt to where it is hosted.** Inside `#if os(iOS)`, read
   `@Environment(\.tabViewBottomAccessoryPlacement) private var placement`.
   - `.inline` (the tab bar collapsed): show only the countdown and the pause/resume button.
   - `.expanded` or `nil`: show the countdown, the "exercise · Set n" caption, −15, +15,
     pause/resume and skip.
   - In the accessory (`placement != nil`), drop the opaque `.background(Tokens.Color.surface)`.
     The accessory already provides Liquid Glass, and glass on glass is wrong. Outside it, keep the
     background.
   - Size buttons to `Tokens.minimumTapTarget` (44 pt) when `placement != nil`, because the
     accessory is short, and keep `loggerTapTarget` otherwise.
2. **Tap to open.** Wrap the countdown and caption `VStack` in
   `Button { onOpen?() } label: { … }.buttonStyle(.plain).disabled(onOpen == nil)`, with the
   accessibility hint "Opens the workout".
3. **Paused remainder rolls.** On the paused `Text(remaining.clockString)`, add
   `.contentTransition(.numericText(countsDown: true))` and
   `.animation(Tokens.Motion.quick(reduceMotion), value: remaining)`. The running countdown stays
   `Text(timerInterval:)`, which the system animates.
4. **The adjust haptic.** Add `@State private var adjustCount = 0`. Increment it in both adjust
   buttons, and add
   `.sensoryFeedback(Tokens.Haptic.feedback(for: .restAdjust), trigger: adjustCount)`.

Ledger:

```markdown
- [ ] (feat(ui): one rest cluster …) HardsetUI builds. With Task 19 merged, on the simulator:
  - [ ] During a rest, the countdown appears once: in the tab accessory, never also in the
        Train screen.
  - [ ] Scroll the set list down: the tab bar collapses and the accessory shows only the
        countdown and pause; scroll up: −15 / +15 / skip return.
  - [ ] ±15 plays a selection haptic (device) and the paused remainder rolls (off with Reduce
        Motion).
  - [ ] All accessory buttons are at least 44 pt (Accessibility Inspector).
```

Commit, citing the URLs above.

---

### Task 16: The summary sheet (Mac-only)

**Files:**
- Create: `Packages/HardsetKit/Sources/HardsetUI/WorkoutSummaryView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes:
  - `WorkoutSummary`, `.RecordLine` and `.MuscleLine` (Task 8)
  - `RecordCopy` (Task 3)
  - `WeightFormatter.total(kilograms:)` and `CountText` (Phase 1)
  - `ExercisePickerView.displayName(_:)`, which is internal static in HardsetUI
  - `Tokens` (Task 12)
- Produces, for Task 19:
  `public struct WorkoutSummaryView: View`, with
  `init(summary: WorkoutSummary?, unit: WeightUnit, errorMessage: String? = nil, onRetry: (() -> Void)? = nil, onDone: @escaping () -> Void)`.

Changes, a new file:
- A `NavigationStack { List { … } }`, titled "Workout saved", with a `Done` button in
  `.confirmationAction` calling `onDone`.
- `summary == nil && errorMessage != nil`: a `ContentUnavailableView` showing `errorMessage` and a
  "Try again" `Button` calling `onRetry`.
- `summary == nil && errorMessage == nil`: a `ProgressView()`.
- With a summary:
  - **When.** The start date, formatted
    `.dateTime.weekday(.abbreviated).day().month(.abbreviated)`, and `summary.lengthText`. When
    `summary.length == nil`, show `Label(summary.lengthText, systemImage: "questionmark.circle")`
    in `Tokens.Color.caveat`.
  - **Totals.**
    - `CountText.sets(volume.workingSets)` and `CountText.reps(volume.reps)`
    - `WeightFormatter(unit: unit).total(kilograms: volume.volumeKg)` + " volume", only when
      `volumeKg > 0`
    - "\(volume.warmupSets) warm-up", only when non-zero
  - **Records,** when any. Per line: a trophy in `Tokens.Color.record`, `record.kind.label`,
    `RecordCopy.detail(for:formatter:)`, and `exerciseName` with `machineName` (" · " joined) in
    caption. One accessibility element per line.
  - **Muscles touched,** when any. Per line: `ExercisePickerView.displayName(line.muscle)` and
    `line.setsText()`, with `.accessibilityLabel("\(name), \(line.spokenSetsText())")`.
    - When `summary.unattributedSets > 0`, the footer reads "\(CountText.sets(n)) on movements
      with no muscles recorded, so these are at least this much." in `Tokens.Color.caveat`, with
      an `info.circle` glyph.
  - **Machines,** when any: one row per name.
- No goals, targets, streaks or comparison with a plan. Nothing here is "great job". The sheet is
  static, so it has no animation.
- `#Preview` with a sample `WorkoutSummary` that has a record, a lower-bound muscle line, and an
  unknown length.

Ledger:

```markdown
- [ ] (feat(ui): the summary sheet) HardsetUI builds; the preview renders. With Task 19 merged:
  - [ ] Finish a workout with a record: the sheet lists the record, the muscles (with ≥ when a
        custom movement was logged), the machines, and the length.
  - [ ] A workout left open overnight and finished shows "Length unknown", not 20 hours.
  - [ ] Pounds mode: every weight in the sheet is in lb.
  - [ ] VoiceOver reads "Chest, at least 6 sets", not "greater than or equal to".
  - [ ] There is no goal, target or streak anywhere on it.
```

Commit:

```text
feat(ui): a summary at the end of a workout, and nothing to live up to

Finishing used to drop the lifter back on an empty start screen. The sheet says
what was done, read from the database: how long it took (or that it is
unknown), sets, reps and volume, each record against what it beat, the muscles
trained with "≥" where some sets could not be attributed, and the machines used.
It names no target, streak or goal.

Co-Authored-By: <your model's trailer>
```

---

### Task 17: Picker Recent and Cancel; Repeat in history (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetUI/ExercisePickerView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetUI/HistoryView.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes: `CatalogEntry`, `HistoryRow` and `Tokens.Color.caveat` (Task 12).
- Produces, for Tasks 18 and 19:
  - `ExercisePickerView(query:entries:recent: [CatalogEntry] = [], onCancel: (() -> Void)? = nil, onSelect:)`
  - `HistoryView(rows:unit:onSelect:onRepeat: ((HistoryRow) -> Void)? = nil)`

**Read and cite first:**
- https://developer.apple.com/documentation/swiftui/toolbaritemplacement/cancellationaction
  (already used in the codebase; recorded for completeness)
- https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)

Changes:

1. **`ExercisePickerView`.**
   - Add `recent` and `onCancel` to the stored properties and the init, between `entries` and
     `onSelect`, so the trailing-closure call site
     `ExercisePickerView(query:entries:) { … }` still compiles.
   - When `query.isEmpty && !recent.isEmpty`, render `Section("Recent") { ForEach(recent) { row($0) } }`
     before the muscle groups. Entries also stay in their group.
   - When `onCancel` is non-nil, add
     `.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }`.
     Bind `onCancel` locally with `if let`, so the button's action is non-optional.
2. **`HistoryView`.**
   - When `onRepeat` is non-nil, each row gets:

     ```swift
     .contextMenu {
       if let onRepeat {
         Button("Repeat this workout", systemImage: "arrow.clockwise") { onRepeat(row) }
       }
     }
     .accessibilityAction(named: Text("Repeat this workout")) { onRepeat?(row) }
     ```

     It is offered only when asked for, and nothing is preselected or suggested (spec 2.9).
   - The "Length unknown" label (around line 117): from `certainty(.low)` to
     `Tokens.Color.caveat`. Keep the glyph.

Ledger:

```markdown
- [ ] (feat(ui): picker Recent and Cancel; repeat from history) HardsetUI builds. In the
      simulator, with Task 18/19 merged:
  - [ ] Add movement: the picker has Cancel, and with an empty search a "Recent" section listing
        the last movements logged, newest first. Typing hides it.
  - [ ] History: long-press a workout: "Repeat this workout". No row suggests it otherwise.
  - [ ] "Length unknown" in history is grey with its glyph, not orange.
```

Commit, citing the URLs above.

---

### Task 18: Live session wiring (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift`
- Modify, mechanically:
  `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`. The `onFinished:` closure at
  the `LiveSessionScreen(` call (around line 162) becomes `onFinished: { _ in self.coordinator = nil }`.
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes:
  - `editSet`, `deleteSet`, `undoDelete`, `expireUndo`, `undoableDeletion`, `finishDecision`,
    `discard` and `isDiscarded` (Task 10)
  - `recordsBySlot` and `feedback` (Task 9)
  - `FinishFlow` and `FinishDecision` (Task 2)
  - `WorkoutShortcutsStore.recentExercises` (Task 11)
  - `FailureCopy` actions `.editSet`, `.deleteSet`, `.undoDelete` and `.discardWorkout` (Task 6)
  - the Task 14 `SessionView` inputs and the Task 17 picker inputs
- Produces, for Task 19:
  - `public enum SessionExit: Hashable, Sendable { case finished(SessionID), discarded }`
  - The `LiveSessionScreen` init's `onFinished` becomes `(SessionExit) -> Void`, defaulting to
    `{ _ in }`.
  - It gains `shortcuts: WorkoutShortcutsStore? = nil`.

**Read and cite first:**
- https://developer.apple.com/documentation/swiftui/buttonrole/confirm (iOS 26.0, **macOS 26.0**,
  so guard it)
- https://developer.apple.com/documentation/swiftui/toolbaritemplacement/confirmationaction
- https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)
  (iOS 15; new to this codebase)

Changes:

1. **Finish moves to the toolbar,** as the prominent action (spec 2.7):

   ```swift
   .toolbar {
     ToolbarItem(placement: .confirmationAction) {
       if #available(iOS 26.0, macOS 26.0, *) {
         Button("Finish", role: .confirm, action: requestFinish)
       } else {
         Button("Finish", action: requestFinish)
       }
     }
   }
   ```

   Stop passing `onFinish:` to `SessionView`, so the in-list button is hidden.
2. **The finish flow** (spec 2.4). Add `@State private var finishPrompt: FinishDecision?`:

   ```swift
   private func requestFinish() {
     switch coordinator.finishDecision {
     case .finish: finish()
     case .confirmUnlogged, .discardEmpty: finishPrompt = coordinator.finishDecision
     }
   }
   ```

   - For `.confirmUnlogged(let n)`: a
     `.confirmationDialog(FinishFlow.unloggedTitle(count: n), isPresented:, titleVisibility: .visible)`
     with "Finish workout", which calls `finish()`, and "Keep logging" (`role: .cancel`).
   - For `.discardEmpty`: a dialog titled `FinishFlow.discardTitle`, with message
     `FinishFlow.discardMessage`. "Discard workout" (`role: .destructive`) calls `discard()`, and
     "Keep logging" is `role: .cancel`.
3. **Exit.**
   - `finish()` calls `onFinished(.finished(coordinator.sessionID))` on success, and in the
     existing `alreadyFinished` branch.
   - `discard()`:

     ```swift
     private func discard() {
       lastAction = .discardWorkout
       if coordinator.discard() {
         hooks.cancel()
         onFinished(.discarded)
       }
     }
     ```
4. **The error copy follows the action that failed.** Add
   `@State private var lastAction: FailureCopy.Action = .logSet`, set it before each coordinator
   call (`.logSet`, `.editSet`, `.deleteSet`, `.undoDelete` or `.discardWorkout`), and compute:

   ```swift
   coordinator.lastError.map { FailureCopy.message(for: $0, during: lastAction) }
   ```

   Keep Phase 1 Task 11's `.finishWorkout` handling for finish failures.
5. **Corrections and moments into `SessionView`:**

   ```swift
   recordsBySlot: coordinator.recordsBySlot,
   feedback: coordinator.feedback,
   pendingUndo: coordinator.undoableDeletion.map { PendingUndo(id: $0.slot.id, label: "Set deleted") },
   onEditSet: { exerciseID, slotID, draft in
     lastAction = .editSet
     return coordinator.editSet(slotID: slotID, inExercise: exerciseID, to: draft)
   },
   onDeleteSet: { exerciseID, slotID in
     lastAction = .deleteSet
     coordinator.deleteSet(slotID: slotID, inExercise: exerciseID)
   },
   onUndoDelete: { lastAction = .undoDelete; coordinator.undoDelete() },
   onExpireUndo: { coordinator.expireUndo() },
   ```

   The `onLogSet` closure sets `lastAction = .logSet` first.
6. **The picker.**
   - Add `@State private var recentEntries: [CatalogEntry] = []`, loaded in the picker sheet's
     `.task` with `shortcuts?.recentExercises()`.
   - On failure it becomes `[]`, with a comment: Recent is a convenience, and the full list below
     is unaffected.
   - Pass `recent: recentEntries` and
     `onCancel: { isPickerPresented = false; pickerQuery = "" }`.

Check:
- `rg -n 'onFinished\(\)' Packages/HardsetKit/Sources/HardsetFeature` returns nothing.
- `rg -n 'onFinish:' Packages/HardsetKit/Sources/HardsetFeature/LiveSessionScreen.swift` returns
  nothing.

Ledger:

```markdown
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
```

Commit, citing the URLs above.

---

### Task 19: Root — tabs, the rest accessory, glass Start, the summary, Repeat (Mac-only)

**Files:**
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HardsetRootView.swift`
- Modify: `Packages/HardsetKit/Sources/HardsetFeature/HistoryScreen.swift`
- Modify: `docs/MAC-VERIFICATION.md`

**Interfaces:**
- Consumes:
  - `WorkoutSummaryStore` (Task 8)
  - `WorkoutShortcutsStore`, `RepeatPlan` and `.plannedExercises` (Task 11)
  - `RestBarView(onOpen:)` (Task 15)
  - `WorkoutSummaryView` (Task 16)
  - `HistoryView(onRepeat:)` (Task 17)
  - `SessionExit` and `LiveSessionScreen(shortcuts:onFinished:)` (Task 18)
  - `FailureCopy.Action.loadSummary` (Task 8)
  - `SessionCoordinator.activeRest` and `endRest()` (Phase 1)
- Produces:
  - `HardsetEnvironment` gains `public let summaries: WorkoutSummaryStore` and
    `public let shortcuts: WorkoutShortcutsStore`.
  - `HistoryScreen(store:unit:onRepeat: ((SessionID) -> Void)? = nil)`

**Read and cite first:**
- https://developer.apple.com/documentation/swiftui/tabview/init(selection:content:) (iOS 18)
- https://developer.apple.com/documentation/swiftui/tab/init(_:systemimage:value:content:) (iOS 18)
- https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)
  (**iOS 26.1**, which is the deployment floor, and iOS-only, so `#if os(iOS)`)
- https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:) (iOS 26.0,
  macOS 26.0; already inside `#if os(iOS)`)
- https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent (iOS 26.0,
  **macOS 26.0**, so guard it)

Changes:

1. **Selection** (spec 2.9). Add `private enum RootTab: Hashable { case train, volume, history }`
   and `@State private var selectedTab: RootTab = .train`. Build
   `TabView(selection: $selectedTab)`, giving each `Tab` its value:
   `Tab("Train", systemImage: "figure.strengthtraining.traditional", value: RootTab.train) { … }`,
   and likewise for `.volume` and `.history`.
2. **One identity.** Replace the `if coordinator != nil { content.tabViewBottomAccessory { … } } else { content }`
   (around lines 135–148) with:

   ```swift
   #if os(iOS)
     content
       // `isEnabled:` keeps one TabView identity whether or not a session exists. The old
       // `if/else` swapped identity, which reset tab state on every start and finish.
       .tabViewBottomAccessory(isEnabled: coordinator != nil) { liveSessionAccessory }
       .tabBarMinimizeBehavior(.onScrollDown)
   #else
     content
   #endif
   ```

   Update the comment above it: an empty pill came from attaching unconditionally, and
   `isEnabled:` is the documented fix.
3. **The accessory is the one rest cluster** (spec 2.7).
   - While `hooks.state()` is not `.idle`, show:

     ```swift
     RestBarView(
       state: hooks.state(), metadata: coordinator.activeRest,
       onAdjust: hooks.adjust, onPauseResume: hooks.pauseOrResume,
       onSkip: { hooks.cancel(); coordinator.endRest() },
       onOpen: { selectedTab = .train })
     ```

   - Otherwise show the existing status `HStack`, wrapped in
     `Button { selectedTab = .train } label: { … }.buttonStyle(.plain)`, with the hint "Opens the
     workout".
   - Delete the accessory's own `Text(timerInterval:)`. The countdown is now drawn once.
4. **The glass Start button** (spec 2.7). In `startView`:

   ```swift
   if #available(iOS 26.0, macOS 26.0, *) {
     Button(action: startEmptyWorkout) {
       Text("Start workout").font(Tokens.Text.label.weight(.semibold))
         .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
     }
     .buttonStyle(.glassProminent)
   } else {
     // the existing plain button, unchanged
   }
   ```

   Glass appears only here, on the toolbar Finish, the accessory and the Undo bar. Never on rows
   or cards.
5. **The summary after finishing** (spec 2.4).
   - Add `private struct SummaryTarget: Identifiable, Hashable { let id: SessionID }` and
     `@State private var summaryTarget: SummaryTarget?`.
   - `LiveSessionScreen`'s `onFinished`:
     ```swift
     { exit in
       coordinator = nil
       if case .finished(let id) = exit { summaryTarget = SummaryTarget(id: id) }
     }
     ```
   - Attach `.sheet(item: $summaryTarget) { SummarySheet(sessionID: $0.id, store: environment.summaries, unit: unit) { summaryTarget = nil } }`
     to the `TabView`, so it outlives the Train tab's content.
   - Add a private `SummarySheet: View` in the same file. It loads in `.task`, with
     `@State var summary: WorkoutSummary?` and `@State var loadError: String?`:
     - on failure, `loadError = FailureCopy.message(for: error, during: .loadSummary)`
     - the result renders as `WorkoutSummaryView(summary:unit:errorMessage: loadError, onRetry: load, onDone:)`
   - The workout is already finished and saved when this runs, which is why the copy says so.
6. **Repeat this workout** (spec 2.9).
   - `HistoryScreen` gains `onRepeat` and passes `onRepeat.map { repeatSession in { row in repeatSession(row.id) } }`
     to `HistoryView`.
   - `HardsetRootView` passes `onRepeat: coordinator == nil ? repeatWorkout : nil`. A workout in
     progress hides the action rather than replacing the session.
   - `repeatWorkout`:

     ```swift
     private func repeatWorkout(_ id: SessionID) {
       do {
         let plan = try environment.shortcuts.repeatPlan(of: id)
         guard !plan.isEmpty else { return }
         coordinator = try SessionCoordinator.start(
           store: environment.logger, gymID: plan.gymID, plan: plan.plannedExercises,
           restPreferences: restPreferences, hooks: hooks)
         selectedGym = plan.gymID
         startFailed = false
         selectedTab = .train
       } catch {
         startFailed = true
         selectedTab = .train
       }
     }
     ```

   - It is started only by the lifter's explicit menu choice. Nothing is preselected or
     recommended.
7. **The environment.** In `HardsetEnvironment.init`:
   ```swift
   self.summaries = WorkoutSummaryStore(database: database)
   self.shortcuts = WorkoutShortcutsStore(database: database)
   ```
   Pass `shortcuts: environment.shortcuts` to `LiveSessionScreen`.
8. **Colours.** `startFailed` (around line 192) and `gymError` (around line 255) go from
   `certainty(.low)` to `Tokens.Color.critical`.

Check:
- `rg -n 'certainty\(' Packages/HardsetKit/Sources/HardsetFeature` returns nothing.
- `rg -n 'Text\(timerInterval' Packages/HardsetKit/Sources/HardsetFeature` returns nothing.

Ledger:

```markdown
- [ ] (feat(feature): one tab identity, the rest accessory, glass Start, the summary, repeat)
      App builds for iOS 26.4. In the simulator:
  - [ ] Start a workout on Train, switch to History, start a rest: the accessory shows the
        countdown with controls; tap its label: the app returns to Train.
  - [ ] Start and finish a workout: the tabs keep their navigation state (no identity reset),
        and no empty pill shows above the tab bar on the start screen.
  - [ ] Start workout is a prominent glass button; no set row or card is glass.
  - [ ] Finish a workout: the summary sheet appears over whichever tab is showing; Done
        dismisses it. Force a read failure (debug): "Your workout is saved, but its summary
        could not be read." with Try again.
  - [ ] History › long-press › Repeat this workout: a session starts on Train with the same
        movements and machines, prefilled from the latest history (not the repeated loads).
        With a workout already open, the action is absent.
```

Commit, citing the URLs above.

---

## Spec coverage

| Spec item | Logic (tested on Linux) | Rendering and wiring (Mac ledger) |
|---|---|---|
| 2.1 Keypad v2 | 1 (replace on first input, `LoadStep`, Next, Clear, header text, two- and five-tap paths) | 13 |
| 2.2 Active-set focus | 2 (`ActiveSet`) | 13 |
| 2.3 Edit and delete | 6 (write-first store corrections, undo under a new id), 7 (re-judging), 10 (coordinator order, 5 s undo, never announcing) | 14, 18 |
| 2.4 Finish flow and summary | 2 (`FinishDecision`, copy), 6 (cascading discard), 8 (`WorkoutSummary` from the database), 10 (`finishDecision`, `discard`) | 16, 18, 19 |
| 2.5 The record moment | 3 (`FeedbackEvent`, `RecordCopy` in the lifter's unit), 4 and 7 (records per set from the database), 9 (kept per row, rebuilt on resume) | 14 |
| 2.6 Motion and haptics | 3 (`FeedbackEvent`) | 12 (`Motion`, `Haptic`), 14, 15 |
| 2.7 Liquid Glass, functional layer only | — | 14 (Undo bar), 15 (accessory), 18 (Finish), 19 (Start, single rest cluster) |
| 2.8 Tokens v2 | 5 (palette contrast, Increase Contrast, card separation) | 12; call sites in 13, 14, 17 and 19 |
| 2.9 Navigation | 11 (recent movements, repeat plan) | 17, 18, 19 |

Self-review, run against the spec after writing:
- **Coverage.** All nine items have owners.
- **Placeholders.** Every Core and Store step has complete code. UI steps give exact changes and
  snippets. The only angle-bracket tokens left are the deliberate `<your model's trailer>`, and
  `<the URLs above>` in commit templates, which the executor fills from that task's "Read and cite
  first" list.
- **Types.** `FeedbackPulse.slotID`, `recordsBySlot`, `DeletedSet.slot.id`, `PendingUndo`,
  `SessionExit`, `WorkoutSummary` and `RepeatPlan.plannedExercises` are spelled identically
  wherever they are produced and consumed.
- **Review Focus.** The five failure modes each carry a named test in the owning task.
