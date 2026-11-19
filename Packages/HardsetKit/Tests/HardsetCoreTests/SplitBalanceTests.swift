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

  @Test("Each body group reads as the sets that touch it, or says nothing is planned")
  func rowsStateWhatIsPlanned() {
    let x = ExerciseID()
    let attribution = AttributionIndex([
      x: [
        MuscleContribution(.chest, role: .direct, certainty: .moderate, source: .convention),
        MuscleContribution(.triceps, role: .indirect, certainty: .moderate, source: .convention),
      ]
    ])
    let template = WorkoutTemplate(
      name: "Push", position: 0,
      exercises: [TemplateExercise(exerciseID: x, exerciseName: "Press", plannedSets: 1)])
    let single = SplitBalanceAnalyzer.balance(templates: [template], attribution: attribution)

    let rows = single.rows

    // Neck is left out when nothing is planned for it: it is rarely trained, and is not a gap.
    #expect(rows.map(\.group) == [.chest, .shoulders, .back, .arms, .core, .legs, .glutes])
    #expect(rows.first { $0.group == .chest }?.line == "1 set touches it")
    #expect(rows.first { $0.group == .arms }?.line == "1 set touches it")
    #expect(rows.first { $0.group == .back }?.line == "Nothing planned")
    #expect(rows.filter(\.isEmpty).map(\.group) == [.shoulders, .back, .core, .legs, .glutes])
    #expect(rows.first { $0.group == .chest }?.title == "Chest")
  }

  @Test("Several sets read as a count, and a planned neck is shown")
  func rowsCountAndShowNeck() {
    let neck = ExerciseID()
    let attribution = AttributionIndex([
      neck: [MuscleContribution(.neck, role: .direct, certainty: .moderate, source: .convention)]
    ])
    let template = WorkoutTemplate(
      name: "Neck", position: 0,
      exercises: [TemplateExercise(exerciseID: neck, exerciseName: "Neck curl", plannedSets: 4)])

    let rows = SplitBalanceAnalyzer.balance(templates: [template], attribution: attribution).rows

    #expect(rows.first { $0.group == .neck }?.line == "4 sets touch it")
  }

  @Test("Planned sets on a movement with no muscles are said not to count")
  func unattributedNote() {
    let unknown = ExerciseID()
    let template = WorkoutTemplate(
      name: "Mystery", position: 0,
      exercises: [TemplateExercise(exerciseID: unknown, exerciseName: "Sled drag", plannedSets: 3)])
    let balance = SplitBalanceAnalyzer.balance(templates: [template], attribution: AttributionIndex([:]))
    let none = SplitBalanceAnalyzer.balance(templates: [], attribution: AttributionIndex([:]))

    #expect(balance.unattributedNote == "3 planned sets are on movements with no muscles recorded, so they count toward none.")
    #expect(none.unattributedNote == nil)
    let one = WorkoutTemplate(
      name: "One", position: 0,
      exercises: [TemplateExercise(exerciseID: unknown, exerciseName: "Sled drag", plannedSets: 1)])
    #expect(SplitBalanceAnalyzer.balance(templates: [one], attribution: AttributionIndex([:])).unattributedNote
      == "1 planned set is on a movement with no muscles recorded, so it counts toward none.")
  }
}
