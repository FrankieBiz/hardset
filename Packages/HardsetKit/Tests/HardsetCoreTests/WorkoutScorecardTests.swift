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
}
