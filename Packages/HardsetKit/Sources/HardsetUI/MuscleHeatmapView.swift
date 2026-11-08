import HardsetCore
import SwiftUI

/// A comparative map of all permanent muscle tokens. Intensity means credited sets,
/// never training quality or an invented optimal target. Unknown attribution stays visible.
public struct MuscleHeatmapView: View {
  private let report: MuscleVolumeReport
  @Environment(\.dynamicTypeSize) private var typeSize
  public init(report: MuscleVolumeReport) { self.report = report }
  public var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      Text("Deep muscle map").font(Tokens.Text.title)
      Text("Last 7 days · Comparative fractional sets. Colour shows volume relative to your most-credited muscle; it does not rate whether you trained enough.")
        .font(Tokens.Text.provenance).foregroundStyle(Tokens.Color.textSecondary)
      CertaintyBadge(level: .moderate, methodology: SetCounting.source.methodology, citation: SetCounting.source.citation)
      if report.isLowerBound {
        HardsetBanner(.caveat, message: "\(report.unattributedHardSets) working sets have unknown attribution. All muscle counts are lower bounds.")
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.snug), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Tokens.Spacing.snug) {
        ForEach(Muscle.allCases, id: \.self) { muscle in
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            Text(ExercisePickerView.displayName(MuscleKey(muscle))).font(Tokens.Text.headline)
            Text("\(report.isLowerBound ? "≥ " : "")\(report.sets(for: muscle).formatted(.number.precision(.fractionLength(0...1)))) fractional sets")
              .font(Tokens.Text.figure).monospacedDigit()
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
