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

  // MARK: - The board

  private typealias Sets = [(daysBack: Int, kg: Double, reps: Int)]

  private func row(
    _ name: String, _ sets: Sets, incrementKg: Double? = 2.5, estimates: Bool = true
  ) throws -> ProgressBoard.Row {
    let key = ProgressionKey(exerciseID: ExerciseID())
    let samples = sets.enumerated().map { index, set in
      ProgressionSample(
        sessionID: sessionID(index), machineID: nil, weightKg: set.kg, reps: set.reps,
        completedAt: epoch.addingTimeInterval(-Double(set.daysBack) * 86_400))
    }
    let trend = try #require(
      ProgressTrendAnalyzer.trend(
        key: key, samples: samples, incrementKg: incrementKg, estimatesOneRepMax: estimates))
    return ProgressBoard.Row(trend: trend, exerciseName: name)
  }

  private let singles: Sets = [(42, 100, 1), (28, 102.5, 1), (14, 105, 1), (0, 108, 1)]
  private let fives: Sets = [(42, 100, 5), (28, 102, 5), (14, 104, 5), (0, 108, 5)]

  @Test("Two 1-rep claims read Max in the row, the section row, the strip heading and the scorecard gain; a 5-rep set stays Estimated max")
  func everySurfaceNamesTheSingleAMax() throws {
    let single = try row("Chest press", singles)
    let five = try row("Hack squat", fives)
    #expect(single.trend.isMeasured)
    #expect(single.trend.certainty == .high)
    #expect(!five.trend.isMeasured)
    #expect(five.trend.certainty == .moderate)

    // The board, as the Progress tab reads it: section rows and the Most improved strip.
    let measuredBoard = ProgressBoard.make([.init(row: single, bodyPart: .chest)])
    let sectionRow = try #require(measuredBoard.sections.first?.rows.first)
    #expect(ProgressCopy.changeText(for: sectionRow.trend) == "Max +8% in 6 weeks")
    #expect(ProgressCopy.spokenRow(sectionRow).contains("Max +8% in 6 weeks"))
    #expect(!ProgressCopy.spokenRow(sectionRow).contains("Estimated"))
    #expect(
      ProgressCopy.mostImprovedHeading(measuredBoard.mostImproved.map(\.trend), metric: .estimatedMax)
        == "Most improved · max")

    let estimatedBoard = ProgressBoard.make([.init(row: five, bodyPart: .chest)])
    let estimatedRow = try #require(estimatedBoard.sections.first?.rows.first)
    #expect(ProgressCopy.changeText(for: estimatedRow.trend) == "Estimated max +8% in 6 weeks")
    #expect(
      ProgressCopy.mostImprovedHeading(estimatedBoard.mostImproved.map(\.trend), metric: .estimatedMax)
        == "Most improved · estimated max")

    // One estimated row behind the strip keeps the whole heading an estimate.
    let mixed = ProgressBoard.make([.init(row: single, bodyPart: .chest), .init(row: five, bodyPart: .back)])
    #expect(mixed.mostImproved.count == 2)
    #expect(
      ProgressCopy.mostImprovedHeading(mixed.mostImproved.map(\.trend), metric: .estimatedMax)
        == ProgressCopy.mostImprovedTitle)

    // The scorecard gain built from the same two sessions of each.
    func card(_ sets: Sets) -> WorkoutScorecard {
      let ordered = sets.sorted { $0.daysBack > $1.daysBack }
      let first = ordered.first!
      let last = ordered.last!
      return WorkoutScorecard.make([
        ScorecardInput(
          key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: "Chest press",
          currentSets: [prior(last.kg, last.reps, day: 42)],
          previousSets: [prior(first.kg, first.reps, day: 0)])
      ])
    }
    #expect(ScorecardCopy.gainText(card(singles)) == "Biggest gain: Chest press, max +8%")
    #expect(ScorecardCopy.gainText(card(fives)) == "Biggest gain: Chest press, estimated max +8%")
  }

  /// The Progress render's fixture rows, rebuilt here from the same sets, because the render itself
  /// only runs where SwiftUI compiles. It pins that each row's pair of words is one the analyser can
  /// produce: "High confidence" only ever beside "Max".
  @Test("The Progress fixture's rows are what the analyser says they are")
  func progressFixture() throws {
    let press = try row("Chest press", [(42, 100, 5), (35, 98, 5), (28, 100, 5), (21, 102, 5), (14, 104, 5), (0, 108, 5)])
    let fly = try row("Cable fly", [(42, 40, 1), (35, 38, 1), (28, 39, 1), (21, 39, 1), (14, 39.5, 1), (0, 42, 1)], incrementKg: 1)
    let lever = try row("Lever row", [(42, 50, 12), (35, 49, 12), (28, 56, 12), (21, 52, 12), (14, 54, 12), (0, 56, 12)])
    let squat = try row("Back squat", [(25, 100, 15), (20, 100, 15), (15, 102.5, 15), (10, 102.5, 15), (5, 105, 15), (0, 105, 15)])
    let pullup = try row("Pull-up", [(42, 0, 10), (35, 0, 9), (28, 0, 10), (21, 0, 11), (14, 0, 11), (0, 0, 12)], estimates: false)
    let mystery = try row("Pendulum squat", [(42, 100, 15), (35, 100, 15), (28, 100, 15), (21, 100, 15), (14, 100, 15), (0, 97, 15)])

    func change(_ r: ProgressBoard.Row) -> Double { r.trend.sixWeekChange ?? .nan }
    #expect(press.trend.metric == .estimatedMax && !press.trend.isMeasured && press.trend.certainty == .moderate)
    #expect(abs(change(press) - 0.08) < 1e-9)
    #expect(fly.trend.metric == .estimatedMax && fly.trend.isMeasured && fly.trend.certainty == .high)
    #expect(abs(change(fly) - 0.05) < 1e-9)
    #expect(lever.trend.metric == .estimatedMax && !lever.trend.isMeasured && lever.trend.certainty == .low)
    #expect(abs(change(lever) - 0.12) < 1e-9)
    #expect(lever.trend.stalledSessions == 3)
    #expect(squat.trend.metric == .heaviestLoad && squat.trend.sixWeekChange == nil)
    #expect(pullup.trend.metric == .repsAtTopLoad && abs(change(pullup) - 0.2) < 1e-9)
    #expect(mystery.trend.metric == .heaviestLoad && abs(change(mystery) + 0.03) < 1e-9)

    // No row anywhere pairs "Estimated max" with High confidence.
    for fixture in [press, fly, lever, squat, pullup, mystery] {
      let words = ProgressCopy.changeText(for: fixture.trend) ?? ProgressCopy.noChangeText(for: fixture.trend)
      if fixture.trend.certainty == .high { #expect(!words.contains("Estimated")) }
    }
    #expect(ProgressCopy.changeText(for: fly.trend) == "Max +5% in 6 weeks")
    #expect(ProgressCopy.changeText(for: press.trend) == "Estimated max +8% in 6 weeks")

    // The strip: a High row, a Moderate row and a Low row, so the heading stays "estimated max".
    let board = ProgressBoard.make([
      .init(row: press, bodyPart: .chest), .init(row: fly, bodyPart: .chest),
      .init(row: lever, bodyPart: .back), .init(row: pullup, bodyPart: .back),
      .init(row: squat, bodyPart: .quads), .init(row: mystery, bodyPart: nil),
    ])
    #expect(board.mostImproved.map(\.exerciseName) == ["Cable fly", "Chest press", "Lever row"])
    #expect(
      ProgressCopy.mostImprovedHeading(board.mostImproved.map(\.trend), metric: .estimatedMax)
        == "Most improved · estimated max")
  }
}
