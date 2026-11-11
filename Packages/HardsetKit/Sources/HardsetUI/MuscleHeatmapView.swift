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
  /// The map's one badge states the weakest certainty among the muscles it actually credits,
  /// as `SetCounting` grades each one, rather than a fixed "Moderate" for every cell. With nothing
  /// credited there is nothing to be certain about.
  private var certainty: Certainty {
    let credited = Muscle.allCases.filter { report.sets(for: $0) > 0 }
    guard !credited.isEmpty else { return .unevaluated }
    return Certainty.combine(credited.map {
      SetCounting.certaintyCeiling(for: $0, fractionalSets: report.sets(for: $0))
    })
  }

  private func isUncatalogued(_ muscle: Muscle) -> Bool {
    report.sets(for: muscle) == 0 && ExerciseCatalog.unauthoredDirectTokens.contains(muscle)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      Text("\(windowLabel) · Comparative fractional sets. Bars compare volume with your most-credited muscle; it does not rate whether you trained enough.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      CertaintyBadge(level: certainty, methodology: SetCounting.source.methodology, citation: SetCounting.source.citation)
      if report.isLowerBound {
        HardsetBanner(.caveat, message: "\(report.unattributedHardSets) working sets have unknown attribution. All muscle counts are lower bounds.")
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.snug), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Tokens.Spacing.snug) {
        ForEach(Muscle.allCases, id: \.self) { muscle in
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            Text(ExercisePickerView.displayName(MuscleKey(muscle))).font(Tokens.Text.headline)
            if isUncatalogued(muscle) {
              // No catalogue movement credits it directly, so a zero here is the catalogue's gap,
              // not the lifter's.
              Text("No catalogue movement credits this yet")
                .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
            } else {
              Text("\(report.isLowerBound ? "≥ " : "")\(report.sets(for: muscle).formatted(.number.precision(.fractionLength(0...1)))) fractional sets")
                .font(Tokens.Text.figure).monospacedDigit()
            }
            if muscle.tier == .counted { Text("Counted, not modelled").font(Tokens.Text.caption) }
            ProgressView(value: report.sets(for: muscle), total: max(report.fractionalSets.values.max() ?? 0, 1))
              .tint(Tokens.Color.accent)
              .accessibilityHidden(true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Tokens.Spacing.regular)
          .background(report.sets(for: muscle) > 0 ? Tokens.Color.accentSurface : Tokens.Color.surface,
            in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
          .accessibilityElement(children: .combine)
        }
      }
      Text("A zero means no credited sets, not proof that a muscle was untrained. Direct sets receive 1.0, indirect sets 0.5, and stabilizing contributions 0. Current catalogue attribution is used.")
        .font(Tokens.Text.caption).foregroundStyle(Tokens.Color.textSecondary)
    }
    .foregroundStyle(Tokens.Color.textPrimary)
    .padding(Tokens.Spacing.loose)
  }
}
