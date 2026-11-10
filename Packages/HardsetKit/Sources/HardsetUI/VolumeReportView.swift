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
///
/// When given a `title`, the view draws its own `ScreenHeader` as the first thing in its scroll
/// content, because the tab that hosts it hides the stock navigation bar.
///
/// The window is a rolling seven days, not a calendar week, and the copy says so: `period` is the
/// phrase every sentence uses ("in the last 7 days"), so a Monday morning never reads as "this
/// week". `onEarlier` and `onLater` step the window back and forward a week at a time.
public struct VolumeReportView: View {
  private let report: MuscleVolumeReport
  private let excludedFromGaps: Set<Muscle>
  private let title: String?
  private let subtitle: String?
  private let onExplainCounting: (() -> Void)?
  private let period: String
  private let onShowSettings: (() -> Void)?
  private let onEarlier: (() -> Void)?
  private let onLater: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    report: MuscleVolumeReport,
    excludedFromGaps: Set<Muscle> = [],
    title: String? = nil,
    subtitle: String? = nil,
    onExplainCounting: (() -> Void)? = nil,
    period: String = "in the last 7 days",
    onShowSettings: (() -> Void)? = nil,
    onEarlier: (() -> Void)? = nil,
    onLater: (() -> Void)? = nil
  ) {
    self.report = report
    self.excludedFromGaps = excludedFromGaps
    self.title = title
    self.subtitle = subtitle
    self.onExplainCounting = onExplainCounting
    self.period = period
    self.onShowSettings = onShowSettings
    self.onEarlier = onEarlier
    self.onLater = onLater
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        if let title {
          ScreenHeader(title, subtitle: subtitle) {
            if let onShowSettings {
              HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings)
            }
          }
        }
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          if onEarlier != nil || onLater != nil {
            windowControls
          }
          if report.hardSets == 0 {
            HardsetEmptyState(
              title: "Nothing logged \(period)",
              detail: "Sets per muscle appear here once you log a workout.",
              systemImage: "chart.bar"
            )
          } else {
            header
            trainedSection(trained)
            gapsSection
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
      }
      .padding(.top, title == nil ? Tokens.Spacing.loose : 0)
      .padding(.bottom, Tokens.Spacing.block)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.background)
  }

  // MARK: - Window

  /// Steps the rolling window a week at a time. "Later" is disabled, not hidden, on the newest
  /// window, so the pair never moves under the lifter's thumb.
  private var windowControls: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      Button {
        onEarlier?()
      } label: {
        Label("Earlier", systemImage: "chevron.left")
      }
      .buttonStyle(HardsetButtonStyle(.secondary, fullWidth: false))
      .disabled(onEarlier == nil)
      .accessibilityLabel("Earlier 7 days")
      Spacer(minLength: Tokens.Spacing.snug)
      Button {
        onLater?()
      } label: {
        HStack(spacing: Tokens.Spacing.tight) {
          Text("Later")
          Image(systemName: "chevron.right").accessibilityHidden(true)
        }
      }
      .buttonStyle(HardsetButtonStyle(.secondary, fullWidth: false))
      .disabled(onLater == nil)
      .accessibilityLabel("Later 7 days")
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      // The total is exact even when the per-muscle figures are not: unattributed sets are still
      // working sets, they just cannot be credited to a muscle. So no "≥" here.
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text(report.hardSets, format: .number)
          .font(Tokens.Text.hero)
          .foregroundStyle(Tokens.Color.textPrimary)
        Text(verbatim: "\(report.hardSets == 1 ? "working set" : "working sets") \(period)")
          .font(Tokens.Text.unit)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text("^[\(report.hardSets) working set](inflect: true) \(period)"))

      // The lower-bound statement is not a footnote. If some sets could not be attributed, every
      // number below is a floor, and saying so is the whole point of the coverage field.
      if report.isLowerBound {
        HardsetBanner(
          .caveat,
          title: "Counts below are lower bounds",
          message: Self.lowerBoundMessage(unattributed: report.unattributedHardSets)
        )
      }

      if let onExplainCounting {
        Button(action: onExplainCounting) {
          Label("How sets are counted", systemImage: "questionmark.circle")
        }
        .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
        // The quiet style insets its label; pulling it back aligns the words with the content
        // edge while the full 44 pt region stays tappable.
        .padding(.leading, -Tokens.Spacing.snug)
      }
    }
  }

  static func lowerBoundMessage(unattributed: Int) -> String {
    let lead =
      unattributed == 1
      ? "1 of those is on an exercise with no muscles recorded"
      : "\(unattributed) of those are on exercises with no muscles recorded"
    return lead + ", so every count below is at least this much — not exactly this much."
  }

  // MARK: - Trained

  private func trainedSection(_ rows: [Row]) -> some View {
    let maxSets = max(rows.first?.sets ?? 1, 1)
    return VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        // The per-muscle figures are fractional credits (an indirect set counts 0.5), an adopted
        // convention rather than a measurement, so their certainty sits beside them. The hero total
        // above is an exact count and carries none.
        let layout =
          dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
          : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.regular))
        layout {
          SectionLabel("Where the work went", count: rows.count)
          CertaintyBadge(
            level: .moderate,
            methodology: SetCounting.source.methodology,
            citation: SetCounting.source.citation
          )
        }
        // No goal line, so the scale is the report's own maximum. Stated in the caption rather than
        // left for the user to assume it means something absolute.
        Text("Bars are relative to your biggest muscle \(period). There is no target line, because no weekly set target is established.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        ForEach(rows, id: \.muscle) { row in
          bar(for: row, maxSets: maxSets)
        }
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
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

  private func bar(for row: Row, maxSets: Double) -> some View {
    let name = ExercisePickerView.displayName(MuscleKey(row.muscle))
    // A muscle outside the studied corpus gets a quieter claim, because the count means less.
    let isCounted = row.muscle.tier == .counted
    // The "≥" is load-bearing, not decorative.
    let value = (report.isLowerBound ? "≥ " : "") + Self.format(row.sets)
    let spoken: String =
      "\(name), \(report.isLowerBound ? "at least " : "")\(Self.format(row.sets)) sets"
      + (isCounted ? ", counted, not modelled" : "")

    return VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(name)
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textPrimary)
          if isCounted {
            Text("Counted, not modelled")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        Spacer(minLength: Tokens.Spacing.snug)
        Text(value)
          .font(Tokens.Text.figure)
          .foregroundStyle(Tokens.Color.textPrimary)
      }
      track(fraction: CGFloat(row.sets / maxSets), isCounted: isCounted)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spoken)
  }

  /// The bar itself: a raised track with a readout-cyan fill, square-ended like a gauge.
  ///
  /// A modelled muscle's fill is solid. A counted one is drawn hollow -- a cyan outline over the
  /// accent tint -- so the weaker claim reads as weaker without a second hue, and certainly without
  /// an evaluative one. The words "Counted, not modelled" carry the same meaning beside it.
  private func track(fraction: CGFloat, isCounted: Bool) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Tokens.Color.surfaceRaised)
        Group {
          if isCounted {
            Rectangle()
              .fill(Tokens.Color.accentSurface)
              .overlay(
                Rectangle()
                  .strokeBorder(Tokens.Color.accent, lineWidth: Tokens.Stroke.hairline)
              )
          } else {
            Rectangle()
              .fill(Tokens.Color.accent)
          }
        }
        // Never narrower than the bar is tall, so the smallest real count is still a visible mark.
        .frame(width: max(Tokens.Spacing.snug, proxy.size.width * fraction))
      }
    }
    .frame(height: Tokens.Spacing.snug)
    .accessibilityHidden(true)
  }

  // MARK: - Gaps

  private var gapsSection: some View {
    let gaps = report.untrainedMuscles(excluding: excludedFromGaps)
    return Group {
      if !gaps.isEmpty {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            SectionLabel("Nothing logged for", count: gaps.count)
            // A gap is a fact, not a verdict. No "you should", no red. When some sets could not be
            // attributed, "no sets" would overclaim: the muscle may have been trained by one of them.
            Text(
              report.isLowerBound
                ? "No sets were credited to these \(period). Some sets could not be attributed to "
                  + "a muscle, so any of these may still have been trained."
                : "These had no sets \(period). Whether that matters depends on your plan."
            )
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          // Tags, not chips: a fill and no control border, because none of them does anything
          // when tapped and none of them should look as if it might.
          FlowLayout(spacing: Tokens.Spacing.snug) {
            ForEach(gaps, id: \.self) { muscle in
              Text(ExercisePickerView.displayName(MuscleKey(muscle)))
                .font(Tokens.Text.caption.weight(.medium))
                .foregroundStyle(Tokens.Color.textSecondary)
                .padding(.horizontal, Tokens.Spacing.snug)
                .padding(.vertical, Tokens.Spacing.tight)
                .background(
                  Tokens.Color.surfaceRaised,
                  in: RoundedRectangle(cornerRadius: Tokens.Radius.control / 2)
                )
            }
          }
          .accessibilityElement(children: .combine)
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
      title: "Volume",
      subtitle: "Last 7 days, 2 Nov to now",
      onExplainCounting: {},
      onShowSettings: {},
      onEarlier: {}
    )
  }

  #Preview("Fully attributed, no header") {
    VolumeReportView(
      report: MuscleVolumeReport(
        fractionalSets: [MuscleKey(.chest): 1],
        hardSets: 1,
        unattributedHardSets: 0,
        setsTouchingGroup: [.chest: 1]
      )
    )
  }

  #Preview("Nothing logged") {
    VolumeReportView(
      report: MuscleVolumeReport(
        fractionalSets: [:], hardSets: 0, unattributedHardSets: 0, setsTouchingGroup: [:]
      ),
      title: "Volume",
      subtitle: "Last 7 days, 2 Nov to now"
    )
  }
#endif
