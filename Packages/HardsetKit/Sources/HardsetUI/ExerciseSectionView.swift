import HardsetCore
import SwiftUI

/// One exercise in a live session: its header, its set rows, and a way to add another set.
///
/// The view owns no logic. Which suggestion belongs to which row, what a new row starts at,
/// and whether the history was borrowed from other equipment are all decided by
/// `ExerciseLogState` and tested there. This renders the result and reports taps upward.
///
/// Persistence deliberately does not happen here. `onLogSet` hands the slot to the caller,
/// which writes it through `LoggerStore` and calls `markLogged` on success — so a failed write
/// can never leave a row showing a check mark for a set that was not saved.
public struct ExerciseSectionView: View {
  @Binding private var state: ExerciseLogState
  private let unit: WeightUnit
  private let onLogSet: (SetSlot) -> Void
  private let onSelectMachine: (() -> Void)?
  private let onShowHistory: (() -> Void)?
  private let restChoice: Duration?
  private let onChooseRest: ((Duration?) -> Void)?
  private let onStartRest: (() -> Void)?
  private let activeSlotID: UUID?
  private let focusedSlotID: UUID?
  private let keypad: SetEntryKeypad?
  private let onFocus: ((SetSlot, SetRowField) -> Void)?
  private let recordsBySlot: [UUID: [PersonalRecord]]
  private let recordPulses: [UUID: Int]
  private let editingSlotID: UUID?
  private let onEdit: ((SetSlot) -> Void)?
  private let onDelete: ((SetSlot) -> Void)?

