import Foundation

/// The words on the Progress tab, held apart from any view so they are tested without one.
///
/// A change is always named for the metric it measures, as a whole percent: "Estimated max +8% in
/// 6 weeks", never a bare "+8%", because the same number means different things for an estimate, a
/// heaviest load and a count of reps. A change too small to round to a percent is said to be
/// unchanged. A movement with no session five to seven weeks before its latest has no change to
/// state, and says exactly that, with the history it does have, rather than borrowing another
/// window or claiming it has too little history when the history is long and only misses the band.
public enum ProgressCopy {
  public static let importedHistory = "Imported · machine not recorded"
  public static let noMachineRecorded = "No machine recorded"
  public static var mostImprovedTitle: String {
    "Most improved · " + metricName(ProgressTrendAnalyzer.mostImprovedMetric).lowercased()
  }

  /// The metric's name. `measured` is true when every claim behind the figure is a measured single,
  /// which estimates nothing: that figure is the lifter's max and says "Max", not "Estimated max".
  /// Only the estimated-max metric has a measured form; the others are unchanged.
  /// "Most improved · estimated max", or "Most improved · max" when every row behind the strip is a
  /// measured single, so the heading never calls a measured figure an estimate.
  public static func mostImprovedHeading(_ trends: [MovementTrend], metric: TrendMetric) -> String {
    let measured = !trends.isEmpty && trends.allSatisfy(\.isMeasured)
    return "Most improved · " + metricName(metric, measured: measured).lowercased()
  }

