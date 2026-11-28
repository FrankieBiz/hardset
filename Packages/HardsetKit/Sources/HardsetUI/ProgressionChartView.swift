import Charts
import HardsetCore
import SwiftUI

/// What a series plots. Load is always available; the estimate is not.
public enum ProgressionMetric: String, Sendable, CaseIterable, Hashable {
  case heaviestLoad
  case estimatedOneRepMax
  case repsAtTopLoad

  public var label: String {
    switch self {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Est. 1RM"
    case .repsAtTopLoad: "Reps at top weight"
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
  /// Opens the working behind a machine's latest estimated max, from the legend's figure. `nil`
  /// where the screen has no working to show, such as a preview, and the figure is then plain text.
  private let onShowEstimateWorking: ((ProgressionKey) -> Void)?
  /// Opens the working behind the record stars: the set that set each, what it beat and the rule.
  /// `nil` where the screen has none to show.
  private let onShowRecordWorking: (() -> Void)?
  /// `false` for movements whose logged load is not the load moved (bodyweight work), where no
  /// one-rep max is ever estimated. Says so instead of blaming the rep count.
  private let estimatesOneRepMax: Bool
  private let assumesAddedLoad: Bool
  @State private var metric: ProgressionMetric
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Grows with the axis labels, so larger text does not squeeze the plot itself.
  @ScaledMetric(relativeTo: .footnote) private var plotHeight: CGFloat = 220
  /// The axis labels' point size at the current Dynamic Type size (the caption role is Footnote), so
  /// the date axis can ask how many labels the width holds.
  @ScaledMetric(relativeTo: .footnote) private var axisPointSize: CGFloat = 13
  /// The chart's measured width, `0` until the first layout.
  @State private var chartWidth: CGFloat = 0

  /// A series plus the label the store resolved for it, so this view does no lookups.
  public struct SeriesInput: Identifiable, Hashable, Sendable {
    public let label: String
    public let points: [ProgressionPoint]
    /// The sessions in which this machine's line set a record, marked on it with a star.
    public let recordSessionIDs: Set<SessionID>
    /// The most reps at each weight this machine has seen, heaviest first, for the table beneath.
    public let bestAtWeight: [BestAtWeight]
    /// Which series this is, so a tap on its figure can ask for the working behind it. `nil` for a
    /// series built without one, such as a preview's.
    public let key: ProgressionKey?
    public var id: String { label }

    public init(
      label: String, points: [ProgressionPoint], recordSessionIDs: Set<SessionID> = [],
      bestAtWeight: [BestAtWeight] = [], key: ProgressionKey? = nil
    ) {
      self.label = label
      self.points = points
      self.recordSessionIDs = recordSessionIDs
      self.bestAtWeight = bestAtWeight
      self.key = key
    }
  }

  public init(
    series: [SeriesInput],
    machineChanges: [MachineChange] = [],
    unit: WeightUnit,
    estimatesOneRepMax: Bool = true,
    assumesAddedLoad: Bool = false,
    onExplain: (() -> Void)? = nil,
    onShowEstimateWorking: ((ProgressionKey) -> Void)? = nil,
    onShowRecordWorking: (() -> Void)? = nil
  ) {
    self.estimatesOneRepMax = estimatesOneRepMax && !assumesAddedLoad
    self.assumesAddedLoad = assumesAddedLoad
    self.series = series
    self.machineChanges = machineChanges
    self.unit = unit
    self.onExplain = onExplain
    self.onShowEstimateWorking = onShowEstimateWorking
    self.onShowRecordWorking = onShowRecordWorking
    self._metric = State(
      initialValue: assumesAddedLoad
        ? (ProgressionAnalyzer.hasNoAddedLoad(series.map(\.points)) ? .repsAtTopLoad : .heaviestLoad)
        : Self.opensOn(series: series, estimatesOneRepMax: estimatesOneRepMax))
  }

  /// The graph opens on the estimated max, because that is the line that rises when the lifter does
  /// more weight or more reps. It opens on the heaviest load when no estimate can be made: a history
  /// of high-rep sets, or bodyweight work, has no estimate to open on.
  private static func opensOn(series: [SeriesInput], estimatesOneRepMax: Bool) -> ProgressionMetric {
    guard estimatesOneRepMax,
      series.contains(where: { $0.points.contains { $0.bestEstimatedOneRepMaxKg != nil } })
    else { return .heaviestLoad }
    return .estimatedOneRepMax
  }

  public var body: some View {
    let plotted = Self.plotted(series)
    VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
      if plotted.isEmpty {
        HardsetEmptyState(
          title: "No history yet",
          detail: "Log this movement a few times and its load history appears here.",
          systemImage: "chart.xyaxis.line",
          style: .quiet
        )
      } else {
        metricSwitch

        if assumesAddedLoad {
          Text(ExerciseModality.unknownLoadAssumption)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
          Text(ProgressCopy.equipmentNotSet)
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
          metricHeader
          if isUnevaluated {
            // Says why there is no line instead of drawing nothing and letting the user guess.
            UnevaluatedReadout(explanation: unevaluatedExplanation)
          } else {
            chart(plotted)
          }
          Rectangle()
            .fill(Tokens.Color.hairline)
            .frame(height: Tokens.Stroke.hairline)
            .accessibilityHidden(true)
          legend(plotted)
          if plotted.contains(where: { !$0.recordSessionIDs.isEmpty }) {
            recordKey(plotted)
            if let onShowRecordWorking {
              WorkedFromButton(
                "Worked from these records", style: .inline, action: onShowRecordWorking)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if plotted.contains(where: { !$0.bestAtWeight.isEmpty }) {
          bestAtEachWeight(plotted)
        }

        if !machineChanges.isEmpty {
          machineChangeNotes
        }

        if let onExplain {
          Button(action: onExplain) {
            Label("How this is measured", systemImage: "questionmark.circle")
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.chalk)
          }
          .buttonStyle(InlineControlStyle(alignment: .leading))
        }
      }
    }
  }

  /// Estimated max leads, because it is where the graph opens; the heaviest load is the toggle.
  private var metricOrder: [ProgressionMetric] {
    assumesAddedLoad ? [.heaviestLoad, .repsAtTopLoad] : [.estimatedOneRepMax, .heaviestLoad]
  }

  private func metricLabel(_ metric: ProgressionMetric) -> String {
    metric == .heaviestLoad && assumesAddedLoad ? "Added load" : metric.label
  }

  private var metricUnit: String { metric == .repsAtTopLoad ? "reps" : unit.abbreviation }

  // MARK: - Metric switch

  /// Which metric is plotted, as words: the chosen one in `chalk` with a 2 pt rule under it, the
  /// other in `chalkDim`, as the rest bar marks its chosen length. The shared segmented control
  /// filled the chosen segment with `plateBlueFill`, which put a blue block on a screen that has no
  /// primary action to own an accent, and in the same blue as a second machine's line, so the
  /// selection read as a key to that series. The choice is carried by value and a mark, never a hue,
  /// and the `isSelected` trait says it to VoiceOver. Each choice is an inline control, so Increase
  /// Contrast and Button Shapes outline it. At accessibility sizes the choices stack, so a label
  /// that says which metric it is never truncates.
  private var metricSwitch: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tokens.Spacing.tight))
      : AnyLayout(HStackLayout(alignment: .center, spacing: Tokens.Spacing.section))
    return layout {
      ForEach(metricOrder, id: \.self) { option in
        let isSelected = option == metric
        Button {
          withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
            metric = option
          }
        } label: {
          Text(metricLabel(option))
            .hardsetText(.label, weight: .semibold)
            .foregroundStyle(isSelected ? Tokens.Color.chalk : Tokens.Color.chalkDim)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            .overlay(alignment: .bottom) {
              if isSelected {
                Rectangle()
                  .fill(Tokens.Color.chalk)
                  .frame(height: Tokens.Stroke.selected)
                  .offset(y: Tokens.Spacing.tight)
                  .accessibilityHidden(true)
              }
            }
        }
        .buttonStyle(InlineControlStyle(alignment: .leading))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Metric header

  /// What is plotted, in which unit, and how far to trust it -- the certainty sits beside the
  /// metric it qualifies, not in a footnote, as a phrase under the line that says what is plotted.
  private var metricHeader: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      Text(metricTitle)
        .font(Tokens.Text.headline)
        .foregroundStyle(Tokens.Color.chalk)
        .fixedSize(horizontal: false, vertical: true)
      Text("Best per session, in \(metricUnit). One line per machine.")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .fixedSize(horizontal: false, vertical: true)
      certaintyBadge
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var metricTitle: String {
    switch metric {
    case .heaviestLoad: assumesAddedLoad ? "Added load" : "Heaviest load"
    case .estimatedOneRepMax: "Estimated one-rep max"
    case .repsAtTopLoad: "Reps at the top weight"
    }
  }

  @ViewBuilder private var certaintyBadge: some View {
    if assumesAddedLoad {
      CertaintyBadge(
        level: .low, methodology: ExerciseModality.unknownLoadAssumption, style: .language)
    } else {
      switch metric {
      case .repsAtTopLoad:
        CertaintyBadge(
          level: .high, methodology: "The most reps logged at each session's top weight.",
          style: .language)
      case .heaviestLoad:
        // High only for the arithmetic of taking a maximum of what was entered. The load itself is
        // user-entered and not independently verified, which is what the receipt says too.
        CertaintyBadge(
          level: hasNoAddedLoad ? .unevaluated : .high,
          methodology: hasNoAddedLoad
            ? "No added load was recorded for these sets, so there is no load to chart."
            : "The heaviest load you entered in each session. Each machine is its own line; sets "
              + "with no machine recorded form a separate line.",
          citation: "User-entered load",
          style: .language
        )
      case .estimatedOneRepMax:
        // The weakest certainty among each line's latest estimate, from the reps behind it. With no
        // estimate there is nothing to be sure of, and the badge says so rather than vouching for an
        // empty chart.
        CertaintyBadge(
          level: MethodologySheet.level(
            for: ProgressionAnalyzer.estimateCertainty(latestOf: series.map(\.points))),
          methodology: ProgressionAnalyzer.source.methodology,
          citation: ProgressionAnalyzer.source.validRange,
          style: .language
        )
      }
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
    let recordColour = Tokens.Color.plateYellow
    let grid = Tokens.Color.hairline
    let axisText = Tokens.Color.chalkDim
    let axisFont = Tokens.Text.caption
    let lineWidth = Tokens.Stroke.selected
    let gridWidth = Tokens.Stroke.hairline
    let axis = DateAxisLayout(chartWidth: chartWidth, labelPointSize: axisPointSize)
    let dates = plotted.flatMap { plottable($0.points).map(\.date) }
    let firstDate = dates.min()
    let lastDate = dates.max()

    let styled = Chart {
      ForEach(plotted) { entry in
        ForEach(plottable(entry.points)) { point in
          LineMark(
            x: .value("Date", point.date),
            y: .value(metricLabel(metric), value(point)),
            series: .value("Machine", entry.name)
          )
          .foregroundStyle(by: .value("Machine", entry.name))
          .lineStyle(StrokeStyle(lineWidth: lineWidth))
          // One spoken element per session, on the line: the machine and the date, then the value
          // at the legend's precision with its unit, and the word "estimate" with its confidence
          // when it is one. Charts' automatic labels read the raw plotted number with no unit.
          .accessibilityLabel(pointLabel(entry, point))
          .accessibilityValue(pointValue(point, isRecord: entry.recordSessionIDs.contains(point.sessionID)))
          PointMark(
            x: .value("Date", point.date),
            y: .value(metricLabel(metric), value(point))
          )
          .foregroundStyle(by: .value("Machine", entry.name))
          .symbol(by: .value("Machine", entry.name))
          // The same session as the line mark above; read once, not twice.
          .accessibilityHidden(true)
          // A record is a fact the detector found, marked where it happened: a star, in the record
          // colour, over the machine's own point. The shape and the legend say what it means, so
          // the colour is never the only carrier.
          if entry.recordSessionIDs.contains(point.sessionID) {
            PointMark(
              x: .value("Date", point.date),
              y: .value(metricLabel(metric), value(point))
            )
            .symbol {
              Image(systemName: "star.fill")
                .font(axisFont)
                .foregroundStyle(recordColour)
            }
            .accessibilityHidden(true)
          }
        }
      }
      // A switch is drawn on the chart, not just described below it, so the eye meets the caveat
      // at the same moment it meets the discontinuity. Two points wide and dashed, so it survives
      // glare and cannot be mistaken for a machine's line.
      ForEach(machineChanges) { change in
        RuleMark(x: .value("Machine change", change.date))
          .foregroundStyle(caveat)
          .lineStyle(StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
          .accessibilityLabel("Machine change")
          .accessibilityValue(change.date.formatted(.dateTime.day().month(.wide).year()))
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
    // The newest point sat on the plot's trailing edge, leaving its date label no room, so it
    // collapsed to an ellipsis. Inset both ends by half a label, so the first and last dates read
    // in full whatever the text size.
    .chartXScale(range: .plotDimension(startPadding: axis.edgeInset, endPadding: axis.edgeInset))
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
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }

    // As many date labels as the width holds at this text size, four at most, each centred under
    // its tick. Charts starts a date label at its tick by default, so the newest date needed its
    // whole width past the last tick and truncated to "Nov…"; centred, it needs half, which the
    // scale's end padding provides. Where fewer than four fit, the ticks are placed evenly between
    // the first and last date rather than left to `desiredCount`, which is only a hint. Two
    // `chartXAxis` calls under an `if`, because the axis builder takes one kind of mark values.
    return Group {
      if let ticks = axis.ticks(from: firstDate, to: lastDate) {
        styled.chartXAxis {
          AxisMarks(values: ticks) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: gridWidth))
              .foregroundStyle(grid)
            // A day, said explicitly: these ticks sit at the sessions' time of day, and left to
            // choose, Charts labelled them "7:33:2…".
            AxisValueLabel(format: DateAxisLayout.labelFormat, anchor: .top)
              .font(axisFont)
              .foregroundStyle(axisText)
          }
        }
      } else {
        styled.chartXAxis {
          AxisMarks(values: .automatic(desiredCount: axis.tickCount)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: gridWidth))
              .foregroundStyle(grid)
            AxisValueLabel(anchor: .top)
              .font(axisFont)
              .foregroundStyle(axisText)
          }
        }
      }
    }
  }

