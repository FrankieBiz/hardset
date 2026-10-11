import Accessibility
import Charts
import HardsetCore
import SwiftUI

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
  private let exerciseName: String
  private let onExplain: (() -> Void)?
  @State private var metric: ProgressionMetric = .heaviestLoad
  /// Where the finger is, as a date; the readout snaps it to the nearest logged session.
  @State private var selectedDate: Date?
  /// The chart grows with Dynamic Type, so its axis labels keep their room at large sizes.
  @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 220

  /// A series plus the label the store resolved for it, so this view does no lookups.
  public typealias SeriesInput = ProgressionChartSeries

  public init(
    series: [SeriesInput],
    machineChanges: [MachineChange] = [],
    unit: WeightUnit,
    exerciseName: String = "",
    onExplain: (() -> Void)? = nil
  ) {
    self.series = series
    self.machineChanges = machineChanges
    self.unit = unit
    self.exerciseName = exerciseName
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
        headline
        picker
        chart
        if hasNoEstimates && metric == .estimatedOneRepMax {
          // Says why the chart is empty instead of drawing nothing and letting the user guess.
          UnevaluatedReadout(
            explanation:
              "A one-rep max is only estimated from sets of twelve reps or fewer, and none of these sessions qualify."
          )
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

  private var formatter: WeightFormatter { WeightFormatter(unit: unit) }

  /// "Cybex Leg Press: +5 kg over 2 sessions", always for one machine; Core words it.
  @ViewBuilder private var headline: some View {
    if let headline = ProgressionHeadline.current(in: series, metric: metric, formatter: formatter) {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Text(headline.text)
          .font(Tokens.Text.label.weight(.semibold))
          .accessibilityLabel(headline.spoken)
        if let certainty = headline.certainty {
          CertaintyBadge(certainty, source: StrengthMath.epleySource, style: .compact)
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
          if let value = metric.displayValue(of: point, unit: unit) {
            // Shape as well as colour tells machines apart, and a dash marks an estimate.
            LineMark(
              x: .value("Date", point.date),
              y: .value(metric.label, value),
              series: .value("Machine", input.label)
            )
            .foregroundStyle(by: .value("Machine", input.label))
            .symbol(by: .value("Machine", input.label))
            .lineStyle(StrokeStyle(lineWidth: 2, dash: metric.isEstimate ? [5, 3] : []))
            PointMark(
              x: .value("Date", point.date),
              y: .value(metric.label, value)
            )
            .foregroundStyle(by: .value("Machine", input.label))
            .symbol(by: .value("Machine", input.label))
          }
        }
      }
      // A switch is drawn on the chart, not just described below it, so the eye meets the caveat
      // at the same moment it meets the discontinuity.
      ForEach(machineChanges) { change in
        RuleMark(x: .value("Machine change", change.date))
          .foregroundStyle(Tokens.Color.caveat)
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
          .annotation(position: .top, alignment: .leading) {
            Image(systemName: "arrow.triangle.branch")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.caveat)
          }
      }
      if let selectedDate,
        let selection = ProgressionSelection.nearest(
          to: selectedDate, in: series, metric: metric, formatter: formatter)
      {
        RuleMark(x: .value("Selected", selection.point.date))
          .foregroundStyle(Tokens.Color.textSecondary)
          .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
            Text(selection.text)
              .font(Tokens.Text.caption.weight(.semibold))
              .padding(Tokens.Spacing.tight)
              .background(
                Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
          }
      }
    }
    .chartXSelection(value: $selectedDate)
    .chartYAxisLabel(unit.abbreviation)
    .chartLegend(position: .bottom)
    .frame(height: chartHeight)
    .modifier(
      AudioGraph(
        description: ProgressionChartDescription.make(
          exerciseName: exerciseName, series: series, metric: metric, formatter: formatter)))
  }

  private var machineChangeNotes: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      ForEach(machineChanges) { change in
        Label {
          Text(change.explanation(in: unit))
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
    points.filter { metric.kilograms(of: $0) != nil }
  }

  private var hasNoEstimates: Bool {
    series.allSatisfy { input in
      input.points.allSatisfy { $0.bestEstimatedOneRepMaxKg == nil }
    }
  }
}

/// The chart as VoiceOver's audio graph hears it. Every value comes from Core's description;
/// this only converts types.
private nonisolated struct ProgressionAudioGraph: AXChartDescriptorRepresentable {
  let description: ProgressionChartDescription

  func makeChartDescriptor() -> AXChartDescriptor {
    let dates = description.dateRange
    let xAxis = AXNumericDataAxisDescriptor(
      title: "Date",
      range: dates.lowerBound.timeIntervalSince1970...dates.upperBound.timeIntervalSince1970,
      gridlinePositions: []
    ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
    let yAxis = AXNumericDataAxisDescriptor(
      title: description.valueAxisTitle, range: description.valueRange, gridlinePositions: []
    ) { [description] in description.spokenValue($0) }
    return AXChartDescriptor(
      title: description.title,
      summary: description.summary,
      xAxis: xAxis,
      yAxis: yAxis,
      additionalAxes: [],
      series: description.series.map { line in
        AXDataSeriesDescriptor(
          name: line.name, isContinuous: true,
          dataPoints: line.points.map {
            AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.value, label: $0.spokenValue)
          })
      })
  }
}

/// `ProgressionChartDescription.make` returns nil only when nothing is plotted, and then no chart
/// is drawn, so the descriptor is attached here rather than through an invented empty description.
private struct AudioGraph: ViewModifier {
  let description: ProgressionChartDescription?

  func body(content: Content) -> some View {
    if let description {
      content.accessibilityChartDescriptor(ProgressionAudioGraph(description: description))
    } else {
      content
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
      .background(Tokens.Color.background)
    }
  }

  #Preview("Two machines, one switch") {
    ProgressionPreviewHarness()
  }
#endif
