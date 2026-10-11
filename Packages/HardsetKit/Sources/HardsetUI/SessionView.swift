import HardsetCore
import SwiftUI

/// The live workout screen.
///
/// Deliberately knows nothing about storage. It takes the exercise states, reports taps, and
/// renders whatever error the caller hands it — so `HardsetUI` keeps depending on `HardsetCore`
/// alone, and this screen compiles and previews on the host without a database, a CloudKit
/// container or a simulator.
///
/// The app target owns the wiring: it holds the `SessionCoordinator`, passes
/// `$coordinator.exercises` in, and forwards `onLogSet` to `coordinator.logSet`, which is the
/// only thing allowed to mark a row logged.
///
/// What this screen does own is the keypad: which row it is on, what it holds, and where the list
/// scrolls. The pad is the bottom inset, so the row it edits stays in view above it.
public struct SessionView: View {
  @Binding private var exercises: [ExerciseLogState]
  private let unit: WeightUnit
  private let restState: RestTimerState
  private let restMetadata: RestMetadata?
  private let errorMessage: String?
  private let records: [PersonalRecord]
  private let onLogSet: (UUID, SetSlot) -> Void
  private let onAdjustRest: (Duration) -> Void
  private let onPauseResumeRest: () -> Void
  private let onSkipRest: () -> Void
  private let onAddExercise: (() -> Void)?
  private let onSelectMachine: ((UUID) -> Void)?
  private let onShowHistory: ((UUID) -> Void)?
  private let restChoices: [ExerciseID: Duration]
  private let onChooseRest: ((UUID, Duration?) -> Void)?
  private let onStartRest: ((UUID) -> Void)?
  private let onFinish: () -> Void

  /// The row the pad is editing. Ids, not indices: rows can be added while the pad is open.
  @State private var focus: KeypadFocus?
  @State private var keypad: SetEntryKeypad?
  /// The set logged last, which decides the active set: the lifter's order, not the plan's.
  @State private var lastLoggedSlotID: UUID?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// - Parameter restChoices: Each exercise's chosen rest. An exercise with no entry has no rest,
  ///   and its chip reads "Off" — there is no default.
  /// - Parameter onChooseRest: Reports a rest chosen for an exercise (by its state id), or `nil`
  ///   for Off. Passing `nil` hides the rest chips.
  /// - Parameter onStartRest: Starts an exercise's chosen rest now.
  public init(
    exercises: Binding<[ExerciseLogState]>,
    unit: WeightUnit,
    restState: RestTimerState = .idle,
    restMetadata: RestMetadata? = nil,
    errorMessage: String? = nil,
    records: [PersonalRecord] = [],
    onLogSet: @escaping (UUID, SetSlot) -> Void,
    onAdjustRest: @escaping (Duration) -> Void = { _ in },
    onPauseResumeRest: @escaping () -> Void = {},
    onSkipRest: @escaping () -> Void = {},
    onAddExercise: (() -> Void)? = nil,
    onSelectMachine: ((UUID) -> Void)? = nil,
    onShowHistory: ((UUID) -> Void)? = nil,
    restChoices: [ExerciseID: Duration] = [:],
    onChooseRest: ((UUID, Duration?) -> Void)? = nil,
    onStartRest: ((UUID) -> Void)? = nil,
    onFinish: @escaping () -> Void = {}
  ) {
    self._exercises = exercises
    self.unit = unit
    self.restState = restState
    self.restMetadata = restMetadata
    self.errorMessage = errorMessage
    self.records = records
    self.onLogSet = onLogSet
    self.onAdjustRest = onAdjustRest
    self.onPauseResumeRest = onPauseResumeRest
    self.onSkipRest = onSkipRest
    self.onAddExercise = onAddExercise
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
    self.restChoices = restChoices
    self.onChooseRest = onChooseRest
    self.onStartRest = onStartRest
    self.onFinish = onFinish
  }

  public var body: some View {
    // Pure: the next unlogged row after the last one logged. No storage is read to draw this.
    let active = ActiveSet.next(in: exercises, after: lastLoggedSlotID)

    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: Tokens.Spacing.regular) {
          if let errorMessage {
            // A failed write is stated, not swallowed. The row it belongs to is still unlogged,
            // so the user can retry rather than discovering the gap days later.
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.critical)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(Tokens.Spacing.regular)
              .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
              .padding(.horizontal, Tokens.Spacing.regular)
          }

