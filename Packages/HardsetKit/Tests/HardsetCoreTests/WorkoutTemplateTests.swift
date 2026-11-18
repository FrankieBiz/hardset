import Foundation
import Testing

@testable import HardsetCore

@Suite("Saved workouts and their rotation")
struct WorkoutTemplateTests {
  @Test func repRangeRejectsImpossibleRanges() {
    #expect(RepRange(lower: 12, upper: 8) == nil)
    #expect(RepRange(lower: 0, upper: 5) == nil)
    #expect(RepRange(lower: 8, upper: 51) == nil)
    #expect(RepRange(lower: 8, upper: 12)?.label == "8–12")   // en dash
    #expect(RepRange(lower: 10, upper: 10)?.label == "10")
  }

  @Test func plannedSetsAndRestAreClamped() {
    let low = TemplateExercise(exerciseID: ExerciseID(), exerciseName: "Row", plannedSets: 0, restSeconds: 0)
    let high = TemplateExercise(exerciseID: ExerciseID(), exerciseName: "Row", plannedSets: 14, restSeconds: 90)
    #expect(low.plannedSets == 1); #expect(low.restSeconds == nil)
    #expect(high.plannedSets == 10); #expect(high.restSeconds == 90)
  }

  @Test func upNextIsNeverDoneThenOldestThenPosition() {
    // a: position 0, done day 10; b: position 1, done day 3; c: position 2, never; d: position 3, done day 3
    // expected order: c, b, d, a
    let day0 = Date(timeIntervalSince1970: 1_700_000_000)
    func day(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 86_400) }
    func template(_ position: Int, lastDoneAt: Date?) -> WorkoutTemplate {
      WorkoutTemplate(
        id: TemplateID(),
        name: "Workout \(position)",
        position: position,
        exercises: [],
        lastDoneAt: lastDoneAt
      )
    }

    let a = template(0, lastDoneAt: day(10))
    let b = template(1, lastDoneAt: day(3))
    let c = template(2, lastDoneAt: nil)
    let d = template(3, lastDoneAt: day(3))

    #expect(WorkoutRotation.upNextOrder([a, b, c, d]).map(\.id) == [c.id, b.id, d.id, a.id])
  }

  @Test func upNextOfEmptyIsEmpty() { #expect(WorkoutRotation.upNextOrder([]).isEmpty) }
}
