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
  private let onEditNote: (() -> Void)?
  /// The letter this movement carries inside its superset, or `nil` when it stands alone.
  /// Derived by the caller through `SupersetGrouping`, which is the layer that can see the whole
  /// session — this view only ever holds one movement.
  private let supersetLetter: String?
  /// Pairs this movement with the one after it. `nil` hides the item, which is correct for the
  /// last movement in the session: there is nothing to pair with.
  private let onJoinSuperset: (() -> Void)?
  /// Takes it back out. `nil` hides the item.
  private let onLeaveSuperset: (() -> Void)?

  /// - Parameter onSelectMachine: Opens the machine picker. Passing `nil` hides the chip, which is
  ///   correct when no gym is known — an affordance that opens an empty list is worse than none.
  /// - Parameter onShowHistory: Opens this movement's load history. `nil` leaves the name inert.
  /// - Parameter onEditNote: Opens the note editor for this movement. `nil` hides the menu item.
  public init(
    state: Binding<ExerciseLogState>,
    unit: WeightUnit,
    tracksRPE: Bool = false,
    onLogSet: @escaping (SetSlot) -> Void,
    onUnlogSet: ((SetSlot) -> Void)? = nil,
    onRemoveSlot: ((SetSlot) -> Void)? = nil,
    onRemoveExercise: (() -> Void)? = nil,
    onSelectMachine: (() -> Void)? = nil,
    onShowHistory: (() -> Void)? = nil,
    onEditNote: (() -> Void)? = nil,
    supersetLetter: String? = nil,
    onJoinSuperset: (() -> Void)? = nil,
    onLeaveSuperset: (() -> Void)? = nil
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
    self.onEditNote = onEditNote
    self.supersetLetter = supersetLetter
    self.onJoinSuperset = onJoinSuperset
    self.onLeaveSuperset = onLeaveSuperset
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      header

      VStack(spacing: Tokens.Spacing.hairline) {
        ForEach($state.slots) { $slot in
          SetRowView(
            draft: $slot.draft,
            ordinal: ordinal(of: slot),
            kind: slot.kind,
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
            // Resolved here rather than in the row, because this is the layer that knows the
            // movement's modality and whether the machine's own step has been recorded.
            loadStep: PlateMath.step(
              modality: state.modality,
              machineIncrementKg: state.machineIncrementKg,
              unit: unit
            ),
            onLog: { onLogSet(slot) },
            onUnlog: onUnlogSet.map { handler in { handler(slot) } },
            // Only offered when there is more than one row: removing the last one would leave a
            // movement with nothing to log into and no obvious way back.
            onRemove: state.slots.count > 1
              ? onRemoveSlot.map { handler in { handler(slot) } }
              : nil
          )
          .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
          // A drop is inset so a chain reads as one block rather than as separate sets. The
          // badge already says so; this makes it legible without reading anything.
          .padding(.leading, slot.isDropSet ? Tokens.Spacing.regular : 0)
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
        if let onJoinSuperset {
          Button(action: onJoinSuperset) {
            Label(
              supersetLetter == nil ? "Superset with next movement" : "Add next movement to this superset",
              systemImage: "arrow.triangle.2.circlepath"
            )
          }
        }
        if let onLeaveSuperset, supersetLetter != nil {
          Button(action: onLeaveSuperset) {
            Label("Take out of superset", systemImage: "arrow.uturn.backward")
          }
        }
        if let onEditNote {
          Button(action: onEditNote) {
            Label(
              state.notes.isEmpty ? "Add a note" : "Edit note",
              systemImage: state.notes.isEmpty ? "square.and.pencil" : "pencil"
            )
          }
        }
        if let onRemoveExercise {
          Button(role: .destructive, action: onRemoveExercise) {
            Label(
              state.loggedCount == 0
                ? "Remove this movement"
                // Rows, not sets, deliberately: this warns about what is destroyed, and a drop
                // that is about to be deleted is a record the lifter loses whether or not the
                // week counts it as a set.
                : "Remove this movement and its ^[\(state.loggedCount) logged row](inflect: true)",
              systemImage: "trash"
            )
          }
        }
      }
  }

  @ViewBuilder private var headerContent: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      if let supersetLetter {
        // Stated on the movement rather than drawn as a container around the pair. A card that
        // wraps two movements is a layout the logger does not otherwise have, and the thing the
        // lifter needs to know here is small: this is part of a superset, and it is the Nth part.
        // Where the rest goes is the behaviour, and the behaviour is in `SupersetRest`.
        Label("Superset \(supersetLetter)", systemImage: "arrow.triangle.2.circlepath")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.accent)
          .accessibilityLabel("Superset, movement \(supersetLetter)")
          .accessibilityHint("Rest starts when the round is finished, not after this set.")
      }
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
      if !state.notes.isEmpty {
        // The lifter's own words, so they are shown plainly and in full rather than truncated --
        // "seat 4, pin 3" is useless if it reads "seat 4, pin…". Tapping opens the editor, because
        // a note on screen that cannot be corrected is worse than none.
        Button {
          onEditNote?()
        } label: {
          Label(state.notes, systemImage: "note.text")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onEditNote == nil)
        .accessibilityLabel("Your note: \(state.notes)")
        .accessibilityHint(onEditNote == nil ? "" : "Double tap to edit this note.")
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
  private var machineChipLabel: String {
    guard let name = state.machineName else { return "Choose a machine for this movement" }
    guard let increment = state.machineIncrementKg else { return "Machine, \(name)" }
    return "Machine, \(name), moves in \(Self.format(increment)) kilogram steps"
  }

  private func machineChip(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: Tokens.Spacing.hairline) {
        Image(systemName: state.machineID == nil ? "dumbbell" : "dumbbell.fill")
        Text(state.machineName ?? "Choose machine")
        if let increment = state.machineIncrementKg {
          // Shown because it is the constraint on what a suggestion may propose. Converted, not
          // labelled: printing "kg" beside a pounds figure is the defect `SetRowView` documents.
          Text("· \(Self.format(unit.displayValue(fromKilograms: increment))) \(unit.abbreviation) steps")
        }
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(
        state.machineID == nil ? Tokens.Color.textSecondary : Tokens.Color.accent
      )
      .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      // One element with a sentence, rather than three fragments and a spoken bullet.
      .accessibilityElement(children: .combine)
      .accessibilityLabel(machineChipLabel)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // One label, on the button.
    //
    // There were two: `machineChipLabel` inside the label view and a second one out here. The outer
    // wins, so the authored sentence -- the only place the stack step is ever spoken -- never
    // reached VoiceOver. The action belongs in a hint rather than being welded onto the label.
    .accessibilityHint(state.machineID == nil ? "Double tap to choose." : "Double tap to change.")
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

      // Offered only when there is a row to continue. A drop under nothing, or under a warm-up,
      // would be a row that continues something that is not a set.
      if state.canAppendDropSet {
        Button {
          state.appendDropSet()
        } label: {
          Label("Drop", systemImage: "arrow.down.circle")
            .font(Tokens.Text.label)
            .frame(minHeight: Tokens.minimumTapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.Color.textSecondary)
        .accessibilityLabel("Add a drop set")
        .accessibilityHint("Continues the last set at a lower load, with no rest.")
      }
    }
    .padding(.horizontal, Tokens.Spacing.regular)
  }

  /// Warm-ups do not consume a working-set number, so the badge on row three still reads "3"
  /// when a warm-up sits above it. Neither do drops — a drop shows an arrow rather than a number,
  /// and the value passed here is what its parent set is called.
  private func ordinal(of slot: SetSlot) -> Int {
    guard let index = state.slots.firstIndex(of: slot) else { return 0 }
    let preceding = state.slots[..<index].count { $0.countsAsWorkingSet }
    // A drop borrows the number of the set above it, which is already counted in `preceding`.
    return slot.countsAsWorkingSet ? preceding : max(preceding - 1, 0)
  }

  /// "2 of 4 logged", counting sets rather than rows.
  ///
  /// Both halves have to agree about what a set is. Counting logged *rows* against working *sets*
  /// made a movement with one drop report "4 of 3 logged" — a progress line that overshoots its
  /// own total the moment anyone uses the feature.
  private var progressDescription: String {
    let working = state.workingSetCount
    let logged = state.slots.count { $0.isLogged && $0.countsAsWorkingSet }
    return "\(logged) of \(working) logged"
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
