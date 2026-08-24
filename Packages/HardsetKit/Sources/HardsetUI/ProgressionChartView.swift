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
/// one-rep-max estimate at all, and the metric picker says so rather than drawing a flat line at
/// zero.
public struct ProgressionChartView: View {
  private let series: [SeriesInput]
  private let machineChanges: [MachineChange]
  private let unit: WeightUnit
  private let onExplain: (() -> Void)?
  @State private var metric: ProgressionMetric = .heaviestLoad

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Colour follows the gym, permanently for this chart. A series that disappears must not
  /// repaint the survivors.
  private func colour(for input: SeriesInput) -> SwiftUI.Color {
    // A hue exists to tell series apart. With one series there is nothing to tell it apart from, so
    // the hue carries no information and the line takes the accent instead -- which is also the
    // highest-contrast option on this ground. This is the common case, and it used to fall through
    // to `overflow`: a free-weight lift has no gym index, so the single most frequent chart in the
    // app drew its only line in the neutral grey reserved for "we ran out of hues".
    guard series.count > 1 else { return Tokens.Color.accent }
    guard let index = input.gymIndex else { return Tokens.Color.Series.overflow }
    return Tokens.Color.Series.hue(forGymIndex: index)
  }

  /// Stroke carries the machine inside the gym. The first machine is solid; later ones dash, so
  /// they stay distinguishable without spending a hue that would fail colour-blind separation.
  private func dash(for input: SeriesInput) -> [CGFloat] {
    switch input.machineIndexInGym {
    case 0: []
    case 1: [6, 4]
    case 2: [2, 3]
    default: [8, 3, 2, 3]
    }
  }
  /// Left-to-right reveal of the plot area, once per visit.
  @State private var drawProgress: Double = 0

  /// A series plus the label the store resolved for it, so this view does no lookups.
  public struct SeriesInput: Identifiable, Hashable, Sendable {
    public let label: String
    public let points: [ProgressionPoint]
    /// Which gym this series is at, as an index into the validated hue order. `nil` for free
    /// weights or an unknown gym, which take the neutral rather than a hue.
    public let gymIndex: Int?
    /// Which machine this is *within* its gym. Two leg presses at one gym share a hue and differ
    /// by stroke, because they are the same place and different equipment.
    public let machineIndexInGym: Int

    public var id: String { label }

