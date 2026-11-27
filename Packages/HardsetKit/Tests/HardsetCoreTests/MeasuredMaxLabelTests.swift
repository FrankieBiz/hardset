import Foundation
import Testing

@testable import HardsetCore

/// A one-rep set is the observation, not an estimate, and `StrengthMath` rates it High with a
/// measured source. So the words beside it must not say "Estimated max": a row, a scorecard gain and
/// the account that explains them all name a measured figure "Max" and a formula's figure
/// "Estimated max", through one rule, `ProgressTrendAnalyzer.isMeasured`.
@Suite("A measured single is a max, not an estimated max")
struct MeasuredMaxLabelTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)
  let exercise = ExerciseID()
  private let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func sessionID(_ n: Int) -> SessionID {
    SessionID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!)
  }

  private func sample(_ session: Int, day: Int, kg: Double, reps: Int) -> ProgressionSample {
    ProgressionSample(
      sessionID: sessionID(session), machineID: nil, weightKg: kg, reps: reps,
      completedAt: epoch.addingTimeInterval(Double(day) * 86_400))
  }

  private func trend(_ samples: [ProgressionSample]) -> MovementTrend? {
    ProgressTrendAnalyzer.trend(
      key: ProgressionKey(exerciseID: exercise), samples: samples, incrementKg: 2.5,
      estimatesOneRepMax: true)
  }

  private func prior(_ kg: Double, _ reps: Int, day: Int) -> PriorSetRecord {
    PriorSetRecord(
      weightKg: kg, reps: reps, completedAt: epoch.addingTimeInterval(Double(day) * 86_400))
  }

  private func scorecardInput(current: (Double, Int), previous: (Double, Int)) -> ScorecardInput {
    ScorecardInput(
      key: ProgressionKey(exerciseID: exercise), exerciseName: "Bench press",
      currentSets: [prior(current.0, current.1, day: 42)],
      previousSets: [prior(previous.0, previous.1, day: 0)])
  }

  @Test("The metric's name is Max only when the figure is measured")
  func metricName() {
    #expect(ProgressCopy.metricName(.estimatedMax) == "Estimated max")
    #expect(ProgressCopy.metricName(.estimatedMax, measured: false) == "Estimated max")
    #expect(ProgressCopy.metricName(.estimatedMax, measured: true) == "Max")
    // No other metric has a measured form: they were never estimates.
    #expect(ProgressCopy.metricName(.heaviestLoad, measured: true) == "Heaviest weight")
    #expect(ProgressCopy.metricName(.repsAtTopLoad, measured: true) == "Reps at the top weight")
  }

  @Test("A trend whose best estimate is a one-rep set is labelled Max")
  func trendOfASingle() throws {
    let single = try #require(trend([sample(0, day: 0, kg: 100, reps: 1)]))
    #expect(single.metric == .estimatedMax)
    #expect(single.isMeasured)
    #expect(ProgressCopy.noChangeText(for: single) == "Max · no 6-week comparison")
  }

  @Test("A five-rep set is a formula's figure and is still labelled Estimated max")
  func trendOfAFiveRepSet() throws {
    let five = try #require(trend([sample(0, day: 0, kg: 100, reps: 5)]))
    #expect(five.metric == .estimatedMax)
    #expect(!five.isMeasured)
    #expect(ProgressCopy.noChangeText(for: five) == "Estimated max · no 6-week comparison")
  }

  @Test("A six-week change between two singles is a change in max")
  func changeBetweenSingles() throws {
    let row = try #require(trend([
      sample(0, day: 0, kg: 100, reps: 1), sample(1, day: 42, kg: 105, reps: 1),
    ]))
    #expect(row.isMeasured)
    #expect(row.certainty == .high)
    #expect(ProgressCopy.changeText(for: row) == "Max +5% in 6 weeks")
  }

  @Test("A change that has a formula's estimate on either side stays an estimated max")
  func changeAgainstAnEstimate() throws {
    // The latest session is a single, but the baseline is five reps: half the change is a formula.
    let lastIsSingle = try #require(trend([
      sample(0, day: 0, kg: 80, reps: 5), sample(1, day: 42, kg: 105, reps: 1),
    ]))
    #expect(!lastIsSingle.isMeasured)
    #expect(ProgressCopy.changeText(for: lastIsSingle)?.hasPrefix("Estimated max ") == true)

    let baselineIsSingle = try #require(trend([
      sample(0, day: 0, kg: 100, reps: 1), sample(1, day: 42, kg: 90, reps: 5),
    ]))
    #expect(!baselineIsSingle.isMeasured)
    #expect(ProgressCopy.changeText(for: baselineIsSingle)?.hasPrefix("Estimated max ") == true)
  }

  @Test("A trend on another metric is never measured-max, whatever its sets")
  func otherMetricsAreUnchanged() throws {
    let bodyweight = try #require(
      ProgressTrendAnalyzer.trend(
        key: ProgressionKey(exerciseID: exercise),
        samples: [sample(0, day: 0, kg: 100, reps: 1)], incrementKg: nil, estimatesOneRepMax: false))
    #expect(bodyweight.metric == .repsAtTopLoad)
    #expect(!bodyweight.isMeasured)
  }

  @Test("The spoken row says Max for a single")
  func spokenRow() throws {
    let row = try #require(trend([
      sample(0, day: 0, kg: 100, reps: 1), sample(1, day: 42, kg: 105, reps: 1),
    ]))
    let spoken = ProgressCopy.spokenRow(ProgressBoard.Row(trend: row, exerciseName: "Bench press"))
    #expect(spoken.contains("Max +5% in 6 weeks"))
    #expect(!spoken.contains("Estimated"))
  }

  @Test("The scorecard's gain between two singles says max, and the five-rep gain says estimated")
  func scorecardGain() throws {
    let singles = try #require(
      WorkoutScorecard.make([scorecardInput(current: (105, 1), previous: (100, 1))]).biggestGain)
    #expect(singles.isMeasured)
    #expect(ScorecardCopy.gainText(WorkoutScorecard.make([scorecardInput(current: (105, 1), previous: (100, 1))]))
      == "Biggest gain: Bench press, max +5%")

    let fives = WorkoutScorecard.make([scorecardInput(current: (105, 5), previous: (100, 5))])
    let fiveGain = try #require(fives.biggestGain)
    #expect(!fiveGain.isMeasured)
    #expect(ScorecardCopy.gainText(fives) == "Biggest gain: Bench press, estimated max +5%")

    let mixed = WorkoutScorecard.make([scorecardInput(current: (120, 1), previous: (100, 5))])
    let mixedGain = try #require(mixed.biggestGain)
    #expect(!mixedGain.isMeasured)
    #expect(ScorecardCopy.gainText(mixed)?.contains("estimated max") == true)
  }

  @Test("The scorecard gain, the Progress row and the Worked from account name a single alike")
  func surfacesAgree() throws {
    let row = try #require(trend([
      sample(0, day: 0, kg: 100, reps: 1), sample(1, day: 42, kg: 105, reps: 1),
    ]))
    let card = WorkoutScorecard.make([scorecardInput(current: (105, 1), previous: (100, 1))])
    let gain = try #require(card.biggestGain)

    #expect(ProgressCopy.changeText(for: row)?.hasPrefix("Max ") == true)
    #expect(ScorecardCopy.gainText(card)?.contains(", max +") == true)

    let working = try #require(ChangeWorking.lastTime(gain: gain))
    #expect(working.isMeasured == gain.isMeasured)
    #expect(working.account(format: format).title == "Max since last time")

    let sixWeek = try #require(
      ChangeWorking.sixWeek(
        key: ProgressionKey(exerciseID: exercise),
        samples: [sample(0, day: 0, kg: 100, reps: 1), sample(1, day: 42, kg: 105, reps: 1)],
        estimatesOneRepMax: true, label: { _ in "Free weight" }))
    #expect(sixWeek.isMeasured == row.isMeasured)
    #expect(sixWeek.account(format: format).title == "Max over six weeks")
  }

  @Test("The account of a formula's change keeps the estimated name")
  func accountKeepsEstimatedName() throws {
    let card = WorkoutScorecard.make([scorecardInput(current: (105, 5), previous: (100, 5))])
    let gain = try #require(card.biggestGain)
    let working = try #require(ChangeWorking.lastTime(gain: gain))
    #expect(!working.isMeasured)
    #expect(working.account(format: format).title == "Estimated max since last time")
  }
}
