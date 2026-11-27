import Foundation
import Testing

@testable import HardsetCore

@Suite("Workout scorecard")
struct WorkoutScorecardTests {
  private func set(_ kg: Double, _ reps: Int) -> PriorSetRecord {
    PriorSetRecord(weightKg: kg, reps: reps, completedAt: .distantPast)
  }

  private func input(
    _ key: ProgressionKey, _ name: String,
    current: [(Double, Int)], previous: [(Double, Int)],
    range: RepRange? = nil, record: Bool = false, estimates: Bool = true
  ) -> ScorecardInput {
    ScorecardInput(
      key: key, exerciseName: name,
      currentSets: current.map { set($0.0, $0.1) },
      previousSets: previous.map { set($0.0, $0.1) },
      repRange: range, setRecord: record, estimatesOneRepMax: estimates
    )
  }

  @Test func countsMovementsNotSets() {
    let a = input(ProgressionKey(exerciseID: ExerciseID()), "A", current: [(40, 11)], previous: [(40, 10)])
    let b = input(ProgressionKey(exerciseID: ExerciseID()), "B", current: [(40, 10)], previous: [(40, 10)])
    let c = input(ProgressionKey(exerciseID: ExerciseID()), "C", current: [(40, 9)], previous: [(40, 10)])
    let d = input(ProgressionKey(exerciseID: ExerciseID()), "D", current: [(40, 10)], previous: [])
    let scorecard = WorkoutScorecard.make([a, b, c, d])

    #expect(scorecard.entries.count == 4)
    #expect(scorecard.beatenCount == 1)
    #expect(scorecard.comparedCount == 3)
    #expect(scorecard.headline == "Beat last time on 1 of 3")
    #expect(scorecard.entries[0].outcome == .beat(.beat(addedKg: 0, addedReps: 1)))
    #expect(scorecard.entries[1].outcome == .matched)
    #expect(scorecard.entries[2].outcome == .notBeaten)
    #expect(scorecard.entries[3].outcome == .firstTime)
  }

  @Test func recordWithoutBeatingPairStillBeats() {
    let a = input(
      ProgressionKey(exerciseID: ExerciseID()), "A",
      current: [(40, 9)], previous: [(40, 10)], record: true
    )
    let scorecard = WorkoutScorecard.make([a])
    #expect(scorecard.entries[0].outcome == .beat(nil))
    #expect(scorecard.beatenCount == 1)
    #expect(scorecard.recordMovementCount == 1)
  }

  @Test func loadJumpIsABeat() {
    let range = RepRange(lower: 8, upper: 12)!
    let a = input(
      ProgressionKey(exerciseID: ExerciseID()), "A",
      current: [(42.5, 8)], previous: [(40, 12)], range: range
    )
    let scorecard = WorkoutScorecard.make([a])
    #expect(scorecard.entries[0].outcome == .beat(.beat(addedKg: 2.5, addedReps: -4)))
  }

  @Test func biggestGainUsesEstimatedMax() {
    let a = input(ProgressionKey(exerciseID: ExerciseID()), "A", current: [(42.5, 10)], previous: [(40, 10)])
    let b = input(ProgressionKey(exerciseID: ExerciseID()), "B", current: [(40, 12)], previous: [(40, 10)])
    let scorecard = WorkoutScorecard.make([a, b])
    #expect(scorecard.biggestGain?.key == a.key)
    #expect(scorecard.biggestGain?.metric == .estimatedMax)
    #expect(abs((scorecard.biggestGain?.fraction ?? 0) - 0.0625) < 1e-9)
  }