    public init(
      label: String,
      points: [ProgressionPoint],
      gymIndex: Int? = nil,
      machineIndexInGym: Int = 0
    ) {
      self.label = label
      self.points = points
      self.gymIndex = gymIndex
      self.machineIndexInGym = machineIndexInGym
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
    VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
      if series.isEmpty {
        ContentUnavailableView {
          Label("No history yet", systemImage: "chart.xyaxis.line")
        } description: {
          Text("Log this movement a few times and its load history appears here.")
        }
      } else {
        picker
        chart
        if hasNoEstimates && metric == .estimatedOneRepMax {
          // Says why the chart is empty instead of drawing nothing and letting the user guess.
          Text(
            "No estimate is available. A one-rep max is only estimated from sets of twelve reps "
              + "or fewer, and none of these sessions qualify."
          )
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
        }
        machineChangeNotes
        if let onExplain {
          Button(action: onExplain) {
            HStack(spacing: Tokens.Spacing.tight) {
              Image(systemName: "questionmark.circle")
              Text("How this is measured")
            }
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.accent)
          }
          .buttonStyle(.plain)
          .frame(minHeight: Tokens.minimumTapTarget)
        }
      }
    }
  }

  private var picker: some View {
    Picker("Metric", selection: $metric) {
      ForEach(ProgressionMetric.allCases, id: \.self) { option in
        Text(option.label).tag(option)
      }
    }
    .pickerStyle(.segmented)
  }

  private var chart: some View {
    Chart {
      ForEach(series) { input in
        ForEach(plottable(input.points), id: \.sessionID) { point in
          LineMark(
            x: .value("Date", point.date),
            y: .value(metric.label, value(point)),
            series: .value("Machine", input.label)
          )
          .foregroundStyle(by: .value("Machine", input.label))
          .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash(for: input)))
          PointMark(
            x: .value("Date", point.date),
            y: .value(metric.label, value(point))
          )
          .foregroundStyle(by: .value("Machine", input.label))
          .symbol(by: .value("Machine", input.label))
        }
      }
      // A switch is drawn on the chart, not just described below it, so the eye meets the caveat
      // at the same moment it meets the discontinuity.
      ForEach(machineChanges) { change in
        RuleMark(x: .value("Machine change", change.date))
          .foregroundStyle(Tokens.Color.certainty(.low))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
          .annotation(position: .top, alignment: .leading) {
            Image(systemName: "arrow.triangle.branch")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.certainty(.low))
          }
      }
    }
    // Not zero-based. Swift Charts includes zero by default, which is right for a bar whose length
    // encodes magnitude and wrong for a line whose slope encodes change: a lifter going 100 to 110 kg
    // saw a flat line pinned to the top of a 0-110 plot, which is the one thing this view exists to
    // make visible. Nobody reads a load chart to be reminded that zero exists.
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxisLabel(unit.abbreviation)
    // Named for VoiceOver, which otherwise reaches a chart that announces nothing. The bodyweight
    // chart has carried one since it was written; this one, the older of the two, never did.
    .accessibilityLabel(
      "\(metric.label) over time, in \(unit.abbreviation)"
        + (series.count > 1 ? ", one line per machine" : "")
    )
    // No legend for a single series: the screen's own title names it, and a one-row legend reading
    // "Free weight" tells the reader nothing they did not already know.
    .chartLegend(series.count > 1 ? .visible : .hidden)
    // The validated series palette rather than Swift Charts' defaults, which are not contrast
    // checked against this ground. Three hues, assigned in fixed order and never cycled; a
    // fourth *gym* folds to the neutral rather than inventing a hue that fails colour-blind
    // separation. Hue is the gym and the stroke is the machine within it, so two leg presses at
    // one gym read as the same place with different equipment -- `SeriesInput.gymIndex` carries the
    // gym and `ExerciseProgressScreen` fills it from `ProgressionHistory.gymOrder`. (A NOTE here
    // claimed that plumbing did not exist, sitting directly above the line that reads it.)
    .chartForegroundStyleScale(
      domain: series.map(\.label),
      range: series.map { colour(for: $0) }
    )
    // Masking the plot area rather than the whole chart, so the axes and legend stay put while
    // the lines draw in. One animated value, and it cannot stair-step the way a point-prefix does.
    .chartPlotStyle { plot in
      plot.mask {
        GeometryReader { proxy in
          Rectangle()
            .frame(width: proxy.size.width * drawProgress)
            .frame(width: proxy.size.width, alignment: .leading)
        }
      }
    }
    .frame(height: 220)
    .task {
      guard drawProgress == 0 else { return }
      if reduceMotion {
        drawProgress = 1
      } else {
        withAnimation(Tokens.Motion.reveal) { drawProgress = 1 }
      }
    }
  }

  private var machineChangeNotes: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      ForEach(machineChanges) { change in
        Label {
          Text(change.explanation)
        } icon: {
          Image(systemName: "arrow.triangle.branch")
        }
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
      }
    }
  }

  // MARK: - Data

  /// Points that actually have a value for the selected metric. An unestimable session is dropped
  /// from the estimate chart rather than plotted at zero.
  private func plottable(_ points: [ProgressionPoint]) -> [ProgressionPoint] {
    switch metric {
    case .heaviestLoad: points
    case .estimatedOneRepMax: points.filter { $0.bestEstimatedOneRepMaxKg != nil }
    }
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
}

#if DEBUG
  private struct ProgressionPreviewHarness: View {
    private let day = Date(timeIntervalSince1970: 13_000_000)

    private func point(_ n: Int, _ load: Double, _ estimate: Double?) -> ProgressionPoint {
      ProgressionPoint(
        sessionID: SessionID(), machineID: nil,
        date: day.addingTimeInterval(Double(n) * 604_800),
        heaviestLoadKg: load, bestEstimatedOneRepMaxKg: estimate, workingSets: 3
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
        .padding()
      }
      .background(Tokens.Color.ground)
    }
  }

  #Preview("Two machines, one switch") {
    ProgressionPreviewHarness()
  }
#endif
