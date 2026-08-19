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
  private let restState: RestTimerState
  private let restMetadata: RestMetadata?
  private let errorMessage: String?
  private let onLogSet: (UUID, SetSlot) -> Void
  private let onAdjustRest: (Duration) -> Void
  private let onPauseResumeRest: () -> Void
  private let onSkipRest: () -> Void
  private let onAddExercise: (() -> Void)?
  private let onFinish: () -> Void

  public init(
    exercises: Binding<[ExerciseLogState]>,
    unit: WeightUnit,
    restState: RestTimerState = .idle,
    restMetadata: RestMetadata? = nil,
    errorMessage: String? = nil,
    onLogSet: @escaping (UUID, SetSlot) -> Void,
    onAdjustRest: @escaping (Duration) -> Void = { _ in },
    onPauseResumeRest: @escaping () -> Void = {},
    onSkipRest: @escaping () -> Void = {},
    onAddExercise: (() -> Void)? = nil,
    onFinish: @escaping () -> Void = {}
  ) {
    self._exercises = exercises
    self.unit = unit
    self.restState = restState
    self.restMetadata = restMetadata
    self.errorMessage = errorMessage
    self.onLogSet = onLogSet
    self.onAdjustRest = onAdjustRest
    self.onPauseResumeRest = onPauseResumeRest
    self.onSkipRest = onSkipRest
    self.onAddExercise = onAddExercise
    self.onFinish = onFinish
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

        ForEach($exercises) { $exercise in
          ExerciseSectionView(state: $exercise, unit: unit) { slot in
            onLogSet(exercise.id, slot)
          }
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
    .background(Tokens.Color.background)
    .safeAreaInset(edge: .bottom) {
      RestBarView(
        state: restState,
        metadata: restMetadata,
        onAdjust: onAdjustRest,
        onPauseResume: onPauseResumeRest,
        onSkip: onSkipRest
      )
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
    let displayed = unit.fromKilograms(volume.volumeKg)
    var parts = ["\(volume.workingSets) sets", "\(volume.reps) reps"]
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
