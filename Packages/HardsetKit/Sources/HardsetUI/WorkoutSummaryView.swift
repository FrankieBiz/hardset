import HardsetCore
import SwiftUI

/// What a finished workout contained, and nothing it is measured against.
///
/// Presented by `HardsetRootView` once a workout is finished, so finishing ends in a statement of
/// what was done rather than an empty start screen. It takes a value and callbacks only: Core's
/// `WorkoutSummary` carries every figure and its own text (`lengthText`, `setsText()`,
/// `spokenSetsText()`), so this view formats nothing itself. There is no target, goal, streak or
/// comparison with a plan, and no celebration beyond stating a record and what it beat. The sheet
/// is static, so it has no animation to gate on Reduce Motion.
public struct WorkoutSummaryView: View {
  private let summary: WorkoutSummary?
  private let unit: WeightUnit
  private let errorMessage: String?
  private let onRetry: (() -> Void)?
  private let onDone: () -> Void

  /// `summary == nil` with an `errorMessage` shows the error and a retry; with neither it shows a
  /// spinner while the summary is read.
  public init(
    summary: WorkoutSummary?,
    unit: WeightUnit,
    errorMessage: String? = nil,
    onRetry: (() -> Void)? = nil,
    onDone: @escaping () -> Void
  ) {
    self.summary = summary
    self.unit = unit
    self.errorMessage = errorMessage
    self.onRetry = onRetry
    self.onDone = onDone
  }

  public var body: some View {
    NavigationStack {
      content
        .navigationTitle("Workout saved")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: onDone)
          }
        }
    }
  }

  @ViewBuilder private var content: some View {
    if let summary {
      List {
        whenSection(summary)
        totalsSection(summary)
        if !summary.records.isEmpty { recordsSection(summary) }
        if !summary.muscles.isEmpty { musclesSection(summary) }
        if !summary.machinesUsed.isEmpty { machinesSection(summary) }
      }
    } else if let errorMessage {
      ContentUnavailableView {
        Label("Couldn't load the summary", systemImage: "exclamationmark.circle")
      } description: {
        Text(errorMessage)
      } actions: {
        if let onRetry {
          Button("Try again", action: onRetry)
        }
      }
    } else {
      ProgressView()
        .accessibilityLabel("Loading summary")
    }
  }

  // MARK: - Sections

  private func whenSection(_ summary: WorkoutSummary) -> some View {
    Section {
      HStack(alignment: .firstTextBaseline) {
        Text(
          summary.timeline.startedAt,
          format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)
        )
        Spacer(minLength: Tokens.Spacing.snug)
        if summary.length == nil {
          // The honest statement: a span no workout could have had is withheld, not shown. Grey
          // with a glyph, so the caveat is not carried by colour.
          Label(summary.lengthText, systemImage: "questionmark.circle")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.caveat)
        } else {
          Text(summary.lengthText)
            .font(Tokens.Text.label)
            .monospacedDigit()
            .foregroundStyle(Tokens.Color.textSecondary)
        }
      }
      .frame(minHeight: Tokens.minimumTapTarget)
      .accessibilityElement(children: .combine)
    }
  }

  private func totalsSection(_ summary: WorkoutSummary) -> some View {
    let volume = summary.volume
    let formatter = WeightFormatter(unit: unit)
    return Section("Totals") {
      Text("\(CountText.sets(volume.workingSets)), \(CountText.reps(volume.reps))")
        .font(Tokens.Text.readout)
        .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      if volume.volumeKg > 0 {
        Text("\(formatter.total(kilograms: volume.volumeKg)) volume")
          .monospacedDigit()
          .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      }
      if volume.warmupSets > 0 {
        Text("\(volume.warmupSets) warm-up")
          .foregroundStyle(Tokens.Color.textSecondary)
          .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      }
    }
  }

  private func recordsSection(_ summary: WorkoutSummary) -> some View {
    let formatter = WeightFormatter(unit: unit)
    return Section("Records") {
      ForEach(summary.records) { line in
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
          Image(systemName: "trophy")
            .foregroundStyle(Tokens.Color.record)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(line.record.kind.label)
              .font(Tokens.Text.label.weight(.semibold))
            Text(RecordCopy.detail(for: line.record, formatter: formatter))
              .monospacedDigit()
            Text(Self.subtitle(for: line))
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(for: line, formatter: formatter))
      }
    }
  }

  private func musclesSection(_ summary: WorkoutSummary) -> some View {
    Section {
      ForEach(summary.muscles) { line in
        let name = ExercisePickerView.displayName(line.muscle)
        HStack {
          Text(name)
          Spacer(minLength: Tokens.Spacing.snug)
          Text(line.setsText())
            .monospacedDigit()
            .foregroundStyle(Tokens.Color.textSecondary)
        }
        .frame(minHeight: Tokens.minimumTapTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(line.spokenSetsText())")
      }
    } header: {
      Text("Muscles touched")
    } footer: {
      if summary.unattributedSets > 0 {
        Label {
          Text(
            "\(CountText.sets(summary.unattributedSets)) on movements with no muscles recorded, so these are at least this much."
          )
        } icon: {
          Image(systemName: "info.circle")
        }
        .foregroundStyle(Tokens.Color.caveat)
      }
    }
  }

  private func machinesSection(_ summary: WorkoutSummary) -> some View {
    Section("Machines") {
      ForEach(summary.machinesUsed, id: \.self) { name in
        Text(name)
          .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
      }
    }
  }

  // MARK: - Record line text

  /// "Bench press · Hammer Strength" or just the movement.
  static func subtitle(for line: WorkoutSummary.RecordLine) -> String {
    [line.exerciseName, line.machineName].compactMap { $0 }.joined(separator: " · ")
  }

  /// Spoken in full, units spelled out: the movement and machine, then the kind and what it beat.
  static func spokenLabel(for line: WorkoutSummary.RecordLine, formatter: WeightFormatter)
    -> String
  {
    let spoken = RecordCopy.announcement(
      for: [line.record], exerciseName: subtitle(for: line), formatter: formatter)
    return spoken ?? "\(line.record.kind.label), \(subtitle(for: line))"
  }
}