          if !records.isEmpty {
            // Each record names what it beat, so the claim is checkable rather than a bare "PR!".
            VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
              ForEach(records) { record in
                Label {
                  VStack(alignment: .leading, spacing: 0) {
                    Text(record.kind.label)
                      .font(Tokens.Text.label.weight(.semibold))
                    Text(Self.describe(record, unit: unit))
                      .font(Tokens.Text.caption)
                      .foregroundStyle(Tokens.Color.textSecondary)
                  }
                } icon: {
                  Image(systemName: "trophy")
                }
                .foregroundStyle(Tokens.Color.certainty(.high))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Spacing.regular)
            .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .padding(.horizontal, Tokens.Spacing.regular)
            .accessibilityElement(children: .combine)
          }

          ForEach($exercises) { $exercise in
            ExerciseSectionView(
              state: $exercise,
              unit: unit,
              onLogSet: { slot in logSet(exerciseID: exercise.id, slot: slot, proxy: proxy) },
              onSelectMachine: onSelectMachine.map { select in
                { select(exercise.id) }
              },
              onShowHistory: onShowHistory.map { show in
                { show(exercise.id) }
              },
              restChoice: restChoices[exercise.exerciseID],
              onChooseRest: onChooseRest.map { choose in
                { choice in choose(exercise.id, choice) }
              },
              onStartRest: onStartRest.map { start in
                { start(exercise.id) }
              },
              activeSlotID: active?.slotID,
              focusedSlotID: focusedSlotID(in: exercise.id),
              keypad: keypadState(in: exercise.id),
              onFocus: { slot, field in
                focusRow(exerciseID: exercise.id, slotID: slot.id, field: field, proxy: proxy)
              }
            )
            .background(Tokens.Color.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .padding(.horizontal, Tokens.Spacing.snug)
          }

          if let onAddExercise {
            Button(action: onAddExercise) {
              Label("Add movement", systemImage: "plus")
                .font(Tokens.Text.label)
                .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Color.accent)
            .background(
              Tokens.Color.surface,
              in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
            )
            .padding(.horizontal, Tokens.Spacing.regular)
          }

          // An empty workout says so, and says what to do about it, rather than rendering a bare
          // "Finish" button under nothing.
          if exercises.isEmpty {
            ContentUnavailableView {
              Label("Nothing added yet", systemImage: "dumbbell")
            } description: {
              Text("Add a movement to start logging sets.")
            }
          }

          summary
        }
        .padding(.vertical, Tokens.Spacing.regular)
        #if !os(iOS)
          // Room for the rest bar so the last row is never trapped underneath it. On iOS the rest
          // cluster is in the tab bar's accessory (Task 19), and the tab view makes room for it.
          .safeAreaPadding(.bottom, restState == .idle ? 0 : 72)
        #endif
      }
      .background(Tokens.Color.background)
      // The pad is an inset, not a sheet, so the scroll view shrinks above it and the row being
      // edited can be scrolled into view instead of sitting under the pad.
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let binding = keypadBinding {
          NumericPad(
            keypad: binding, commit: keypad?.field == .weight ? .next : .done,
            onCommit: { commitKey() }, onDismiss: { closeKeypad() }
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
    }
    // A draft changed by something other than the pad: a machine change re-prefills the unlogged
    // rows and brings its own step, and a unit change rewrites how both fields read. The pad is
    // rebuilt from the row each time, or it would show one value while the row saved another.
    .onChange(of: focusedDraft) { reseedKeypad() }
    .onChange(of: focusedMachineIncrementKg) { reseedKeypad() }
    .onChange(of: unit) { reseedKeypad() }
  }

  // MARK: - Keypad

  /// Which row the pad is on, by id.
  private struct KeypadFocus: Hashable {
    let exercise: UUID
    let slot: UUID
  }

  // Only the focused exercise sees the pad, so a keystroke redraws one section. Helpers rather
  // than inline ternaries, to keep the section's initialiser cheap to type-check.
  private func focusedSlotID(in exerciseID: UUID) -> UUID? {
    focus?.exercise == exerciseID ? focus?.slot : nil
  }

  private func keypadState(in exerciseID: UUID) -> SetEntryKeypad? {
    focus?.exercise == exerciseID ? keypad : nil
  }

  /// The focused row's position, looked up fresh, or `nil` when the pad is closed or its row is
  /// gone.
  private var focusedIndices: (exercise: Int, slot: Int)? {
    guard let focus,
      let e = exercises.firstIndex(where: { $0.id == focus.exercise }),
      let s = exercises[e].slots.firstIndex(where: { $0.id == focus.slot })
    else { return nil }
    return (e, s)
  }

  private var focusedDraft: SetEntryDraft? {
    focusedIndices.map { exercises[$0.exercise].slots[$0.slot].draft }
  }

  /// Watched only so a machine change rebuilds the pad's step even when the prefill is unchanged.
  private var focusedMachineIncrementKg: Double? {
    focusedIndices.flatMap { exercises[$0.exercise].machineIncrementKg }
  }

  /// Every keystroke goes straight into the focused row's draft, as the row's own buffers used to,
  /// so the row, the pad and what Log writes are one value. `nil` while the pad is closed.
  private var keypadBinding: Binding<SetEntryKeypad>? {
    guard let current = keypad else { return nil }
    return Binding(
      // The snapshot only covers the frames in which the pad is animating away after closing.
      get: { keypad ?? current },
      set: { newValue in
        keypad = newValue
        guard let index = focusedIndices else { return }
        // A logged row is read-only: only the store changes a saved set.
        guard !exercises[index.exercise].slots[index.slot].isLogged else { return }
        exercises[index.exercise].slots[index.slot].draft = newValue.draft
      }
    )
  }

  /// Opens the pad on a field, with that field selected so the first key replaces the prefill.
  private func focusRow(
    exerciseID: UUID, slotID: UUID, field: SetRowField, proxy: ScrollViewProxy
  ) {
    guard let e = exercises.firstIndex(where: { $0.id == exerciseID }),
      let slot = exercises[e].slots.first(where: { $0.id == slotID }),
      !slot.isLogged
    else { return }
    // `SetRowField` is the UI's name for a field; the keypad has its own.
    let keypadField: SetEntryKeypad.Field = field == .weight ? .weight : .reps
    var pad = SetEntryKeypad(
      draft: slot.draft, unit: unit,
      machineIncrementKg: exercises[e].machineIncrementKg, field: keypadField)
    pad.focus(keypadField)
    withAnimation(Tokens.Motion.quick(reduceMotion)) {
      keypad = pad
      focus = KeypadFocus(exercise: exerciseID, slot: slotID)
      // Centred in the space above the pad, so the row being edited is never under it.
      proxy.scrollTo(slotID, anchor: .center)
    }
  }

  /// Next moves weight → reps; on reps the key closes the pad.
  private func commitKey() {
    guard let current = keypad else { return }
    if current.field == .weight {
      _ = keypad?.advance()
    } else {
      closeKeypad()
    }
  }

  private func closeKeypad() {
    withAnimation(Tokens.Motion.quick(reduceMotion)) {
      keypad = nil
      focus = nil
    }
  }

  /// Rebuilds the open pad from its row when the row changed from outside. The pad's own
  /// keystrokes land here too, and are recognised because the draft then already matches.
  private func reseedKeypad() {
    guard let current = keypad else { return }
    guard let index = focusedIndices else {
      // The row went away under the pad. There is nothing left to edit.
      closeKeypad()
      return
    }
    let exercise = exercises[index.exercise]
    let draft = exercise.slots[index.slot].draft
    let step = LoadStep(machineIncrementKg: exercise.machineIncrementKg, unit: unit)
    guard draft != current.draft || step != current.loadStep || unit != current.unit
    else { return }
    var pad = SetEntryKeypad(
      draft: draft, unit: unit, machineIncrementKg: exercise.machineIncrementKg,
      field: current.field)
    pad.focus(current.field)
    keypad = pad
  }

  // MARK: - Logging

  /// Logs through the caller, then follows the lifter to the next set.
  ///
  /// `onLogSet` is synchronous on the main actor (`SessionCoordinator.logSet`), so the bound rows
  /// already say whether the write succeeded. Only a row that has just become logged moves the
  /// screen: a failed write leaves the lifter where they are, with the error above.
  private func logSet(exerciseID: UUID, slot: SetSlot, proxy: ScrollViewProxy) {
    let wasLogged = isLogged(slot.id)
    onLogSet(exerciseID, slot)
    guard !wasLogged, isLogged(slot.id) else { return }
    lastLoggedSlotID = slot.id
    let next = ActiveSet.next(in: exercises, after: slot.id)
    withAnimation(Tokens.Motion.quick(reduceMotion)) {
      // A logged row is read-only, so a pad left on it would be editing nothing.
      if focus?.slot == slot.id {
        keypad = nil
        focus = nil
      }
      if let next { proxy.scrollTo(next.slotID, anchor: .center) }
    }
  }

  private func isLogged(_ slotID: UUID) -> Bool {
    exercises.contains { exercise in
      exercise.slots.contains { $0.id == slotID && $0.isLogged }
    }
  }

  /// Spells out the comparison. An estimated-1RM record says it is an estimate, and states the new
  /// estimate as well as the old one, because guideline 1.4.1 is about not presenting an estimate
  /// as a measurement and "up from about 80 kg" alone never said what it was up to.
  static func describe(_ record: PersonalRecord, unit: WeightUnit) -> String {
    let f = WeightFormatter(unit: unit)
    switch record.kind {
    case .heaviestLoad:
      if let previous = record.previousWeightKg {
        return "\(f.load(kilograms: record.weightKg)), up from \(f.load(kilograms: previous))"
      }
      return f.load(kilograms: record.weightKg)
    case .repsAtLoad:
      let reps = CountText.reps(record.reps)
      if let previousReps = record.previousReps {
        return "\(reps) at \(f.load(kilograms: record.weightKg)), up from \(previousReps)"
      }
      return "\(reps) at \(f.load(kilograms: record.weightKg))"
    case .estimatedOneRepMax:
      // The record carries the set that earned it. For this kind `previousWeightKg` is the
      // previous best estimate rather than a lifted weight, so the new estimate is derived here
      // from the same function the detector used.
      let estimate = StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps)
      guard let newEstimate = estimate.value else { return "estimated" }
      if let previous = record.previousWeightKg {
        return "\(f.estimate(kilograms: newEstimate)), up from \(f.estimate(kilograms: previous))"
      }
      return f.estimate(kilograms: newEstimate)
    }
  }

  private var summary: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      Text(volumeDescription)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
      Button(action: onFinish) {
        Text("Finish workout")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)
      .background(
        Tokens.Color.surface,
        in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
      )
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    .padding(.top, Tokens.Spacing.snug)
  }

  /// Counted by `SessionVolume`, which is tested. The rules that matter — unlogged rows and
  /// warm-ups excluded — live there rather than here, so this screen cannot disagree with the
  /// history screen about what the session contained.
  private var volumeDescription: String {
    let volume = SessionVolume(exercises: exercises)
    guard !volume.isEmpty else { return "No sets logged yet" }
    var parts = [CountText.sets(volume.workingSets), CountText.reps(volume.reps)]
    if volume.volumeKg > 0 {
      parts.append("\(WeightFormatter(unit: unit).total(kilograms: volume.volumeKg)) volume")
    }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
    return parts.joined(separator: " · ")
  }
}

