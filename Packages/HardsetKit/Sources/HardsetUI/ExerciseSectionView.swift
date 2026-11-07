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

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// - Parameter onSelectMachine: Opens the machine picker. Passing `nil` hides the chip, which is
  ///   correct when no gym is known — an affordance that opens an empty list is worse than none.
  /// - Parameter onShowHistory: Opens this movement's load history. `nil` leaves the name inert.
  public init(
    state: Binding<ExerciseLogState>,
    unit: WeightUnit,
    onLogSet: @escaping (SetSlot) -> Void,
    onSelectMachine: (() -> Void)? = nil,
    onShowHistory: (() -> Void)? = nil
  ) {
    self._state = state
    self.unit = unit
    self.onLogSet = onLogSet
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      header

      VStack(spacing: Tokens.Spacing.tight) {
        // Labelled once, above the columns, rather than inside every row: "Last time" and "kg"
        // repeated down a five-set card is noise the eye learns to skip. At accessibility sizes
        // the rows stack and label themselves, so there are no columns to head.
        if !dynamicTypeSize.isAccessibilitySize {
          columnHeader
        }

        ForEach($state.slots) { $slot in
          SetRowView(
            draft: $slot.draft,
            ordinal: ordinal(of: slot),
            isWarmup: slot.isWarmup,
            isLogged: slot.isLogged,
            isNext: slot.id == state.nextUnloggedSlotID,
            showsInlineLabels: false,
            unit: unit,
            previous: state.suggestion(forSetIndex: ordinal(of: slot)),
            // The borrowed-history note is shown once in the header, not repeated on every
            // row — an honest caveat that appears five times reads as noise and gets ignored.
            priorNote: nil,
            onLog: { onLogSet(slot) }
          )
        }
      }

      addSetButtons
    }
    .padding(Tokens.Spacing.regular)
    .hardsetCard()
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        // The name is the way into this movement's load history. Placed here because "how have I
        // been doing on this" is a question asked while standing at the machine, and a chart
        // buried in a separate browse tab does not get looked at mid-set.
        Button {
          onShowHistory?()
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
            Text(state.exerciseName)
              .font(Tokens.Text.title)
              .foregroundStyle(Tokens.Color.textPrimary)
              .multilineTextAlignment(.leading)
            if onShowHistory != nil {
              Image(systemName: "chart.xyaxis.line")
                .font(Tokens.Text.caption.weight(.semibold))
                .foregroundStyle(Tokens.Color.accent)
            }
          }
          .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onShowHistory == nil)
        .accessibilityLabel(
          onShowHistory == nil
            ? state.exerciseName : "\(state.exerciseName). Show load history."
        )
        .accessibilityAddTraits(.isHeader)

        Spacer(minLength: Tokens.Spacing.snug)

        progress
      }
      if let onSelectMachine {
        machineChip(action: onSelectMachine)
      }
      if let note = state.priorNote {
        CertaintyBadge(
          level: .low,
          methodology: "Suggested loads are borrowed from another machine (\(note)). Movement mechanics and leverage differ between equipment.",
          citation: "Epistemic honesty: equipment cannot be merged"
        )
      }
    }
  }

  /// How far through the working sets the lifter is: a pip per set, filled when logged, and the
  /// count in figures beside it. The pips are hidden from VoiceOver, which reads the sentence.
  private var progress: some View {
    let working = state.workingSetCount
    let logged = loggedWorkingSets
    return HStack(spacing: Tokens.Spacing.snug) {
      // Beyond eight sets the pips stop being countable at a glance, so only the figure remains.
      if working > 0 && working <= 8 {
        HStack(spacing: Tokens.Spacing.hairline) {
          ForEach(0..<working, id: \.self) { index in
            Capsule()
              .fill(index < logged ? Tokens.Color.success : Tokens.Color.surfaceRaised)
              .overlay(
                Capsule().strokeBorder(
                  index < logged ? Tokens.Color.success : Tokens.Color.controlBorder,
                  lineWidth: Tokens.Stroke.hairline
                )
              )
              .frame(width: 10, height: 6)
          }
        }
        .accessibilityHidden(true)
      }
      Text("\(logged)/\(working)")
        .font(Tokens.Text.figure)
        .foregroundStyle(logged == working && working > 0 ? Tokens.Color.success : Tokens.Color.textSecondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(logged) of \(working) working sets logged")
  }

  /// Working sets only. Counting a logged warm-up here made "1 of 3 logged" appear before a single
  /// working set had been done.
  private var loggedWorkingSets: Int {
    state.slots.count { !$0.isWarmup && $0.isLogged }
  }

  /// Labels for the set rows' columns, using the same widths so each label sits over its values.
  private var columnHeader: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Text("Set")
        .frame(width: SetRowMetrics.ordinalWidth)
      Text("Last time")
        // A label, not a value, so it may tighten to share the narrow column's width.
        .minimumScaleFactor(0.8)
        .frame(width: SetRowMetrics.previousWidth, alignment: .leading)
      Text(unit.abbreviation)
        .frame(minWidth: SetRowMetrics.weightMinWidth, maxWidth: .infinity)
      Text("Reps")
        .frame(minWidth: SetRowMetrics.repsMinWidth, maxWidth: .infinity)
      Color.clear
        .frame(width: Tokens.loggerTapTarget, height: 1)
    }
    .font(Tokens.Text.caption.weight(.medium))
    .foregroundStyle(Tokens.Color.textSecondary)
    .lineLimit(1)
    // The same inset as each row, so every label sits over its column.
    .padding(.horizontal, Tokens.Spacing.tight)
    // The rows carry the same information in their spoken labels; reading the header as well
    // would only add a stop before every set.
    .accessibilityHidden(true)
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
      HStack(spacing: Tokens.Spacing.snug) {
        Image(systemName: state.machineID == nil ? "plus" : "dumbbell.fill")
          .font(Tokens.Text.caption.weight(.semibold))
        Text(state.machineName ?? "Choose machine")
          .font(Tokens.Text.caption.weight(.semibold))
          .lineLimit(1)
        if let increment = state.machineIncrementKg {
          // Shown because it is the constraint on what a suggestion may propose.
          Text("\(Self.format(unit.fromKilograms(increment))) \(unit.abbreviation) steps")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .lineLimit(1)
        }
        Image(systemName: "chevron.down")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .foregroundStyle(state.machineID == nil ? Tokens.Color.accent : Tokens.Color.textPrimary)
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .background(
        state.machineID == nil ? Tokens.Color.accentSurface : Tokens.Color.surfaceRaised,
        in: Capsule()
      )
      .overlay(
        Capsule().strokeBorder(
          state.machineID == nil ? Tokens.Color.accent : Tokens.Color.controlBorder,
          lineWidth: Tokens.Stroke.hairline
        )
      )
      .frame(minHeight: Tokens.minimumTapTarget)
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

  private var addSetButtons: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Button {
        state.appendSlot()
      } label: {
        Label("Add set", systemImage: "plus")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, fullWidth: true))

      Button {
        state.appendSlot(isWarmup: true)
      } label: {
        Label("Warm-up", systemImage: "plus")
      }
      .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
      .accessibilityLabel("Add warm-up set")
    }
  }

  /// Warm-ups do not consume a working-set number, so the badge on row three still reads "3"
  /// when a warm-up sits above it.
  private func ordinal(of slot: SetSlot) -> Int {
    guard let index = state.slots.firstIndex(of: slot) else { return 0 }
    return state.slots[..<index].count { !$0.isWarmup }
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
            exerciseName: "Leg Press",
            machineName: "Hammer Strength",
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
            onSelectMachine: {},
            onShowHistory: {}
          )
          .padding()
        }
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
