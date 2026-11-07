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
  private let title: String?
  private let gymName: String?
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
  private let onShowSettings: (() -> Void)?
  private let onFinish: () -> Void

  /// Finishing closes the session for good, so it takes a second, deliberate tap. The first tap
  /// only asks; a lifter brushing the button with a chalky thumb loses nothing.
  @State private var isConfirmingFinish = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// - Parameter title: Draws a screen header when present. The live session passes "Workout";
  ///   previews and embedded uses can leave it out.
  /// - Parameter gymName: The header's context line. `nil` says no gym is recorded, which is
  ///   also why the machine chips are absent.
  /// - Parameter onShowSettings: Puts a settings button in the header.
  public init(
    exercises: Binding<[ExerciseLogState]>,
    unit: WeightUnit,
    title: String? = nil,
    gymName: String? = nil,
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
    onShowSettings: (() -> Void)? = nil,
    onFinish: @escaping () -> Void = {}
  ) {
    self._exercises = exercises
    self.unit = unit
    self.title = title
    self.gymName = gymName
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
    self.onShowSettings = onShowSettings
    self.onFinish = onFinish
  }

  public var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        if let title {
          header(title: title)
            .padding(.bottom, Tokens.Spacing.snug)
        }

        if let errorMessage {
          // A failed write is stated, not swallowed. The row it belongs to is still unlogged,
          // so the user can retry rather than discovering the gap days later.
          HardsetBanner(.error, message: errorMessage)
            .padding(.horizontal, Tokens.Spacing.regular)
            .transition(.opacity)
        }

        if !records.isEmpty {
          recordsCard
            .padding(.horizontal, Tokens.Spacing.regular)
            .transition(.opacity)
        }

        ForEach($exercises) { $exercise in
          ExerciseSectionView(
            state: $exercise,
            unit: unit,
            onLogSet: { slot in onLogSet(exercise.id, slot) },
            onSelectMachine: onSelectMachine.map { select in
              { select(exercise.id) }
            },
            onShowHistory: onShowHistory.map { show in
              { show(exercise.id) }
            }
          )
          .padding(.horizontal, Tokens.Spacing.regular)
        }

        // An empty workout says so, and says what to do about it, rather than rendering a bare
        // "Finish" button under nothing. When it is empty, the empty state carries the add action,
        // so the dashed slot below is not drawn twice.
        if exercises.isEmpty {
          HardsetEmptyState(
            title: "Nothing added yet",
            detail: "Add a movement to start logging sets.",
            systemImage: "dumbbell",
            actionTitle: onAddExercise == nil ? nil : "Add movement",
            action: onAddExercise
          )
        } else if let onAddExercise {
          addMovementSlot(action: onAddExercise)
            .padding(.horizontal, Tokens.Spacing.regular)
        }

        summary
          .padding(.horizontal, Tokens.Spacing.regular)
          .padding(.top, Tokens.Spacing.section)
      }
      .padding(.bottom, Tokens.Spacing.section)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion),
        value: errorMessage
      )
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion),
        value: records.map(\.kind)
      )
    }
    .background(Tokens.Color.background)
    // The inset measures the rest bar and reserves exactly its height, so the last row is never
    // trapped underneath it. A guessed 72 pt allowance used to sit on top of this and was wrong as
    // soon as the bar wrapped onto two lines.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      RestBarView(
        state: restState,
        metadata: restMetadata,
        onAdjust: onAdjustRest,
        onPauseResume: onPauseResumeRest,
        onSkip: onSkipRest
      )
    }
  }

  private func header(title: String) -> some View {
    ScreenHeader(title, subtitle: gymName ?? "No gym recorded") {
      if let onShowSettings {
        HeaderIconButton(
          systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings
        )
      }
    }
  }

  /// Records from the set just logged. Each one names what it beat, so the claim is checkable
  /// rather than a bare "PR!", and an estimated maximum carries its certainty beside it.
  private var recordsCard: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      ForEach(records) { record in
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
          Image(systemName: "trophy.fill")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.pr)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            Text(record.kind.label)
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.pr)
            Text(Self.describe(record, unit: unit))
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.textPrimary)
              .fixedSize(horizontal: false, vertical: true)
            if record.kind == .estimatedOneRepMax {
              CertaintyBadge(
                level: .moderate,
                methodology: ProgressionAnalyzer.source.methodology,
                citation: ProgressionAnalyzer.source.validRange
              )
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .padding(Tokens.Spacing.regular)
    .background(Tokens.Color.prSurface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.card)
        .strokeBorder(Tokens.Color.pr.opacity(0.35), lineWidth: Tokens.Stroke.hairline)
    )
  }

  /// The place the next movement goes. Dashed, like every empty slot in the app.
  private func addMovementSlot(action: @escaping () -> Void) -> some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
    return Button(action: action) {
      Label("Add movement", systemImage: "plus")
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.accent)
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        .contentShape(shape)
        .overlay(
          shape.strokeBorder(
            Tokens.Color.controlBorder,
            style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [5, 4])
          )
        )
    }
    .buttonStyle(.plain)
  }

  /// Spells out the comparison. An estimated-1RM record says it is an estimate, because
  /// guideline 1.4.1 is about not presenting an estimate as a measurement.
  ///
  /// Written in the unit the lifter reads everything else in. Hard-coding "kg" here told a lifter
  /// training in pounds that they had set a record of 102 kg, a number they never saw anywhere.
  static func describe(_ record: PersonalRecord, unit: WeightUnit = .kilograms) -> String {
    let weight = "\(Self.trim(unit.fromKilograms(record.weightKg))) \(unit.abbreviation)"
    let previousWeight = record.previousWeightKg.map {
      "\(Self.trim(unit.fromKilograms($0))) \(unit.abbreviation)"
    }
    switch record.kind {
    case .heaviestLoad:
      if let previousWeight {
        return "\(weight), up from \(previousWeight)"
      }
      return weight
    case .repsAtLoad:
      if let previousReps = record.previousReps {
        return "\(record.reps) reps at \(weight), up from \(previousReps)"
      }
      return "\(record.reps) reps at \(weight)"
    case .estimatedOneRepMax:
      if let previousWeight {
        return "Estimated, up from about \(previousWeight)"
      }
      return "Estimated"
    }
  }

  static func trim(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }

  /// The session's totals, then the way out of it.
  private var summary: some View {
    let volume = SessionVolume(exercises: exercises)
    return VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        SectionLabel("This workout")
        if volume.isEmpty {
          Text("No sets logged yet")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
        } else {
          StatLedger(ledgerItems(volume))
        }
      }
      .padding(Tokens.Spacing.regular)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
      .accessibilityElement(children: .combine)
      .accessibilityLabel(volumeDescription)

      finishControls
    }
  }

  @ViewBuilder private var finishControls: some View {
    if isConfirmingFinish {
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        Text("Finish this workout? Sets you have not logged are not saved.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Tokens.Spacing.snug) {
          Button("Keep training") {
            setConfirming(false)
          }
          .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
          Button("Finish") {
            setConfirming(false)
            onFinish()
          }
          .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
        }
      }
      .transition(.opacity)
    } else {
      Button {
        setConfirming(true)
      } label: {
        Label("Finish workout", systemImage: "flag.checkered")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, size: .logger))
      .transition(.opacity)
    }
  }

  private func setConfirming(_ value: Bool) {
    withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
      isConfirmingFinish = value
    }
  }

  private func ledgerItems(_ volume: SessionVolume) -> [StatLedger.Item] {
    var items = [
      StatLedger.Item(label: "Working sets", value: String(volume.workingSets)),
      StatLedger.Item(label: "Reps", value: String(volume.reps)),
    ]
    if volume.volumeKg > 0 {
      let displayed = Int(unit.fromKilograms(volume.volumeKg).rounded())
      items.append(
        StatLedger.Item(
          label: "Volume", value: displayed.formatted(.number), unit: unit.abbreviation
        )
      )
    }
    if volume.warmupSets > 0 {
      items.append(StatLedger.Item(label: "Warm-ups", value: String(volume.warmupSets)))
    }
    return items
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
    return parts.joined(separator: ", ")
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
          title: "Workout",
          gymName: "Metroflex Gym",
          restState: .running(endsAt: Date().addingTimeInterval(96)),
          restMetadata: RestMetadata(
            exerciseName: "Leg Press", setOrdinal: 1, plannedSets: 2,
            machineName: "Hammer Strength"
          ),
          onLogSet: { stateID, slot in
            guard let index = exercises.firstIndex(where: { $0.id == stateID }) else { return }
            exercises[index].markLogged(slotID: slot.id, setID: SetID())
          },
          onAddExercise: {},
          onSelectMachine: { _ in },
          onShowHistory: { _ in },
          onShowSettings: {}
        )
      }
    }
    return Harness()
  }
#endif