#if DEBUG
  #Preview("Live session") {
    struct Harness: View {
      @State private var exercises: [ExerciseLogState]
      @State private var restChoices: [ExerciseID: Duration] = [:]

      init() {
        let press = ExerciseID()
        let machine = MachineID()
        let key = ProgressionKey(exerciseID: press, machineID: machine)
        let records = [
          PriorSetRecord(weightKg: 100, reps: 10, completedAt: .distantPast),
          PriorSetRecord(weightKg: 105, reps: 8, completedAt: .distantPast),
        ]
        let snapshot = PriorPerformanceSnapshot(
          entries: [key: PriorPerformance(key: key, lastSets: records, heaviestSet: records.last)],
          capturedAt: .distantPast
        )
        _exercises = State(
          initialValue: [
            .build(
              exerciseID: press, machineID: machine, exerciseName: "Leg Press",
              machineName: "Hammer Strength", snapshot: snapshot
            ),
            // No history: one empty row, nothing loggable, no invented numbers.
            .build(
              exerciseID: ExerciseID(), exerciseName: "Standing Calf Raise",
              snapshot: .empty(capturedAt: .distantPast)
            ),
          ]
        )
      }

      var body: some View {
        SessionView(
          exercises: $exercises,
          unit: .kilograms,
          restState: .running(endsAt: Date().addingTimeInterval(96)),
          restMetadata: RestMetadata(
            exerciseName: "Leg Press", setOrdinal: 1, plannedSets: 2,
            machineName: "Hammer Strength"
          ),
          onLogSet: { stateID, slot in
            guard let index = exercises.firstIndex(where: { $0.id == stateID }) else { return }
            exercises[index].markLogged(slotID: slot.id, setID: SetID())
          },
          restChoices: restChoices,
          onChooseRest: { stateID, choice in
            guard let exercise = exercises.first(where: { $0.id == stateID }) else { return }
            restChoices[exercise.exerciseID] = choice
          },
          onStartRest: { _ in }
        )
      }
    }
    return Harness()
  }
#endif
