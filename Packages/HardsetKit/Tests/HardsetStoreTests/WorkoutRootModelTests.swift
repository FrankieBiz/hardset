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
    let coordinator = try #require(model.coordinator)
    #expect(coordinator.gymID == nil)
    let session = try logger.openSession()
    let saved = try #require(session)
    #expect(saved.gymID == nil)
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

  // MARK: - Saved workouts

  private struct SavedWorkoutFixture {
    let database: DatabaseQueue
    let logger: LoggerStore
    let gyms: GymStore
    let model: WorkoutRootModel
    let press: ExerciseID
    let home: GymID
    let homeMachine: MachineID
  }

  /// What the rest timer was asked to do, as `HardsetRootView`'s own wiring would see it.
  private final class TimerSpy {
    var starts: [(duration: Duration, metadata: RestMetadata)] = []
    var cancels = 0
  }

  @MainActor
  private func savedWorkoutFixture(
    clock: (@Sendable () -> Date)? = nil, restPreferences: RestPreferences? = nil,
    timer: TimerSpy? = nil
  ) async throws -> SavedWorkoutFixture {
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let homeMachine = try gyms.createMachine(at: home, name: "Chest Press", brand: "Hammer")
    let press = ExerciseID()
    try await database.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Chest Press") }.execute(db)
    }
    let fixedNow = now
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database), gyms: gyms,
      now: clock ?? { fixedNow },
      onStartRest: { duration, metadata in timer?.starts.append((duration, metadata)) },
      restPreferences: restPreferences, onCancelRest: { timer?.cancels += 1 }
    )
    await model.load()
    #expect(model.restoreGymPick(home))
    return SavedWorkoutFixture(
      database: database, logger: logger, gyms: gyms, model: model, press: press, home: home,
      homeMachine: homeMachine
    )
  }

  private func plan(
    _ name: String = "Upper A", press: ExerciseID, machine: MachineID?, sets: Int = 3,
    range: RepRange? = RepRange(lower: 8, upper: 12), rest: Int? = 90
  ) -> WorkoutTemplate {
    WorkoutTemplate(
      name: name, position: 0,
      exercises: [
        TemplateExercise(
          exerciseID: press, exerciseName: "Chest Press", machineID: machine, plannedSets: sets,
          repRange: range, restSeconds: rest
        )
      ]
    )
  }

  /// One saved working set in the open workout's first movement: what makes a finished workout one
  /// the lifter did.
  @MainActor
  private func logOneWorkingSet(_ live: SessionCoordinator) {
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
  }

  @MainActor
  private func scratchRest() -> RestPreferences {
    RestPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  }

  @Test("Starting a saved workout opens every movement on its machine and remembers where it came from")
  @MainActor
  func startFromTemplatePersistsTemplateAndRange() async throws {
    let f = try await savedWorkoutFixture()
    let saved = plan(press: f.press, machine: f.homeMachine)

    try f.model.startWorkout(from: saved, unit: .kilograms, rest: scratchRest())

    let live = try #require(f.model.coordinator)
    #expect(live.exercises.count == 1)
    #expect(live.exercises[0].machineID == f.homeMachine)
    #expect(live.exercises[0].repRange == RepRange(lower: 8, upper: 12))
    #expect(live.exercises[0].slots.count == 3)
    #expect(live.gymID == f.home)
    let liveID = live.sessionID.rawValue
    let (session, rows) = try await f.database.read { db in
      (
        try Session.where { $0.id.eq(liveID) }.fetchOne(db),
        try SessionExercise.where { $0.sessionID.eq(liveID) }.fetchAll(db)
      )
    }
    #expect(session?.templateID == saved.id.rawValue)
    #expect(session?.title == "Upper A")
    #expect(rows.count == 1)
    #expect(rows[0].plannedSets == 3)
    #expect(rows[0].repRangeLower == 8)
    #expect(rows[0].repRangeUpper == 12)
    #expect(rows[0].machineID == f.homeMachine.rawValue)
  }

  @Test("A machine from another gym is replaced by the one last used here, and never refused")
  @MainActor
  func machineFromOtherGymIsReplacedByRecentHere() async throws {
    let f = try await savedWorkoutFixture()
    let away = try f.gyms.createGym(name: "Away")
    let awayMachine = try f.gyms.createMachine(at: away, name: "Chest Press", brand: "Life Fitness")
    let earlier = try SessionCoordinator.start(
      store: f.logger, gymID: f.home,
      plan: [PlannedExercise(
        exerciseID: f.press, machineID: f.homeMachine, exerciseName: "Chest Press", plannedSets: 1)],
      now: { self.now }
    )
    earlier.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(earlier.logSet(slotID: earlier.exercises[0].slots[0].id, inExercise: earlier.exercises[0].id))
    try earlier.finish()

    try f.model.startWorkout(
      from: plan(press: f.press, machine: awayMachine), unit: .kilograms, rest: scratchRest())

    #expect(f.model.coordinator?.exercises[0].machineID == f.homeMachine)
    #expect(f.model.coordinator?.exercises[0].machineName == "Hammer Chest Press")
  }

  @Test("A machine from another gym with no history here is dropped, not refused")
  @MainActor
  func machineFromOtherGymWithNoHistoryIsDropped() async throws {
    let f = try await savedWorkoutFixture()
    let away = try f.gyms.createGym(name: "Away")
    let awayMachine = try f.gyms.createMachine(at: away, name: "Chest Press")

    try f.model.startWorkout(
      from: plan(press: f.press, machine: awayMachine), unit: .kilograms, rest: scratchRest())

    let live = try #require(f.model.coordinator)
    #expect(live.exercises[0].machineID == nil)
    #expect(live.exercises[0].slots.count == 3)
  }

  @Test("A workout with no gym recorded cannot vouch for a saved machine, so it opens on none")
  @MainActor
  func noGymMeansNoSavedMachine() async throws {
    let f = try await savedWorkoutFixture()
    #expect(f.model.restoreGymPick(nil))

    try f.model.startWorkout(
      from: plan(press: f.press, machine: f.homeMachine), unit: .kilograms, rest: scratchRest())

    #expect(f.model.coordinator?.gymID == nil)
    #expect(f.model.coordinator?.exercises[0].machineID == nil)
  }

  @Test("A saved rest becomes the movement's remembered rest, and a blank one leaves it alone")
  @MainActor
  func restSecondsAreRemembered() async throws {
    let f = try await savedWorkoutFixture()
    let rest = scratchRest()
    let other = ExerciseID()
    try await f.database.write { db in
      try Exercise.insert { Exercise.Draft(id: other.rawValue, name: "Curl") }.execute(db)
    }
    rest.remember(.seconds(45), for: other)
    let saved = WorkoutTemplate(
      name: "Upper A", position: 0,
      exercises: [
        TemplateExercise(exerciseID: f.press, exerciseName: "Chest Press", plannedSets: 3, restSeconds: 90),
        TemplateExercise(exerciseID: other, exerciseName: "Curl", plannedSets: 3),
      ]
    )

    try f.model.startWorkout(from: saved, unit: .kilograms, rest: rest)

    #expect(rest.lastRest(for: f.press) == .seconds(90))
    #expect(rest.lastRest(for: other) == .seconds(45))
  }

  // MARK: - Rest, as the app wires it

  /// The app passes no fixed rest length (`restAfterSet` is nil), so these are the only rests it
  /// ever starts: the one remembered for the movement, through a model built the way
  /// `HardsetRootView` builds it.
  @Test("A workout started the way the app starts one rests after a set at the remembered length")
  @MainActor
  func startedWorkoutRestsAtTheRememberedLength() async throws {
    let rest = scratchRest()
    let timer = TimerSpy()
    let f = try await savedWorkoutFixture(restPreferences: rest, timer: timer)
    rest.remember(.seconds(75), for: f.press)

    try f.model.startWorkout()

    let live = try #require(f.model.coordinator)
    live.addExercise(exerciseID: f.press, exerciseName: "Chest Press", plannedSets: 1)
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    #expect(timer.starts.map(\.duration) == [.seconds(75)])
    #expect(timer.starts.first?.metadata.exerciseName == "Chest Press")
    #expect(live.restExerciseID == live.exercises[0].id)

    try live.finish()
    #expect(timer.cancels == 1)
  }

  @Test("A saved workout's own rest is what its first working set starts, over an older choice")
  @MainActor
  func savedWorkoutRestStartsAfterTheFirstSet() async throws {
    let rest = scratchRest()
    let timer = TimerSpy()
    let f = try await savedWorkoutFixture(restPreferences: rest, timer: timer)
    // The lifter once chose a minute for this movement; the saved workout says a minute and a half.
    rest.remember(.seconds(60), for: f.press)

    try f.model.startWorkout(
      from: plan(press: f.press, machine: nil, rest: 90), unit: .kilograms, rest: rest)

    let live = try #require(f.model.coordinator)
    #expect(timer.starts.isEmpty)
    // The card offers what the next set will start, not the choice it replaced.
    #expect(live.lastRestByCard[live.exercises[0].id] == .seconds(90))
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    #expect(timer.starts.map(\.duration) == [.seconds(90)])
  }

  @Test("A workout recovered after a relaunch rests after its next set, and ends that rest when it closes")
  @MainActor
  func recoveredWorkoutRests() async throws {
    let rest = scratchRest()
    let timer = TimerSpy()
    let database = try fixture()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let press = ExerciseID()
    let curl = ExerciseID()
    try await database.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Chest Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: curl.rawValue, name: "Curl") }.execute(db)
    }
    // A workout left open by the app being killed.
    _ = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(exerciseID: press, exerciseName: "Chest Press", plannedSets: 2),
        PlannedExercise(exerciseID: curl, exerciseName: "Curl", plannedSets: 1),
      ],
      now: { self.now })
    rest.remember(.seconds(75), for: press)
    let fixedNow = now
    let model = WorkoutRootModel(
      logger: logger, catalog: CatalogSeeder(database: database), gyms: gyms,
      now: { fixedNow },
      onStartRest: { timer.starts.append(($0, $1)) },
      restPreferences: rest, onCancelRest: { timer.cancels += 1 })

    await model.load()

    let live = try #require(model.coordinator)
    // A movement the lifter never chose a rest for starts none.
    live.exercises[1].slots[0].draft = SetEntryDraft(weightKg: 15, reps: 12)
    #expect(live.logSet(slotID: live.exercises[1].slots[0].id, inExercise: live.exercises[1].id))
    #expect(timer.starts.isEmpty)
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    #expect(timer.starts.map(\.duration) == [.seconds(75)])
    try live.discard()
    #expect(timer.cancels == 1)
  }

  @Test("Repeating the last workout rests the same way")
  @MainActor
  func repeatedWorkoutRests() async throws {
    let rest = scratchRest()
    let timer = TimerSpy()
    let f = try await savedWorkoutFixture(restPreferences: rest, timer: timer)
    rest.remember(.seconds(100), for: f.press)
    try f.model.startWorkout()
    let first = try #require(f.model.coordinator)
    first.addExercise(exerciseID: f.press, exerciseName: "Chest Press", plannedSets: 1)
    first.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(first.logSet(slotID: first.exercises[0].slots[0].id, inExercise: first.exercises[0].id))
    try first.finish()
    f.model.clearFinishedWorkout()
    timer.starts.removeAll()

    try f.model.repeatLastWorkout(unit: .kilograms)

    let again = try #require(f.model.coordinator)
    again.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 40, reps: 10)
    #expect(again.logSet(slotID: again.exercises[0].slots[0].id, inExercise: again.exercises[0].id))
    #expect(timer.starts.map(\.duration) == [.seconds(100)])
  }

  @Test("A start that fails changes no remembered rest")
  @MainActor
  func failedStartRemembersNoRest() async throws {
    let f = try await savedWorkoutFixture()
    let rest = scratchRest()
    try f.model.startWorkout(from: plan(press: f.press, machine: nil), unit: .kilograms, rest: scratchRest())

    #expect(throws: WorkoutRootError.workoutAlreadyOpen) {
      try f.model.startWorkout(
        from: self.plan(press: f.press, machine: nil, rest: 120), unit: .kilograms, rest: rest)
    }
    #expect(rest.lastRest(for: f.press) == nil)
  }

  @Test("Repeating the last workout copies its plan, counting working sets and not warm-ups")
  @MainActor
  func repeatLastWorkoutCopiesPlan() async throws {
    let f = try await savedWorkoutFixture()
    let saved = plan(press: f.press, machine: f.homeMachine)
    try f.model.startWorkout(from: saved, unit: .kilograms, rest: scratchRest())
    let live = try #require(f.model.coordinator)
    live.exercises[0].appendSlot(isWarmup: true)
    let slots = live.exercises[0].slots.map(\.id)
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 20, reps: 12)
    live.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 40, reps: 10)
    live.exercises[0].slots[2].draft = SetEntryDraft(weightKg: 40, reps: 9)
    for id in slots.prefix(3) {
      #expect(live.logSet(slotID: id, inExercise: live.exercises[0].id))
    }
    try live.finish()
    f.model.clearFinishedWorkout()
    #expect(f.model.coordinator == nil)

    try f.model.repeatLastWorkout(unit: .kilograms)

    let repeated = try #require(f.model.coordinator)
    #expect(repeated.sessionID != live.sessionID)
    #expect(repeated.exercises[0].machineID == f.homeMachine)
    #expect(repeated.exercises[0].repRange == RepRange(lower: 8, upper: 12))
    // Two working sets were logged, and the warm-up is not one of them.
    #expect(repeated.exercises[0].slots.count == 2)
    let repeatedID = repeated.sessionID.rawValue
    let (session, rows) = try await f.database.read { db in
      (
        try Session.where { $0.id.eq(repeatedID) }.fetchOne(db),
        try SessionExercise.where { $0.sessionID.eq(repeatedID) }.fetchAll(db)
      )
    }
    #expect(session?.templateID == saved.id.rawValue)
    #expect(session?.title == "Upper A")
    #expect(rows.first?.plannedSets == 2)
    #expect(rows.first?.repRangeUpper == 12)
    // The prefill is the double-progression target, built from the workout just finished.
    #expect(repeated.exercises[0].slots[0].draft.target != nil)
    #expect(repeated.exercises[0].slots[0].draft.reps == 11)
  }

  @Test("The workout repeated is the one finished last, whichever began last")
  @MainActor
  func repeatLastWorkoutUsesTheLatestFinished() async throws {
    let f = try await savedWorkoutFixture()
    // Overlapping workouts, as two devices can leave: Upper A began first and ended last.
    let first = UUID()
    let second = UUID()
    try await f.database.write { db in
      for (id, title, began, ended) in [
        (first, "Upper A", 0.0, 10_800.0), (second, "Upper B", 3_600.0, 7_200.0),
      ] {
        try Session.insert {
          Session.Draft(
            id: id, title: title, startedAt: self.now.addingTimeInterval(began),
            finishedAt: self.now.addingTimeInterval(ended))
        }
        .execute(db)
        try SessionExercise.insert {
          SessionExercise.Draft(
            id: UUID(), sessionID: id, exerciseID: f.press.rawValue, position: 0, plannedSets: 3)
        }
        .execute(db)
        try LoggedSet.insert {
          LoggedSet.Draft(
            sessionID: id, exerciseID: f.press.rawValue, weightKg: 40, reps: 10,
            completedAt: self.now.addingTimeInterval(began + 60))
        }
        .execute(db)
      }
    }

    try f.model.repeatLastWorkout(unit: .kilograms)

    let repeatedID = try #require(f.model.coordinator).sessionID.rawValue
    let title = try await f.database.read { db in
      try Session.where { $0.id.eq(repeatedID) }.select(\.title).fetchOne(db)
    }
    #expect(title == "Upper A")
  }

  @Test("Finishing a saved workout hands the Train tab's up-next card to the other one")
  @MainActor
  func upNextUsesRotation() async throws {
    let start = now
    let clock = Mutex(start)
    let f = try await savedWorkoutFixture(clock: { clock.withLock { $0 } })
    let templates = TemplateStore(database: f.database)
    let upperA = plan("Upper A", press: f.press, machine: nil)
    let upperB = WorkoutTemplate(
      name: "Upper B", position: 1,
      exercises: [TemplateExercise(exerciseID: f.press, exerciseName: "Chest Press", plannedSets: 3)])
    try await templates.save(upperA, now: start)
    try await templates.save(upperB, now: start)

    func upNext() async throws -> String? {
      WorkoutRotation.upNextOrder(try await templates.loadTemplates()).first?.name
    }
    #expect(try await upNext() == "Upper A")

    try f.model.startWorkout(from: upperA, unit: .kilograms, rest: scratchRest())
    // Started but not finished: an open workout is not done, so A is still first.
    #expect(try await upNext() == "Upper A")
    logOneWorkingSet(try #require(f.model.coordinator))
    clock.withLock { $0 = start.addingTimeInterval(3_600) }
    try #require(f.model.coordinator).finish()
    f.model.clearFinishedWorkout()
    #expect(try await upNext() == "Upper B")

    clock.withLock { $0 = start.addingTimeInterval(86_400) }
    try f.model.startWorkout(from: upperB, unit: .kilograms, rest: scratchRest())
    logOneWorkingSet(try #require(f.model.coordinator))
    clock.withLock { $0 = start.addingTimeInterval(90_000) }
    try #require(f.model.coordinator).finish()
    f.model.clearFinishedWorkout()
    #expect(try await upNext() == "Upper A")
  }

  /// An imported workout is kept apart from native tracking on purpose: its movements are separate,
  /// "Unevaluated Machine" copies. Repeating one would start a native workout on those copies, and
  /// every record, mark and scorecard after it would compare against unevaluated history.
  @Test("Repeat last workout skips imported workouts, even when one ended later")
  @MainActor
  func repeatLastWorkoutSkipsImports() async throws {
    let f = try await savedWorkoutFixture()
    try f.model.startWorkout(
      from: plan(press: f.press, machine: nil), unit: .kilograms, rest: scratchRest())
    logOneWorkingSet(try #require(f.model.coordinator))
    try #require(f.model.coordinator).finish()
    f.model.clearFinishedWorkout()
    let csv = "Date,Workout Name,Duration,Exercise Name,Weight,Reps\n2026-11-01 10:00:00,Push,3600,Press,100,8\n"
    _ = try await DataTransferStore(database: f.database).importWorkouts(
      WorkoutCSVImport.preview(csv, strongUnit: .kilograms))

    let canRepeat = try f.logger.hasRepeatableWorkout()
    try f.model.repeatLastWorkout(unit: .kilograms)

    #expect(canRepeat)
    let live = try #require(f.model.coordinator)
    #expect(live.exercises.map(\.exerciseID) == [f.press])
  }

  /// The same rule the rotation and "Repeat last workout" use: a workout the lifter did holds a working set.
  /// An accidental Start finished empty must not become "Repeat last workout", which would start
  /// the lifter on nothing in place of the workout they last trained.
  @Test("Repeat last workout skips a workout finished with no working set")
  @MainActor
  func repeatLastWorkoutSkipsAnEmptyOne() async throws {
    let clock = Mutex(now)
    let f = try await savedWorkoutFixture(clock: { clock.withLock { $0 } })
    try f.model.startWorkout(
      from: plan("Upper A", press: f.press, machine: nil), unit: .kilograms, rest: scratchRest())
    logOneWorkingSet(try #require(f.model.coordinator))
    let real = try #require(f.model.coordinator).sessionID
    clock.withLock { $0 = self.now.addingTimeInterval(3_600) }
    try #require(f.model.coordinator).finish()
    f.model.clearFinishedWorkout()
    // A second Start, finished at once with nothing trained, and a third with warm-ups only.
    clock.withLock { $0 = self.now.addingTimeInterval(7_200) }
    try f.model.startWorkout(
      from: plan("Upper B", press: f.press, machine: nil), unit: .kilograms, rest: scratchRest())
    clock.withLock { $0 = self.now.addingTimeInterval(7_300) }
    try #require(f.model.coordinator).finish()
    f.model.clearFinishedWorkout()
    clock.withLock { $0 = self.now.addingTimeInterval(8_000) }
    try f.model.startWorkout(
      from: plan("Upper C", press: f.press, machine: nil), unit: .kilograms, rest: scratchRest())
    let warmUpOnly = try #require(f.model.coordinator)
    warmUpOnly.exercises[0].appendSlot(isWarmup: true)
    let warmUpIndex = try #require(warmUpOnly.exercises[0].slots.firstIndex { $0.isWarmup })
    warmUpOnly.exercises[0].slots[warmUpIndex].draft = SetEntryDraft(weightKg: 20, reps: 10)
    // The warm-up is the only row logged: the planned working rows stay open.
    #expect(warmUpOnly.logSet(
      slotID: warmUpOnly.exercises[0].slots[warmUpIndex].id, inExercise: warmUpOnly.exercises[0].id))
    #expect(warmUpOnly.loggedSetCount == 1)
    clock.withLock { $0 = self.now.addingTimeInterval(8_100) }
    try warmUpOnly.finish()
    f.model.clearFinishedWorkout()

    let canRepeat = try f.logger.hasRepeatableWorkout()
    try f.model.repeatLastWorkout(unit: .kilograms)

    #expect(canRepeat)
    let repeatedID = try #require(f.model.coordinator).sessionID.rawValue
    let title = try await f.database.read { db in
      try Session.where { $0.id.eq(repeatedID) }.select(\.title).fetchOne(db)
    }
    #expect(title == "Upper A")
    #expect(repeatedID != real.rawValue)
  }

  @Test("With only a workout finished empty there is nothing to repeat")
  @MainActor
  func onlyAnEmptyWorkoutMeansNothingToRepeat() async throws {
    let f = try await savedWorkoutFixture()
    try f.model.startWorkout(
      from: plan(press: f.press, machine: nil), unit: .kilograms, rest: scratchRest())
    try #require(f.model.coordinator).finish()
    f.model.clearFinishedWorkout()

    let canRepeat = try f.logger.hasRepeatableWorkout()

    #expect(!canRepeat)
    #expect(throws: WorkoutRootError.nothingToRepeat) {
      try f.model.repeatLastWorkout(unit: .kilograms)
    }
  }

  @Test("With only imported workouts there is nothing to repeat")
  @MainActor
  func onlyImportsMeansNothingToRepeat() async throws {
    let f = try await savedWorkoutFixture()
    let csv = "Date,Workout Name,Duration,Exercise Name,Weight,Reps\n2026-11-01 10:00:00,Push,3600,Press,100,8\n"
    _ = try await DataTransferStore(database: f.database).importWorkouts(
      WorkoutCSVImport.preview(csv, strongUnit: .kilograms))

    let canRepeat = try f.logger.hasRepeatableWorkout()

    #expect(!canRepeat)
    #expect(throws: WorkoutRootError.nothingToRepeat) {
      try f.model.repeatLastWorkout(unit: .kilograms)
    }
  }

  @Test("There is nothing to repeat before a workout has been finished")
  @MainActor
  func nothingToRepeat() async throws {
    let f = try await savedWorkoutFixture()
    #expect(throws: WorkoutRootError.nothingToRepeat) {
      try f.model.repeatLastWorkout(unit: .kilograms)
    }
    #expect(f.model.coordinator == nil)
  }

  @Test("Starting without a saved workout is exactly as it was")
  @MainActor
  func emptyStartUnchanged() async throws {
    let f = try await savedWorkoutFixture()

    try f.model.startWorkout()

    let live = try #require(f.model.coordinator)
    #expect(live.exercises.isEmpty)
    let liveID = live.sessionID.rawValue
    let session = try await f.database.read { db in
      try Session.where { $0.id.eq(liveID) }.fetchOne(db)
    }
    #expect(session?.templateID == nil)
    #expect(session?.title == "")
  }
}
