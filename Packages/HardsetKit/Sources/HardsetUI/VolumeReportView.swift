import HardsetCore
import SwiftUI

/// Sets per muscle for a week.
///
/// The hard constraint on this screen: **there are no targets.** No per-muscle weekly set target
/// is established for any muscle, so there is nothing to draw a goal line against and nothing to
/// colour red. Bars are therefore scaled to the largest value in the report — they are
/// comparative, not evaluative. They answer "where is my volume going" and never "am I doing
/// enough", because the app cannot honestly answer the second.
///
/// That is also why the empty muscles get their own section rather than a red bar. A muscle at
/// zero is a fact the user can act on; a muscle at four sets being called insufficient is a claim
/// this app has no basis for.
public struct VolumeReportView: View {
  private let report: MuscleVolumeReport
  private let excludedFromGaps: Set<Muscle>
  private let onExplainCounting: (() -> Void)?

  public init(
    report: MuscleVolumeReport,
    excludedFromGaps: Set<Muscle> = [],
    onExplainCounting: (() -> Void)? = nil
  ) {
    self.report = report
    self.excludedFromGaps = excludedFromGaps
    self.onExplainCounting = onExplainCounting
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        header
        if report.hardSets == 0 {
          ContentUnavailableView {
            Label("Nothing logged this week", systemImage: "chart.bar")
          } description: {
            Text("Sets per muscle appear here once you log a workout.")
          }
        } else {
          trainedSection
          gapsSection
        }
      }
      .padding(Tokens.Spacing.regular)
    }
    .background(Tokens.Color.ground)
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("^[\(report.hardSets) working set](inflect: true) this week")
        .font(Tokens.Text.readout)
        .monospacedDigit()

      // The lower-bound statement is not a footnote. If some sets could not be attributed, every
      // number below is a floor, and saying so is the whole point of the coverage field.
      if report.isLowerBound {
        Label {
          Text(
            "\(report.unattributedHardSets) of those are on exercises with no muscles recorded, "
              + "so every count below is at least this much — not exactly this much."
          )
        } icon: {
          Image(systemName: "exclamationmark.circle")
        }
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.certainty(.low))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Spacing.regular)
        .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
      }

      if let onExplainCounting {
        Button(action: onExplainCounting) {
          HStack(spacing: Tokens.Spacing.tight) {
            Image(systemName: "questionmark.circle")
            Text("How sets are counted")
          }
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.accent)
        }
        .buttonStyle(.plain)
        .frame(minHeight: Tokens.minimumTapTarget)
      }
    }
  }

  // MARK: - Trained

  private var trainedSection: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text("Where the work went")
        .font(Tokens.Text.label.weight(.semibold))

      // No goal line, so the scale is the report's own maximum. Stated in the caption rather than
      // left for the user to assume it means something absolute.
      Text("Bars are relative to your biggest muscle this week. There is no target line, because no weekly set target is established.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)

      ForEach(trained, id: \.muscle) { row in
        bar(for: row)
      }
    }
  }

  private struct Row: Hashable {
    let muscle: Muscle
    let sets: Double
  }

  private var trained: [Row] {
    Muscle.allCases
      .map { Row(muscle: $0, sets: report.sets(for: $0)) }
      .filter { $0.sets > 0 }
      .sorted { $0.sets > $1.sets }
  }

  private var maxSets: Double {
    max(trained.first?.sets ?? 1, 1)
  }

  private func bar(for row: Row) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      HStack(alignment: .firstTextBaseline) {
        Text(ExercisePickerView.displayName(MuscleKey(row.muscle)))
          .font(Tokens.Text.label)
        Spacer(minLength: Tokens.Spacing.snug)
        // The "≥" is load-bearing, not decorative.
        Text("\(report.isLowerBound ? "≥ " : "")\(Self.format(row.sets))")
          .font(Tokens.Text.label)
          .monospacedDigit()
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Tokens.Color.surface)
          RoundedRectangle(cornerRadius: 4)
            .fill(Tokens.Color.accent)
            .frame(width: max(2, proxy.size.width * row.sets / maxSets))
        }
      }
      .frame(height: 10)
      // A muscle outside the studied corpus gets a quieter claim, because the count means less.
      if row.muscle.tier == .counted {
        Text("counted, not modelled")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
    .padding(.vertical, Tokens.Spacing.tight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(ExercisePickerView.displayName(MuscleKey(row.muscle))), "
        + "\(report.isLowerBound ? "at least " : "")\(Self.format(row.sets)) sets"
    )
  }

  // MARK: - Gaps

  private var gapsSection: some View {
    let gaps = report.untrainedMuscles(excluding: excludedFromGaps)
    return Group {
      if !gaps.isEmpty {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text("Nothing logged for")
            .font(Tokens.Text.label.weight(.semibold))
          // A gap is a fact, not a verdict. No "you should", no red.
          Text("These had no sets this week. Whether that matters depends on your plan.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)

          FlowLayout(spacing: Tokens.Spacing.snug) {
            ForEach(gaps, id: \.self) { muscle in
              Text(ExercisePickerView.displayName(MuscleKey(muscle)))
                .font(Tokens.Text.caption)
                .padding(.horizontal, Tokens.Spacing.snug)
                .padding(.vertical, Tokens.Spacing.tight)
                .background(Tokens.Color.surface, in: Capsule())
                .foregroundStyle(Tokens.Color.textSecondary)
            }
          }
        }
      }
    }
  }

  static func format(_ sets: Double) -> String {
    sets == sets.rounded() ? String(Int(sets)) : String(format: "%.1f", sets)
  }
}

/// Wraps chips onto as many lines as they need.
///
/// Hand-rolled because `LazyVGrid` with a fixed column count leaves ragged gaps for
/// variable-width text, and the gap list is exactly variable-width text.
struct FlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > width, x > 0 {
        x = 0
        y += lineHeight + spacing
        lineHeight = 0
      }
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: proposal.width ?? x, height: y + lineHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += lineHeight + spacing
        lineHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}

#if DEBUG
  #Preview("Weekly volume") {
    VolumeReportView(
      report: MuscleVolumeReport(
        fractionalSets: [
          MuscleKey(.chest): 12, MuscleKey(.lats): 9, MuscleKey(.quadriceps): 8,
          MuscleKey(.triceps): 6.5, MuscleKey(.biceps): 6, MuscleKey(.upperBack): 5,
          MuscleKey(.frontDelts): 4, MuscleKey(.hamstrings): 3, MuscleKey(.glutes): 3,
          MuscleKey(.sideDelts): 2,
        ],
        hardSets: 34,
        unattributedHardSets: 3,
        setsTouchingGroup: [.chest: 12, .back: 14, .legs: 11, .arms: 12, .shoulders: 6]
      ),
      excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
      onExplainCounting: {}
    )
  }
#endif
