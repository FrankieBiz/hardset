import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A record stays on the row that earned it, and each moment is told once")
@MainActor
struct RecordMomentTests {
  let start = Date(timeIntervalSince1970: 23_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// A store with one exercise and a week-old 100 × 8, so there is something to beat.
  private func fixture() throws -> (LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let store = LoggerStore(database: database)
    let past = start.addingTimeInterval(-7 * 86_400)
    let session = try store.startSession(at: past)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: past)
    try store.finishSession(session, at: past.addingTimeInterval(3_600))
    return (store, exercise)
  }

  private func session(_ store: LoggerStore, _ exercise: ExerciseID) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)],
      now: { self.start }
    )
  }

  @discardableResult
  private func log(_ coordinator: SessionCoordinator, row: Int, _ weight: Double?, _ reps: Int) -> Bool {
    coordinator.exercises[0].slots[row].draft = SetEntryDraft(weightKg: weight, reps: reps)
    return coordinator.logSet(
      slotID: coordinator.exercises[0].slots[row].id, inExercise: coordinator.exercises[0].id)
  }

  @Test("A record is kept on its row after later sets are logged")
  func keptOnTheRow() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    #expect(log(coordinator, row: 0, 110, 8))
    let earned = coordinator.exercises[0].slots[0].id
    #expect(coordinator.recordsBySlot[earned]?.contains { $0.kind == .heaviestLoad } == true)

    #expect(log(coordinator, row: 1, 100, 8))

    #expect(coordinator.lastRecords.isEmpty)
    #expect(coordinator.recordsBySlot[earned]?.isEmpty == false)
    #expect(coordinator.recordsBySlot[coordinator.exercises[0].slots[1].id] == nil)
  }

  @Test("A record plays the record haptic and an ordinary set the log haptic, each once")
  func feedbackPerLog() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    log(coordinator, row: 0, 110, 8)
    let first = try #require(coordinator.feedback)
    #expect(first.event == .record)
    #expect(first.slotID == coordinator.exercises[0].slots[0].id)

    log(coordinator, row: 1, 100, 8)
    let second = try #require(coordinator.feedback)
    #expect(second.event == .log)
    #expect(second.slotID == coordinator.exercises[0].slots[1].id)
    #expect(second.sequence == first.sequence + 1)
  }

  @Test("A refused write plays the error haptic and claims nothing")
  func failureClaimsNothing() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    #expect(!log(coordinator, row: 0, nil, 8))
    #expect(coordinator.feedback?.event == .error)
    #expect(coordinator.recordsBySlot.isEmpty)
    #expect(!coordinator.exercises[0].slots[0].isLogged)
  }

  @Test("Logging a row twice plays nothing the second time")
  func noDoubleFeedback() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    log(coordinator, row: 0, 100, 8)
    let pulse = coordinator.feedback
    #expect(
      coordinator.logSet(
        slotID: coordinator.exercises[0].slots[0].id, inExercise: coordinator.exercises[0].id))
    #expect(coordinator.feedback == pulse)
  }

  @Test("A resumed workout gets its trophies back on the same rows, silently")
  func resumeRestoresTrophies() throws {
    let (store, exercise) = try fixture()
    let coordinator = try session(store, exercise)
    log(coordinator, row: 0, 110, 8)
    log(coordinator, row: 1, 100, 8)
    let recordSet = coordinator.exercises[0].slots[0].loggedSetID
    let plainSet = coordinator.exercises[0].slots[1].loggedSetID

    let resumed = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))

    let recordRow = try #require(resumed.exercises[0].slots.first { $0.loggedSetID == recordSet })
    let plainRow = try #require(resumed.exercises[0].slots.first { $0.loggedSetID == plainSet })
    #expect(resumed.recordsBySlot[recordRow.id]?.contains { $0.kind == .heaviestLoad } == true)
    #expect(resumed.recordsBySlot[plainRow.id] == nil)
    #expect(resumed.feedback == nil)
  }
}
