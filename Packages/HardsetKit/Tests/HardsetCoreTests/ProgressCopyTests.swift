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

  @Test("With no session six weeks back there is no change to state, and the row says so")
  func noWindowMeansNotEnoughHistory() {
    #expect(ProgressCopy.changeText(for: trend(.estimatedMax, change: nil)) == nil)
    #expect(ProgressCopy.notEnoughHistory == "Not enough history")
  }

  @Test("The short form is what the Most improved strip shows")
  func shortChange() {
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: 0.08)) == "+8% in 6 weeks")
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: -0.03)) == "−3% in 6 weeks")
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: 0.001)) == "unchanged in 6 weeks")
    #expect(ProgressCopy.shortChangeText(for: trend(.estimatedMax, change: nil)) == nil)
  }

  @Test("Stalled says how many sessions, and states no advice")
  func stalledText() {
    #expect(ProgressCopy.stalledText(for: trend(.estimatedMax, change: 0.1, stalled: 3))
      == "Stalled · 3 sessions")
    #expect(ProgressCopy.stalledText(for: trend(.estimatedMax, change: 0.1, stalled: nil)) == nil)
  }

  @Test("A row is spoken as the movement, its machine, the change and any stall")
  func spokenRow() {
    let key = ProgressionKey(exerciseID: ExerciseID(), machineID: MachineID())
    let stalled = MovementTrend(
      key: key, metric: .estimatedMax, sparkline: [1], sixWeekChange: 0.08, sessionCount: 5,
      stalledSessions: 3, latestDate: Date(timeIntervalSince1970: 0), certainty: .moderate)
    let plain = MovementTrend(
      key: key, metric: .heaviestLoad, sparkline: [1], sixWeekChange: nil, sessionCount: 2,
      stalledSessions: nil, latestDate: Date(timeIntervalSince1970: 0))

    #expect(ProgressCopy.spokenRow(
      ProgressBoard.Row(trend: stalled, exerciseName: "Chest press", machineName: "Hammer"))
      == "Chest press, Hammer. Estimated max +8% in 6 weeks. Stalled · 3 sessions.")
    #expect(ProgressCopy.spokenRow(ProgressBoard.Row(trend: plain, exerciseName: "Squat"))
      == "Squat. Not enough history.")
  }

  @Test("Each metric has a name the lifter would use")
  func metricNames() {
    #expect(ProgressCopy.metricName(.estimatedMax) == "Estimated max")
    #expect(ProgressCopy.metricName(.heaviestLoad) == "Heaviest weight")
    #expect(ProgressCopy.metricName(.repsAtTopLoad) == "Reps at the top weight")
  }
}