  @Test func anEstimatedGainCarriesTheWeakerCertaintyOfTheTwoEstimatesItCompares() {
    // A single is measured and so high; five or ten reps are a formula and so moderate; twelve is
    // low. The gain is a ratio of two estimates, so it is only as sure as the weaker one,
    // whichever session it came from, and two formula estimates are never better than moderate.
    func gainCertainty(current: Int, previous: Int) -> Certainty? {
      let a = input(
        ProgressionKey(exerciseID: ExerciseID()), "A",
        current: [(60, current)], previous: [(40, previous)])
      return WorkoutScorecard.make([a]).biggestGain?.certainty
    }

    #expect(gainCertainty(current: 1, previous: 1) == .high)
    #expect(gainCertainty(current: 5, previous: 5) == .moderate)
    #expect(gainCertainty(current: 1, previous: 5) == .moderate)
    #expect(gainCertainty(current: 5, previous: 1) == .moderate)
    #expect(gainCertainty(current: 10, previous: 5) == .moderate)
    #expect(gainCertainty(current: 12, previous: 5) == .low)
    #expect(gainCertainty(current: 12, previous: 1) == .low)
  }

  @Test func aHeaviestLoadGainHasNoCertainty() {
    let a = input(ProgressionKey(exerciseID: ExerciseID()), "A", current: [(45, 15)], previous: [(40, 15)])
    let gain = WorkoutScorecard.make([a]).biggestGain

    #expect(gain?.metric == .heaviestLoad)
    #expect(gain?.certainty == nil)
  }

  @Test func biggestGainFallsBackToHeaviestLoad() {
    let a = input(ProgressionKey(exerciseID: ExerciseID()), "A", current: [(40, 15)], previous: [(40, 15)])
    let b = input(ProgressionKey(exerciseID: ExerciseID()), "B", current: [(45, 15)], previous: [(40, 15)])
    let scorecard = WorkoutScorecard.make([a, b])
    #expect(scorecard.biggestGain?.key == b.key)
    #expect(scorecard.biggestGain?.metric == .heaviestLoad)
    #expect(abs((scorecard.biggestGain?.fraction ?? 0) - 0.125) < 1e-9)
  }

  @Test func allFirstTimeHeadline() {
    let a = input(ProgressionKey(exerciseID: ExerciseID()), "A", current: [(40, 10)], previous: [])
    let scorecard = WorkoutScorecard.make([a])
    #expect(scorecard.comparedCount == 0)
    #expect(scorecard.headline == "First time on every movement")
  }

  @Test func emptyCurrentSetsDropped() {
    let empty = input(ProgressionKey(exerciseID: ExerciseID()), "Empty", current: [], previous: [(40, 10)])
    let firstTime = input(ProgressionKey(exerciseID: ExerciseID()), "First", current: [(40, 10)], previous: [])
    let scorecard = WorkoutScorecard.make([empty, firstTime])
    #expect(scorecard.entries.map(\.exerciseName) == ["First"])
  }
  @Test("An added-load percentage never outranks an estimated-max percentage")
  func addedLoadAndEstimatedGainsStaySeparate() {
    let bench = input(ProgressionKey(exerciseID: ExerciseID()), "Bench",
      current: [(110, 5)], previous: [(100, 5)])
    let dip = ScorecardInput(key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: "Dip",
      currentSets: [set(30, 5)], previousSets: [set(20, 5)],
      estimatesOneRepMax: false, assumesAddedLoad: true)
    let card = WorkoutScorecard.make([dip, bench])
    #expect(card.biggestGain?.key == bench.key)
    let added = WorkoutScorecard.make([dip])
    #expect(added.biggestGain?.metric == .addedLoad)
    #expect(added.biggestGain?.certainty == .low)
    #expect(ScorecardCopy.gainShareText(added)?.contains("body's own load is unknown") == true)
    let pull = ScorecardInput(key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: "Pull-up",
      currentSets: [set(0, 13)], previousSets: [set(0, 8)],
      estimatesOneRepMax: false, assumesAddedLoad: true)
    let reps = WorkoutScorecard.make([pull])
    #expect(reps.biggestGain?.metric == .repsAtTopLoad)
    #expect(reps.biggestGain?.certainty == .low)
    #expect(ScorecardCopy.gainShareText(reps)?.contains("body's own load is unknown") == true)
  }

