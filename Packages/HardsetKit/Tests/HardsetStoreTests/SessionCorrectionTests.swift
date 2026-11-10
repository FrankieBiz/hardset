import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Correcting a live workout through the coordinator. Every command persists first and changes
/// memory only after the write succeeded; a refusal leaves both exactly as they were.
@Suite("A live workout can be corrected, and memory follows the database")
@MainActor
struct SessionCorrectionTests {
  let start = Date(timeIntervalSince1970: 9_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(_ database: any DatabaseWriter, name: String = "Leg Press") throws
    -> ExerciseID
  {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  /// A clock the test moves, so save times and finish bounds are exact.
  private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  private final class RestSpy {
    var requests: [(Duration, RestMetadata)] = []
  }

  private func live(
    _ database: any DatabaseWriter, clock: Clock, gymID: GymID? = nil,
    plan: [PlannedExercise], rest: RestSpy? = nil
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: LoggerStore(database: database), gymID: gymID, plan: plan, now: { clock.now },
      restAfterSet: rest == nil ? nil : .seconds(90),
      onStartRest: { rest?.requests.append(($0, $1)) }
    )
  }

  @discardableResult
  private func log(
    _ coordinator: SessionCoordinator, exercise index: Int = 0, slot: Int,
    weight: Double, reps: Int = 8
  ) -> Bool {
    coordinator.exercises[index].slots[slot].draft = SetEntryDraft(weightKg: weight, reps: reps)
    let state = coordinator.exercises[index]
    return coordinator.logSet(slotID: state.slots[slot].id, inExercise: state.id)
  }

  // MARK: - Start time and summaries

  @Test("The real start is kept, including after a resume")
  func startedAtSurvivesResume() throws {
    let database = try migratedDatabase()
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press")])
    #expect(coordinator.startedAt == start)
    clock.now = start.addingTimeInterval(3_600)
    let resumed = try #require(
      try SessionCoordinator.resume(store: LoggerStore(database: database), now: { clock.now })
    )
    #expect(resumed.startedAt == start)
  }

