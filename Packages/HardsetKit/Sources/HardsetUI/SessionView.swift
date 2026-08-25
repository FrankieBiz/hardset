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
        if let errorMessage {
          // A failed write is stated, not swallowed. The row it belongs to is still unlogged,
          // so the user can retry rather than discovering the gap days later.
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.certainty(.low))
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
                  Text(Self.describe(record))
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
      // Room for the rest bar so the last row is never trapped underneath it.
      .safeAreaPadding(.bottom, restState == .idle ? 0 : 72)
    }
    .background(Tokens.Color.ground)
    // A record is stated, not celebrated -- but it is worth feeling, because the lifter is looking
    // at the bar and not at the screen. Keyed on the count so a second record in the same session
    // fires again.
    .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: records.count)
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
  static func describe(_ record: PersonalRecord) -> String {
    switch record.kind {
    case .heaviestLoad:
      if let previous = record.previousWeightKg {
        return "\(Self.trim(record.weightKg)) kg, up from \(Self.trim(previous)) kg"
      }
      return "\(Self.trim(record.weightKg)) kg"
    case .repsAtLoad:
      if let previousReps = record.previousReps {
        return "\(record.reps) reps at \(Self.trim(record.weightKg)) kg, up from \(previousReps)"
      }
      return "\(record.reps) reps at \(Self.trim(record.weightKg)) kg"
    case .estimatedOneRepMax:
      if let previous = record.previousWeightKg {
        return "estimated, up from about \(Self.trim(previous)) kg"
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
    let displayed = unit.fromKilograms(volume.volumeKg)
    var parts = [
      volume.workingSets == 1 ? "1 set" : "\(volume.workingSets) sets",
      volume.reps == 1 ? "1 rep" : "\(volume.reps) reps",
    ]
    if volume.volumeKg > 0 {
      parts.append("\(Int(displayed.rounded())) \(unit.abbreviation) volume")
    }
    if volume.warmupSets > 0 { parts.append("\(volume.warmupSets) warm-up") }
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
