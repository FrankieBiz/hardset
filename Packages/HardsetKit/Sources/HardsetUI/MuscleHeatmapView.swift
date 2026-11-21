import HardsetCore
import SwiftUI

/// A comparative map of all permanent muscle tokens. Intensity means credited sets,
/// never training quality or an invented optimal target. Unknown attribution stays visible.
public struct MuscleHeatmapView: View {
  private let report: MuscleVolumeReport
  private let windowLabel: String
  @Environment(\.dynamicTypeSize) private var typeSize
  /// - Parameter windowLabel: The window the report covers, in words. The sheet presenting the
  ///   map draws its title, so the view does not repeat it.
  public init(report: MuscleVolumeReport, windowLabel: String = "Last 7 days") {
    self.report = report
    self.windowLabel = windowLabel
  }
  private func isUncatalogued(_ muscle: Muscle) -> Bool {
    report.sets(for: muscle) == 0 && ExerciseCatalog.unauthoredDirectTokens.contains(muscle)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      Text("\(windowLabel) · Comparative fractional sets. Bars compare volume with your most-credited muscle; it does not rate whether you trained enough.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.chalkDim)
      // What a certainty beside a count is about, in the engine's own sentence, the same one the
      // volume rows state. The map has no single level of its own: a weakest-of-all badge would read
      // "Not evaluated" over a week that credited one lats set, so each credited muscle carries the
      // certainty the volume row gives the same count.
      Text(VolumeAnalyzer.certaintyMeaning)
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.chalkDim)
      if report.isLowerBound {
        HardsetBanner(
          .caveat, title: "Counts below are lower bounds",
          message: VolumeReportView.lowerBoundMessage(unattributed: report.unattributedHardSets))
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.snug), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Tokens.Spacing.snug) {
        ForEach(Muscle.allCases, id: \.self) { muscle in
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            // The name and the count are one spoken element; the certainty beside a credited count
            // stays a control of its own, as it is on the volume rows.
            VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
              Text(ExercisePickerView.displayName(MuscleKey(muscle))).font(Tokens.Text.headline)
              if isUncatalogued(muscle) {
                // No catalogue movement credits it directly, so a zero here is the catalogue's gap,
                // not the lifter's.
                Text(UncatalogedMuscleCopy.tile)
                  .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.chalkDim)
              } else {
                Text("\(report.isLowerBound ? "≥ " : "")\(report.sets(for: muscle).formatted(.number.precision(.fractionLength(0...1)))) fractional sets")
                  .font(Tokens.Text.figure).monospacedDigit()
              }
              if muscle.tier == .counted { Text("Counted, not modelled").font(Tokens.Text.caption) }
            }
            .accessibilityElement(children: .combine)
            if report.sets(for: muscle) > 0 {
              MuscleCertaintyBadge(muscle: muscle, fractionalSets: report.sets(for: muscle))
            }
            MuscleShareGauge(
              fraction: report.sets(for: muscle)
                / max(report.fractionalSets.values.max() ?? 0, 1))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Tokens.Spacing.regular)
          .background(report.sets(for: muscle) > 0 ? Tokens.Color.plateBlueSurface : Tokens.Color.steel,
            in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
      }
      Text("A zero means no credited sets, not proof that a muscle was untrained. Direct sets receive 1.0, indirect sets 0.5, and stabilizing contributions 0. Current catalogue attribution is used.")
        .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.chalkDim)
    }
    .foregroundStyle(Tokens.Color.chalk)
    .padding(Tokens.Spacing.loose)
  }
}

/// A comparative gauge on the same tokens as the volume report, not a system progress view.
///
/// The report's gauges are square-ended bars scaled to the week's own maximum; this is the same
/// measure on the same screen family, so it draws the same way and its track follows the palette.
private struct MuscleShareGauge: View {
  let fraction: Double

  var body: some View {
    let clamped = min(max(fraction, 0), 1)
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Rectangle().fill(Tokens.Color.steelRaised)
        Rectangle()
          .fill(Tokens.Color.plateBlue)
          .frame(width: proxy.size.width * clamped)
      }
    }
    .frame(height: 6)
    .accessibilityHidden(true)
  }
}
