import HardsetCore
import SwiftUI

/// What the paid unlock sells: when each muscle was last trained, how the last four weeks compare
/// with the four before, the lifetime total, and the shape of the last twelve weeks.
///
/// There is no seven-day count anywhere on this sheet. The free Volume tab already lists every
/// muscle's count for the week on screen, so repeating it here would add nothing and restating it in
/// a grid was the defect this surface replaced (D24 §0).
///
/// Every per-muscle figure is a derived fractional credit, not a measurement, so none is drawn as a
/// monument and none carries the weekly certainty badge: the badge's research is about weekly sets,
/// and this sheet covers four weeks or a lifetime (D24 §3.2–3.3). The sheet says that once, above
/// the rows, and every derived figure opens the working it was made from.
///
/// A muscle with no credited set is never drawn as a zero. It is content debt, a floor because
/// history holds sets with no body part, or a plain absence, each in its own words (D24 §3.4).
public struct MuscleHistoryView: View {
  private let history: MuscleHistory
  /// Opens the working behind a muscle's four-week comparison or lifetime figure. `nil` where the
  /// host has no sheet to show, and then the figures are plain text.
  private let onShowWorking: ((Muscle, MuscleHistoryFigure) -> Void)?
  /// Opens the Library, where a movement with no body part gets one.
  private let onShowLibrary: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var typeSize

  /// Counts hold no load, so the unit is never read; only the locale and the day formatting are.
  private static let format = WorkedFromFormat(unit: .kilograms)

  public init(
    history: MuscleHistory,
    onShowWorking: ((Muscle, MuscleHistoryFigure) -> Void)? = nil,
    onShowLibrary: (() -> Void)? = nil
  ) {
    self.history = history
    self.onShowWorking = onShowWorking
    self.onShowLibrary = onShowLibrary
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      caption
      if history.isEmpty {
        HardsetEmptyState(
          title: MuscleHistoryCopy.nothingLoggedTitle,
          detail: MuscleHistoryCopy.nothingLoggedDetail,
          systemImage: "clock.arrow.circlepath",
          style: .quiet
        )
      } else {
        if history.futureDatedSets > 0 {
          Text(MuscleHistoryCopy.futureDated(history.futureDatedSets))
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Muscle.allCases, id: \.self) { muscle in
            row(muscle)
          }
        }
      }
    }
    .foregroundStyle(Tokens.Color.chalk)
    .padding(Tokens.Spacing.loose)
  }

  private var caption: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(MuscleHistoryCopy.counting)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      Text(MuscleHistoryCopy.currentAttribution)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      Text(MuscleHistoryCopy.weeklyBadgeStaysOnVolume)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      if history.includesImportedHistory {
        Text(MuscleHistoryCopy.importedHistory)
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func row(_ muscle: Muscle) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(Tokens.Color.hairline)
        .frame(height: Tokens.Stroke.hairline)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
        Text(ExercisePickerView.displayName(MuscleKey(muscle)))
          .font(Tokens.Text.headline)
          .fixedSize(horizontal: false, vertical: true)
        if history.isTrained(muscle) {
          trainedRows(muscle)
        } else {
          emptyRows(muscle)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, Tokens.Spacing.regular)
    }
  }

  // MARK: - Trained

  @ViewBuilder private func trainedRows(_ muscle: Muscle) -> some View {
    if let last = history.lastTrained[MuscleKey(muscle)] {
      Text("\(MuscleHistoryCopy.lastTrained) \(Self.day(last.date)) · \(last.movementName)")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
    fourWeekFigures(muscle)
    lifetimeFigure(muscle)
    if let label = shapeLabel, !typeSize.isAccessibilitySize, history.weeks.count > 1 {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        Sparkline(values: history.shape(for: muscle), includesZero: true)
          .frame(width: 96, height: 32)
        Text(label)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
    } else if let label = shapeLabel {
      Text(label)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
    workingControls(muscle)
  }

  /// Two counts and their signed difference, never a percentage when the earlier window is zero.
  private func fourWeekFigures(_ muscle: Muscle) -> some View {
    let current = history.currentSets(for: muscle)
    let previous = history.previousSets(for: muscle)
    return VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      // Named by its dates, not "this month": a rolling window called a month counts the wrong days
      // on the first of it.
      Text("\(MuscleHistoryCopy.lastFourWeeks), \(Self.day(history.currentSpan.start)) to now")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text(Self.format.sets(current))
          .font(Tokens.Text.figure)
          .monospacedDigit()
        Text("sets")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
        Text("· against \(Self.format.sets(previous)) in the 4 weeks before")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(MuscleHistoryCopy.comparison(current: current, previous: previous, format: Self.format))
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func lifetimeFigure(_ muscle: Muscle) -> some View {
    let total = history.lifetimeSets(for: muscle)
    let floor = history.isLowerBound ? "≥ " : ""
    return VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(lifetimeLabel)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text("\(floor)\(Self.format.sets(total))")
          .font(Tokens.Text.readout)
          .monospacedDigit()
        Text("sets")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
    }
  }

  /// "Lifetime, since 5 Mar 2026" when the first logged set is known; "Lifetime" otherwise.
  private var lifetimeLabel: String {
    guard let first = history.firstSetAt else { return MuscleHistoryCopy.lifetime }
    return "\(MuscleHistoryCopy.lifetime), since \(Self.day(first))"
  }

  @ViewBuilder private func workingControls(_ muscle: Muscle) -> some View {
    if let onShowWorking {
      let layout = typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
        : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.regular))
      layout {
        WorkedFromButton("Worked from: last 4 weeks", style: .compact) {
          onShowWorking(muscle, .fourWeeks)
        }
        .accessibilityLabel(
          "Worked from, \(ExercisePickerView.displayName(MuscleKey(muscle))), last four weeks")
        WorkedFromButton("Worked from: lifetime", style: .compact) {
          onShowWorking(muscle, .lifetime)
        }
        .accessibilityLabel(
          "Worked from, \(ExercisePickerView.displayName(MuscleKey(muscle))), lifetime")
      }
      .padding(.top, Tokens.Spacing.hairline)
    }
  }

  // MARK: - Empty

  @ViewBuilder private func emptyRows(_ muscle: Muscle) -> some View {
    switch history.emptyState(for: muscle) {
    case .contentDebt:
      // A gap in the catalogue, not in the lifter's training.
      Text(UncatalogedMuscleCopy.tile)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
    case .noneCredited:
      Text(MuscleHistoryCopy.noCreditedSets)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
    case .floor(let unattributed):
      Text(MuscleHistoryCopy.noCreditedSetsFloor(unattributed))
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      if let onShowLibrary {
        Button(MuscleHistoryCopy.floorWayOut) { onShowLibrary() }
          .buttonStyle(InlineControlStyle(alignment: .leading))
          .font(Tokens.Text.caption)
      }
    }
  }

  // MARK: - Words

  private var shapeLabel: String? {
    guard let first = history.weeks.first, let last = history.weeks.last else { return nil }
    return MuscleHistoryCopy.shapeSpan(
      weeks: history.weeks.count, first: first.start, last: last.lastDay, format: Self.format)
  }

  private static func day(_ date: Date) -> String { format.day(date) }
}