  @State private var isChoosingCustomRest = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// - Parameter onSelectMachine: Opens the machine picker. Passing `nil` hides the chip, which is
  ///   correct when no gym is known — an affordance that opens an empty list is worse than none.
  /// - Parameter onShowHistory: Opens this movement's load history. `nil` leaves the name inert.
  /// - Parameter restChoice: The rest the lifter chose for this exercise, or `nil` for none. There
  ///   is no default rest, so `nil` reads "Off" and no preset is shown as selected.
  /// - Parameter onChooseRest: Reports a rest chosen from the menu, or `nil` for Off. Passing `nil`
  ///   hides the rest chip, as `onSelectMachine` does for the machine chip.
  /// - Parameter onStartRest: Starts the chosen rest now. `nil` leaves "Start rest now" out.
  /// - Parameter activeSlotID: The set the lifter is about to do, drawn as the hero. `nil` when it
  ///   is in another exercise.
  /// - Parameter focusedSlotID: The row the pad is editing, if it is in this exercise.
  /// - Parameter keypad: The pad's state, handed to the focused row only.
  /// - Parameter onFocus: A row's field was tapped. `nil` makes the fields inert.
  /// - Parameter recordsBySlot: The records each row earned, by `SetSlot.id`, as the coordinator
  ///   holds them. A row shows a trophy only when it has an entry here.
  /// - Parameter recordPulses: The feedback sequence of the record log each row earned, by
  ///   `SetSlot.id`. A row's trophy bounces when its entry changes, and only then.
  /// - Parameter editingSlotID: The logged row the pad is correcting, if it is in this exercise.
  /// - Parameter onEdit: Corrects a logged row. `nil` offers no Edit.
  /// - Parameter onDelete: Deletes a logged row. `nil` offers no Delete.
  public init(
    state: Binding<ExerciseLogState>,
    unit: WeightUnit,
    onLogSet: @escaping (SetSlot) -> Void,
    onSelectMachine: (() -> Void)? = nil,
    onShowHistory: (() -> Void)? = nil,
    restChoice: Duration? = nil,
    onChooseRest: ((Duration?) -> Void)? = nil,
    onStartRest: (() -> Void)? = nil,
    activeSlotID: UUID? = nil,
    focusedSlotID: UUID? = nil,
    keypad: SetEntryKeypad? = nil,
    onFocus: ((SetSlot, SetRowField) -> Void)? = nil,
    recordsBySlot: [UUID: [PersonalRecord]] = [:],
    recordPulses: [UUID: Int] = [:],
    editingSlotID: UUID? = nil,
    onEdit: ((SetSlot) -> Void)? = nil,
    onDelete: ((SetSlot) -> Void)? = nil
  ) {
    self._state = state
    self.unit = unit
    self.onLogSet = onLogSet
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
    self.restChoice = restChoice
    self.onChooseRest = onChooseRest
    self.onStartRest = onStartRest
    self.activeSlotID = activeSlotID
    self.focusedSlotID = focusedSlotID
    self.keypad = keypad
    self.onFocus = onFocus
    self.recordsBySlot = recordsBySlot
    self.recordPulses = recordPulses
    self.editingSlotID = editingSlotID
    self.onEdit = onEdit
    self.onDelete = onDelete
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      header

      VStack(spacing: Tokens.Spacing.hairline) {
        // Values, not bindings: a row never writes its draft. The pad's keystrokes reach the draft
        // through `SessionView`, which owns the pad.
        ForEach(state.slots) { slot in
          SetRowView(
            draft: slot.draft,
            ordinal: ordinal(of: slot),
            isWarmup: slot.isWarmup,
            isLogged: slot.isLogged,
            unit: unit,
            previous: state.suggestion(forSetIndex: ordinal(of: slot)),
            // The borrowed-history note is shown once in the header, not repeated on every
            // row — an honest caveat that appears five times reads as noise and gets ignored.
            priorNote: nil,
            emphasis: emphasis(of: slot),
            keypad: slot.id == focusedSlotID ? keypad : nil,
            // Only what the coordinator holds for this row. The view never judges a record.
            records: recordsBySlot[slot.id] ?? [],
            recordPulse: recordPulses[slot.id] ?? 0,
            isEditingSaved: slot.id == editingSlotID,
            onFocus: { field in onFocus?(slot, field) },
            onLog: { onLogSet(slot) },
            onEdit: editAction(for: slot),
            onDelete: deleteAction(for: slot)
          )
          .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
          // What `SessionView` scrolls to, on focus and after a log.
          .id(slot.id)
        }
      }

      addSetButton
    }
    .padding(.vertical, Tokens.Spacing.regular)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(alignment: .firstTextBaseline) {
        // The name is the way into this movement's load history. Placed here because "how have I
        // been doing on this" is a question asked while standing at the machine, and a chart
        // buried in a separate browse tab does not get looked at mid-set.
        Button {
          onShowHistory?()
        } label: {
          HStack(spacing: Tokens.Spacing.tight) {
            Text(state.exerciseName)
              .font(Tokens.Text.label.weight(.semibold))
              .foregroundStyle(Tokens.Color.textPrimary)
            if onShowHistory != nil {
              Image(systemName: "chart.xyaxis.line")
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.accent)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onShowHistory == nil)
        .accessibilityLabel(
          onShowHistory == nil
            ? state.exerciseName : "\(state.exerciseName). Show load history."
        )
        Spacer()
        Text(progressDescription)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .monospacedDigit()
          // The count rolls to its new value; under Reduce Motion it simply changes.
          .contentTransition(.numericText(value: Double(state.loggedCount)))
          .animation(Tokens.Motion.quick(reduceMotion), value: state.loggedCount)
      }
      if onSelectMachine != nil || onChooseRest != nil {
        chipRow
      }
      if let note = state.priorNote {
        // Stated as a caveat about where the numbers came from, in words, once.
        Label(note, systemImage: "arrow.triangle.branch")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.caveat)
          .accessibilityLabel("Suggested loads came from another machine.")
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
    // Attached to the header rather than to the chip, so the sheet's anchor survives the chip row
    // switching layout (see `chipRow`) while the sheet is up.
    .sheet(isPresented: $isChoosingCustomRest) {
      RestCustomSheet(
        initial: restChoice,
        onConfirm: { duration in
          onChooseRest?(duration)
          isChoosingCustomRest = false
        },
        onCancel: { isChoosingCustomRest = false }
      )
    }
  }

