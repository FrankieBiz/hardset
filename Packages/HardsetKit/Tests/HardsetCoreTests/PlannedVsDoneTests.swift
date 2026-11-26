import Foundation
import Testing

@testable import HardsetCore

@Suite("Planned against done counts one session's plan and the working sets it got")
struct PlannedVsDoneTests {
  private let bench = ExerciseID()
  private let row = ExerciseID()
  private let machine = MachineID()

  private func plan(
    _ id: UUID = UUID(), _ exercise: ExerciseID?, _ name: String,
    equipment: WorkoutReceipt.Equipment = .freeWeight, planned: Int?, machine: MachineID? = nil
  ) -> PlannedVsDone.PlanRow {
    .init(
      id: id, exerciseID: exercise, exerciseName: name, equipment: equipment,
      plannedSets: planned, machineID: machine)
  }

  private func logged(
    _ row: UUID?, _ exercise: ExerciseID, machine: MachineID? = nil, warmup: Bool = false
  ) -> PlannedVsDone.LoggedSet {
    .init(sessionExerciseID: row, exerciseID: exercise, machineID: machine, isWarmup: warmup)
  }

  @Test("Each row counts its own working sets, and a warm-up counts for no row")
  func countsOwnWorkingSets() throws {
    let first = UUID(), second = UUID()
    let planned = try #require(PlannedVsDone(
      planRows: [
        plan(first, bench, "Bench", planned: 4),
        plan(second, row, "Row", equipment: .unrecorded, planned: 3),
      ],
      loggedSets: [
        logged(first, bench), logged(first, bench), logged(first, bench),
        logged(first, bench, warmup: true),
        logged(second, row), logged(second, row),
      ]))

    #expect(planned.rows.map(\.doneSets) == [3, 2])
  }

  @Test("A planned movement with no working set is present as zero, not left out")
  func zeroDoneIsPresent() throws {
    let id = UUID()
    let planned = try #require(PlannedVsDone(
      planRows: [plan(id, bench, "Bench", planned: 3)], loggedSets: []))

    #expect(planned.rows.map(\.id) == [id])
    #expect(planned.rows.map(\.plannedSets) == [3])
    #expect(planned.rows.map(\.doneSets) == [0])
  }

  @Test("Rows stay in the plan's order")
  func planOrder() throws {
    let ids = [UUID(), UUID(), UUID()]
    let planned = try #require(PlannedVsDone(
      planRows: [
        plan(ids[2], row, "Row", planned: 1),
        plan(ids[0], bench, "Bench", planned: 1),
        plan(ids[1], row, "Curl", planned: 1),
      ],
      loggedSets: []))

    #expect(planned.rows.map(\.id) == [ids[2], ids[0], ids[1]])
    #expect(planned.rows.map(\.exerciseName) == ["Row", "Bench", "Curl"])
  }

  @Test("A plan row with no stated count, or a zero, produces no row at all")
  func noStatedCountIsAbsent() throws {
    let kept = UUID()
    let planned = try #require(PlannedVsDone(
      planRows: [
        plan(UUID(), bench, "Bench", planned: nil),
        plan(UUID(), row, "Row", planned: 0),
        plan(kept, bench, "Press", planned: 2),
      ],
      loggedSets: []))

    #expect(planned.rows.map(\.id) == [kept])
  }

  @Test("A set with no plan row counts only when its movement and machine name exactly one row")
  func unboundSetNeedsOneMatchingRow() throws {
    let only = UUID()
    let one = try #require(PlannedVsDone(
      planRows: [plan(only, bench, "Bench", planned: 3)],
      loggedSets: [logged(nil, bench)]))
    #expect(one.rows.map(\.doneSets) == [1])

    let first = UUID(), second = UUID()
    let ambiguous = try #require(PlannedVsDone(
      planRows: [
        plan(first, bench, "Bench", planned: 3),
        plan(second, bench, "Bench", planned: 3),
      ],
      loggedSets: [logged(nil, bench)]))
    // Neither row may claim the set, and no row is silently picked as its owner.
    #expect(ambiguous.rows.map(\.doneSets) == [0, 0])

    // A named set is never ambiguous: it belongs to the row it names.
    let named = try #require(PlannedVsDone(
      planRows: [
        plan(first, bench, "Bench", planned: 3),
        plan(second, bench, "Bench", planned: 3),
      ],
      loggedSets: [logged(first, bench), logged(nil, bench)]))
    #expect(named.rows.map(\.doneSets) == [1, 0])
  }

  @Test("A set for another machine does not count for a row with a machine")
  func unboundSetMustMatchTheMachine() throws {
    let id = UUID()
    let planned = try #require(PlannedVsDone(
      planRows: [plan(id, row, "Row", equipment: .machine("Sled"), planned: 3, machine: machine)],
      loggedSets: [logged(nil, row, machine: MachineID())]))
    #expect(planned.rows.map(\.doneSets) == [0])
  }

  @Test("An imported workout, or one with no plan rows, has no planned block")
  func absentBlocks() {
    let planned = [plan(UUID(), bench, "Bench", planned: 3)]

    #expect(PlannedVsDone(
      planRows: planned, loggedSets: [logged(nil, bench)], notes: "Imported from Strong") == nil)
    #expect(PlannedVsDone(planRows: [], loggedSets: [logged(nil, bench)]) == nil)
    // A workout built by hand has no plan row to compare against.
    #expect(PlannedVsDone(planRows: [], loggedSets: []) == nil)
  }

  @Test("The copy states counts only: no percentage, failure word or advice")
  func copyIsCountsOnly() throws {
    let first = UUID(), second = UUID()
    let planned = try #require(PlannedVsDone(
      planRows: [
        plan(first, bench, "Bench", planned: 4),
        plan(second, row, "Row", equipment: .unrecorded, planned: 3),
      ],
      loggedSets: [
        logged(first, bench), logged(first, bench), logged(first, bench),
      ]))
    let single = try #require(PlannedVsDone(
      planRows: [plan(UUID(), bench, "Bench", planned: 3)], loggedSets: []))

    #expect(PlannedVsDoneCopy.heading == "Planned against done")
    #expect(PlannedVsDoneCopy.rowText(done: 3, planned: 4) == "3 of 4 planned sets")
    #expect(PlannedVsDoneCopy.rowText(planned.rows[0]) == "3 of 4 planned sets")
    #expect(PlannedVsDoneCopy.totalText(planned) == "3 of 7 planned sets")
    #expect(PlannedVsDoneCopy.totalText(single) == nil)
    #expect(PlannedVsDoneCopy.accessibilityLabel(planned.rows[0]) == "Bench, 3 of 4 planned sets")
    #expect(PlannedVsDoneCopy.accessibilityLabel(planned.rows[1]) == "Row, 0 of 3 planned sets")

    let phrases = [
      PlannedVsDoneCopy.heading,
      PlannedVsDoneCopy.rowText(planned.rows[0]),
      PlannedVsDoneCopy.rowText(planned.rows[1]),
      PlannedVsDoneCopy.totalText(planned) ?? "",
      PlannedVsDoneCopy.accessibilityLabel(planned.rows[0]),
    ]
    for phrase in phrases {
      let lower = phrase.lowercased()
      #expect(!phrase.contains("%"))
      #expect(phrase.range(of: #"\d%"#, options: .regularExpression) == nil)
      for word in ["missed", "failed", "only", "should", "behind", "short"] {
        #expect(!lower.contains(word), "\(word) appeared in: \(phrase)")
      }
      for verb in ["try", "aim", "add", "increase", "reduce", "keep", "must"] {
        #expect(!lower.contains(verb), "\(verb) appeared in: \(phrase)")
      }
    }
  }
}
