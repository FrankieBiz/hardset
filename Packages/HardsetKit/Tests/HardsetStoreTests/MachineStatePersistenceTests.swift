import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Regression tests for four defects found by an audit of the machine path.
///
/// They share one root cause: after `changeMachine`, the coordinator's in-memory state and the
/// database disagreed. Nothing wrote the new machine to `sessionExercises`, and nothing refreshed
/// the machine's load increment — so recovery rebuilt from a stale plan and record detection used
/// the wrong equipment's step size.
@Suite("Machine state survives a change and a recovery")
@MainActor
struct MachineStatePersistenceTests {
  let now = Date(timeIntervalSince1970: 18_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (LoggerStore, GymStore, ExerciseID, GymID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Gym", now: now)
    return (LoggerStore(database: database), gyms, exercise, gym)
  }

  private func seedHistory(
    _ logger: LoggerStore, _ exercise: ExerciseID, _ machine: MachineID,
    weight: Double, daysAgo: Int
  ) throws {
    let start = now.addingTimeInterval(Double(-daysAgo) * 86_400)
    let session = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: 8), setOrdinal: 0, at: start
    )
    try logger.finishSession(session, at: start.addingTimeInterval(3600))
  }

  // MARK: - Defect D: the machine change was never persisted

  /// The worst of the four. Sets logged after a machine change carry the new machine, but the
  /// stored plan still carried the old one, so recovery grouped by a key that matched nothing and
  /// reported zero logged sets — inviting the user to log them a second time.
  @Test("A machine change is written to the session plan")
  func machineChangeIsPersisted() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let hammer = try gyms.createMachine(at: gym, name: "Hammer Press", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex Press", now: now)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press",
          machineName: "Hammer Press", plannedSets: 3
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(
      to: cybex, machineName: "Cybex Press", inExercise: live.exercises[0].id
    ))

    let planned = try logger.sessionExercises(in: live.sessionID)
    #expect(planned.count == 1)
    #expect(planned[0].machineID == cybex, "the plan row still points at the old machine")
  }

  @Test("Sets logged after a machine change survive recovery")
  func setsSurviveRecoveryAfterChange() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let hammer = try gyms.createMachine(at: gym, name: "Hammer Press", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex Press", now: now)
    try seedHistory(logger, exercise, hammer, weight: 120, daysAgo: 7)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 3
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id))
    for index in 0..<2 {
      live.exercises[0].slots[index].draft = SetEntryDraft(weightKg: 80, reps: 10)
      #expect(live.logSet(
        slotID: live.exercises[0].slots[index].id, inExercise: live.exercises[0].id
      ))
    }

    // Crash, relaunch.
    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(recovered.exercises.count == 1)
    #expect(
      recovered.exercises[0].loggedCount == 2,
      "two written sets vanished from recovery and could be logged twice"
    )
    #expect(recovered.exercises[0].machineID == cybex)
  }

  /// Recovery must not offer an already-written set as unlogged, because logging it again is a
  /// duplicate the user cannot see.
  @Test("Recovery does not allow a written set to be logged twice")
  func recoveryDoesNotDuplicate() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let hammer = try gyms.createMachine(at: gym, name: "Hammer Press", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex Press", now: now)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 2
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id))
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 80, reps: 10)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))

    let before = try logger.sets(in: live.sessionID).count
    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    // The first row is already logged, so the coordinator refuses to write it again.
    _ = recovered.logSet(
      slotID: recovered.exercises[0].slots[0].id, inExercise: recovered.exercises[0].id
    )
    #expect(try logger.sets(in: live.sessionID).count == before)
  }

  /// Mixed machines within one exercise is a legitimate state — you move mid-exercise. Recovery
  /// must return every set, not the subset matching whichever machine the plan happens to name.
  @Test("Recovery returns sets performed across two machines in one exercise")
  func recoveryHandlesMixedMachines() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let hammer = try gyms.createMachine(at: gym, name: "Hammer Press", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex Press", now: now)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 3
        )
      ],
      now: { self.now }
    )
    // One set on the Hammer...
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 120, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    // ...then it is taken, so move.
    #expect(live.changeMachine(to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id))
    live.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 80, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[1].id, inExercise: live.exercises[0].id))

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(recovered.exercises[0].loggedCount == 2, "a set on the abandoned machine was lost")
    // Both loads come back as performed.
    let logged = recovered.exercises[0].slots.filter(\.isLogged).compactMap(\.draft.weightKg)
    #expect(Set(logged) == [120, 80])
  }

  // MARK: - Defects A and B: a stale load increment

  /// The margin for a heaviest-load record is the greater of 2.5% and one real step of the
  /// equipment. Carrying the previous machine's step across a change announces records the new
  /// machine cannot justify.
  @Test("Moving to a coarser stack does not announce a false record")
  func coarserStackNoFalseRecord() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let plate = try gyms.createMachine(
      at: gym, name: "Plate Press", stackIncrementKg: 2.5, now: now
    )
    let stack = try gyms.createMachine(
      at: gym, name: "Stack Press", stackIncrementKg: 10, now: now
    )
    try seedHistory(logger, exercise, plate, weight: 60, daysAgo: 7)
    try seedHistory(logger, exercise, stack, weight: 100, daysAgo: 5)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: plate, exerciseName: "Leg Press",
          machineIncrementKg: 2.5, plannedSets: 2
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(
      to: stack, machineName: "Stack Press", machineIncrementKg: 10,
      inExercise: live.exercises[0].id
    ))
    #expect(live.exercises[0].machineIncrementKg == 10, "the stale increment was carried across")

    // History best on this stack is 100; one real step is 10, so 105 is not a record.
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 105, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    #expect(
      !live.lastRecords.map(\.kind).contains(.heaviestLoad),
      "announced a record the stack's own step size cannot justify"
    )
  }

  /// The mirror image: carrying a coarse step onto a fine-stepped machine hides a real record.
  @Test("Moving to a finer stack does not suppress a real record")
  func finerStackNoSuppressedRecord() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let stack = try gyms.createMachine(
      at: gym, name: "Stack Press", stackIncrementKg: 10, now: now
    )
    let plate = try gyms.createMachine(
      at: gym, name: "Plate Press", stackIncrementKg: 2.5, now: now
    )
    try seedHistory(logger, exercise, stack, weight: 100, daysAgo: 7)
    try seedHistory(logger, exercise, plate, weight: 60, daysAgo: 5)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: stack, exerciseName: "Leg Press",
          machineIncrementKg: 10, plannedSets: 2
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(
      to: plate, machineName: "Plate Press", machineIncrementKg: 2.5,
      inExercise: live.exercises[0].id
    ))
    #expect(live.exercises[0].machineIncrementKg == 2.5)

    // History best on the plate machine is 60. Margin is max(2.5% of 60 = 1.5, one 2.5 kg step)
    // = 2.5, so 65 clears it and IS a record.
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 65, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    #expect(
      live.lastRecords.map(\.kind).contains(.heaviestLoad),
      "a real record was suppressed by the previous machine's step size"
    )
  }

  // MARK: - Defect C: recovery lost the increment

  @Test("Recovery restores the machine's load increment")
  func recoveryRestoresIncrement() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let stack = try gyms.createMachine(
      at: gym, name: "Stack Press", stackIncrementKg: 10, now: now
    )
    try seedHistory(logger, exercise, stack, weight: 100, daysAgo: 7)

    _ = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: stack, exerciseName: "Leg Press",
          machineIncrementKg: 10, plannedSets: 2
        )
      ],
      now: { self.now }
    )

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(
      recovered.exercises[0].machineIncrementKg == 10,
      "the increment was dropped, so records use a 2.5 kg default the equipment cannot hit"
    )

    // And the consequence it exists to prevent.
    recovered.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 105, reps: 8)
    #expect(recovered.logSet(
      slotID: recovered.exercises[0].slots[0].id, inExercise: recovered.exercises[0].id
    ))
    #expect(!recovered.lastRecords.map(\.kind).contains(.heaviestLoad))
  }

  @Test("A machine with an unknown increment stays unknown rather than defaulting")
  func unknownIncrementStaysNil() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let machine = try gyms.createMachine(at: gym, name: "Cable", now: now)

    _ = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", plannedSets: 1
        )
      ],
      now: { self.now }
    )
    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(recovered.exercises[0].machineIncrementKg == nil)
  }

  /// Silently skipping persistence is the exact defect being fixed, so an exercise with no plan
  /// row must refuse the change rather than appear to accept it.
  @Test("An untracked exercise refuses a machine change instead of half-applying it")
  func untrackedExerciseRefusesChange() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let cybex = try gyms.createMachine(at: gym, name: "Cybex", now: now)
    let sessionID = try logger.startSession(at: now)

    // Built through the public initialiser, so no plan row id is known.
    let orphan = SessionCoordinator(
      store: logger,
      sessionID: sessionID,
      exercises: [
        ExerciseLogState.build(
          exerciseID: exercise, exerciseName: "Leg Press",
          snapshot: .empty(capturedAt: now), plannedSets: 1
        )
      ],
      now: { self.now }
    )

    #expect(!orphan.changeMachine(
      to: cybex, machineName: "Cybex", inExercise: orphan.exercises[0].id
    ))
    #expect(orphan.lastError as? SessionCoordinatorError == .untrackedExercise)
    // Memory was not changed either, so the two still agree.
    #expect(orphan.exercises[0].machineID == nil)
  }

  /// A movement added mid-session must track its plan row too, or changing its machine later
  /// silently fails to persist.
  @Test("A mid-session addition can also change machine and have it persist")
  func addedExerciseCanChangeMachine() throws {
    let (logger, gyms, exercise, gym) = try fixture()
    let hammer = try gyms.createMachine(at: gym, name: "Hammer", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex", now: now)

    let live = try SessionCoordinator.start(
      store: logger, plan: [], now: { self.now }
    )
    #expect(live.addExercise(
      exerciseID: exercise, exerciseName: "Leg Press", machineID: hammer,
      machineName: "Hammer", plannedSets: 2
    ))
    #expect(live.changeMachine(
      to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id
    ))

    let planned = try logger.sessionExercises(in: live.sessionID)
    #expect(planned.count == 1)
    #expect(planned[0].machineID == cybex)
  }
}
