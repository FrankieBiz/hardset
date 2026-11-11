import Dispatch
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

@Suite("The root recovers before offering a new workout")
struct WorkoutRootModelTests {
  let now = Date(timeIntervalSince1970: 16_000_000)

  private func fixture() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    return database
  }

  @Test("A failed recovery cannot enable a second workout")
  @MainActor
  func recoveryFailureKeepsStartGated() async throws {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let session = try logger.startSession(at: now)
    try await database.write { db in
      try db.execute(sql: "ALTER TABLE sessionExercises RENAME TO hiddenPlan")
    }
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database), gyms: GymStore(database: database)
    )
    await model.load()
    #expect(!model.isReady)
    #expect(model.lastError != nil)
    #expect(throws: WorkoutRootError.notReady) { try model.startWorkout() }
    let count = try await database.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM sessions") }
    #expect(count == 1)
    #expect(try logger.openSession()?.id == session)
    try await database.write { db in
      try db.execute(sql: "ALTER TABLE hiddenPlan RENAME TO sessionExercises")
    }
    await model.load()
    #expect(model.isReady)
    #expect(model.lastError == nil)
    #expect(model.coordinator?.sessionID == session)
  }

  @Test("Root catalog loading leaves the main actor available")
  @MainActor
  func rootLoadReleasesMainActor() async throws {
    let database = try fixture()
    let fired = Mutex(false)
    let mainActorRan = Mutex(false)
    let begins = Mutex(0)
    let model = WorkoutRootModel(
      logger: LoggerStore(database: database), catalog: CatalogSeeder(database: database),
      gyms: GymStore(database: database)
    )
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        guard case .statement(let statement) = event else { return }
        if statement.sql.hasPrefix("BEGIN") { begins.withLock { $0 += 1 } }
        guard statement.sql.contains("FROM \"exercises\"") else { return }
        let shouldProbe = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        guard shouldProbe else { return }
        let signal = DispatchSemaphore(value: 0)
        Task { @MainActor in
          signal.signal()
          // Join preparation without asking this SQL callback to wait for itself.
          await model.load()
        }
        let result = signal.wait(timeout: .now() + 2)
        mainActorRan.withLock { $0 = result == .success }
      }
    }
    await model.load()
    #expect(model.isReady)
    #expect(model.lastError == nil)
    #expect(fired.withLock { $0 })
    #expect(mainActorRan.withLock { $0 })
    // One seed write, one recovery read, one combined gym-selection read.
    #expect(begins.withLock { $0 } == 3)
    await model.load()
    #expect(begins.withLock { $0 } == 3)
  }

  enum FailureStage: CaseIterable { case catalog, gyms }

  @Test("Any required input failure keeps the root gated until retry", arguments: FailureStage.allCases)
  @MainActor
  func requiredInputFailure(stage: FailureStage) async throws {
    let database = try fixture()
    try await database.write { db in
      switch stage {
      case .catalog:
        try db.execute(sql: "CREATE TRIGGER refuseSeed BEFORE INSERT ON exercises BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
      case .gyms:
        try db.execute(sql: "ALTER TABLE gyms RENAME TO hiddenGyms")
      }
    }
    let model = WorkoutRootModel(
      logger: LoggerStore(database: database), catalog: CatalogSeeder(database: database),
      gyms: GymStore(database: database)
    )
    await model.load()
    #expect(!model.isReady)
    #expect(!model.isLoading)
    #expect(model.lastError != nil)
    #expect(throws: WorkoutRootError.notReady) { try model.startWorkout() }
    let count = try await database.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM sessions") }
    #expect(count == 0)
    try await database.write { db in
      switch stage {
      case .catalog: try db.execute(sql: "DROP TRIGGER refuseSeed")
      case .gyms: try db.execute(sql: "ALTER TABLE hiddenGyms RENAME TO gyms")
      }
    }
    await model.load()
    #expect(model.isReady)
    #expect(model.lastError == nil)
    #expect(model.coordinator == nil)
    try model.startWorkout()
    #expect(model.coordinator != nil)
  }

  @Test("Recovery preserves working sets, gym and finished-state transitions")
  @MainActor
  func recoveryAndNextWorkout() async throws {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home")
    let exercise = ExerciseID()
    try await database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute(db)
    }
    let live = try SessionCoordinator.start(
      store: logger, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Press", plannedSets: 2)], now: { now }
    )
    let first = try #require(live.exercises.first)
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: first.slots[0].id, inExercise: first.id))
    let model = WorkoutRootModel(logger: logger, catalog: CatalogSeeder(database: database), gyms: gyms, now: { now })
    #expect(throws: WorkoutRootError.notReady) { try model.startWorkout() }
    await model.load()
    let recovered = try #require(model.coordinator)
    #expect(recovered.sessionID == live.sessionID)
    #expect(recovered.loggedSetCount == 1)
    #expect(recovered.exercises.first?.slots.first?.draft.weightKg == 100)
    #expect(model.gymOptions.map(\.id) == [gym])
    #expect(model.selectedGym == gym)
    #expect(throws: WorkoutRootError.workoutAlreadyOpen) { try model.startWorkout() }
    model.clearFinishedWorkout()
    #expect(model.coordinator === recovered)
    try recovered.finish()
    model.clearFinishedWorkout()
    #expect(model.coordinator == nil)
    await model.load()
    #expect(model.coordinator == nil)
    try model.startWorkout()
    #expect(model.coordinator?.sessionID != live.sessionID)
    #expect(model.coordinator?.gymID == gym)
  }

  @Test("A discarded workout leaves the root like a finished one")
  @MainActor
  func discardedWorkoutClears() async throws {
    let database = try fixture()
    let model = WorkoutRootModel(
      logger: LoggerStore(database: database), catalog: CatalogSeeder(database: database),
      gyms: GymStore(database: database), now: { now }
    )
    await model.load()
    try model.startWorkout()
    let live = try #require(model.coordinator)
    model.clearFinishedWorkout()
    #expect(model.coordinator === live)
    try live.discard()
    model.clearFinishedWorkout()
    #expect(model.coordinator == nil)
    try model.startWorkout()
    #expect(model.coordinator != nil)
    #expect(model.coordinator !== live)
  }

  @Test("A gym picked on the start screen and not yet trained at can be restored")
  @MainActor
  func restoresUnstartedGymPick() async throws {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let metroflex = try gyms.createGym(name: "Metroflex")
    // A workout at Home makes it the learned default.
    let earlier = try SessionCoordinator.start(store: logger, gymID: home, plan: [], now: { now })
    try earlier.finish()
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database), gyms: gyms, now: { now }
    )
    // Nothing to restore against until the saved gyms have been read.
    #expect(!model.restoreGymPick(metroflex))
    await model.load()
    #expect(model.selectedGym == home)
    #expect(model.restoreGymPick(metroflex))
    #expect(model.selectedGym == metroflex)
    // "Not recorded" is a real pick too.
    #expect(model.restoreGymPick(nil))
    #expect(model.selectedGym == nil)
    // A gym that is no longer a saved option is ignored rather than selected.
    #expect(!model.restoreGymPick(GymID()))
    #expect(model.selectedGym == nil)
    #expect(model.restoreGymPick(metroflex))
    try model.startWorkout()
    #expect(model.coordinator?.gymID == metroflex)
  }

  @Test("An explicit Not recorded pick survives a gym refresh and the session keeps it")
  @MainActor
  func explicitNoGymSurvivesRefresh() async throws {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let metroflex = try gyms.createGym(name: "Metroflex")
    // A workout at Home makes it the learned default preparation applies.
    let earlier = try SessionCoordinator.start(store: logger, gymID: home, plan: [], now: { now })
    try earlier.finish()
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database), gyms: gyms, now: { now }
    )
    await model.load()
    #expect(model.selectedGym == home)
    // "Not recorded" is a real pick, not missing input, so a gym refresh must not revive the
    // learned default underneath it.
    #expect(model.restoreGymPick(nil))
    #expect(model.selectedGym == nil)
    try model.refreshGyms()
    #expect(model.selectedGym == nil)
    #expect(model.gymOptions.map(\.id) == [home, metroflex])
    try model.startWorkout()
    #expect(model.coordinator?.gymID == nil)
    #expect(try logger.openSession()?.gymID == nil)
  }

  @Test("A refresh keeps a valid pick and drops an archived one without reviving the default")
  @MainActor
  func refreshKeepsValidPickAndDropsArchivedGym() async throws {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let metroflex = try gyms.createGym(name: "Metroflex")
    let earlier = try SessionCoordinator.start(store: logger, gymID: home, plan: [], now: { now })
    try earlier.finish()
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database), gyms: gyms, now: { now }
    )
    await model.load()
    #expect(model.selectedGym == home)
    #expect(model.restoreGymPick(metroflex))
    try model.refreshGyms()
    #expect(model.selectedGym == metroflex)
    try gyms.archiveGym(metroflex)
    try model.refreshGyms()
    // The archived pick is no longer offered, so it is dropped rather than kept unseen.
    #expect(model.selectedGym == nil)
    #expect(model.gymOptions.map(\.id) == [home])
  }

  @Test("A disappearing caller cannot abandon recovery for the next appearance")
  @MainActor
  func cancellationCanRetry() async throws {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let session = try logger.startSession(at: now)
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database),
      gyms: GymStore(database: database)
    )
    let handle = Mutex<Task<Void, Never>?>(nil)
    let fired = Mutex(false)
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        guard case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") else { return }
        let cancel = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        if cancel { handle.withLock { $0?.cancel() } }
      }
    }
    let caller = Task { await model.load() }
    handle.withLock { $0 = caller }
    await caller.value
    handle.withLock { $0 = nil }
    #expect(fired.withLock { $0 })
    #expect(model.isReady)
    #expect(model.lastError == nil)
    #expect(model.coordinator?.sessionID == session)
    await model.load()
    #expect(model.coordinator?.sessionID == session)
    #expect(throws: WorkoutRootError.workoutAlreadyOpen) { try model.startWorkout() }
  }
}
