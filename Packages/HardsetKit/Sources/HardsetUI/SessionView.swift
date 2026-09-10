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
public struct SessionView: View {
  @Binding private var exercises: [ExerciseLogState]
  private let unit: WeightUnit
  private let tracksRPE: Bool
  private let restState: RestTimerState
  private let restMetadata: RestMetadata?
  /// The full rest length, so the bar can draw a fraction rather than guess one.
  private let restTotal: Duration?
  private let errorMessage: String?
  private let records: [PersonalRecord]
  private let onLogSet: (UUID, SetSlot) -> Void
  private let onUnlogSet: ((UUID, SetSlot) -> Void)?
  private let onRemoveSlot: ((UUID, SetSlot) -> Void)?
  private let onRemoveExercise: ((UUID) -> Void)?
  private let onAdjustRest: (Duration) -> Void
  private let onPauseResumeRest: () -> Void
  private let onSkipRest: () -> Void
  private let onAddExercise: (() -> Void)?
  private let onSelectMachine: ((UUID) -> Void)?
  private let onShowHistory: ((UUID) -> Void)?
  private let onEditNote: ((UUID) -> Void)?
  /// Pairs a movement with the one after it so rest waits for the round. `nil` hides the action
  /// everywhere, which is what a caller with no coordinator (a preview) wants.
  private let onJoinSuperset: ((UUID) -> Void)?
  private let onLeaveSuperset: ((UUID) -> Void)?
  private let onFinish: () -> Void
  /// Whether the finish confirmation is up.
  @State private var confirmsFinish = false

  public init(
    exercises: Binding<[ExerciseLogState]>,
    unit: WeightUnit,
    tracksRPE: Bool = false,
    restState: RestTimerState = .idle,
    restMetadata: RestMetadata? = nil,
    restTotal: Duration? = nil,
    errorMessage: String? = nil,
    records: [PersonalRecord] = [],
    onLogSet: @escaping (UUID, SetSlot) -> Void,
    onUnlogSet: ((UUID, SetSlot) -> Void)? = nil,
    onRemoveSlot: ((UUID, SetSlot) -> Void)? = nil,
    onRemoveExercise: ((UUID) -> Void)? = nil,
    onAdjustRest: @escaping (Duration) -> Void = { _ in },
    onPauseResumeRest: @escaping () -> Void = {},
    onSkipRest: @escaping () -> Void = {},
    onAddExercise: (() -> Void)? = nil,
    onSelectMachine: ((UUID) -> Void)? = nil,
    onShowHistory: ((UUID) -> Void)? = nil,
    onEditNote: ((UUID) -> Void)? = nil,
    onJoinSuperset: ((UUID) -> Void)? = nil,
    onLeaveSuperset: ((UUID) -> Void)? = nil,
    onFinish: @escaping () -> Void = {}
  ) {
    self._exercises = exercises
    self.unit = unit
    self.tracksRPE = tracksRPE
    self.restState = restState
    self.restMetadata = restMetadata
    self.restTotal = restTotal
    self.errorMessage = errorMessage
    self.records = records
    self.onLogSet = onLogSet
    self.onUnlogSet = onUnlogSet
    self.onRemoveSlot = onRemoveSlot
    self.onRemoveExercise = onRemoveExercise
    self.onAdjustRest = onAdjustRest
    self.onPauseResumeRest = onPauseResumeRest
    self.onSkipRest = onSkipRest
    self.onAddExercise = onAddExercise
    self.onSelectMachine = onSelectMachine
    self.onShowHistory = onShowHistory
    self.onEditNote = onEditNote
    self.onJoinSuperset = onJoinSuperset
    self.onLeaveSuperset = onLeaveSuperset
    self.onFinish = onFinish
  }

