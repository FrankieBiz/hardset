import Foundation

/// One recorded bodyweight.
public nonisolated struct BodyweightReading: Hashable, Sendable {
  public let weightKg: Double
  public let measuredAt: Date

  public init(weightKg: Double, measuredAt: Date) {
    self.weightKg = weightKg
    self.measuredAt = measuredAt
  }
}

/// What a run of bodyweight readings actually says, as opposed to what the newest number says.
///
/// A scale reading moves one to two kilograms a day on food, water and time of day. A logger that
/// prints "up 0.8 kg since yesterday" is reporting hydration and calling it progress, which is the
/// same class of lie as counting a set that was not performed. So no single reading is ever
/// presented as a change: the readout is a trailing average, and the rate of change is a fit over
/// weeks that refuses to exist until there is enough spread to support one.
///
/// Pure, and dependency-free, so the rules can be tested directly rather than through a screen.
public nonisolated enum BodyweightTrend {
  /// How far back a rate is measured. Older readings describe a diet that has since changed.
  public static let windowDays = 28
  /// The span of the trailing average. A week covers the weekly eating cycle, which is the largest
  /// periodic component in the noise.
  public static let smoothingDays = 7
  /// Below this there is no rate, at any certainty. Two readings a day apart can imply 7 kg a week.
  public static let minimumSpanDays = 7

  /// Below this, a fitted rate is reported as holding steady rather than as a direction.
  ///
  /// A fit will almost never return exactly zero, so without a threshold the app would tell a lifter
  /// whose weight has not moved in a month that they are gaining 0.02 kg a week -- technically the
  /// slope, and a false statement about their body. 0.1 kg a week is below what a bathroom scale can
  /// resolve as a trend over a month.
  public static let steadyThresholdKgPerWeek = 0.1

  /// Which way the weight is going, once the threshold has had its say.
  public enum Direction: Sendable, Hashable {
    case gaining
    case losing
    case steady
  }

  public static func direction(perWeek: Double) -> Direction {
    if perWeek > steadyThresholdKgPerWeek { return .gaining }
    if perWeek < -steadyThresholdKgPerWeek { return .losing }
    return .steady
  }

  /// The trailing average ending at `date`, which is the number to show as "your bodyweight".
  ///
  /// `nil` when the window is empty. Deliberately not "the last reading you happened to take three
  /// weeks ago" -- a stale number presented as current is worse than an honest blank.
  public static func smoothed(
    _ readings: [BodyweightReading],
    endingAt date: Date,
    days: Int = smoothingDays
  ) -> Double? {
    let window = readings.filter {
      $0.measuredAt <= date
        && $0.measuredAt > date.addingTimeInterval(-Double(days) * 86_400)
    }
    guard !window.isEmpty else { return nil }
    return window.reduce(0) { $0 + $1.weightKg } / Double(window.count)
  }

  /// The trailing average evaluated at each reading's date, which is the line worth plotting.
  ///
  /// Plotting the raw readings draws the noise as if it were the signal -- a sawtooth that looks
  /// like weekly gains and losses when nothing happened. The raw points still belong on the chart,
  /// faintly, because hiding them would overstate how smooth the underlying data is.
  ///
  /// Sorted oldest first, which is the order a chart wants.
  public static func smoothedSeries(
    _ readings: [BodyweightReading],
    days: Int = smoothingDays
  ) -> [BodyweightReading] {
    readings
      .sorted { $0.measuredAt < $1.measuredAt }
      .compactMap { reading in
        smoothed(readings, endingAt: reading.measuredAt, days: days)
          .map { BodyweightReading(weightKg: $0, measuredAt: reading.measuredAt) }
      }
  }

  /// Change in kilograms per week, fitted across the window.
  ///
  /// A least-squares slope rather than last-minus-first, so one unusual morning cannot set the
  /// number, and every reading contributes. Certainty comes from how much time the readings
  /// actually span and how densely they cover it -- both matter, because six readings in two days
  /// and two readings a month apart are each unable to support a weekly rate.
  public static func weeklyRate(
    _ readings: [BodyweightReading],
    asOf date: Date,
    windowDays: Int = windowDays
  ) -> Claim<Double> {
    let window =
      readings
      .filter {
        $0.measuredAt <= date
          && $0.measuredAt > date.addingTimeInterval(-Double(windowDays) * 86_400)
      }
      .sorted { $0.measuredAt < $1.measuredAt }

    guard let first = window.first, let last = window.last, window.count >= 2 else {
      return .unevaluated(source: source)
    }
    let spanDays = last.measuredAt.timeIntervalSince(first.measuredAt) / 86_400
    guard spanDays >= Double(minimumSpanDays) else { return .unevaluated(source: source) }

    // x in days from the first reading, y in kilograms.
    let xs = window.map { $0.measuredAt.timeIntervalSince(first.measuredAt) / 86_400 }
    let ys = window.map(\.weightKg)
    let n = Double(window.count)
    let meanX = xs.reduce(0, +) / n
    let meanY = ys.reduce(0, +) / n
    var numerator = 0.0
    var denominator = 0.0
    for (x, y) in zip(xs, ys) {
      numerator += (x - meanX) * (y - meanY)
      denominator += (x - meanX) * (x - meanX)
    }
    // Every reading on the same instant. Guarded rather than trusted: the span check above uses
    // first-to-last, which cannot catch a pile of readings sharing one timestamp.
    guard denominator > 0 else { return .unevaluated(source: source) }

    let perWeek = (numerator / denominator) * 7
    return Claim(perWeek, certainty: certainty(spanDays: spanDays, count: window.count), source: source)
  }

  /// Never `.high` on a fortnight, and never better than `.low` when the readings are sparse.
  ///
  /// The thresholds are a judgement about presentation, not a statistical test: they decide whether
  /// the UI states a rate plainly, hedges it, or shows nothing.
  private static func certainty(spanDays: Double, count: Int) -> Certainty {
    if spanDays >= 21, count >= 7 { return .high }
    if spanDays >= 14, count >= 4 { return .moderate }
    return .low
  }

  public static let source = EvidenceSource(
    id: "hardset-bodyweight-trend-v1",
    title: "Bodyweight trend",
    methodology: """
      The figure shown is the average of your readings over the last \(smoothingDays) days, not \
      your most recent one. The rate is the slope of a straight-line fit through every reading in \
      the last \(windowDays) days, expressed as a change per week in whichever unit you have \
      chosen. Nothing here is uploaded.
      """,
    citation: nil,
    validRange: """
      No rate is produced until your readings span at least \(minimumSpanDays) days, because a \
      day-to-day difference in scale weight is mostly food and water rather than tissue. A rate \
      from a short or sparsely covered window is marked as uncertain rather than stated plainly.
      """
  )
}