  /// The machine chip and the rest chip, side by side when they fit and stacked when they do not —
  /// a long machine name or a large Dynamic Type size would otherwise truncate one of them.
  private var chipRow: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Tokens.Spacing.loose) { chips }
      VStack(alignment: .leading, spacing: 0) { chips }
    }
  }

  @ViewBuilder private var chips: some View {
    if let onSelectMachine {
      machineChip(action: onSelectMachine)
    }
    if let onChooseRest {
      restChip(onChoose: onChooseRest)
    }
  }

  /// Where per-machine tracking is actually reached.
  ///
  /// It sits in the header of the exercise being performed, one tap from the set rows, because the
  /// only moment a lifter knows which machine they are on is while standing at it. Anywhere else —
  /// a setup screen, a gym profile — and the field stays empty forever, which is what happened in
  /// the ancestor app: the schema tracked machines, no screen ever set one, and every set was
  /// logged against nothing.
  ///
  /// Unset reads as an invitation, never a warning. A set with no machine is a real set.
  private func machineChip(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: Tokens.Spacing.hairline) {
        Image(systemName: state.machineID == nil ? "dumbbell" : "dumbbell.fill")
        Text(state.machineName ?? "Choose machine")
        if let increment = state.machineIncrementKg {
          // Shown because it is the constraint on what a suggestion may propose.
          Text("· \(WeightFormatter(unit: unit).load(kilograms: increment)) steps")
        }
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(
        state.machineID == nil ? Tokens.Color.textSecondary : Tokens.Color.accent
      )
      .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      state.machineName.map { "Machine: \($0). Change." } ?? "No machine recorded. Choose one."
    )
  }

  /// Where an exercise's rest is chosen. It sits beside the machine chip for the same reason the
  /// machine chip sits here: the lifter decides how long to rest while standing at the exercise,
  /// not on a settings screen.
  ///
  /// There is no default. With no choice the chip reads "Rest · Off" and no preset carries a
  /// check mark. The presets are plain buttons marking the current one, rather than a `Picker`
  /// bound to `restChoice`: a picker needs a tag for the `nil` selection, and what it does with
  /// none is not documented, so "nothing selected" would rest on behaviour nobody here can check.
  /// Here a preset is marked only when `restChoice == preset`, which is `false` for `nil`.
  private func restChip(onChoose: @escaping (Duration?) -> Void) -> some View {
    Menu {
      ForEach(RestPlan.presets, id: \.self) { preset in
        Button {
          onChoose(preset)
        } label: {
          if restChoice == preset {
            Label(preset.clockString, systemImage: "checkmark")
          } else {
            Text(preset.clockString)
          }
        }
        .accessibilityAddTraits(restChoice == preset ? .isSelected : [])
      }
      Button("Custom…") { isChoosingCustomRest = true }
      if restChoice != nil {
        Button("Off") { onChoose(nil) }
        if let onStartRest {
          Divider()
          Button("Start rest now", action: onStartRest)
        }
      }
    } label: {
      Label("Rest · \(RestPlan.label(for: restChoice))", systemImage: "timer")
        .font(Tokens.Text.caption)
        .foregroundStyle(
          restChoice == nil ? Tokens.Color.textSecondary : Tokens.Color.accent
        )
        .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("Rest after each set, \(restChoice?.clockString ?? "off")")
  }

  private var addSetButton: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Button {
        state.appendSlot()
      } label: {
        Label("Add set", systemImage: "plus.circle")
          .font(Tokens.Text.label)
          .frame(minHeight: Tokens.minimumTapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)

      Button {
        state.appendSlot(isWarmup: true)
      } label: {
        Label("Warm-up", systemImage: "plus.circle.dashed")
          .font(Tokens.Text.label)
          .frame(minHeight: Tokens.minimumTapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.textSecondary)
    }
    .padding(.horizontal, Tokens.Spacing.regular)
  }

  // Helpers rather than inline `map`s, to keep the row's initialiser cheap to type-check.
  private func editAction(for slot: SetSlot) -> (() -> Void)? {
    onEdit.map { edit in { edit(slot) } }
  }

  private func deleteAction(for slot: SetSlot) -> (() -> Void)? {
    onDelete.map { delete in { delete(slot) } }
  }

  /// A logged row is compact whatever else is true; otherwise the active set leads.
  private func emphasis(of slot: SetSlot) -> SetRowEmphasis {
    if slot.isLogged { return .logged }
    return slot.id == activeSlotID ? .active : .upcoming
  }

  /// Warm-ups do not consume a working-set number, so the badge on row three still reads "3"
  /// when a warm-up sits above it.
  private func ordinal(of slot: SetSlot) -> Int {
    guard let index = state.slots.firstIndex(of: slot) else { return 0 }
    return state.slots[..<index].count { !$0.isWarmup }
  }

  private var progressDescription: String {
    let working = state.slots.count { !$0.isWarmup }
    return "\(state.loggedCount) of \(working) logged"
  }
}

