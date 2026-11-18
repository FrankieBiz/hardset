import Foundation
import Testing

@testable import HardsetCore

@Suite("Planned split balance")
struct SplitBalanceTests {
  @Test func splitBalanceCountsPlannedSets() {
    let x = ExerciseID()
    let y = ExerciseID()
    let z = ExerciseID()

    let attribution = AttributionIndex([
      x: [
        MuscleContribution(.chest, role: .direct, certainty: .moderate, source: .convention),
        MuscleContribution(.triceps, role: .indirect, certainty: .moderate, source: .convention),
      ],
      y: [
        MuscleContribution(.lats, role: .direct, certainty: .moderate, source: .convention),
        MuscleContribution(.biceps, role: .indirect, certainty: .moderate, source: .convention),
      ],
    ])

    func exercise(_ id: ExerciseID, sets: Int) -> TemplateExercise {
      TemplateExercise(exerciseID: id, exerciseName: "Movement", plannedSets: sets)
    }

    let a = WorkoutTemplate(
      name: "A", position: 0, exercises: [exercise(x, sets: 3)]
    )
    let b = WorkoutTemplate(
      name: "B", position: 1, exercises: [exercise(y, sets: 4), exercise(z, sets: 2)]
    )

    let balance = SplitBalanceAnalyzer.balance(templates: [a, b], attribution: attribution)

    #expect(balance.report.setsTouchingGroup[.chest] == 3)
    #expect(balance.report.setsTouchingGroup[.arms] == 7)
    #expect(balance.report.setsTouchingGroup[.back] == 4)
    #expect(balance.report.sets(for: .chest) == 3)
    #expect(balance.report.sets(for: .triceps) == 1.5)
    #expect(balance.report.sets(for: .lats) == 4)
    #expect(balance.report.sets(for: .biceps) == 2)
    #expect(balance.report.unattributedHardSets == 2)
    #expect(balance.emptyGroups == [.shoulders, .core, .legs, .glutes])
  }
}
