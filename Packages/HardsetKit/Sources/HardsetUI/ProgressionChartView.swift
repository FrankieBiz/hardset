import Charts
import HardsetCore
import SwiftUI

/// What a series plots. Load is always available; the estimate is not.
public enum ProgressionMetric: String, Sendable, CaseIterable, Hashable {
  case heaviestLoad
  case estimatedOneRepMax

  public var label: String {
    switch self {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Est. 1RM"
    }
  }
}

/// One exercise's load history, one line per machine.
///
/// The whole point of this chart is the thing most lifting apps get wrong: it does **not** merge
/// machines. A single line through a leg press at one gym and a different leg press at another
/// draws progress the lifter did not make, or a decline they did not suffer. Each machine is its
/// own line, and every switch between them is annotated with a sentence saying the load difference
/// is a property of the equipment rather than of the lifter.
///
/// It also refuses to plot what it cannot estimate. A history of twenty-rep sets has no
/// one-rep-max estimate at all, and the chart says so rather than drawing a flat line at zero.
///
/// Machines are told apart by colour *and* point shape, and named in a legend drawn in the app's
/// own type, so two lines are never distinguished by hue alone.
public struct ProgressionChartView: View {
  private let series: [SeriesInput]
  private let machineChanges: [MachineChange]
  private let unit: WeightUnit
  private let onExplain: (() -> Void)?
  @State private var metric: ProgressionMetric = .heaviestLoad
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Grows with the axis labels, so larger text does not squeeze the plot itself.
  @ScaledMetric(relativeTo: .footnote) private var plotHeight: CGFloat = 220

  /// A series plus the label the store resolved for it, so this view does no lookups.
  public struct SeriesInput: Identifiable, Hashable, Sendable {
    public let label: String
    public let points: [ProgressionPoint]
    public var id: String { label }

    public init(label: String, points: [ProgressionPoint]) {
      self.label = label
      self.points = points
    }
  }

  public init(
    series: [SeriesInput],
    machineChanges: [MachineChange] = [],
    unit: WeightUnit,
    onExplain: (() -> Void)? = nil
  ) {
    self.series = series
    self.machineChanges = machineChanges
    self.unit = unit
    self.onExplain = onExplain
  }

