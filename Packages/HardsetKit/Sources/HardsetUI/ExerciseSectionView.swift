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
  private let tracksRPE: Bool
  private let onLogSet: (SetSlot) -> Void
  private let onUnlogSet: ((SetSlot) -> Void)?
  private let onRemoveSlot: ((SetSlot) -> Void)?
  private let onRemoveExercise: (() -> Void)?
  private let onSelectMachine: (() -> Void)?
  private let onShowHistory: (() -> Void)?

  /// - Parameter onSelectMachine: Opens the machine picker. Passing `nil` hides the chip, which is
  ///   correct when no gym is known — an affordance that opens an empty list is worse than none.
  /// - Parameter onShowHistory: Opens this movement's load history. `nil` leaves the name inert.
  public init(
    state: Binding<ExerciseLogState>,
    unit: WeightUnit,
    tracksRPE: Bool = false,
    onLogSet: @escaping (SetSlot) -> Void,
    onUnlogSet: ((SetSlot) -> Void)? = nil,
    onRemoveSlot: ((SetSlot) -> Void)? = nil,
    onRemoveExercise: (() -> Void)? = nil,
    onSelectMachine: (() -> Void)? = nil,
    onShowHistory: (() -> Void)? = nil
  ) {
    self._state = state
    self.unit = unit
    self.tracksRPE = tracksRPE
    self.onLogSet = onLogSet
    self.onUnlogSet = onUnlogSet
    self.onRemoveSlot = onRemoveSlot
    self.onRemoveExercise = onRemoveExercise
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      header

      VStack(spacing: Tokens.Spacing.hairline) {
        ForEach($state.slots) { $slot in
          SetRowView(
            draft: $slot.draft,
            ordinal: ordinal(of: slot),
            isWarmup: slot.isWarmup,
            isLogged: slot.isLogged,
            unit: unit,
            previous: state.suggestion(forSetIndex: ordinal(of: slot)),
            // The borrowed-history note is shown once in the header, not repeated on every
            // row — an honest caveat that appears five times reads as noise and gets ignored.
            priorNote: nil,
            // How heavy this set is against the lifter's own best on this movement, which is what
            // gives the commit its weight. `nil` when no weight is entered yet or there is no
            // history — both are genuinely unknown, and unknown must not feel like anything.
            loadFraction: slot.draft.weightKg.flatMap {
              LoadIntensity.fraction(weightKg: $0, heaviestKg: state.heaviestPriorKg)
            },
            isBodyweight: state.modality == .bodyweight,
            tracksRPE: tracksRPE,
            onLog: { onLogSet(slot) },
            onUnlog: onUnlogSet.map { handler in { handler(slot) } },
            // Only offered when there is more than one row: removing the last one would leave a
            // movement with nothing to log into and no obvious way back.
            onRemove: state.slots.count > 1
              ? onRemoveSlot.map { handler in { handler(slot) } }
              : nil
          )
          .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
      }

      addSetButton
    }
    .padding(.vertical, Tokens.Spacing.regular)
  }

  private var header: some View {
    headerContent
      // On the movement's own header rather than a set row, because this discards every set in it.
      // Long press, with the count stated, so it cannot be confused with removing one row.
      .contextMenu {
        if let onRemoveExercise {
          Button(role: .destructive, action: onRemoveExercise) {
            Label(
              state.loggedCount == 0
                ? "Remove this movement"
                : "Remove this movement and its ^[\(state.loggedCount) set](inflect: true)",
              systemImage: "trash"
            )
          }
        }
      }
  }

  @ViewBuilder private var headerContent: some View {
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
      }
      if let onSelectMachine {
        machineChip(action: onSelectMachine)
      }
      if let note = state.priorNote {
        // Stated as a caveat about where the numbers came from, in words, once.
        Label(note, systemImage: "arrow.triangle.branch")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
          .accessibilityLabel("Suggested loads came from another machine.")
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
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
          Text("· \(Self.format(increment)) kg steps")
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

  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
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

#if DEBUG
  #Preview("Exercise section") {
    struct Harness: View {
      @State private var state: ExerciseLogState

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
          ExerciseSectionView(state: $state, unit: .kilograms) { slot in
            // Stands in for the store write.
            state.markLogged(slotID: slot.id, setID: SetID())
          }
        }
        .background(Tokens.Color.ground)
      }
    }
    return Harness()
  }
#endif