  @Test("Only movements with exclusively estimated records receive the estimate-only qualifier")
  func estimateOnlyAndObservedRecordsStayDistinct() {
    func scored(_ kinds: Set<PersonalRecordKind>) -> WorkoutScorecard {
      WorkoutScorecard.make([ScorecardInput(key: ProgressionKey(exerciseID: ExerciseID()),
        exerciseName: "Press", currentSets: [set(97.5, 8)], previousSets: [set(100, 5)],
        recordKinds: kinds)])
    }
    let estimated = scored([.estimatedOneRepMax])
    #expect(estimated.estimateOnlyRecordMovementCount == 1)
    #expect(estimated.headline == "Beat last time on 1 of 1 · 1 estimate-only record")
    #expect(ScorecardCopy.recordsText(estimated) == "An estimated record on 1 movement")
    let observed = scored([.estimatedOneRepMax, .repsAtLoad])
    #expect(observed.estimateOnlyRecordMovementCount == 0)
    #expect(observed.headline == "Beat last time on 1 of 1")
    #expect(ScorecardCopy.recordsText(observed) == "A record on 1 movement")
    let mixed = WorkoutScorecard(entries: estimated.entries + observed.entries,
      beatenCount: 2, comparedCount: 2, recordMovementCount: 2, biggestGain: nil)
    #expect(ScorecardCopy.recordsText(mixed) == "A record on 1 movement · An estimated record on 1 movement")
  }

}

/// The receipt-scorecard render is built from these inputs through `WorkoutScorecard.make`, so its
/// counts, its records line and its rows come from one derivation. This pins what that fixture says,
/// on a machine that can run Core, since the render itself runs only where SwiftUI compiles.
@Suite("The scorecard fixture reconciles with what it draws")
struct ScorecardFixtureReconcilesTests {
  private func set(_ kg: Double, _ reps: Int) -> PriorSetRecord {
    PriorSetRecord(weightKg: kg, reps: reps, completedAt: .distantPast)
  }

  private func input(
    _ name: String, current: [PriorSetRecord], previous: [PriorSetRecord], record: Bool = false,
    equipment: WorkoutReceipt.Equipment? = nil
  ) -> ScorecardInput {
    ScorecardInput(
      key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: name, currentSets: current,
      previousSets: previous, setRecord: record, equipment: equipment)
  }

  @Test("Three of five beat last time, one record, two first times, and a gain the rows can reach")
  func fixture() throws {
    let card = WorkoutScorecard.make([
      input("Incline Press", current: [set(85, 8)], previous: [set(80, 8)],
        equipment: .machine("Cybex · Station 2")),
      input("Cable Row", current: [set(52.5, 11)], previous: [set(50, 10)]),
      input("Pec Deck", current: [set(60, 10)], previous: [set(60, 10)], record: true),
      input("Lateral Raise", current: [set(10, 12)], previous: [set(10, 12)]),
      input("Hack Squat", current: [set(120, 8)], previous: [], equipment: .machine("Hack Squat Sled")),
      input("Barbell Row", current: [set(70, 8)], previous: [], equipment: .freeWeight),
      input("Curl", current: [set(30, 9)], previous: [set(30, 10)]),
    ])
    #expect(card.headline == "Beat last time on 3 of 5")
    #expect(card.recordMovementCount == 1)
    #expect(ScorecardCopy.recordsText(card) == "A record on 1 movement")

    // Rows: the three that beat last time, the match and the two first times. The curl fell short,
    // which the headline's count carries, so it has no row; six rows over five compared movements.
    let marks = card.entries.compactMap { ScorecardCopy.markText($0, unit: .kilograms) }
    #expect(marks == [
      "+5 kg", "+2.5 kg · +1 rep", "Record", "Matched", "First time on this machine", "First time",
    ])
    #expect(card.entries.filter { if case .beat = $0.outcome { true } else { false } }.count
      == card.beatenCount)

    let gain = try #require(card.biggestGain)
    #expect(card.entries.contains { $0.exerciseName == gain.exerciseName })
    #expect(ScorecardCopy.gainText(card) == "Biggest gain: Cable Row, estimated max +8%")
  }
}
