import Foundation

/// The words on the Progress tab, held apart from any view so they are tested without one.
///
/// A change is always named for the metric it measures, as a whole percent: "Estimated max +8% in
/// 6 weeks", never a bare "+8%", because the same number means different things for an estimate, a
/// heaviest load and a count of reps. A change too small to round to a percent is said to be
/// unchanged, and a movement with no session six weeks back says it does not have enough history
/// rather than borrowing another window.
public enum ProgressCopy {
  public static let notEnoughHistory = "Not enough history"
  public static let importedHistory = "Imported · machine not recorded"
  public static let noMachineRecorded = "No machine recorded"
  public static var mostImprovedTitle: String {
    "Most improved · " + metricName(ProgressTrendAnalyzer.mostImprovedMetric).lowercased()
  }

  public static func metricName(_ metric: TrendMetric) -> String {
    switch metric {
    case .estimatedMax: "Estimated max"
    case .heaviestLoad: "Heaviest weight"
    case .repsAtTopLoad: "Reps at the top weight"
    }
  }

  /// "+8% in 6 weeks", "−3% in 6 weeks" with a true minus, or "unchanged in 6 weeks". Nil when the
  /// movement has no session in the six-week window.
  public static func shortChangeText(for trend: MovementTrend) -> String? {
    guard let change = trend.sixWeekChange else { return nil }
    if (change * 100).rounded() == 0 { return "unchanged in 6 weeks" }
    return "\(signedPercent(change)) in 6 weeks"
  }

  /// A fraction as a signed whole percent with a true minus: 0.08 is "+8%", -0.03 is "−3%".
  public static func signedPercent(_ fraction: Double) -> String {
    let percent = (fraction * 100).rounded()
    return "\(percent < 0 ? "−" : "+")\(Int(abs(percent)))%"
  }

  /// "Estimated max +8% in 6 weeks": the change, labelled with its metric.
  public static func changeText(for trend: MovementTrend) -> String? {
    shortChangeText(for: trend).map { "\(metricName(trend.metric)) \($0)" }
  }

  /// "Stalled · 3 sessions". A fact about the last sessions, with no advice attached.
  public static func stalledText(for trend: MovementTrend) -> String? {
    trend.stalledSessions.map { "Stalled · \($0) sessions" }
  }

  /// A row as VoiceOver reads it: the movement and machine, the change, and any stall.
  public static func spokenRow(_ row: ProgressBoard.Row) -> String {
    var sentences = [[row.exerciseName, row.machineName].compactMap { $0 }.joined(separator: ", ")]
    sentences.append(changeText(for: row.trend) ?? notEnoughHistory)
    if let stalled = stalledText(for: row.trend) { sentences.append(stalled) }
    return sentences.map { $0 + "." }.joined(separator: " ")
  }
}