  public var body: some View {
    let plotted = Self.plotted(series)
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      if plotted.isEmpty {
        HardsetEmptyState(
          title: "No history yet",
          detail: "Log this movement a few times and its load history appears here.",
          systemImage: "chart.xyaxis.line"
        )
      } else {
        HardsetSegmentedControl(
          selection: $metric,
          segments: ProgressionMetric.allCases.map { HardsetSegment($0.label, value: $0) }
        )

        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
          metricHeader
          if isUnevaluated {
            // Says why there is no line instead of drawing nothing and letting the user guess.
            UnevaluatedReadout(
              explanation: "No estimate is available. A one-rep max is only estimated from sets "
                + "of twelve reps or fewer, and none of these sessions qualify."
            )
          } else {
            chart(plotted)
          }
          Rectangle()
            .fill(Tokens.Color.border)
            .frame(height: Tokens.Stroke.hairline)
            .accessibilityHidden(true)
          legend(plotted)
        }
        .padding(Tokens.Spacing.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hardsetCard()

        if !machineChanges.isEmpty {
          machineChangeNotes
        }

        if let onExplain {
          Button(action: onExplain) {
            Label("How this is measured", systemImage: "questionmark.circle")
          }
          .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
          // The quiet style insets its label; pulling it back aligns the words with the content
          // edge while the full 44 pt region stays tappable.
          .padding(.leading, -Tokens.Spacing.snug)
        }
      }
    }
  }

  // MARK: - Metric header

  /// What is plotted, in which unit, and how far to trust it -- the certainty sits beside the
  /// metric it qualifies, not in a footnote.
  private var metricHeader: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.snug))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.regular))
    return layout {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(metricTitle)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Text("Best per session, in \(unit.abbreviation). One line per machine.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      certaintyBadge
    }
  }

  private var metricTitle: String {
    switch metric {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Estimated one-rep max"
    }
  }

  @ViewBuilder private var certaintyBadge: some View {
    switch metric {
    case .heaviestLoad:
      CertaintyBadge(
        level: .high,
        methodology: "Verified empirical load logged in active sessions on this specific machine.",
        citation: "Exact weight recorded by user"
      )
    case .estimatedOneRepMax:
      // Moderate when there is an estimate to qualify. With none, there is nothing to be moderately
      // sure of, and the badge says so rather than vouching for an empty chart.
      CertaintyBadge(
        level: hasNoEstimates ? .unevaluated : .moderate,
        methodology: ProgressionAnalyzer.source.methodology,
        citation: ProgressionAnalyzer.source.validRange
      )
    }
  }

  // MARK: - Chart

  private func chart(_ plotted: [PlottedSeries]) -> some View {
    let names = plotted.map(\.name)
    let colours = plotted.map { Self.colour(at: $0.index) }
    let shapes = plotted.map { Self.symbol(at: $0.index) }
    // Resolved once, outside the axis and annotation builders, so those closures capture plain
    // values rather than reaching back into the token namespace.
    let caveat = Tokens.Color.warning
    let grid = Tokens.Color.border
    let axisText = Tokens.Color.textSecondary
    let axisFont = Tokens.Text.caption
    let lineWidth = Tokens.Stroke.selected
    let gridWidth = Tokens.Stroke.hairline

    return Chart {
      ForEach(plotted) { entry in
        ForEach(plottable(entry.points)) { point in
          LineMark(
            x: .value("Date", point.date),
            y: .value(metric.label, value(point)),
            series: .value("Machine", entry.name)
          )
          .foregroundStyle(by: .value("Machine", entry.name))
          .lineStyle(StrokeStyle(lineWidth: lineWidth))
          PointMark(
            x: .value("Date", point.date),
            y: .value(metric.label, value(point))
          )
          .foregroundStyle(by: .value("Machine", entry.name))
          .symbol(by: .value("Machine", entry.name))
        }
      }
      // A switch is drawn on the chart, not just described below it, so the eye meets the caveat
      // at the same moment it meets the discontinuity. Two points wide and dashed, so it survives
      // glare and cannot be mistaken for a machine's line.
      ForEach(machineChanges) { change in
        RuleMark(x: .value("Machine change", change.date))
          .foregroundStyle(caveat)
          .lineStyle(StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
          .annotation(position: .top, alignment: .leading) {
            Image(systemName: "arrow.triangle.branch")
              .font(axisFont)
              .foregroundStyle(caveat)
          }
      }
    }
    // Explicit scales rather than the automatic palette: each machine gets a measured series
    // colour and its own point shape, in legend order.
    .chartForegroundStyleScale(domain: names, range: colours)
    .chartSymbolScale(domain: names, range: shapes)
    .chartLegend(.hidden)
    .chartXAxis {
      AxisMarks { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: gridWidth))
          .foregroundStyle(grid)
        AxisValueLabel()
          .font(axisFont)
          .foregroundStyle(axisText)
      }
    }
    .chartYAxis {
      AxisMarks { _ in
        AxisGridLine(stroke: StrokeStyle(lineWidth: gridWidth))
          .foregroundStyle(grid)
        AxisValueLabel()
          .font(axisFont)
          .foregroundStyle(axisText)
      }
    }
    .frame(height: plotHeight)
  }

  // MARK: - Legend

  /// One row per machine: its line-and-point glyph, its name, and its latest value for the
  /// selected metric. Drawn here rather than by Charts so it uses the app's type and contrast, and
  /// so each row can be read aloud as one sentence.
  private func legend(_ plotted: [PlottedSeries]) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      ForEach(plotted) { entry in
        let latest = latestPoint(entry.points)
        HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
          legendGlyph(index: entry.index)
          Text(entry.name)
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textPrimary)
            .lineLimit(2)
          Spacer(minLength: Tokens.Spacing.snug)
          if let latest {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
              Text(Self.format(value(latest)))
                .font(Tokens.Text.figure)
                .foregroundStyle(Tokens.Color.textPrimary)
              Text(unit.abbreviation)
                .font(Tokens.Text.unit)
                .foregroundStyle(Tokens.Color.textSecondary)
            }
          } else {
            Text(emptyValueText)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(legendLabel(entry, latest: latest))
      }
    }
  }

  private func legendGlyph(index: Int) -> some View {
    let colour = Self.colour(at: index)
    return ZStack {
      Rectangle()
        .fill(colour)
        .frame(width: Tokens.Spacing.section, height: Tokens.Stroke.selected)
      Self.symbol(at: index)
        .fill(colour)
        .frame(width: Tokens.Spacing.regular, height: Tokens.Spacing.regular)
    }
    .frame(width: Tokens.Spacing.section, height: Tokens.Spacing.regular)
    .accessibilityHidden(true)
  }

  /// What a legend row says when its machine has nothing to plot for the selected metric.
  private var emptyValueText: String {
    switch metric {
    case .heaviestLoad: "No sessions"
    case .estimatedOneRepMax: "No estimate"
    }
  }

  private func legendLabel(_ entry: PlottedSeries, latest: ProgressionPoint?) -> String {
    let shape = Self.symbolNames[Self.symbolIndex(at: entry.index)]
    guard let latest else {
      return "\(entry.name), \(shape) points, \(emptyValueText.lowercased())"
    }
    let date = latest.date.formatted(.dateTime.day().month(.wide))
    // Spoken as an estimate when it is one, so the word travels with the number.
    let kind = metric == .estimatedOneRepMax ? "latest estimate" : "latest"
    return "\(entry.name), \(shape) points, \(kind) \(Self.format(value(latest))) "
      + "\(unit.abbreviation) on \(date)"
  }

  // MARK: - Machine changes

  private var machineChangeNotes: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Machine changes", count: machineChanges.count)
      ForEach(machineChanges) { change in
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
          Image(systemName: "arrow.triangle.branch")
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.warning)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            Text(change.date, format: .dateTime.day().month(.abbreviated).year())
              .font(Tokens.Text.figure)
              .foregroundStyle(Tokens.Color.textPrimary)
            Text(change.explanation(in: unit))
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  // MARK: - Data

  /// One series as drawn: its position, which fixes its colour and shape, and a name that is
  /// unique within the chart.
  /// `nonisolated` for the same reason as `HardsetSegment`: its `id` is computed.
  private nonisolated struct PlottedSeries: Identifiable {
    let index: Int
    let name: String
    let points: [ProgressionPoint]
    var id: Int { index }
  }

  /// Gives every series a distinct name before it reaches Charts.
  ///
  /// Charts groups marks by the series value, so two machines that share a name -- two deleted
  /// machines are both "Unnamed machine", and two gyms can each have a "Leg press" -- would
  /// otherwise be joined into one line through two machines, which is the exact merge this chart
  /// exists to refuse. The second of a name is shown as "Leg press (2)".
  private static func plotted(_ series: [SeriesInput]) -> [PlottedSeries] {
    var used = Set<String>()
    var result: [PlottedSeries] = []
    for (index, input) in series.enumerated() {
      var name = input.label
      var ordinal = 1
      while used.contains(name) {
        ordinal += 1
        name = "\(input.label) (\(ordinal))"
      }
      used.insert(name)
      result.append(PlottedSeries(index: index, name: name, points: input.points))
    }
    return result
  }

  /// Points that actually have a value for the selected metric. An unestimable session is dropped
  /// from the estimate chart rather than plotted at zero.
  private func plottable(_ points: [ProgressionPoint]) -> [ProgressionPoint] {
    switch metric {
    case .heaviestLoad: points
    case .estimatedOneRepMax: points.filter { $0.bestEstimatedOneRepMaxKg != nil }
    }
  }

  private func latestPoint(_ points: [ProgressionPoint]) -> ProgressionPoint? {
    plottable(points).max { $0.date < $1.date }
  }

  private func value(_ point: ProgressionPoint) -> Double {
    switch metric {
    case .heaviestLoad: unit.fromKilograms(point.heaviestLoadKg)
    case .estimatedOneRepMax: unit.fromKilograms(point.bestEstimatedOneRepMaxKg ?? 0)
    }
  }

  private var hasNoEstimates: Bool {
    series.allSatisfy { input in
      input.points.allSatisfy { $0.bestEstimatedOneRepMaxKg == nil }
    }
  }

  /// True when the selected metric has nothing to plot for any machine.
  private var isUnevaluated: Bool {
    metric == .estimatedOneRepMax && hasNoEstimates
  }

  private static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }

  // MARK: - Series styling

  /// Point shapes in legend order. Paired with `Tokens.Color.series`, so a machine is identified
  /// by colour and shape together.
  private static let symbols: [BasicChartSymbolShape] = [.circle, .square, .triangle, .diamond]
  /// The same shapes as words, for the legend's spoken label.
  private static let symbolNames = ["circle", "square", "triangle", "diamond"]

  private static func colour(at index: Int) -> Color {
    let palette = Tokens.Color.series
    return palette[index % palette.count]
  }

  /// Steps one shape further each time the colours wrap, so the fifth machine is a cyan square
  /// rather than a second cyan circle. Colour and shape pairs stay distinct for sixteen machines.
  private static func symbol(at index: Int) -> BasicChartSymbolShape {
    symbols[symbolIndex(at: index)]
  }

  private static func symbolIndex(at index: Int) -> Int {
    (index + index / Tokens.Color.series.count) % symbols.count
  }
}

