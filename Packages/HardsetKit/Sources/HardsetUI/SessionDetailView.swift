import HardsetCore
import SwiftUI

/// A finished workout, read back: when, how long, the totals, and every set by movement and
/// machine, with the records each set earned.
///
/// Holds no storage and reads nothing: the caller loads a `SessionDetail` and passes it in. It
/// shows what happened. It compares nothing with a plan and shows no target or streak. A movement
/// done on two machines is two sections, never one (`DECISIONS.md` §20).
public struct SessionDetailView: View {
  @State private var explainedSet: SessionDetail.SetLine?

  private let detail: SessionDetail
  private let unit: WeightUnit
  private let onShowProgress: ((ExerciseID, String) -> Void)?

  /// - Parameter onShowProgress: Opens a movement's load history. When non-nil each section's
  ///   header becomes a button that calls it with that block's movement; nil leaves plain headers.
  public init(
    detail: SessionDetail,
    unit: WeightUnit,
    onShowProgress: ((ExerciseID, String) -> Void)? = nil
  ) {
    self.detail = detail
    self.unit = unit
    self.onShowProgress = onShowProgress
  }

  public var body: some View {
    let formatter = WeightFormatter(unit: unit)
    List {
      whenSection
      Section {
        Text(SessionVolumeText.written(detail.summary.volume, formatter: formatter))
          .monospacedDigit()
          .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
          .accessibilityLabel(SessionVolumeText.spoken(detail.summary.volume, formatter: formatter))
      }
      ForEach(detail.blocks) { block in
        Section {
          ForEach(Self.numbered(block.sets), id: \.id) { item in
            setRow(item.line, number: item.number, label: item.label, in: block, formatter: formatter)
          }
        } header: {
          header(for: block)
        }
      }
    }
    .sheet(item: $explainedSet) { line in
      MethodologySheet(
        source: StrengthMath.epleySource,
        certainty: line.records.compactMap(\.estimateCertainty).min())
    }
  }

  // MARK: - When

  private var whenSection: some View {
    let summary = detail.summary
    return Section {
      HStack(alignment: .firstTextBaseline) {
        Text(
          summary.timeline.startedAt,
          format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)
        )
        Spacer(minLength: Tokens.Spacing.snug)
        if summary.length == nil {
          // The honest statement: a span no workout could have had is withheld, not shown. Grey
          // with a glyph, so the caveat is not carried by colour.
          Label(summary.lengthText, systemImage: CaveatMark.lengthUnknown.symbolName)
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

  // MARK: - Blocks

  static func title(for block: SessionDetail.Block) -> String {
    guard let machine = block.machineName else { return block.exerciseName }
    return "\(block.exerciseName) · \(machine)"
  }

  @ViewBuilder private func header(for block: SessionDetail.Block) -> some View {
    let title = Self.title(for: block)
    if let onShowProgress {
      Button {
        onShowProgress(block.exerciseID, block.exerciseName)
      } label: {
        HStack(spacing: Tokens.Spacing.snug) {
          Text(title)
          Spacer(minLength: Tokens.Spacing.snug)
          Image(systemName: "chart.xyaxis.line")
        }
        // A plain button does not inherit a section header's styling, so it is stated, and the
        // plain-text branch matches it.
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .textCase(nil)
        .frame(minHeight: Tokens.minimumTapTarget)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(title). Show load history.")
      .accessibilityAddTraits(.isHeader)
    } else {
      Text(title)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .textCase(nil)
    }
  }

  private struct NumberedSet: Identifiable {
    let line: SessionDetail.SetLine
    let number: Int
    let label: String
    var id: SetID { line.id }
  }

  /// Working sets count from 1; a warm-up is "W" and takes no number.
  private static func numbered(_ lines: [SessionDetail.SetLine]) -> [NumberedSet] {
    var working = 0
    return lines.map { line in
      if line.isWarmup { return NumberedSet(line: line, number: 0, label: "W") }
      working += 1
      return NumberedSet(line: line, number: working, label: "\(working)")
    }
  }

  private func setRow(
    _ line: SessionDetail.SetLine, number: Int, label: String, in block: SessionDetail.Block,
    formatter: WeightFormatter
  ) -> some View {
    let estimate = line.records.compactMap(\.estimateCertainty).min()
    return VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
        Text(label)
          .font(Tokens.Text.label.weight(.semibold))
          .foregroundStyle(Tokens.Color.textSecondary)
          .frame(minWidth: Tokens.Spacing.regular * 2, alignment: .leading)
        Text("\(formatter.load(kilograms: line.weightKg)) × \(line.reps)")
          .font(Tokens.Text.label)
          .monospacedDigit()
      }
      ForEach(line.records) { record in
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          Image(systemName: "trophy")
            .foregroundStyle(Tokens.Color.record)
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(RecordCopy.line(for: record, formatter: formatter))
              .font(Tokens.Text.caption)
              .monospacedDigit()
            if let certainty = record.estimateCertainty {
              CertaintyBadge(certainty, source: StrengthMath.epleySource, style: .compact)
            }
          }
        }
      }
    }
    .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
    // One element per set. The badge's own button is out of reach inside it, so the explanation
    // is offered as an action instead.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(SetRowSpeech.label(number: number, isWarmup: line.isWarmup))
    .accessibilityValue(
      [
        SetRowSpeech.value(
          weightKg: line.weightKg, reps: line.reps, isLogged: true, formatter: formatter),
        RecordCopy.announcement(
          for: line.records, exerciseName: block.exerciseName, formatter: formatter),
        estimate?.mark.word,
      ]
      .compactMap { $0 }.joined(separator: ". ")
    )
    .accessibilityActions {
      if estimate != nil {
        Button("How this estimate is calculated") { explainedSet = line }
      }
    }
  }
}

#if DEBUG
  private enum SessionDetailPreviewData {
    static let start = Date(timeIntervalSince1970: 15_000_000)

    static func line(_ kg: Double, _ reps: Int, warmup: Bool = false, records: [PersonalRecord] = [])
      -> SessionDetail.SetLine
    {
      SessionDetail.SetLine(
        setID: SetID(), weightKg: kg, reps: reps, isWarmup: warmup, records: records)
    }

    static let legPress = ExerciseID()

    static let detail = SessionDetail(
      summary: WorkoutSummary(
        sessionID: SessionID(),
        timeline: SessionTimeline(startedAt: start, finishedAt: start.addingTimeInterval(3_600)),
        volume: SessionVolume(workingSets: 3, warmupSets: 1, volumeKg: 2_900, reps: 24),
        records: [], muscles: [], unattributedSets: 0,
        machinesUsed: ["Hammer Strength Leg Press", "Cybex Leg Press"]),
      blocks: [
        SessionDetail.Block(
          exerciseID: legPress, exerciseName: "Leg Press", machineID: MachineID(),
          machineName: "Hammer Strength Leg Press",
          sets: [
            line(60, 10, warmup: true),
            line(120, 8, records: [PersonalRecord(kind: .estimatedOneRepMax, weightKg: 120, reps: 8, previousWeightKg: 140)]),
            line(120, 8),
          ]),
        SessionDetail.Block(
          exerciseID: legPress, exerciseName: "Leg Press", machineID: MachineID(),
          machineName: "Cybex Leg Press",
          sets: [line(100, 8)]),
      ])
  }

  #Preview("Session detail") {
    NavigationStack {
      SessionDetailView(
        detail: SessionDetailPreviewData.detail, unit: .kilograms, onShowProgress: { _, _ in }
      )
      .navigationTitle("Workout")
    }
  }
#endif
