import Foundation

/// What a load-history chart plots. Load is always available; the estimate is not.
///
/// In Core rather than in the chart view, because the headline, the scrub readout and the
/// VoiceOver description all depend on it and are tested here.
public enum ProgressionMetric: String, Sendable, CaseIterable, Hashable {
  case heaviestLoad
  case estimatedOneRepMax

  public var label: String {
    switch self {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Est. 1RM"
    }
  }

  /// The label read aloud, without the abbreviation.
  public var spokenLabel: String {
    switch self {
    case .heaviestLoad: "Heaviest load"
    case .estimatedOneRepMax: "Estimated one-rep max"
    }
  }

  /// An estimate is drawn dashed and said with "about", so it never passes for a lift.
  public var isEstimate: Bool { self == .estimatedOneRepMax }

  /// The point's value for this metric, in kilograms, or nil when it has none.
  public func kilograms(of point: ProgressionPoint) -> Double? {
    switch self {
    case .heaviestLoad: point.heaviestLoadKg
    case .estimatedOneRepMax: point.bestEstimatedOneRepMaxKg
    }
  }

  /// The value as the lifter reads it: in their unit, a load to two decimals and an estimate to
  /// display precision (0.5 kg, 1 lb). Arithmetic on these agrees with the numbers on screen.
  public func displayValue(of point: ProgressionPoint, unit: WeightUnit) -> Double? {
    guard let kilograms = kilograms(of: point) else { return nil }
    if isEstimate { return StrengthMath.displayRounded(kilograms, in: unit) }
    return (unit.fromKilograms(kilograms) * 100).rounded() / 100
  }
}

/// One machine's line, with the label the chart and VoiceOver use for it.
public struct ProgressionChartSeries: Identifiable, Hashable, Sendable {
  public let label: String
  /// Oldest first.
  public let points: [ProgressionPoint]

  /// The chart keys a line by this, so two series must never share a label.
  /// `ProgressionHistory.chartSeries()` guarantees it.
  public var id: String { label }

  public init(label: String, points: [ProgressionPoint]) {
    self.label = label
    self.points = points
  }

  /// The points this metric can plot, with their display values, oldest first.
  func plotted(_ metric: ProgressionMetric, unit: WeightUnit) -> [(point: ProgressionPoint, value: Double)] {
    points.compactMap { point in metric.displayValue(of: point, unit: unit).map { (point, $0) } }
  }
}

/// The sentence over the chart: "Hammer leg press: +5 kg over 6 sessions" (spec 3.3).
///
/// It always describes one machine. A delta taken across a switch would report the difference
/// between two machines as progress or decline, which is exactly what a chart that never merges
/// series exists to refuse (`DECISIONS.md` §20).
public struct ProgressionHeadline: Hashable, Sendable {
  public let text: String
  /// The same sentence for VoiceOver, with units in full.
  public let spoken: String
  /// For an estimate, the weaker of its two ends. Nil for loads, which are measured.
  public let certainty: Certainty?

  /// The headline for the machine used most recently, which is the one the lifter means.
  public static func current(
    in series: [ProgressionChartSeries], metric: ProgressionMetric, formatter: WeightFormatter
  ) -> ProgressionHeadline? {
    let candidates = series.compactMap { line -> (ProgressionChartSeries, Date)? in
      guard let last = line.plotted(metric, unit: formatter.unit).last else { return nil }
      return (line, last.point.date)
    }
    guard let latest = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
    return make(for: latest.0, metric: metric, formatter: formatter)
  }

  /// The headline for one series, from its first plotted session to its last.
  public static func make(
    for series: ProgressionChartSeries, metric: ProgressionMetric, formatter: WeightFormatter
  ) -> ProgressionHeadline? {
    let plotted = series.plotted(metric, unit: formatter.unit)
    guard let first = plotted.first, let last = plotted.last else { return nil }
    let label = series.label
    let sessions = plotted.count == 1 ? "1 session" : "\(plotted.count) sessions"
    let about = metric.isEstimate ? "about " : ""
    let ends = [first.point.bestEstimateCertainty, last.point.bestEstimateCertainty].compactMap { $0 }
    let certainty = metric.isEstimate && !ends.isEmpty ? Certainty.combine(ends) : nil
    let digits = metric.isEstimate ? 1 : 2

    guard plotted.count > 1 else {
      let value = WeightFormatter.text(last.value, fractionDigits: digits, locale: formatter.locale)
      return ProgressionHeadline(
        text: "\(label): \(about)\(value) \(formatter.unit.abbreviation), \(sessions)",
        spoken: "\(label): \(about)\(spoken(last.value, formatter)), \(sessions)",
        certainty: certainty
      )
    }

    let delta = ((last.value - first.value) * 100).rounded() / 100
    guard delta != 0 else {
      let text = "\(label): no change over \(sessions)"
      return ProgressionHeadline(text: text, spoken: text, certainty: certainty)
    }
    let sign = delta > 0 ? "+" : "\u{2212}"
    let magnitude = WeightFormatter.text(abs(delta), fractionDigits: 2, locale: formatter.locale)
    return ProgressionHeadline(
      text: "\(label): \(about)\(sign)\(magnitude) \(formatter.unit.abbreviation) over \(sessions)",
      spoken:
        "\(label): \(delta > 0 ? "up" : "down") \(about)\(spoken(abs(delta), formatter)) over \(sessions)",
      certainty: certainty
    )
  }