  public static func metricName(_ metric: TrendMetric, measured: Bool = false) -> String {
    switch metric {
    case .estimatedMax: measured ? "Max" : "Estimated max"
    case .heaviestLoad: "Heaviest weight"
    case .addedLoad: "Added load"
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
    shortChangeText(for: trend).map { "\(metricName(trend.metric, measured: trend.isMeasured)) \($0)" }
  }

  /// "Estimated max · no 6-week comparison": what is missing, named for the metric it would have
  /// measured. Said when no session sits in the comparison band, however much history there is.
  public static func noChangeText(for trend: MovementTrend) -> String {
    "\(metricName(trend.metric, measured: trend.isMeasured)) · no 6-week comparison"
  }

  /// "4 sessions over 3 weeks. A comparison needs a session 5 to 7 weeks before the latest.": the
  /// history the movement does have, and what the comparison needs, so the lifter can tell a short
  /// history from a gap in a long one. The band is read from the analyser that applies it.
  public static func historyText(for trend: MovementTrend) -> String {
    let have: String
    if trend.sessionCount == 1 {
      have = "1 session so far"
    } else if let first = trend.firstDate {
      have = "\(trend.sessionCount) sessions \(span(from: first, to: trend.latestDate))"
    } else {
      have = "\(trend.sessionCount) sessions"
    }
    return "\(have). A comparison needs a session \(comparisonBandText) before the latest."
  }

  /// "5 to 7 weeks", from the band a six-week change is read against.
  public static var comparisonBandText: String {
    let band = ProgressTrendAnalyzer.comparisonBandDays
    return "\(band.lowerBound / 7) to \(band.upperBound / 7) weeks"
  }

  /// Both marks a board row can carry, defined together where a change is shown: the six-week
  /// comparison window and the record star. The band comes from the analyser that applies it.
  public static var comparisonAndRecordKey: String {
    "A six-week change compares the latest session with one \(comparisonBandText) before it, on the "
      + "same machine. The star marks a session that set a record."
  }

  /// How long a run of sessions is, in the largest unit that reads plainly: "on one day", "over 6
  /// days", "over 3 weeks", "over 5 months", "over 2 years".
  static func span(from first: Date, to latest: Date) -> String {
    let days = Int((latest.timeIntervalSince(first) / 86_400).rounded())
    switch days {
    case ..<1: return "on one day"
    case 1..<14: return days == 1 ? "over 1 day" : "over \(days) days"
    case 14..<90: return "over \(Int((Double(days) / 7).rounded())) weeks"
    case 90..<730: return "over \(Int((Double(days) / 30.4375).rounded())) months"
    default: return "over \(Int((Double(days) / 365.25).rounded())) years"
    }
  }

  /// Said under the Most improved label, because the order is not simply by percentage. The count
  /// is the rule's own, `ProgressTrendAnalyzer.stallRun`, so the words cannot drift from it.
  public static var mostImprovedOrdering: String {
    "Ordered by confidence in the estimate first, then gain. A movement with no record in "
      + "\(ProgressTrendAnalyzer.stallRun) sessions ranks after one that has a record in its last "
      + "\(ProgressTrendAnalyzer.stallRun)."
  }

  /// "No record in 3 sessions". The rule is only that none of the last sessions set a record, so
  /// the words say that and no more: "stalled" would be a claim about the lifter's body, which the
  /// data cannot support. A fact about the last sessions, with no advice attached.
  public static func stalledText(for trend: MovementTrend) -> String? {
    trend.stalledSessions.map { "No record in \($0) sessions" }
  }

  /// Said beside "the body's own load is unknown": what is missing, and the one place it is set.
  ///
  /// The assumption sentence is true of a movement with no equipment on record, but for a barbell or
  /// machine lift it reads as nonsense, and an imported lift has no equipment until its owner says.
  /// This says the max is withheld rather than guessed, and where the lifter can end that. It does
  /// not promise a max: a bodyweight movement gets none however it is declared.
  public static let equipmentNotSet =
    "Equipment not set, so no max is estimated. Set it in Library, on the Train tab."

  /// The note that goes with a trend whose load is assumed, which is exactly a movement with no
  /// equipment on record. Nil for every other trend.
  public static func equipmentNote(for trend: MovementTrend) -> String? {
    trend.loadAssumption == nil ? nil : equipmentNotSet
  }

  // MARK: - Imported history beside what was logged here

  /// An imported movement's own row, with no movement of the same identity logged in Hardset. The
  /// lifter may well have the same lift under another name; the app does not guess that two names
  /// are one movement, so it says the rows are not combined rather than where the other half is.
  public static let importedAlone =
    "Not combined with sets you log in Hardset, even for the same lift."

  /// An imported series on a movement the lifter has also logged here: one movement, two rows.
  public static let importedBesideLogged =
    "Not combined with the sets you logged in Hardset for this movement, which are on their own row."

  /// The logged half of the same pair.
  public static let loggedBesideImported =
    "Not combined with this movement's imported history, which is on its own row."

  /// Said once above the board when any row is imported, for the lift whose two halves carry two
  /// names and so cannot be pointed at one another. States the rule instead of a guess.
  public static let importedBoardNote =
    "Imported history stays on its own rows, so one lift can appear twice: once as imported, once as "
    + "logged in Hardset. Hardset does not guess that two names are the same movement, and never joins "
    + "two series into one line."

  /// Said under a movement's chart when one of its lines is imported history.
  public static let importedSeriesNote =
    "An imported set records no machine, so Hardset keeps the imported line as its own series and "
    + "does not join it to the others."

  /// A row as VoiceOver reads it: the movement and machine, the change, any stall, and, when the row
  /// has one, how it relates to the history on the other source.
  public static func spokenRow(_ row: ProgressBoard.Row, sourceNote: String? = nil) -> String {
    var sentences = [[row.exerciseName, row.machineName].compactMap { $0 }.joined(separator: ", ")]
    if let change = changeText(for: row.trend) {
      sentences.append(change)
    } else {
      sentences.append(noChangeText(for: row.trend))
      sentences.append(historyText(for: row.trend))
    }
    if let assumption = row.trend.loadAssumption { sentences.append(assumption) }
    if let note = equipmentNote(for: row.trend) { sentences.append(note) }
    if let stalled = stalledText(for: row.trend) { sentences.append(stalled) }
    if let sourceNote { sentences.append(sourceNote) }
    return sentences.map { $0.hasSuffix(".") ? $0 : $0 + "." }.joined(separator: " ")
  }
}