  /// Whether a movement has one after it to be paired with.
  private func hasNext(_ exercise: ExerciseLogState) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == exercise.id }) else { return false }
    return exercises.indices.contains(index + 1)
  }

  public var body: some View {
    ScrollView {
      LazyVStack(spacing: Tokens.Spacing.regular) {
        if !records.isEmpty {
          // Each record names what it beat, so the claim is checkable rather than a bare "PR!".
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            ForEach(records) { record in
              Label {
                VStack(alignment: .leading, spacing: 0) {
                  Text(record.kind.label)
                    .font(Tokens.Text.label.weight(.semibold))
                  Text(Self.describe(record, in: unit))
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
          .accessibilityElement(children: .combine)
        }

        ForEach($exercises) { $exercise in
          ExerciseSectionView(
            state: $exercise,
            unit: unit,
            tracksRPE: tracksRPE,
            onLogSet: { slot in onLogSet(exercise.id, slot) },
            onUnlogSet: onUnlogSet.map { handler in
              { slot in handler(exercise.id, slot) }
            },
            onRemoveSlot: onRemoveSlot.map { handler in
              { slot in handler(exercise.id, slot) }
            },
            onRemoveExercise: onRemoveExercise.map { handler in
              { handler(exercise.id) }
            },
            onSelectMachine: onSelectMachine.map { select in
              { select(exercise.id) }
            },
            onShowHistory: onShowHistory.map { show in
              { show(exercise.id) }
            },
            onEditNote: onEditNote.map { edit in
              { edit(exercise.id) }
            },
            // Derived here rather than stored, because this is the only layer that can see the
            // whole session. A section holds one movement and cannot know it has a partner.
            supersetLetter: SupersetGrouping.letter(for: exercise, in: exercises),
            // Hidden on the last movement: there is nothing after it to pair with, and an action
            // that silently does nothing is the dead-button pattern this app keeps finding.
            onJoinSuperset: hasNext(exercise)
              ? onJoinSuperset.map { join in { join(exercise.id) } }
              : nil,
            onLeaveSuperset: onLeaveSuperset.map { leave in { leave(exercise.id) } }
          )
          .background(Tokens.Color.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
          // `ground -> surface` is the subtlest step in the palette, so a card sitting straight on
          // `ground` takes a hairline. Without it this card had no edge at all, and the set rows
          // inside it -- solid `surface` -- read as lighter than the container holding them.
          .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
              .strokeBorder(Tokens.Color.hairline, lineWidth: 1)
          }
        }

        // Above the button it describes. Guidance that renders *below* its own control is read
        // after the decision it was meant to inform.
        if exercises.isEmpty {
          ContentUnavailableView {
            Label("Nothing added yet", systemImage: "dumbbell")
          } description: {
            Text("Add a movement to start logging sets.")
          }
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
        }

        summary
      }
      // One gutter for the whole scroll. Cards were inset `snug` while every control beside them
      // used `regular`, so every card edge sat 4 pt outside every button edge down the screen.
      .padding(Tokens.Spacing.regular)
    }
    .background(Tokens.Color.ground)
    // Pinned rather than scrolled: as the first child of the stack, a failed write on movement
    // twelve reported itself thousands of points above the row that was tapped. Reserves nothing
    // while there is no message, so it composes with the rest bar's inset below.
    .safeAreaInset(edge: .top) {
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.certainty(.low))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Tokens.Spacing.regular)
          .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
          .padding(.horizontal, Tokens.Spacing.regular)
      }
    }
    // A record is stated, not celebrated -- but it is worth feeling, because the lifter is looking
    // at the bar and not at the screen. Keyed on the records themselves, not their count: two
    // heaviest-load records in a row leave the count at one, and the second announcement was
    // silent. A record has to beat the last by a real margin, so consecutive values cannot be
    // equal; the predicate suppresses only the transition back to nothing.
    .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: records) { _, new in
      !new.isEmpty
    }
    .safeAreaInset(edge: .bottom) {
      RestBarView(
        state: restState,
        metadata: restMetadata,
        total: restTotal,
        onAdjust: onAdjustRest,
        onPauseResume: onPauseResumeRest,
        onSkip: onSkipRest
      )
    }
  }

  /// Spells out the comparison. An estimated-1RM record says it is an estimate, because
  /// guideline 1.4.1 is about not presenting an estimate as a measurement.
  ///
  /// Takes the unit rather than assuming one. Records are the only sentences on this screen the
  /// lifter is meant to feel, and they were printed in kilograms unconditionally -- so a lifter
  /// working in pounds, who had just pressed 135 lb, was congratulated on "61 kg, up from 59 kg".
  /// Every load beside it on the same screen was already in pounds.
  static func describe(_ record: PersonalRecord, in unit: WeightUnit) -> String {
    let load = Self.trim(unit.displayValue(fromKilograms: record.weightKg))
    let suffix = unit.abbreviation
    switch record.kind {
    case .heaviestLoad:
      if let previous = record.previousWeightKg {
        let before = Self.trim(unit.displayValue(fromKilograms: previous))
        return "\(load) \(suffix), up from \(before) \(suffix)"
      }
      return "\(load) \(suffix)"
    case .repsAtLoad:
      if let previousReps = record.previousReps {
        return "\(record.reps) reps at \(load) \(suffix), up from \(previousReps)"
      }
      return "\(record.reps) reps at \(load) \(suffix)"
    case .estimatedOneRepMax:
      if let previous = record.previousWeightKg {
        let before = Self.trim(unit.displayValue(fromKilograms: previous))
        return "estimated, up from about \(before) \(suffix)"
      }
      return "estimated"
    }
  }

  static func trim(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }

  private var summary: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      Text(volumeDescription)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .monospacedDigit()
      Button { confirmsFinish = true } label: {
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
      // Asked, because finishing cannot be undone -- `SessionTimeline` refuses to re-open a closed
      // session -- and this control is a same-size, same-colour, same-weight rectangle sitting one
      // gap below "Add movement". Reaching for one and hitting the other ended the workout with no
      // warning and no way back. The message states what is kept and what is dropped rather than
      // asking the lifter to guess which.
      .confirmationDialog(
        finishPrompt,
        isPresented: $confirmsFinish,
        titleVisibility: .visible
      ) {
        Button("Finish workout") { onFinish() }
        Button("Keep going", role: .cancel) {}
      } message: {
        Text(finishConsequence)
      }
    }
    .padding(.top, Tokens.Spacing.snug)
  }

  /// Rows the lifter has opened but not logged. Counted, not implied: "some rows" is the kind of
  /// vagueness that makes a confirmation worthless.
  private var openRowCount: Int {
    exercises.reduce(0) { $0 + $1.slots.count { slot in !slot.isLogged } }
  }

  private var finishPrompt: String {
    SessionVolume(exercises: exercises).isEmpty ? "Finish with nothing logged?" : "Finish this workout?"
  }

  /// What ending the workout actually does, in both directions.
  private var finishConsequence: String {
    let volume = SessionVolume(exercises: exercises)
    if volume.isEmpty {
      return "This saves a workout with no sets in it. You can delete it from History."
    }
    // Pluralised by hand. `^[...](inflect:)` is only interpreted inside a `LocalizedStringKey` --
    // an inline `Text("...")` literal -- and this is a `String` reaching `Text(String)`, which
    // renders the markup verbatim. `HistoryView.volumeText` carries the same note for the same
    // reason: it shipped on screen once as "^[1 set](inflect: true)".
    let kept = volume.workingSets == 1
      ? "1 set already saved."
      : "\(volume.workingSets) sets already saved."
    guard openRowCount > 0 else {
      return "\(kept) A finished workout cannot be reopened."
    }
    let dropped = openRowCount == 1
      ? "The one row you have not logged is discarded."
      : "The \(openRowCount) rows you have not logged are discarded."
    return "\(kept) \(dropped) A finished workout cannot be reopened."
  }

  /// Counted by `SessionVolume`, which is tested. The rules that matter — unlogged rows and
  /// warm-ups excluded — live there rather than here, so this screen cannot disagree with the
  /// history screen about what the session contained.
  private var volumeDescription: String {
    let volume = SessionVolume(exercises: exercises)
    guard !volume.isEmpty else { return "No sets logged yet" }
    var parts = [
      volume.workingSets == 1 ? "1 set" : "\(volume.workingSets) sets",
      volume.reps == 1 ? "1 rep" : "\(volume.reps) reps",
    ]
    if volume.volumeKg > 0 {
      parts.append("\(unit.tonnageText(fromKilograms: volume.volumeKg)) volume")
    }
    if volume.warmupSets > 0 {
      parts.append("\(volume.warmupSets) warm-up\(volume.warmupSets == 1 ? "" : "s")")
    }
    return parts.joined(separator: " · ")
  }
}

#if DEBUG
  #Preview("Live session") {
    struct Harness: View {
      @State private var exercises: [ExerciseLogState]

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
          }
        )
      }
    }
    return Harness()
  }
#endif
