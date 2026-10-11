import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A deleted set stays deleted after a resume")
@MainActor
struct DeletedSetPlanTests {
  let start = Date(timeIntervalSince1970: 24_000_000)

  private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  private func fixture() throws -> (LoggerStore, ExerciseID) {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    let exercise = ExerciseID()
    try queue.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    return (LoggerStore(database: queue), exercise)
  }

  private func begin(
    _ store: LoggerStore, _ exercise: ExerciseID, planned: Int?, clock: Clock
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: planned)],
      now: { clock.now })
  }

  private func log(_ c: SessionCoordinator, count: Int) {
    for row in 0..<count {
      c.exercises[0].slots[row].draft = SetEntryDraft(weightKg: 100, reps: 8)
      #expect(c.logSet(slotID: c.exercises[0].slots[row].id, inExercise: c.exercises[0].id))
    }
  }

  private func delete(_ c: SessionCoordinator, row: Int) -> Bool {
    c.deleteSet(slotID: c.exercises[0].slots[row].id, inExercise: c.exercises[0].id)
  }

  private func resumed(_ store: LoggerStore, _ clock: Clock) throws -> SessionCoordinator {
    try #require(try SessionCoordinator.resume(store: store, now: { clock.now }))
  }

  private func planned(_ store: LoggerStore, _ c: SessionCoordinator) throws -> Int? {
    try store.sessionExercises(in: c.sessionID).first?.plannedSets
  }

  @Test("Plan 3, log 3, delete 1: a resume holds two logged rows and finishes without asking")
  func deletedLoggedRowStaysGone() throws {
    let (store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try begin(store, exercise, planned: 3, clock: clock)
    log(c, count: 3)
    #expect(delete(c, row: 1))
    #expect(c.finishDecision == .finish)

    let r = try resumed(store, clock)

    #expect(r.exercises[0].slots.count == 2)
    #expect(r.exercises[0].slots.allSatisfy { $0.isLogged })
    #expect(r.finishDecision == .finish)
    #expect(try planned(store, r) == 2)
  }

  @Test("Plan 3, log 1, delete it: a resume holds two open rows and offers to discard")
  func deletedOnlySetLeavesOpenRows() throws {
    let (store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try begin(store, exercise, planned: 3, clock: clock)
    log(c, count: 1)
    #expect(delete(c, row: 0))

    let r = try resumed(store, clock)

    #expect(r.exercises[0].slots.count == 2)
    #expect(r.exercises[0].slots.allSatisfy { !$0.isLogged })
    #expect(r.finishDecision == .discardEmpty)
  }

  @Test("Delete then undo within the window: a resume has the original rows and plan")
  func undoRestoresPlan() throws {
    let (store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try begin(store, exercise, planned: 3, clock: clock)
    log(c, count: 3)
    #expect(delete(c, row: 2))
    #expect(try planned(store, c) == 2)

    #expect(c.undoDelete())
    #expect(try planned(store, c) == 3)

    let r = try resumed(store, clock)
    #expect(r.exercises[0].slots.count == 3)
    #expect(r.exercises[0].slots.allSatisfy { $0.isLogged })
    #expect(r.finishDecision == .finish)
  }

  @Test("With no planned count, a delete leaves the plan nil and a resume pads nothing")
  func nilPlanIsUntouched() throws {
    let (store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try begin(store, exercise, planned: nil, clock: clock)
    log(c, count: 1)
    c.addSet(inExercise: c.exercises[0].id)
    c.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(c.logSet(slotID: c.exercises[0].slots[1].id, inExercise: c.exercises[0].id))
    let before = c.exercises[0].slots.count
    #expect(delete(c, row: 0))
    #expect(try planned(store, c) == nil)

    let r = try resumed(store, clock)

    #expect(r.exercises[0].slots.count == before - 1)
    #expect(r.exercises[0].slots.allSatisfy { $0.isLogged })
    #expect(c.undoDelete())
    #expect(try planned(store, c) == nil)
  }

  @Test("A delete that fails changes neither the set rows nor the plan")
  func failedDeleteLeavesPlan() throws {
    let (store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try begin(store, exercise, planned: 3, clock: clock)
    log(c, count: 2)
    let planRow = try #require(try store.sessionExercises(in: c.sessionID).first).id

    #expect(throws: LoggerStoreError.setNotFound) {
      try store.deleteSet(SetID(), loweringPlanRow: planRow, keepingAtLeast: 0)
    }

    #expect(try planned(store, c) == 3)
    #expect(try store.sets(in: c.sessionID).count == 2)
  }

  @Test("The plan is never lowered below the rows the exercise still holds")
  func floorHolds() throws {
    let (store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try begin(store, exercise, planned: 3, clock: clock)
    log(c, count: 3)
    let planRow = try #require(try store.sessionExercises(in: c.sessionID).first).id
    let id = try #require(c.exercises[0].slots[0].loggedSetID)

    let result = try store.deleteSet(id, loweringPlanRow: planRow, keepingAtLeast: 3)

    #expect(result.lowered == 0)
    #expect(try planned(store, c) == 3)
  }
}