  /// A display-unit value read aloud: "5 kilograms".
  static func spoken(_ displayValue: Double, _ formatter: WeightFormatter) -> String {
    formatter.spoken(kilograms: formatter.unit.toKilograms(displayValue))
  }
}

/// What scrubbing the chart shows: the logged point nearest the finger, with its own machine.
///
/// Never an interpolated or combined value. The readout names one session on one machine.
public struct ProgressionSelection: Hashable, Sendable {
  public let seriesLabel: String
  public let point: ProgressionPoint
  /// "Hammer leg press: 102.5 kg".
  public let text: String
  public let spoken: String

  public static func nearest(
    to date: Date, in series: [ProgressionChartSeries], metric: ProgressionMetric,
    formatter: WeightFormatter
  ) -> ProgressionSelection? {
    var best: (label: String, point: ProgressionPoint, value: Double, distance: TimeInterval)?
    for line in series {
      for (point, value) in line.plotted(metric, unit: formatter.unit) {
        let distance = abs(point.date.timeIntervalSince(date))
        if best == nil || distance < best!.distance {
          best = (line.label, point, value, distance)
        }
      }
    }
    guard let best else { return nil }
    let about = metric.isEstimate ? "about " : ""
    let digits = metric.isEstimate ? 1 : 2
    let number = WeightFormatter.text(best.value, fractionDigits: digits, locale: formatter.locale)
    return ProgressionSelection(
      seriesLabel: best.label,
      point: best.point,
      text: "\(best.label): \(about)\(number) \(formatter.unit.abbreviation)",
      spoken: "\(best.label): \(about)\(ProgressionHeadline.spoken(best.value, formatter))"
    )
  }
}

/// The chart, described for VoiceOver's audio graph (`AXChartDescriptor`, spec 3.3).
///
/// The UI turns this into Accessibility types and adds nothing. One series per machine, as drawn.
public struct ProgressionChartDescription: Hashable, Sendable {
  public struct Point: Hashable, Sendable {
    public let date: Date
    /// In the lifter's unit, as plotted.
    public let value: Double
    public let spokenValue: String
  }

  public struct Series: Hashable, Sendable {
    public let name: String
    public let points: [Point]
  }

  /// "Leg Press, heaviest load".
  public let title: String
  /// The spoken headline, when there is one.
  public let summary: String?
  /// "Heaviest load in kilograms".
  public let valueAxisTitle: String
  public let valueRange: ClosedRange<Double>
  public let dateRange: ClosedRange<Date>
  public let series: [Series]
  private let formatter: WeightFormatter
  private let isEstimate: Bool

  /// A plotted value read aloud, for the value axis: "about 116 kilograms".
  public func spokenValue(_ displayValue: Double) -> String {
    (isEstimate ? "about " : "") + ProgressionHeadline.spoken(displayValue, formatter)
  }

  public static func make(
    exerciseName: String, series: [ProgressionChartSeries], metric: ProgressionMetric,
    formatter: WeightFormatter
  ) -> ProgressionChartDescription? {
    let about = metric.isEstimate ? "about " : ""
    let described = series.compactMap { line -> Series? in
      let points = line.plotted(metric, unit: formatter.unit).map { point, value in
        Point(
          date: point.date, value: value,
          spokenValue: about + ProgressionHeadline.spoken(value, formatter))
      }
      return points.isEmpty ? nil : Series(name: line.label, points: points)
    }
    let values = described.flatMap(\.points).map(\.value)
    let dates = described.flatMap(\.points).map(\.date)
    guard let low = values.min(), let high = values.max(), let first = dates.min(),
      let last = dates.max()
    else { return nil }
    let unitName =
      switch formatter.unit {
      case .kilograms: "kilograms"
      case .pounds: "pounds"
      }
    return ProgressionChartDescription(
      title: "\(exerciseName), \(metric.spokenLabel.lowercased())",
      summary: ProgressionHeadline.current(in: series, metric: metric, formatter: formatter)?.spoken,
      valueAxisTitle: "\(metric.spokenLabel) in \(unitName)",
      // A single value would give the axis no width, so it is widened by one unit each way.
      valueRange: low < high ? low...high : (low - 1)...(high + 1),
      dateRange: first...last,
      series: described,
      formatter: formatter,
      isEstimate: metric.isEstimate
    )
  }
}