/// Asks for a rest length the presets do not cover, on minutes and seconds wheels.
///
/// It opens at the exercise's current rest, and at 0:00 when there is none. 0:00 is out of range on
/// purpose: with no rest chosen there is no honest number to start from, so Set stays disabled
/// until the lifter turns a wheel to a valid time. A time outside `RestPlan.allowedRange` is
/// refused, by the same `RestPlan.validated` the coordinator applies, and never clamped into range
/// — a typo must not become a different rest.
private struct RestCustomSheet: View {
  private static let maxMinutes = Int(RestPlan.allowedRange.upperBound.seconds) / 60

  private let onConfirm: (Duration) -> Void
  private let onCancel: () -> Void

  @State private var minutes: Int
  @State private var seconds: Int

  init(
    initial: Duration?,
    onConfirm: @escaping (Duration) -> Void,
    onCancel: @escaping () -> Void
  ) {
    let start = initial.flatMap { RestPlan.validated($0) }.map { Int($0.seconds.rounded()) } ?? 0
    self._minutes = State(initialValue: start / 60)
    self._seconds = State(initialValue: start % 60)
    self.onConfirm = onConfirm
    self.onCancel = onCancel
  }

  private var validChoice: Duration? {
    RestPlan.validated(.seconds(minutes * 60 + seconds))
  }

  /// Always shown, so a disabled Set never leaves the lifter guessing why.
  private var rangeNote: String {
    let range = RestPlan.allowedRange
    return "Between \(range.lowerBound.clockString) and \(range.upperBound.clockString)."
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: Tokens.Spacing.regular) {
        HStack(spacing: 0) {
          wheel("Minutes", suffix: "min", range: 0...Self.maxMinutes, selection: $minutes)
          wheel("Seconds", suffix: "sec", range: 0...59, selection: $seconds)
        }
        Text(rangeNote)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .navigationTitle("Custom rest")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Set", action: confirm)
            .disabled(validChoice == nil)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func wheel(
    _ title: String, suffix: String, range: ClosedRange<Int>, selection: Binding<Int>
  ) -> some View {
    Picker(title, selection: selection) {
      ForEach(range, id: \.self) { value in
        Text("\(value) \(suffix)").tag(value)
      }
    }
    .labelsHidden()
    // The wheel style does not exist on macOS, where the host test suite builds this target.
    #if os(iOS)
      .pickerStyle(.wheel)
    #endif
    .frame(maxWidth: .infinity)
  }

  private func confirm() {
    guard let validChoice else { return }
    onConfirm(validChoice)
  }
}

#if DEBUG
  #Preview("Exercise section") {
    struct Harness: View {
      @State private var state: ExerciseLogState
      @State private var rest: Duration?

      init() {
        let exercise = ExerciseID()
        let machine = MachineID()
        let key = ProgressionKey(exerciseID: exercise, machineID: machine)
        let records = [
          PriorSetRecord(weightKg: 100, reps: 10, completedAt: .distantPast),
          PriorSetRecord(weightKg: 105, reps: 8, completedAt: .distantPast),
        ]
        let snapshot = PriorPerformanceSnapshot(
          entries: [
            key: PriorPerformance(key: key, lastSets: records, heaviestSet: records.last)
          ],
          capturedAt: .distantPast
        )
        _state = State(
          initialValue: .build(
            exerciseID: exercise,
            machineID: machine,
            exerciseName: "Leg Press — Hammer Strength",
            snapshot: snapshot
          )
        )
      }

      var body: some View {
        ScrollView {
          ExerciseSectionView(
            state: $state,
            unit: .kilograms,
            onLogSet: { slot in
              // Stands in for the store write.
              state.markLogged(slotID: slot.id, setID: SetID())
            },
            restChoice: rest,
            onChooseRest: { rest = $0 },
            onStartRest: {},
            activeSlotID: state.nextUnloggedSlotID
          )
        }
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