  // MARK: - Legend

  /// One row per machine: its line-and-point glyph, its name, and its latest value for the
  /// selected metric. Drawn here rather than by Charts so it uses the app's type and contrast, and
  /// so each row can be read aloud as one sentence.
  private func legend(_ plotted: [PlottedSeries]) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      ForEach(plotted) { entry in
        let latest = latestPoint(entry.points)
        if let latest, let key = estimateWorkingKey(for: entry), let onShowEstimateWorking {
          legendRowWithWorking(entry, latest: latest) { onShowEstimateWorking(key) }
        } else {
          HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
            legendGlyph(index: entry.index)
            Text(entry.name)
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.chalk)
              .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Spacing.snug)
            if let latest {
              latestFigure(latest)
            } else {
              Text(emptyValueText)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.chalkDim)
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(legendLabel(entry, latest: latest))
        }
      }
      if onShowEstimateWorking != nil, plotted.contains(where: { estimateWorkingKey(for: $0) != nil }),
        !isUnevaluated
      {
        Text("Tap an estimate to see the sets it was worked from.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// A machine's latest value and its unit.
  private func latestFigure(_ latest: ProgressionPoint) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
      Text(valueText(latest))
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.chalk)
      Text(metricUnit)
        .font(Tokens.Text.unit)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
  }

  /// The series whose latest estimate can open its working: only the estimate view of a movement that
  /// estimates, for a series the screen identified.
  private func estimateWorkingKey(for entry: PlottedSeries) -> ProgressionKey? {
    guard metric == .estimatedOneRepMax, estimatesOneRepMax else { return nil }
    return entry.key
  }

  /// A legend row whose figure is a control. The machine and its point shape are one spoken element,
  /// and the figure is a button of its own that says what it opens, so the figure is read once. A
  /// glyph beside it shows, without a gesture, that it opens something.
  private func legendRowWithWorking(
    _ entry: PlottedSeries, latest: ProgressionPoint, action: @escaping () -> Void
  ) -> some View {
    let shape = Self.symbolNames[Self.symbolIndex(at: entry.index)]
    let date = latest.date.formatted(.dateTime.day().month(.wide))
    return HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        legendGlyph(index: entry.index)
        Text(entry.name)
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.chalk)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: Tokens.Spacing.snug)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(entry.name), \(shape) points")
      Button(action: action) {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
          latestFigure(latest)
          Image(systemName: WorkedFromSheet.glyph)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.chalkDim)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(InlineControlStyle(alignment: .trailing))
      // Begins with the words on the control, so a Voice Control user can say what they see.
      .accessibilityLabel(
        "\(valueText(latest)) \(metricUnit), latest estimate on \(date), \(entry.name)")
      .accessibilityHint("Shows the sets this estimate was worked from")
    }
  }

  /// The star's one-line key, shown only when a record is on the chart.
  private func recordKey(_ plotted: [PlottedSeries]) -> some View {
    HStack(spacing: Tokens.Spacing.regular) {
      Image(systemName: "star.fill")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.plateYellow)
        .frame(width: Tokens.Spacing.section)
        .accessibilityHidden(true)
      Text("A session that set a record")
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    .accessibilityElement(children: .combine)
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
    case .heaviestLoad: hasNoAddedLoad ? "No added load" : "No sessions"
    case .estimatedOneRepMax: "No estimate"
    case .repsAtTopLoad: "No sessions"
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
    return "\(entry.name), \(shape) points, \(kind) \(valueText(latest)) "
      + "\(metricUnit) on \(date)"
  }

  private func pointLabel(_ entry: PlottedSeries, _ point: ProgressionPoint) -> String {
    "\(entry.name), \(point.date.formatted(.dateTime.day().month(.wide).year()))"
  }

  private func pointValue(_ point: ProgressionPoint, isRecord: Bool) -> String {
    let figure = "\(valueText(point)) \(metricUnit)"
    let record = isRecord ? "record set" : nil
    guard metric == .estimatedOneRepMax else { return [figure, record].compactMap { $0 }.joined(separator: ", ") }
    let confidence = point.bestEstimateCertainty.map { MethodologySheet.level(for: $0).label }
    return [figure, "estimate", confidence, record].compactMap { $0 }.joined(separator: ", ")
  }

  // MARK: - Best at each weight

  /// For each machine, the most reps ever done at each weight it has seen and the day they were
  /// first reached: "90 lb · 12 reps · Nov 4". A table of facts from the sets, not an estimate, so it
  /// carries no certainty badge, and it is per machine because a weight on one machine is not a
  /// weight on another.
  private func bestAtEachWeight(_ plotted: [PlottedSeries]) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      SectionLabel("Best at each weight")
      ForEach(plotted.filter { !$0.bestAtWeight.isEmpty }) { entry in
        VStack(alignment: .leading, spacing: 0) {
          if plotted.count > 1 {
            Text(entry.name)
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.chalkDim)
              .padding(.bottom, Tokens.Spacing.tight)
          }
          ForEach(entry.bestAtWeight) { best in
            bestRow(best)
          }
        }
      }
    }
  }

  private func bestRow(_ best: BestAtWeight) -> some View {
    let weight = LoadText.entered(best.weightKg, in: unit)
    let reps = best.reps == 1 ? "1 rep" : "\(best.reps) reps"
    let date = best.achievedAt.formatted(.dateTime.month(.abbreviated).day().year())
    return HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
        Text(weight)
          .font(Tokens.Text.figure)
          .foregroundStyle(Tokens.Color.chalk)
        Text(unit.abbreviation)
          .font(Tokens.Text.unit)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
      Text(reps)
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.chalk)
      Spacer(minLength: Tokens.Spacing.regular)
      Text(date)
        .font(Tokens.Text.provenance)
        .foregroundStyle(Tokens.Color.chalkDim)
    }
    .padding(.vertical, Tokens.Spacing.snug)
    .overlay(alignment: .top) {
      Rectangle().fill(Tokens.Color.hairline).frame(height: Tokens.Stroke.hairline)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(weight) \(unit.abbreviation), \(reps), first reached \(date)")
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
              .foregroundStyle(Tokens.Color.chalk)
            Text(change.explanation(in: unit))
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.chalkDim)
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
    let recordSessionIDs: Set<SessionID>
    let bestAtWeight: [BestAtWeight]
    let key: ProgressionKey?
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
      result.append(
        PlottedSeries(
          index: index, name: name, points: input.points,
          recordSessionIDs: input.recordSessionIDs, bestAtWeight: input.bestAtWeight,
          key: input.key))
    }
    return result
  }

  /// Points that actually have a value for the selected metric. An unestimable session is dropped
  /// from the estimate chart rather than plotted at zero.
  private func plottable(_ points: [ProgressionPoint]) -> [ProgressionPoint] {
    switch metric {
    case .heaviestLoad, .repsAtTopLoad: points
    case .estimatedOneRepMax: points.filter { $0.bestEstimatedOneRepMaxKg != nil }
    }
  }

  /// `nil` when the selected metric has nothing to show, including a bodyweight line with no added
  /// load, so the legend says so instead of reading "0 kg".
  private func latestPoint(_ points: [ProgressionPoint]) -> ProgressionPoint? {
    guard !isUnevaluated else { return nil }
    return plottable(points).max {
      if $0.date != $1.date { return $0.date < $1.date }
      return $0.sessionID.rawValue.uuidString < $1.sessionID.rawValue.uuidString
    }
  }

  private func value(_ point: ProgressionPoint) -> Double {
    switch metric {
    case .heaviestLoad: unit.fromKilograms(point.heaviestLoadKg)
    case .repsAtTopLoad: Double(point.repsAtTopLoad)
    case .estimatedOneRepMax: unit.fromKilograms(point.bestEstimatedOneRepMaxKg ?? 0)
    }
  }

  private var hasNoEstimates: Bool {
    series.allSatisfy { input in
      input.points.allSatisfy { $0.bestEstimatedOneRepMaxKg == nil }
    }
  }

  /// Bodyweight work: every session recorded no added load, so a load line would sit flat at
  /// zero under a confident badge and say nothing.
  private var hasNoAddedLoad: Bool {
    ProgressionAnalyzer.hasNoAddedLoad(series.map(\.points))
  }

  /// True when the selected metric has nothing to plot for any machine.
  private var isUnevaluated: Bool {
    switch metric {
    case .repsAtTopLoad: series.allSatisfy { $0.points.isEmpty }
    case .heaviestLoad: hasNoAddedLoad
    case .estimatedOneRepMax: hasNoEstimates
    }
  }

  /// Why nothing is drawn, by cause. Blaming the rep count for pull-ups with no added load would
  /// be false.
  private var unevaluatedExplanation: String {
    if hasNoAddedLoad {
      return metric == .heaviestLoad
        ? "No added load was recorded for these sets, so there is no load to chart."
        : "No added load was recorded, so there is nothing to estimate from."
    }
    if metric == .estimatedOneRepMax && !estimatesOneRepMax {
      return "Body mass is not recorded with each set, so a one-rep max is not estimated for "
        + "bodyweight movements."
    }
    return "No estimate is available. A one-rep max is only estimated from sets "
      + "of twelve reps or fewer, and none of these sessions qualify."
  }

  /// An entered load keeps the precision it was entered with; an estimate is rounded the way
  /// estimates always are, so neither reads differently here than on the receipt or the logger.
  private func valueText(_ point: ProgressionPoint) -> String {
    switch metric {
    case .heaviestLoad: LoadText.entered(point.heaviestLoadKg, in: unit)
    case .repsAtTopLoad: "\(point.repsAtTopLoad)"
    case .estimatedOneRepMax: LoadText.estimate(point.bestEstimatedOneRepMaxKg ?? 0, in: unit)
    }
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
        workingSets: 3, bestEstimateCertainty: .moderate
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
      .background(Tokens.Color.canvas)
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
      .background(Tokens.Color.canvas)
  }
