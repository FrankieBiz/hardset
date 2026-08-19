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

  public init(
    state: Binding<ExerciseLogState>,
    unit: WeightUnit,
    onLogSet: @escaping (SetSlot) -> Void
  ) {
    self._state = state
    self.unit = unit
    self.onLogSet = onLogSet
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
            onLog: { onLogSet(slot) }
          )
          .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
      }

      addSetButton
    }
    .padding(.vertical, Tokens.Spacing.regular)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(alignment: .firstTextBaseline) {
        Text(state.exerciseName)
          .font(Tokens.Text.label.weight(.semibold))
        Spacer()
        Text(progressDescription)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .monospacedDigit()
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
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