  @Test("The saved-set count and last save time follow saves, undos and resume")
  func summariesFollowSaves() throws {
    let database = try migratedDatabase()
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let coordinator = try live(
      database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press", plannedSets: 2)]
    )
    #expect(coordinator.loggedSetCount == 0)
    #expect(coordinator.lastLoggedAt == nil)

    clock.now = start.addingTimeInterval(60)
    log(coordinator, slot: 0, weight: 100)
    clock.now = start.addingTimeInterval(180)
    log(coordinator, slot: 1, weight: 100)
    #expect(coordinator.loggedSetCount == 2)
    #expect(coordinator.lastLoggedAt == start.addingTimeInterval(180))

    // Typing into a row is not a save.
    coordinator.exercises[0].slots[1].draft.reps = 3
    #expect(coordinator.loggedSetCount == 2)

    let state = coordinator.exercises[0]
    #expect(coordinator.undoSet(slotID: state.slots[1].id, inExercise: state.id))
    #expect(coordinator.loggedSetCount == 1)
    #expect(coordinator.lastLoggedAt == start.addingTimeInterval(60))

    let resumed = try #require(
      try SessionCoordinator.resume(store: LoggerStore(database: database), now: { clock.now })
    )
    #expect(resumed.loggedSetCount == 1)
    #expect(resumed.lastLoggedAt == start.addingTimeInterval(60))
  }

  // MARK: - Undo

  @Test("Undo deletes the saved row and reopens it with its values, and a re-log is a new record")
  func undoThenRelog() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press")])
    #expect(log(coordinator, slot: 0, weight: 1000, reps: 1))
    let firstID = try #require(coordinator.exercises[0].slots[0].loggedSetID)

    let state = coordinator.exercises[0]
    #expect(coordinator.undoSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(coordinator.lastError == nil)
    #expect(try store.sets(in: coordinator.sessionID).isEmpty)
    let reopened = coordinator.exercises[0].slots[0]
    #expect(!reopened.isLogged)
    #expect(reopened.id == state.slots[0].id)
    #expect(reopened.draft.weightKg == 1000)
    #expect(reopened.draft.reps == 1)

    // Editing a saved set is undo, then log again.
    #expect(log(coordinator, slot: 0, weight: 100, reps: 1))
    let saved = try store.sets(in: coordinator.sessionID)
    #expect(saved.count == 1)
    #expect(saved[0].weightKg == 100)
    #expect(saved[0].id != firstID)
    #expect(coordinator.exercises[0].slots[0].loggedSetID == saved[0].id)
  }

  @Test("Undoing a fat-fingered set removes it from the record benchmark")
  func undoRestoresBenchmark() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let past = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(sessionID: past, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: start.addingTimeInterval(-86_000))
    try store.finishSession(past, at: start.addingTimeInterval(-85_000))
    let coordinator = try live(
      database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press", plannedSets: 2)]
    )
    log(coordinator, slot: 0, weight: 1000)
    #expect(coordinator.lastRecords.contains { $0.kind == .heaviestLoad })
    let state = coordinator.exercises[0]
    #expect(coordinator.undoSet(slotID: state.slots[0].id, inExercise: state.id))
    // The celebration belonged to the deleted set.
    #expect(coordinator.lastRecords.isEmpty)

    log(coordinator, slot: 1, weight: 110)
    #expect(coordinator.lastRecords.contains { $0.kind == .heaviestLoad })
  }

  @Test("Undoing a different set keeps the latest celebration")
  func undoOtherSetKeepsRecords() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let past = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(sessionID: past, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: start.addingTimeInterval(-86_000))
    try store.finishSession(past, at: start.addingTimeInterval(-85_000))
    let coordinator = try live(
      database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press", plannedSets: 2)]
    )
    log(coordinator, slot: 0, weight: 60)
    log(coordinator, slot: 1, weight: 120)
    #expect(!coordinator.lastRecords.isEmpty)
    let state = coordinator.exercises[0]
    #expect(coordinator.undoSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(!coordinator.lastRecords.isEmpty)
  }

  @Test("Undo of an unlogged row is a no-op, and an unknown row is reported")
  func undoEdgeCases() throws {
    let database = try migratedDatabase()
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press")])
    let state = coordinator.exercises[0]
    #expect(coordinator.undoSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(coordinator.lastError == nil)
    #expect(!coordinator.undoSet(slotID: UUID(), inExercise: state.id))
    #expect(coordinator.lastError as? SessionCoordinatorError == .unknownSlot)
    #expect(coordinator.lastFailedCommand == .undoSet)
    coordinator.clearError()
    #expect(coordinator.lastError == nil)
    #expect(coordinator.lastFailedCommand == nil)
  }

  @Test("A refused undo leaves the row saved and says why")
  func refusedUndoChangesNothing() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press")])
    log(coordinator, slot: 0, weight: 100)
    try store.finishSession(coordinator.sessionID, at: start.addingTimeInterval(60))
    let before = coordinator.exercises
    let state = coordinator.exercises[0]
    #expect(!coordinator.undoSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(coordinator.lastError as? LoggerStoreError == .sessionClosed)
    #expect(coordinator.lastFailedCommand == .undoSet)
    #expect(coordinator.exercises == before)
    #expect(coordinator.loggedSetCount == 1)
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
  }

  // MARK: - Removing rows and movements

  @Test("An unlogged row can be removed; a saved one cannot")
  func removeSlot() throws {
    let database = try migratedDatabase()
    let clock = Clock(start)
    let exercise = try seedExercise(database)
    let coordinator = try live(
      database, clock: clock, plan: [.init(exerciseID: exercise, exerciseName: "Press", plannedSets: 3)]
    )
    log(coordinator, slot: 0, weight: 100)
    let state = coordinator.exercises[0]

    #expect(!coordinator.removeSlot(slotID: state.slots[0].id, inExercise: state.id))
    #expect(coordinator.lastError as? SessionCoordinatorError == .slotIsLogged)
    #expect(coordinator.lastFailedCommand == .removeSlot)
    #expect(coordinator.exercises[0].slots.count == 3)

    #expect(coordinator.removeSlot(slotID: state.slots[2].id, inExercise: state.id))
    #expect(coordinator.lastError == nil)
    #expect(coordinator.exercises[0].slots.map(\.id) == [state.slots[0].id, state.slots[1].id])

    #expect(!coordinator.removeSlot(slotID: UUID(), inExercise: state.id))
    #expect(coordinator.lastError as? SessionCoordinatorError == .unknownSlot)
  }

  @Test("Removing a movement deletes its saved sets and plan row, and stays removed after resume")
  func removeExercise() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let press = try seedExercise(database, name: "Press")
    let curl = try seedExercise(database, name: "Curl")
    let coordinator = try live(database, clock: clock, plan: [
      .init(exerciseID: press, exerciseName: "Press"),
      .init(exerciseID: curl, exerciseName: "Curl"),
    ])
    log(coordinator, exercise: 0, slot: 0, weight: 100)
    log(coordinator, exercise: 1, slot: 0, weight: 20)
    let pressID = coordinator.exercises[0].id

    #expect(coordinator.removeExercise(pressID))
    #expect(coordinator.lastError == nil)
    #expect(coordinator.exercises.map(\.exerciseName) == ["Curl"])
    #expect(coordinator.loggedSetCount == 1)
    #expect(try store.sets(in: coordinator.sessionID).map(\.exerciseID) == [curl])

    // Positions stay contiguous, so a movement added now lands last after a relaunch too.
    #expect(coordinator.addExercise(exerciseID: press, exerciseName: "Press"))
    let resumed = try #require(try SessionCoordinator.resume(store: store, now: { clock.now }))
    #expect(resumed.exercises.map(\.exerciseName) == ["Curl", "Press"])
    #expect(resumed.loggedSetCount == 1)
  }

  @Test("Removing the movement whose set earned the celebration clears it")
  func removeExerciseClearsItsRecords() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let press = try seedExercise(database)
    let past = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(sessionID: past, exerciseID: press,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: start.addingTimeInterval(-86_000))
    try store.finishSession(past, at: start.addingTimeInterval(-85_000))
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    log(coordinator, slot: 0, weight: 120)
    #expect(!coordinator.lastRecords.isEmpty)
    #expect(coordinator.removeExercise(coordinator.exercises[0].id))
    #expect(coordinator.lastRecords.isEmpty)
  }

  @Test("A refused movement removal leaves memory and the database alone")
  func refusedRemoveExercise() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    log(coordinator, slot: 0, weight: 100)
    try store.finishSession(coordinator.sessionID, at: start.addingTimeInterval(60))
    let before = coordinator.exercises
    #expect(!coordinator.removeExercise(before[0].id))
    #expect(coordinator.lastError as? LoggerStoreError == .sessionClosed)
    #expect(coordinator.lastFailedCommand == .removeExercise)
    #expect(coordinator.exercises == before)
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
    #expect(!coordinator.removeExercise(UUID()))
    #expect(coordinator.lastError as? SessionCoordinatorError == .unknownExercise)
  }

  // MARK: - Reordering

  @Test("Moving a movement is persisted, so a resume keeps the order")
  func moveExercise() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let ids = try ["A", "B", "C"].map { try seedExercise(database, name: $0) }
    let coordinator = try live(
      database, clock: clock,
      plan: zip(ids, ["A", "B", "C"]).map { PlannedExercise(exerciseID: $0, exerciseName: $1) }
    )
    let c = coordinator.exercises[2].id
    #expect(coordinator.moveExercise(c, by: -1))
    #expect(coordinator.exercises.map(\.exerciseName) == ["A", "C", "B"])
    #expect(coordinator.moveExercise(coordinator.exercises[0].id, by: 1))
    #expect(coordinator.exercises.map(\.exerciseName) == ["C", "A", "B"])

    // Past either end there is nothing to do; that is not a failure.
    #expect(!coordinator.moveExercise(c, by: -1))
    #expect(coordinator.lastError == nil)
    #expect(coordinator.exercises.map(\.exerciseName) == ["C", "A", "B"])

    let resumed = try #require(try SessionCoordinator.resume(store: store, now: { clock.now }))
    #expect(resumed.exercises.map(\.exerciseName) == ["C", "A", "B"])

    #expect(!coordinator.moveExercise(UUID(), by: 1))
    #expect(coordinator.lastError as? SessionCoordinatorError == .unknownExercise)
    #expect(coordinator.lastFailedCommand == .moveExercise)
  }

  @Test("A refused move leaves the order alone")
  func refusedMove() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let ids = try ["A", "B"].map { try seedExercise(database, name: $0) }
    let coordinator = try live(
      database, clock: clock,
      plan: zip(ids, ["A", "B"]).map { PlannedExercise(exerciseID: $0, exerciseName: $1) }
    )
    try store.finishSession(coordinator.sessionID, at: start.addingTimeInterval(60))
    #expect(!coordinator.moveExercise(coordinator.exercises[1].id, by: -1))
    #expect(coordinator.lastError as? LoggerStoreError == .sessionClosed)
    #expect(coordinator.exercises.map(\.exerciseName) == ["A", "B"])
  }

  // MARK: - Gym

  @Test("A gym chosen mid-workout is saved and unlocks machines")
  func setGym() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let clock = Clock(start)
    let home = try gyms.createGym(name: "Home")
    let machine = try gyms.createMachine(at: home, name: "Press")
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    #expect(coordinator.gymID == nil)

    #expect(coordinator.setGym(home))
    #expect(coordinator.gymID == home)
    #expect(try store.openSession()?.gymID == home)
    #expect(coordinator.changeMachine(to: machine, machineName: "Press", inExercise: coordinator.exercises[0].id))
  }

  @Test("Once a machine is recorded, the gym cannot change under it")
  func setGymConflicts() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let clock = Clock(start)
    let home = try gyms.createGym(name: "Home")
    let away = try gyms.createGym(name: "Away")
    let machine = try gyms.createMachine(at: home, name: "Press")
    let press = try seedExercise(database)
    let coordinator = try live(
      database, clock: clock, gymID: home, plan: [.init(exerciseID: press, exerciseName: "Press")]
    )
    #expect(coordinator.changeMachine(to: machine, machineName: "Press", inExercise: coordinator.exercises[0].id))

    #expect(!coordinator.setGym(away))
    #expect(coordinator.lastError as? SessionCoordinatorError == .gymChangeConflictsWithMachines)
    #expect(coordinator.lastFailedCommand == .setGym)
    #expect(coordinator.gymID == home)
    #expect(try store.openSession()?.gymID == home)

    #expect(!coordinator.setGym(GymID()))
    #expect(coordinator.lastError as? LoggerStoreError == .gymNotFound)
    // The gym it already has is not a change.
    #expect(coordinator.setGym(home))
    #expect(coordinator.lastError == nil)
  }

  // MARK: - Machine preselection

  @Test("A movement added at a gym opens on the machine it was last done on there")
  func addPreselectsRecentMachine() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let clock = Clock(start)
    let home = try gyms.createGym(name: "Home")
    let hammer = try gyms.createMachine(at: home, name: "Leg Press", brand: "Hammer Strength", stackIncrementKg: 10)
    let press = try seedExercise(database)
    let past = try store.startSession(gymID: home, at: start.addingTimeInterval(-86_400))
    for (offset, weight) in [100.0, 110, 120].enumerated() {
      _ = try store.logSet(sessionID: past, exerciseID: press, machineID: hammer,
                           draft: SetEntryDraft(weightKg: weight, reps: 8),
                           at: start.addingTimeInterval(-86_000 + Double(offset)))
    }
    try store.finishSession(past, at: start.addingTimeInterval(-85_000))

    let coordinator = try live(database, clock: clock, gymID: home, plan: [])
    #expect(coordinator.addExercise(exerciseID: press, exerciseName: "Leg Press"))
    let state = coordinator.exercises[0]
    #expect(state.machineID == hammer)
    #expect(state.machineName == "Hammer Strength Leg Press")
    #expect(state.machineIncrementKg == 10)
    #expect(state.slots.map(\.draft.weightKg) == [100, 110, 120])
    #expect(try store.sessionExercises(in: coordinator.sessionID).first?.machineID == hammer)
  }

  @Test("Without a gym, or with a machine named, nothing is preselected")
  func addWithoutGymOrWithMachine() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let clock = Clock(start)
    let home = try gyms.createGym(name: "Home")
    let hammer = try gyms.createMachine(at: home, name: "Hammer")
    let cybex = try gyms.createMachine(at: home, name: "Cybex")
    let press = try seedExercise(database)
    let past = try store.startSession(gymID: home, at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(sessionID: past, exerciseID: press, machineID: hammer,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: start.addingTimeInterval(-86_000))
    try store.finishSession(past, at: start.addingTimeInterval(-85_000))

    let noGym = try live(database, clock: clock, plan: [])
    #expect(noGym.addExercise(exerciseID: press, exerciseName: "Press"))
    #expect(noGym.exercises[0].machineID == nil)
    try noGym.discard()

    let named = try live(database, clock: clock, gymID: home, plan: [])
    #expect(named.addExercise(exerciseID: press, exerciseName: "Press", machineID: cybex, machineName: "Cybex"))
    #expect(named.exercises[0].machineID == cybex)
  }

  // MARK: - Discard

  @Test("Discarding deletes the open workout and marks the coordinator discarded")
  func discard() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    log(coordinator, slot: 0, weight: 100)
    try coordinator.discard()
    #expect(coordinator.isDiscarded)
    #expect(!coordinator.isFinished)
    #expect(try store.openSession() == nil)
    #expect(try store.sets(in: coordinator.sessionID).isEmpty)
    // Already gone is the outcome asked for.
    try coordinator.discard()
    #expect(coordinator.isDiscarded)
  }

  @Test("A workout already finished elsewhere is kept, and the coordinator learns it is finished")
  func discardFinishedWorkout() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    try store.finishSession(coordinator.sessionID, at: start.addingTimeInterval(60))
    #expect(throws: LoggerStoreError.sessionClosed) { try coordinator.discard() }
    #expect(coordinator.isFinished)
    #expect(!coordinator.isDiscarded)
  }

  // MARK: - Finishing

  @Test("Finishing at a chosen time stores that time")
  func finishAtChosenTime() throws {
    let database = try migratedDatabase()
    let clock = Clock(start)
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    clock.now = start.addingTimeInterval(600)
    log(coordinator, slot: 0, weight: 100)
    // Left open overnight: finished at the last set rather than at "now".
    clock.now = start.addingTimeInterval(40_000)
    let lastSet = try #require(coordinator.lastLoggedAt)
    try coordinator.finish(at: lastSet)
    #expect(coordinator.isFinished)
    let stored = try database.read { db in
      try Session.where { $0.id.eq(coordinator.sessionID.rawValue) }.fetchOne(db)?.finishedAt
    }
    #expect(stored == lastSet)
  }

  @Test("A finish time before the start, before the last set, or in the future is refused",
        arguments: [-1.0, 599.0, 40_001.0])
  func finishAtInvalidTime(offset: TimeInterval) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start)
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    clock.now = start.addingTimeInterval(600)
    log(coordinator, slot: 0, weight: 100)
    clock.now = start.addingTimeInterval(40_000)
    #expect(throws: SessionCoordinatorError.invalidFinishTime) {
      try coordinator.finish(at: start.addingTimeInterval(offset))
    }
    #expect(!coordinator.isFinished)
    #expect(try store.openSession()?.id == coordinator.sessionID)
  }

  @Test("Finishing a workout closed elsewhere marks it finished instead of failing",
        arguments: [false, true])
  func finishAlreadyClosed(chosenTime: Bool) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let clock = Clock(start.addingTimeInterval(600))
    let press = try seedExercise(database)
    let coordinator = try live(database, clock: clock, plan: [.init(exerciseID: press, exerciseName: "Press")])
    try store.finishSession(coordinator.sessionID, at: start.addingTimeInterval(700))
    if chosenTime {
      try coordinator.finish(at: clock.now)
    } else {
      try coordinator.finish()
    }
    #expect(coordinator.isFinished)
    let stored = try database.read { db in
      try Session.where { $0.id.eq(coordinator.sessionID.rawValue) }.fetchOne(db)?.finishedAt
    }
    // The first close stands; nothing drifts.
    #expect(stored == start.addingTimeInterval(700))
  }
}
