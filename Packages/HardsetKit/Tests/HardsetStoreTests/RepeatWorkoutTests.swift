import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("History becomes a deliberate, equipment-safe workout")
struct RepeatWorkoutTests {
  let now = Date(timeIntervalSince1970: 20_000_000)

  private func fixture() async throws -> (DatabaseQueue, SessionID, GymID, MachineID) {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let session = SessionID(), gym = GymID(), machine = MachineID()
    let exercise = UUID(), first = UUID(), second = UUID()
    try await db.write { db in
      try Gym.insert { Gym.Draft(id: gym.rawValue, name: "Home") }.execute(db)
      try Machine.insert { Machine.Draft(id: machine.rawValue, gymID: gym.rawValue, name: "Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: exercise, name: "Chest press") }.execute(db)
      try Session.insert { Session.Draft(id: session.rawValue, gymID: gym.rawValue, title: "Upper", startedAt: now, finishedAt: now.addingTimeInterval(600)) }.execute(db)
      for (position, id) in [first, second].enumerated() {
        try SessionExercise.insert { SessionExercise.Draft(id: id, sessionID: session.rawValue,
          exerciseID: exercise, machineID: machine.rawValue, position: position, plannedSets: 9) }.execute(db)
      }
      for i in 0..<4 {
        try LoggedSet.insert { LoggedSet.Draft(id: UUID(), sessionID: session.rawValue,
          exerciseID: exercise, machineID: machine.rawValue, sessionExerciseID: i < 3 ? first : second,
          setOrdinal: i, weightKg: 60, reps: 8, isWarmup: i == 0,
          completedAt: now.addingTimeInterval(Double(i))) }.execute(db)
      }
    }
    return (db, session, gym, machine)
  }

  @Test("Repeats performed counts and distinct movement occurrences, not the uncompleted plan")
  @MainActor
  func repeatAndRecover() async throws {
    let (db, source, gym, machine) = try await fixture()
    let preview = try await RepeatWorkoutStore(database: db).load(source, at: gym)
    #expect(preview.exercises.map(\.plannedSets) == [2, 1])
    #expect(preview.exercises.map(\.machineID) == [machine, machine])
    #expect(preview.workingSets == 3)
    let logger = LoggerStore(database: db)
    let model = WorkoutRootModel(logger: logger, catalog: CatalogSeeder(database: db), gyms: GymStore(database: db), now: { now.addingTimeInterval(1000) })
    #expect(throws: WorkoutRootError.notReady) { try model.startWorkout(repeating: preview) }
    await model.load()
    model.selectedGym = gym
    try model.startWorkout(repeating: preview)
    let live = try #require(model.coordinator)
    #expect(live.sessionID != source)
    #expect(live.loggedSetCount == 0)
    #expect(live.exercises.map { $0.slots.count } == [2, 1])
    #expect(live.exercises[0].slots[0].draft.resolved()?.weightKg == 60)
    #expect(throws: WorkoutRootError.workoutAlreadyOpen) { try model.startWorkout(repeating: preview) }
    let recovered = try #require(try SessionCoordinator.resume(store: logger))
    #expect(recovered.exercises.map { $0.slots.count } == [2, 1])
    let facts = try await db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM loggedSets") }
    #expect(facts == 4)
  }

  @Test("Changing gyms drops machine identity and all automatic load suggestions")
  @MainActor
  func otherGym() async throws {
    let (db, source, gym, _) = try await fixture()
    // Unknown-equipment history must not become an automatic suggestion, even after relaunch.
    try await db.write { try $0.execute(sql: "UPDATE loggedSets SET machineID = NULL") }
    let preview = try await RepeatWorkoutStore(database: db).load(source, at: nil)
    #expect(preview.exercises.allSatisfy { $0.machineID == nil })
    let model = WorkoutRootModel(logger: LoggerStore(database: db), catalog: CatalogSeeder(database: db), gyms: GymStore(database: db))
    await model.load()
    model.selectedGym = gym
    #expect(throws: RepeatWorkoutError.gymChanged) { try model.startWorkout(repeating: preview) }
    model.selectedGym = nil
    try model.startWorkout(repeating: preview)
    let live = try #require(model.coordinator)
    #expect(live.exercises.allSatisfy { $0.slots.allSatisfy { $0.draft.resolved() == nil } })
    let recovered = try #require(try SessionCoordinator.resume(store: LoggerStore(database: db)))
    #expect(recovered.exercises.allSatisfy { $0.slots.allSatisfy { $0.draft.resolved() == nil } })
  }

  @Test("Archived equipment becomes unknown; archived movements cannot silently return")
  func archived() async throws {
    let (db, source, gym, _) = try await fixture()
    try await db.write { try $0.execute(sql: "UPDATE machines SET isArchived = 1") }
    let preview = try await RepeatWorkoutStore(database: db).load(source, at: gym)
    #expect(preview.exercises.allSatisfy { $0.machineID == nil })
    try await db.write { try $0.execute(sql: "UPDATE exercises SET isArchived = 1") }
    await #expect(throws: RepeatWorkoutError.noAvailableWorkingSets) {
      try await RepeatWorkoutStore(database: db).load(source, at: gym)
    }
  }

  @Test("Open and empty workouts cannot become repeat plans")
  func invalidSource() async throws {
    let (db, source, gym, _) = try await fixture()
    try await db.write { try $0.execute(sql: "UPDATE sessions SET finishedAt = NULL") }
    await #expect(throws: RepeatWorkoutError.unfinishedOrMissing) {
      try await RepeatWorkoutStore(database: db).load(source, at: gym)
    }
    try await db.write { db in
      try db.execute(sql: "UPDATE sessions SET finishedAt = startedAt")
      try db.execute(sql: "DELETE FROM loggedSets")
    }
    await #expect(throws: RepeatWorkoutError.noAvailableWorkingSets) {
      try await RepeatWorkoutStore(database: db).load(source, at: gym)
    }
  }

  @Test("The additive migration preserves existing sessions and defaults their policy")
  func migration() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db, upTo: "v9_progressionOrder")
    try await db.write { db in
      try db.execute(sql: "INSERT INTO sessions (id, title, startedAt) VALUES (?, 'Original', '2026-01-01 00:00:00.000')", arguments: [UUID().uuidString])
    }
    try HardsetMigrations.migrator().migrate(db)
    try HardsetMigrations.migrator().migrate(db)
    let values = try await db.read { db in
      (try String.fetchOne(db, sql: "SELECT title FROM sessions"),
       try Bool.fetchOne(db, sql: "SELECT knownEquipmentOnly FROM sessions"))
    }
    #expect(values.0 == "Original")
    #expect(values.1 == false)
  }

  @Test("A failed plan write creates no partial workout")
  @MainActor
  func failedStart() async throws {
    let (db, source, gym, _) = try await fixture()
    let preview = try await RepeatWorkoutStore(database: db).load(source, at: gym)
    let model = WorkoutRootModel(logger: LoggerStore(database: db), catalog: CatalogSeeder(database: db), gyms: GymStore(database: db))
    await model.load()
    model.selectedGym = gym
    try await db.write { try $0.execute(sql: "CREATE TRIGGER rejectPlan BEFORE INSERT ON sessionExercises BEGIN SELECT RAISE(ABORT, 'test'); END") }
    #expect(throws: (any Error).self) { try model.startWorkout(repeating: preview) }
    #expect(model.coordinator == nil)
    let count = try await db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sessions") }
    #expect(count == 1)
  }
}