#endif

/// How many dates the movement chart's x axis can label at a given width and text size, and the
/// room to keep at each end so the first and last labels are drawn whole.
///
/// The plot grows vertically with Dynamic Type but is always as wide as the screen, so a fixed
/// four labels that fit at the default size overprint each other at accessibility sizes. A label is
/// estimated as `labelEms` of the axis font ("Nov 12"), a tick slot as a label and a gap, and the
/// count is how many slots fit between the two end insets. Plain values in and out, so the
/// arithmetic is tested without a chart.
struct DateAxisLayout: Equatable {
  /// The widest label as a multiple of the font's point size: "Nov 12" and its relatives.
  static let labelEms: CGFloat = 3.6
  /// What the y axis's labels take from the chart's width, in the same unit: a three-digit number.
  static let yAxisEms: CGFloat = 2.4
  /// Clear space kept between two neighbouring labels.
  static let gap: CGFloat = 12
  /// The width assumed before the chart has been measured: a 402 pt phone less the page margins.
  static let assumedWidth: CGFloat = 370
  static let maximumTicks = 4
  static let minimumTicks = 2
  static let minimumInset: CGFloat = 16

  /// How an evenly spaced tick is labelled: the month and day, "Nov 2".
  static let labelFormat = Date.FormatStyle().month(.abbreviated).day()