#if DEBUG
  private struct ProgressionPreviewHarness: View {
    let estimable: Bool
    let day = Date(timeIntervalSince1970: 13_000_000)

    private func point(_ n: Int, _ load: Double, _ estimate: Double?) -> ProgressionPoint {
      ProgressionPoint(
        sessionID: SessionID(), machineID: nil,
        date: day.addingTimeInterval(Double(n) * 604_800),
        heaviestLoadKg: load, bestEstimatedOneRepMaxKg: estimable ? estimate : nil,
        workingSets: 3
      )
    }

    var body: some View {
      ScrollView {
        ProgressionChartView(
          series: [
            .init(
              label: "Hammer Strength",
              points: [point(0, 100, 116), point(1, 105, 122), point(2, 110, 128)]
            ),
            .init(label: "Cybex", points: [point(3, 85, 99), point(4, 90, 105)]),
            // Same name as the first: drawn as its own line, never joined to it.
            .init(label: "Hammer Strength", points: [point(5, 95, nil), point(6, 97.5, 112)]),
          ],
          machineChanges: [
            MachineChange(
              date: day.addingTimeInterval(3 * 604_800),
              fromMachineID: MachineID(), toMachineID: MachineID(),
              heaviestLoadDeltaKg: -25
            )
          ],
          unit: .kilograms,
          onExplain: {}
        )
        .padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.background)
    }
  }

  #Preview("Three machines, one switch") {
    ProgressionPreviewHarness(estimable: true)
  }

  #Preview("No estimates") {
    ProgressionPreviewHarness(estimable: false)
  }

  #Preview("No history") {
    ProgressionChartView(series: [], unit: .pounds)
      .padding(Tokens.Spacing.loose)
      .background(Tokens.Color.background)
  }
#endif
