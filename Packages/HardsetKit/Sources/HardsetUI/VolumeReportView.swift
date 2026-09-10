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
  /// `this week` for the current report, or `in this seven-day window` while browsing history.
  /// Every sentence that names the window reads this rather than assuming the report is current.
  private let periodDescription: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Bars grow once per visit to this screen, never again on scroll. Re-animating on every
  /// scroll-back is the one motion mistake worth naming, because it turns signal into noise.
  @State private var revealed = false

  public init(
    report: MuscleVolumeReport,
    excludedFromGaps: Set<Muscle> = [],
    periodDescription: String = "this week",
    onExplainCounting: (() -> Void)? = nil
  ) {
    self.report = report
    self.excludedFromGaps = excludedFromGaps
    self.periodDescription = periodDescription
    self.onExplainCounting = onExplainCounting
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        header
        if report.hardSets == 0 {
          UnavailableStateView(
            title: "Nothing logged \(periodDescription)",
            systemImage: "chart.bar",
            message: "Sets per muscle appear here once you log a workout."
          )
        } else {
          // Sets were logged but nothing could be attributed, so there are no bars to scale. The
          // heading and the "bars are relative to your biggest muscle" caption used to render over
          // an empty column; `gapsSection` already owns the wording for that case.
          if !trained.isEmpty {
            trainedSection
          }
          gapsSection
        }
      }
      .padding(.horizontal, Tokens.Spacing.edge)
      .padding(.vertical, Tokens.Spacing.regular)
    }
    .background(Tokens.Color.ground)
    .task {
      guard !revealed else { return }
      withAnimation(reduceMotion ? nil : Tokens.Motion.surface) { revealed = true }
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      Text(Self.workingSetText(report.hardSets, periodDescription: periodDescription))
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
          .frame(minHeight: Tokens.minimumTapTarget)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
      Text(
        "Bars are relative to your biggest muscle \(periodDescription). There is no target line, because no weekly set target is established."
      )
      .font(Tokens.Text.caption)
      .foregroundStyle(Tokens.Color.textSecondary)

      ForEach(Array(trained.enumerated()), id: \.element.muscle) { index, row in
        bar(for: row, index: index)
      }

      if trained.contains(where: { $0.muscle.tier == .counted }) {
        // Once, at the foot of the section, rather than under every affected bar. It was repeated
        // on seven of fifteen rows, and this app's own rule elsewhere is that an honest caveat
        // printed five times reads as noise and stops being read. The marker keeps it attached to
        // the rows it applies to; this says what the marker means.
        Text(
          "\(Self.countedMarker) Counted, not modelled \u{2014} these sit outside the corpus the "
            + "fractional credits come from, so the number is a tally rather than a model."
        )
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Tokens.Spacing.tight)
      }
    }
  }

  /// Marks a bar whose count is a tally rather than a modelled credit.
  ///
  /// Visual shorthand only: it is never the sole carrier of the caveat, because a dagger read aloud
  /// is meaningless. Every marked row says "counted, not modelled" in its accessibility label.
  static let countedMarker = "\u{2020}"

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

  private func barWidth(in total: CGFloat, sets: Double) -> CGFloat {
    guard revealed || reduceMotion else { return 0 }
    return max(2, total * sets / maxSets)
  }

  /// Capped rather than escapable: at 40 ms a row a twenty-muscle week would stagger well past the
  /// motion budget, so the total delay is bounded instead of needing a skip affordance.
  private func revealAnimation(index: Int) -> Animation? {
    guard !reduceMotion else { return nil }
    return Tokens.Motion.surface.delay(min(Double(index) * 0.04, 0.28))
  }

  private func bar(for row: Row, index: Int) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      HStack(alignment: .firstTextBaseline) {
        Text(ExercisePickerView.displayName(MuscleKey(row.muscle)))
          .font(Tokens.Text.label)
        Spacer(minLength: Tokens.Spacing.snug)
        // The "≥" is load-bearing, not decorative.
        Text(
          "\(report.isLowerBound ? "≥ " : "")\(Self.format(row.sets))"
            + (row.muscle.tier == .counted ? Self.countedMarker : "")
        )
        .font(Tokens.Text.label)
        .monospacedDigit()
        .foregroundStyle(Tokens.Color.textSecondary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: Tokens.Radius.bar)
            .fill(Tokens.Color.surface)
          RoundedRectangle(cornerRadius: Tokens.Radius.bar)
            .fill(Tokens.Color.accent)
            // The value animates, not a scaleEffect: a scaled bar carries a distorted corner
            // radius and would drag its label with it.
            .frame(width: barWidth(in: proxy.size.width, sets: row.sets))
        }
      }
      .frame(height: 10)
      .animation(revealAnimation(index: index), value: revealed)
    }
    .padding(.vertical, Tokens.Spacing.tight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(ExercisePickerView.displayName(MuscleKey(row.muscle))), "
        + "\(report.isLowerBound ? "at least " : "")\(Self.spokenSetCount(row.sets))"
        // Spoken, not implied by a dagger. The old per-row caption was never in this label at all,
        // so the caveat has been invisible to VoiceOver for as long as it has existed.
        + (row.muscle.tier == .counted ? ". Counted, not modelled." : "")
    )
  }

  // MARK: - Gaps

  private var gapsSection: some View {
    let gaps = report.untrainedMuscles(excluding: excludedFromGaps)
    // Nothing at all could be attributed, so "credited nothing" is true of every muscle and means
    // nothing. Listing all twenty-two as gaps read as "you trained nothing this week" when the
    // truth was "the app could not tell what you trained" -- a confident negative claim built out
    // of missing data, which is the one thing this report exists not to do.
    let nothingAttributed = report.hardSets > 0 && report.coverage == 0
    return Group {
      if nothingAttributed {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text("Where the work went is unknown")
            .font(Tokens.Text.label.weight(.semibold))
          Text(
            "\(Self.setCountText(report.hardSets)) logged \(periodDescription), and none of them could be "
              + "matched to a muscle. That is a gap in the app's movement data, not in your training."
          )
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
          .fixedSize(horizontal: false, vertical: true)
        }
      } else if !gaps.isEmpty {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text("Nothing logged for")
            .font(Tokens.Text.label.weight(.semibold))
          // A gap is a fact, not a verdict. No "you should", no red.
          Text("These had no sets \(periodDescription). Whether that matters depends on your plan.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
          if report.isLowerBound {
            // "Credited nothing" is not "not trained". Some sets could not be attributed, so a
            // muscle below may have been trained by one of them, and the list is a maximum.
            Text(
              "\(Self.setCountText(report.unattributedHardSets)) \(periodDescription) could not be matched "
                + "to a muscle, so some of these may have been trained after all."
            )
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.certainty(.low))
            .fixedSize(horizontal: false, vertical: true)
          }

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

  /// Formatted through the locale rather than `String(format: "%.1f")`, which writes a POSIX point
  /// whatever the reader's decimal separator is. The fraction-length range drops a trailing zero on
  /// its own, so a whole number still reads as one.
  static func format(_ sets: Double) -> String {
    sets.formatted(.number.precision(.fractionLength(0...1)))
  }

  static func workingSetText(_ count: Int, periodDescription: String) -> String {
    "\(count) working set\(count == 1 ? "" : "s") \(periodDescription)"
  }

  static func setCountText(_ count: Int) -> String {
    "\(count) set\(count == 1 ? "" : "s")"
  }

  /// The spoken form of a fractional set count. Separate from `setCountText` because credits are
  /// fractional and that helper takes an `Int`; the visible row prints the bare number, so this
  /// noun is VoiceOver's alone and was reading "1 sets".
  static func spokenSetCount(_ sets: Double) -> String {
    "\(format(sets)) set\(sets == 1 ? "" : "s")"
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
