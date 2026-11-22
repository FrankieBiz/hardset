import Foundation
import Testing

@testable import HardsetCore

@Suite("The words on the Progress tab")
struct ProgressCopyTests {
  private func trend(
    _ metric: TrendMetric, change: Double?, stalled: Int? = nil, certainty: Certainty? = nil
  ) -> MovementTrend {
    MovementTrend(
      key: ProgressionKey(exerciseID: ExerciseID()), metric: metric, sparkline: [1, 2],
      sixWeekChange: change, sessionCount: 5, stalledSessions: stalled,
      latestDate: Date(timeIntervalSince1970: 0), certainty: certainty)
  }

  @Test("The change is labelled with the metric it measures, as a whole percent")
  func changeNamesItsMetric() {
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: 0.08))
      == "Estimated max +8% in 6 weeks")
    #expect(ProgressCopy.changeText(for: trend(.heaviestLoad, change: 0.125))
      == "Heaviest weight +13% in 6 weeks")
    #expect(ProgressCopy.changeText(for: trend(.repsAtTopLoad, change: 0.2))
      == "Reps at the top weight +20% in 6 weeks")
  }

  @Test("A fall is a fall, with a true minus sign")
  func changeCanBeNegative() {
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: -0.03))
      == "Estimated max −3% in 6 weeks")
  }

  @Test("A change too small to round to a percent reads as unchanged, not as plus zero")
  func tinyChangeIsUnchanged() {
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: 0.002))
      == "Estimated max unchanged in 6 weeks")
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: -0.004))
      == "Estimated max unchanged in 6 weeks")
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: 0))
      == "Estimated max unchanged in 6 weeks")
  }

  @Test("With no session in the comparison band there is no change to state, and the row says what is missing")
  func noWindowSaysWhatIsMissing() {
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: nil)) == nil)
    #expect(ProgressCopy.noChangeText(for: trend(.estimatedMax, change: nil))
      == "Estimated max · no 6-week comparison")
    #expect(ProgressCopy.noChangeText(for: trend(.addedLoad, change: nil))
      == "Added load · no 6-week comparison")
    // "Not enough history" is gone: it was false for a long history that only misses the band.
    #expect(!ProgressCopy.noChangeText(for: trend(.estimatedMax, change: nil)).contains("enough"))
  }

  @Test("The band the copy names is the band the change is read against")
  func bandIsFromTheAnalyser() {
    #expect(ProgressTrendAnalyzer.comparisonBandDays == 35...49)
    #expect(ProgressCopy.comparisonBandText == "5 to 7 weeks")
  }

  private func history(sessions: Int, firstDay: Int, latestDay: Int) -> MovementTrend {
    let epoch = Date(timeIntervalSince1970: 0)
    return MovementTrend(
      key: ProgressionKey(exerciseID: ExerciseID()), metric: .estimatedMax, sparkline: [1, 2],
      sixWeekChange: nil, sessionCount: sessions, stalledSessions: nil,
      latestDate: epoch.addingTimeInterval(Double(latestDay) * 86_400),
      firstDate: epoch.addingTimeInterval(Double(firstDay) * 86_400))
  }

  @Test("A short history is stated as the span it has and what a comparison needs")
  func shortHistoryNamesItsSpan() {
    #expect(ProgressCopy.historyText(for: history(sessions: 4, firstDay: 0, latestDay: 21))
      == "4 sessions over 3 weeks. A comparison needs a session 5 to 7 weeks before the latest.")
    #expect(ProgressCopy.historyText(for: history(sessions: 3, firstDay: 0, latestDay: 6))
      == "3 sessions over 6 days. A comparison needs a session 5 to 7 weeks before the latest.")
    #expect(ProgressCopy.historyText(for: history(sessions: 2, firstDay: 0, latestDay: 0))
      == "2 sessions on one day. A comparison needs a session 5 to 7 weeks before the latest.")
    #expect(ProgressCopy.historyText(for: history(sessions: 1, firstDay: 0, latestDay: 0))
      == "1 session so far. A comparison needs a session 5 to 7 weeks before the latest.")
  }

  @Test("A long history that misses the band says how long it is, never that it is too short")
  func longHistoryIsNotCalledShort() {
    let monthly = ProgressCopy.historyText(for: history(sessions: 12, firstDay: 0, latestDay: 336))
    #expect(monthly.hasPrefix("12 sessions over 11 months."))
    let years = ProgressCopy.historyText(for: history(sessions: 90, firstDay: 0, latestDay: 1_100))
    #expect(years.hasPrefix("90 sessions over 3 years."))
    #expect(!monthly.lowercased().contains("not enough"))
    #expect(!years.lowercased().contains("not enough"))
  }

  @Test("Without a first date the count is still stated, with no span invented")
  func unknownFirstDate() {
    #expect(ProgressCopy.historyText(for: trend(.estimatedMax, change: nil))
      == "5 sessions. A comparison needs a session 5 to 7 weeks before the latest.")
  }

  @Test("The Most improved order is stated on screen: confidence, then gain, no-record movements after")
  func mostImprovedOrderingIsStated() {
    #expect(ProgressCopy.mostImprovedOrdering.contains("confidence"))
    #expect(ProgressCopy.mostImprovedOrdering.contains("gain"))
    #expect(ProgressCopy.mostImprovedOrdering.contains("no record in 3 sessions"))
    // The sentence uses the rule's own count, and never the word that claims more than the rule.
    #expect(ProgressTrendAnalyzer.stallRun == 3)
    #expect(!ProgressCopy.mostImprovedOrdering.lowercased().contains("stall"))
  }

  @Test("The short form is what the Most improved strip shows")
  func shortChange() {
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: 0.08)) == "+8% in 6 weeks")
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: -0.03)) == "−3% in 6 weeks")
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: 0.001)) == "unchanged in 6 weeks")
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: nil)) == nil)
  }

  @Test("The flag says how many sessions had no record, states no advice, and never says stalled")
  func stalledText() {
    #expect(ProgressCopy.stalledText(for: trend(.estimatedMax, change: 0.1, stalled: 3))
      == "No record in 3 sessions")
    #expect(ProgressCopy.stalledText(for: trend(.estimatedMax, change: 0.1, stalled: nil)) == nil)
    let said = ProgressCopy.stalledText(for: trend(.estimatedMax, change: 0.1, stalled: 3)) ?? ""
    #expect(!said.lowercased().contains("stall"))
  }

  @Test("A row is spoken as the movement, its machine, the change and any run without a record")
  func spokenRow() {
    let key = ProgressionKey(exerciseID: ExerciseID(), machineID: MachineID())
    let stalled = MovementTrend(
      key: key, metric: .estimatedMax, sparkline: [1], sixWeekChange: 0.08, sessionCount: 5,
      stalledSessions: 3, latestDate: Date(timeIntervalSince1970: 0), certainty: .moderate)
    let plain = MovementTrend(
      key: key, metric: .heaviestLoad, sparkline: [1], sixWeekChange: nil, sessionCount: 2,
      stalledSessions: nil, latestDate: Date(timeIntervalSince1970: 21 * 86_400),
      firstDate: Date(timeIntervalSince1970: 0))

    #expect(ProgressCopy.spokenRow(
      ProgressBoard.Row(trend: stalled, exerciseName: "Chest press", machineName: "Hammer"))
      == "Chest press, Hammer. Estimated max +8% in 6 weeks. No record in 3 sessions.")
    #expect(ProgressCopy.spokenRow(ProgressBoard.Row(trend: plain, exerciseName: "Squat"))
      == "Squat. Heaviest weight · no 6-week comparison. 2 sessions over 3 weeks. "
      + "A comparison needs a session 5 to 7 weeks before the latest.")
  }

  @Test("Each metric has a name the lifter would use")
  func metricNames() {
    #expect(ProgressCopy.metricName(.estimatedMax) == "Estimated max")
    #expect(ProgressCopy.metricName(.heaviestLoad) == "Heaviest weight")
    #expect(ProgressCopy.metricName(.repsAtTopLoad) == "Reps at the top weight")
  }
}