  let tickCount: Int
  /// Kept clear at each end of the x axis: half a label and a margin, so an end label is whole.
  let edgeInset: CGFloat

  init(chartWidth: CGFloat, labelPointSize: CGFloat) {
    let width = chartWidth > 0 ? chartWidth : Self.assumedWidth
    let label = labelPointSize * Self.labelEms
    let inset = max(Self.minimumInset, (label / 2).rounded(.up) + 8)
    let usable = width - labelPointSize * Self.yAxisEms - 2 * inset
    // Ticks are `spacing` apart and `n` of them span `n - 1` gaps, each of which must hold a label
    // and a gap: n - 1 <= usable / (label + gap).
    let fitting = Int((usable / (label + Self.gap)).rounded(.down)) + 1
    self.tickCount = min(Self.maximumTicks, max(Self.minimumTicks, fitting))
    self.edgeInset = inset
  }

  /// Evenly spaced tick dates between the first and last, or `nil` where the automatic ticks are
  /// kept: when the full four fit, or there is no span to divide.
  func ticks(from first: Date?, to last: Date?) -> [Date]? {
    guard tickCount < Self.maximumTicks, let first, let last, last > first else { return nil }
    let step = last.timeIntervalSince(first) / Double(tickCount - 1)
    return (0..<tickCount).map { first.addingTimeInterval(step * Double($0)) }
  }
}

