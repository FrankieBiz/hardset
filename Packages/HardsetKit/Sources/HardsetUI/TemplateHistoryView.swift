import HardsetCore
import SwiftUI

/// The sessions of one saved workout, newest first: a date, its working sets and volume, then one
/// row for each movement that session actually logged.
///
/// There is no card per session, no chart and no comparison between sessions. The sheet says what
/// happened and lets the lifter read it; a trend is the Progress tab's job, per movement.
public struct TemplateHistoryView: View {
  private let history: TemplateHistory
  private let unit: WeightUnit
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(history: TemplateHistory, unit: WeightUnit) {
    self.history = history
    self.unit = unit
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      Text(
        TemplateHistoryCopy.sessionsLine(
          shown: history.sessions.count, total: history.totalSessionCount)
      )
      .font(Tokens.Text.provenance)
      .foregroundStyle(Tokens.Color.chalkDim)

      ForEach(history.sessions) { session in
        sessionBlock(session)
      }
    }
    .padding(Tokens.Spacing.loose)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func sessionBlock(_ session: TemplateHistory.Session) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(day(session.finishedAt))
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      Text(
        TemplateHistoryCopy.movementDetail(
          sets: session.workingSetCount, volume: volumeText(session.volumeKg))
      )
      .font(Tokens.Text.provenance)
      .foregroundStyle(Tokens.Color.chalkDim)
      .fixedSize(horizontal: false, vertical: true)

      if !session.movements.isEmpty {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          ForEach(session.movements) { movement in
            movementRow(movement)
          }
        }
        .padding(.top, Tokens.Spacing.hairline)
      }
    }
  }

  private func movementRow(_ movement: TemplateHistory.Movement) -> some View {
    let name = movement.machineName.map { "\(movement.exerciseName) · \($0)" }
      ?? movement.exerciseName
    let detail = TemplateHistoryCopy.movementDetail(
      sets: movement.workingSetCount, volume: volumeText(movement.volumeKg))

    return movementLayout {
      Text(name)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(detail)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    // Read as one sentence, with the numbers the row draws and no percentage.
    .accessibilityLabel(
      "\(name), \(movement.workingSetCount == 1 ? "1 working set" : "\(movement.workingSetCount) working sets"), volume \(volumeText(movement.volumeKg))"
    )
  }

  /// Side by side at ordinary sizes, stacked at accessibility sizes so a long movement name never
  /// squeezes the figures into a narrow column.
  private var movementLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.hairline))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular))
  }

  /// The measured load in the lifter's unit, rounded the way display loads are, then grouped for
  /// reading: "1,200 kg". Named "volume" by `TemplateHistoryCopy`, so weight × reps is never read
  /// as the load on the bar.
  private func volumeText(_ kilograms: Double) -> String {
    let displayed = StrengthMath.displayRounded(kilograms, in: unit)
    let number = displayed.formatted(.number.precision(.fractionLength(0...1)))
    return "\(number) \(unit.abbreviation)"
  }

  /// "Nov 4, 2026", in the lifter's own time zone. The year is always named, so an old session is
  /// never read as a recent one.
  private func day(_ date: Date) -> String {
    WorkedFromFormat(unit: unit).day(date)
  }
}