#if DEBUG
  #Preview("Summary") {
    let started = Date(timeIntervalSince1970: 1_790_000_000)
    let setID = SetID()
    WorkoutSummaryView(
      summary: WorkoutSummary(
        sessionID: SessionID(),
        // Still open, so the length is unknown.
        timeline: SessionTimeline(startedAt: started),
        volume: SessionVolume(workingSets: 14, warmupSets: 3, volumeKg: 9_840, reps: 118),
        records: [
          .init(
            setID: setID, exerciseName: "Bench press", machineName: nil,
            record: PersonalRecord(
              kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)),
          .init(
            setID: setID, exerciseName: "Chest press", machineName: "Hammer Strength MTS",
            record: PersonalRecord(
              kind: .repsAtLoad, weightKg: 60, reps: 11, previousReps: 10)),
        ],
        muscles: [
          .init(muscle: MuscleKey(.chest), fractionalSets: 6, isLowerBound: true),
          .init(muscle: MuscleKey(.triceps), fractionalSets: 3.5, isLowerBound: true),
          .init(muscle: MuscleKey(.frontDelts), fractionalSets: 2.5, isLowerBound: true),
        ],
        unattributedSets: 2,
        machinesUsed: ["Hammer Strength MTS", "Cable crossover"]
      ),
      unit: .kilograms,
      onDone: {}
    )
  }

  #Preview("Loading") {
    WorkoutSummaryView(summary: nil, unit: .kilograms, onDone: {})
  }

  #Preview("Error") {
    WorkoutSummaryView(
      summary: nil, unit: .kilograms,
      errorMessage: "The workout could not be read.", onRetry: {}, onDone: {})
  }
#endif
