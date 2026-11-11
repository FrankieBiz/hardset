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
  private let onStartRest: ((Duration) -> Void)?
  private let onSelectMachine: (() -> Void)?
  private let onShowHistory: (() -> Void)?
  private let lastRest: Duration?
  private let editingSlotID: UUID?
  private let editingField: SetRowField?
  private let editingText: String?
  private let onBeginEditing: ((SetSlot, SetRowField) -> Void)?
  private let onUndoSet: ((SetSlot) -> Void)?
  private let onEditSet: ((SetSlot) -> Void)?
  private let onRemoveSet: ((SetSlot) -> Void)?
  private let onMoveUp: (() -> Void)?
  private let onMoveDown: (() -> Void)?
  private let onRemove: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityShowButtonShapes) private var showsButtonShapes

  /// Rest durations offered on every card, written the way the rest bar writes time.
  static let restChoices: [Duration] = [.seconds(60), .seconds(90), .seconds(120), .seconds(180)]

  /// - Parameter onSelectMachine: Opens the machine picker. Passing `nil` hides the chip, which is
  ///   correct when no gym is known — an affordance that opens an empty list is worse than none.
  /// - Parameter onShowHistory: Opens this movement's load history. `nil` leaves the name inert.
  /// - Parameter lastRest: The rest the lifter last chose for this movement. When known, it is
  ///   offered as one tap; it is never a default the app made up, so with none the card asks.
  /// - Parameter editingSlotID: The row the session's keypad is on, if it is on this card.
  /// - Parameter onMoveUp: Moves the card up the workout. `nil` for the first card, which shows
  ///   the action disabled rather than absent, so the menu keeps its shape.
  /// - Parameter onRemove: Removes the movement from the workout. The caller confirms first when
  ///   it has logged sets.
  public init(
    state: Binding<ExerciseLogState>,
    unit: WeightUnit,
    onLogSet: @escaping (SetSlot) -> Void,
    onStartRest: ((Duration) -> Void)? = nil,
    onSelectMachine: (() -> Void)? = nil,
    onShowHistory: (() -> Void)? = nil,
    lastRest: Duration? = nil,
    editingSlotID: UUID? = nil,
    editingField: SetRowField? = nil,
    editingText: String? = nil,
    onBeginEditing: ((SetSlot, SetRowField) -> Void)? = nil,
    onUndoSet: ((SetSlot) -> Void)? = nil,
    onEditSet: ((SetSlot) -> Void)? = nil,
    onRemoveSet: ((SetSlot) -> Void)? = nil,
    onMoveUp: (() -> Void)? = nil,
    onMoveDown: (() -> Void)? = nil,
    onRemove: (() -> Void)? = nil
  ) {
    self._state = state
    self.unit = unit
    self.onLogSet = onLogSet
    self.onStartRest = onStartRest
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
    self.lastRest = lastRest
    self.editingSlotID = editingSlotID
    self.editingField = editingField
    self.editingText = editingText
    self.onBeginEditing = onBeginEditing
    self.onUndoSet = onUndoSet
    self.onEditSet = onEditSet
    self.onRemoveSet = onRemoveSet
    self.onMoveUp = onMoveUp
    self.onMoveDown = onMoveDown
    self.onRemove = onRemove
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
          let isEditingRow = slot.id == editingSlotID
          SetRowView(
            draft: $slot.draft,
            ordinal: ordinal(of: slot),
            isWarmup: slot.isWarmup,
            isLogged: slot.isLogged,
            isNext: slot.id == state.nextUnloggedSlotID,
            showsInlineLabels: false,
            unit: unit,
            machineIncrementKg: state.machineIncrementKg,
            // By slot, so a warm-up row is never shown a working set as its "Last time".
            previous: state.previousSet(forSlotID: slot.id),
            // The borrowed-history note is shown once in the header, not repeated on every
            // row — an honest caveat that appears five times reads as noise and gets ignored.
            priorNote: nil,
            editingField: isEditingRow ? editingField : nil,
            editingText: isEditingRow ? editingText : nil,
            onLog: { onLogSet(slot) },
            onBeginEditing: onBeginEditing.map { begin in { field in begin(slot, field) } },
            onUndo: onUndoSet.map { undo in { undo(slot) } },
            onEdit: onEditSet.map { edit in { edit(slot) } },
            onRemove: onRemoveSet.map { remove in { remove(slot) } }
          )
          // Lets the session scroll a row clear of the keypad.
          .id(slot.id)
        }
      }

      // Directly under the rows, where the thumb is after the log tap: resting is the next thing
      // done after nearly every working set.
      if let onStartRest {
        restControl(start: onStartRest)
      }
      addSetButtons
    }
    .padding(Tokens.Spacing.regular)
    .hardsetCard()
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      // At accessibility sizes the name takes the full width and the progress and menu sit on
      // the line below; sharing one line, a name such as "Dumbbell" broke mid-word.
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          nameButton
          HStack(spacing: Tokens.Spacing.snug) {
            progress
            Spacer(minLength: Tokens.Spacing.snug)
            if hasMovementMenu {
              movementMenu
            }
          }
          .frame(minHeight: Tokens.minimumTapTarget)
        }
      } else {
        HStack(alignment: .top, spacing: Tokens.Spacing.snug) {
          nameButton

          Spacer(minLength: Tokens.Spacing.snug)

          HStack(spacing: Tokens.Spacing.snug) {
            progress
            if hasMovementMenu {
              movementMenu
            }
          }
          .frame(minHeight: Tokens.minimumTapTarget)
        }
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

  /// The name is the way into this movement's load history. Placed here because "how have I been
  /// doing on this" is a question asked while standing at the machine, and a chart buried in a
  /// separate browse tab does not get looked at mid-set.
  ///
  /// With Button Shapes on, the name is underlined: the small chart glyph alone did not say that
  /// the title can be tapped.
  private var nameButton: some View {
    let isLink = onShowHistory != nil
    return Button {
      onShowHistory?()
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text(state.exerciseName)
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.textPrimary)
          .underline(isLink && showsButtonShapes)
          .multilineTextAlignment(.leading)
        if isLink {
          Image(systemName: "chart.xyaxis.line")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.accent)
        }
      }
      .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(HardsetPressStyle())
    .disabled(!isLink)
    .accessibilityLabel(isLink ? "\(state.exerciseName). Show load history." : state.exerciseName)
    .accessibilityAddTraits(.isHeader)
  }

  private var hasMovementMenu: Bool {
    onMoveUp != nil || onMoveDown != nil || onRemove != nil
  }

  /// Order and removal: things done to the movement as a whole, rarely, so they sit in one menu
  /// in the card's corner rather than as buttons repeated on every card.
  private var movementMenu: some View {
    HeaderIconMenu(accessibilityLabel: "\(state.exerciseName) options") {
      Button {
        onMoveUp?()
      } label: {
        Label("Move up", systemImage: "arrow.up")
      }
      .disabled(onMoveUp == nil)
      Button {
        onMoveDown?()
      } label: {
        Label("Move down", systemImage: "arrow.down")
      }
      .disabled(onMoveDown == nil)
      if let onRemove {
        Divider()
        Button(role: .destructive, action: onRemove) {
          Label("Remove movement", systemImage: "trash")
        }
      }
    }
  }

  /// How far through the working sets the lifter is: a pip per set, filled when logged, and the
  /// count in figures beside it. The pips are hidden from VoiceOver, which reads the sentence.
  ///
  /// The count turns green only when the number of rows came from this movement's history. With
  /// no history the rows are whatever the lifter added, and "1/1" in green read as a target met.
  private var progress: some View {
    let working = state.workingSetCount
    let logged = loggedWorkingSets
    let hasHistory = state.suggestion(forSetIndex: 0) != nil
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
        .foregroundStyle(
          hasHistory && logged == working && working > 0
            ? Tokens.Color.success : Tokens.Color.textSecondary
        )
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
          // One line at ordinary sizes; at accessibility sizes the name wraps rather than
          // truncating to "Hamm…", because it is how the lifter recognises the machine.
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        if let increment = state.machineIncrementKg {
          // Shown because it is the constraint on what a suggestion may propose. Written with the
          // same figure as the step buttons and the fields, so 10 kg reads "22.05 lb steps" here
          // and "+22.05 lb" on the button below it, not 22 in one place and 22.05 in the other.
          Text("\(LoadFigure.text(unit.fromKilograms(increment))) \(unit.abbreviation) steps")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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
    .buttonStyle(HardsetPressStyle())
    // Begins with the words on the chip, so "Tap Choose machine" works for Voice Control, and
    // includes the load step the chip shows.
    .accessibilityLabel(machineChipLabel)
    .accessibilityInputLabels(
      state.machineName.map { [$0, "Change machine", "Machine"] } ?? ["Choose machine", "Machine"]
    )
  }

  private var machineChipLabel: String {
    guard let name = state.machineName else { return "Choose machine. No machine recorded." }
    guard let increment = state.machineIncrementKg else { return "\(name). Change machine." }
    let step = "\(LoadFigure.text(unit.fromKilograms(increment))) \(unit.abbreviation) steps"
    return "\(name), \(step). Change machine."
  }

  /// Starting a rest. Rest begins only from a duration the lifter chose: with one remembered for
  /// this movement it is a single tap, "Rest 1:30", with the other durations one tap further in
  /// the menu beside it; with none, the menu asks.
  ///
  /// 56 pt like every logger control, and no taller: the label once carried its own minimum height
  /// inside the style's padding and made rest the largest control on the card.
  @ViewBuilder private func restControl(start: @escaping (Duration) -> Void) -> some View {
    if let lastRest {
      HStack(spacing: Tokens.Spacing.snug) {
        Button {
          start(lastRest)
        } label: {
          Label("Rest \(lastRest.clockString)", systemImage: "timer")
            .monospacedDigit()
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
        .accessibilityLabel("Start a rest of \(Self.spoken(lastRest))")

        Menu {
          restMenuItems(start: start)
        } label: {
          Image(systemName: "chevron.down")
            .frame(minWidth: Tokens.minimumTapTarget)
        }
        .buttonStyle(HardsetButtonStyle(.secondary, size: .logger, fullWidth: false))
        .accessibilityLabel("Other rest durations")
      }
    } else {
      Menu {
        restMenuItems(start: start)
      } label: {
        Label("Start rest", systemImage: "timer")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
    }
  }

  @ViewBuilder private func restMenuItems(start: @escaping (Duration) -> Void) -> some View {
    ForEach(Self.restChoices, id: \.self) { duration in
      Button {
        start(duration)
      } label: {
        if duration == lastRest {
          Label(duration.clockString, systemImage: "checkmark")
        } else {
          Text(duration.clockString)
        }
      }
      .accessibilityLabel(Self.spoken(duration))
    }
  }

  /// "1 minute, 30 seconds": a clock figure such as "1:30" is read aloud as a time of day.
  static func spoken(_ duration: Duration) -> String {
    duration.formatted(.units(allowed: [.minutes, .seconds], width: .wide))
  }

  private var addSetButtons: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Button {
        state.appendSlot()
      } label: {
        Label("Add set", systemImage: "plus")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .logger, fullWidth: true))

      Button {
        state.appendSlot(isWarmup: true)
      } label: {
        Label("Warm-up", systemImage: "plus")
      }
      .buttonStyle(HardsetButtonStyle(.quiet, size: .logger, fullWidth: false))
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
            onStartRest: { _ in },
            onSelectMachine: {},
            onShowHistory: {},
            lastRest: .seconds(90),
            onMoveDown: {},
            onRemove: {}
          )
          .padding()
        }
        .background(Tokens.Color.background)
      }
    }
    return Harness()
  }
#endif
