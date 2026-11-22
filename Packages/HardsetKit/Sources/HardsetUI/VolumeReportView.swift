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
  /// Muscles the catalogue cannot yet train directly. They are left out of "Nothing logged for", since
  /// a zero there would blame the lifter for a gap in the catalogue, and named in their own section
  /// instead, so they are neither blamed nor silently missing.
  private let excludedFromGaps: Set<Muscle>
  private let title: String?
  private let subtitle: String?
  private let onExplainCounting: (() -> Void)?
  private let period: String
  private let onShowSettings: (() -> Void)?
  private let onEarlier: (() -> Void)?
  private let onLater: (() -> Void)?
  /// Opens the working behind a muscle's count, from the figure on its row. `nil` where the screen
  /// has no working to show, and the figure is then plain text.
  private let onShowWorking: ((Muscle) -> Void)?

  public init(
    report: MuscleVolumeReport,
    excludedFromGaps: Set<Muscle> = [],
    title: String? = nil,
    subtitle: String? = nil,
    onExplainCounting: (() -> Void)? = nil,
    period: String = "in the last 7 days",
    onShowSettings: (() -> Void)? = nil,
    onEarlier: (() -> Void)? = nil,
    onLater: (() -> Void)? = nil,
    onShowWorking: ((Muscle) -> Void)? = nil
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
    self.onShowWorking = onShowWorking
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
            uncatalogedSection
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
      }
      .padding(.top, title == nil ? Tokens.Spacing.loose : 0)
      .padding(.bottom, Tokens.Spacing.block)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.canvas)
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
          .hardsetText(.hero)
          .foregroundStyle(Tokens.Color.chalk)
        Text(verbatim: "\(report.hardSets == 1 ? "working set" : "working sets") \(period)")
          .font(Tokens.Text.unit)
          .foregroundStyle(Tokens.Color.chalkDim)
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

  /// Says what is wrong, that it is not the lifter's miscount, and where the part that can be fixed
  /// is fixed. Shared with the deep muscle map, so the two screens give the same reason.
  ///
  /// A movement the lifter made, or one a workout import created, gets its muscles from a body part
  /// set in Library, on the Train tab. The message points at that one place for both.
  static func lowerBoundMessage(unattributed: Int) -> String {
    let lead =
      unattributed == 1
      ? "1 working set is on a movement with no muscles recorded, so it counts toward no muscle."
      : "\(unattributed) working sets are on movements with no muscles recorded, so they count toward no muscle."
    return lead + " Every count below is at least this much, not exactly this much. "
      + "Set a body part for these movements in Library, on the Train tab. Imported movements are listed there too."
  }

  // MARK: - Trained

  private func trainedSection(_ rows: [Row]) -> some View {
    let maxSets = max(rows.first?.sets ?? 1, 1)
    return VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        // The per-muscle figures are fractional credits (an indirect set counts 0.5), an adopted
        // convention rather than a measurement. The certainty is each muscle's own, below, from
        // where its count sits on the dose-response; the engine asserts nothing for the report as a
        // whole, so no badge speaks for it. The hero total above is an exact count and carries none.
        SectionLabel("Where the work went", count: rows.count)
        // No goal line, so the scale is the report's own maximum. Stated in the caption rather than
        // left for the user to assume it means something absolute.
        Text("Bars are relative to your biggest muscle \(period). There is no target line, because no weekly set target is established.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
        // What the badge beside each count is about, said once here in words, from the engine's own
        // sentence, so the deep muscle map and the counting disclosure say the same thing.
        Text(VolumeAnalyzer.certaintyMeaning)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
        if onShowWorking != nil {
          Text("Tap a count to see the sets it was worked from.")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        ForEach(rows, id: \.muscle) { row in
          bar(for: row, maxSets: maxSets)
        }
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
      .tourTarget(.volumeFigures)
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
    let figureSpoken =
      "\(report.isLowerBound ? "at least " : "")\(Self.format(row.sets)) sets"
    // With a control on the figure the figure is read once, by the control; the name block then
    // speaks only the name and what is not modelled.
    let spoken: String =
      (onShowWorking == nil ? "\(name), \(figureSpoken)" : name)
      + (isCounted ? ", counted, not modelled" : "")

    // The name, what is not modelled, and the figure are one spoken element, so the figure is read
    // with its muscle and the badge stays a control of its own.
    let nameBlock = VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(name)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.chalk)
      if isCounted {
        Text("Counted, not modelled")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spoken)
    let figureText = Text(value)
      .font(Tokens.Text.figure)
      .foregroundStyle(Tokens.Color.chalk)
    // A glyph beside the figure shows, without a gesture, that it opens the working behind it.
    let figure = Group {
      if let onShowWorking {
        Button {
          onShowWorking(row.muscle)
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
            figureText
            Image(systemName: WorkedFromSheet.glyph)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(InlineControlStyle(alignment: .trailing))
        // Begins with the figure the control shows, so a Voice Control user can say what they see.
        .accessibilityLabel("\(figureSpoken), \(name)")
        .accessibilityHint("Shows the sets this count was worked from")
      } else {
        figureText.accessibilityHidden(true)
      }
    }
    // Where this muscle's count sits on the published dose-response, as the engine states it:
    // moderate inside the studied range, low beyond it, and not evaluated for a muscle outside the
    // corpus. Never a level chosen here.
    let badge = MuscleCertaintyBadge(muscle: row.muscle, fractionalSets: row.sets)

    return VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      // One line when the name, its certainty and the figure fit, which they do at ordinary sizes;
      // otherwise the certainty drops under the name so nothing is squeezed or cut.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: Tokens.Spacing.snug) {
          nameBlock
          badge
          Spacer(minLength: Tokens.Spacing.snug)
          figure
        }
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          HStack(alignment: .top, spacing: Tokens.Spacing.snug) {
            nameBlock
            Spacer(minLength: Tokens.Spacing.snug)
            figure
          }
          badge
        }
      }
      track(fraction: CGFloat(row.sets / maxSets), isCounted: isCounted)
    }
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
          .fill(Tokens.Color.steelRaised)
        Group {
          if isCounted {
            Rectangle()
              .fill(Tokens.Color.plateBlueSurface)
              .overlay(
                Rectangle()
                  .strokeBorder(Tokens.Color.plateBlue, lineWidth: Tokens.Stroke.hairline)
              )
          } else {
            Rectangle()
              .fill(Tokens.Color.plateBlue)
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
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
          }

          // Tags, not chips: a fill and no control border, because none of them does anything
          // when tapped and none of them should look as if it might. The shared tag also carries
          // the accessibility-size radius and wrapping policy.
          FlowLayout(spacing: Tokens.Spacing.snug) {
            ForEach(gaps, id: \.self) { muscle in
              HardsetTag(ExercisePickerView.displayName(MuscleKey(muscle)))
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  // MARK: - Muscles the catalogue cannot train directly yet

  /// The muscles the caller excluded that have nothing credited in this window, named with the
  /// reason, in the place the gap list would otherwise leave them out without a word. A muscle that
  /// did get credit appears among the trained rows instead.
  private var uncatalogedSection: some View {
    let muscles = Muscle.allCases.filter { excludedFromGaps.contains($0) && report.sets(for: $0) == 0 }
    return Group {
      if !muscles.isEmpty {
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            SectionLabel("Not counted directly yet", count: muscles.count)
            Text(UncatalogedMuscleCopy.explanation)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          FlowLayout(spacing: Tokens.Spacing.snug) {
            ForEach(muscles, id: \.self) { muscle in
              HardsetTag(ExercisePickerView.displayName(MuscleKey(muscle)))
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  static func format(_ sets: Double) -> String {
    sets.formatted(.number.precision(.fractionLength(0...1)))
  }
}

/// What the volume report and the deep muscle map say about the muscles the catalogue has no movement
/// for yet, so the two screens give the same reason. A zero there is the catalogue's gap, not the
/// lifter's, and the words say so.
enum UncatalogedMuscleCopy {
  /// Under the list of those muscles. "Only indirect credit" is exact: a few movements credit one of
  /// them at half a set, and none credits it as a main muscle.
  static let explanation =
    "No built-in movement trains these directly yet, so only indirect credit (half a set) can count "
    + "toward them. This is a gap in the catalogue, not in your training. A movement you make "
    + "yourself can credit them."

  /// On a tile with nothing credited.
  static let tile = "No built-in movement trains this directly yet"
}

/// The certainty beside one muscle's weekly count, drawn the same on every screen that shows one.
///
/// It reads `VolumeAnalyzer.doseResponse`, the engine's one rule for where a count sits on the
/// published research, and states nothing of its own. The volume rows and the deep muscle map both
/// draw it, so the same count cannot carry two answers, and what it is about is said once in words
/// by `VolumeAnalyzer.certaintyMeaning`.
struct MuscleCertaintyBadge: View {
  let muscle: Muscle
  let fractionalSets: Double

  var body: some View {
    let claim = VolumeAnalyzer.doseResponse(fractionalSets: fractionalSets, for: muscle)
    CertaintyBadge(
      level: CertaintyLevel(claim.certainty),
      methodology: claim.source.methodology,
      citation: claim.source.citation
    )
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
