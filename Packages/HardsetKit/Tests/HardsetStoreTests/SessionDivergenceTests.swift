import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Regression tests for cases where the live session's in-memory state and the database disagreed.
///
/// Every test here failed when it was written. The theme is one bug repeated: the coordinator held a
/// belief the database did not share, and the divergence only became visible after a restart — which
/// is exactly when a lifter is least able to reconstruct what they did.
@Suite("Live session state agrees with the database")
@MainActor
struct SessionDivergenceTests {
  let now = Date(timeIntervalSince1970: 18_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, GymStore, ExerciseID, GymID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Gym", now: now)
    return (database, LoggerStore(database: database), gyms, exercise, gym)
  }

  private func log(
    _ session: SessionCoordinator, exercise index: Int, slot: Int, kg: Double, reps: Int
  ) {
    session.exercises[index].slots[slot].draft = SetEntryDraft(weightKg: kg, reps: reps)
    #expect(
      session.logSet(
        slotID: session.exercises[index].slots[slot].id, inExercise: session.exercises[index].id
      )
    )
  }

  // MARK: - The same movement twice in one session

  @Test("Two blocks of one movement keep their own sets across a recovery")
  func duplicateExerciseDoesNotDoubleCount() throws {
    let (_, logger, _, exercise, _) = try fixture()
    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 2),
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 2),
      ],
      now: { self.now }
    )
    // One set in the first block, one in the second.
    log(live, exercise: 0, slot: 0, kg: 100, reps: 8)
    log(live, exercise: 1, slot: 0, kg: 60, reps: 12)

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    let stored = try logger.sets(in: recovered.sessionID).count
    #expect(stored == 2)
    // Grouping by exerciseID made BOTH blocks claim BOTH sets, reporting four.
    let recoveredCount = recovered.exercises.reduce(0) { $0 + $1.loggedCount }
    #expect(recoveredCount == stored)
    #expect(recovered.exercises.map(\.loggedCount) == [1, 1])
    // And each block recovers the load it was actually performed at, not the other's.
    #expect(recovered.exercises[0].slots[0].draft.resolved()?.weightKg == 100)
    #expect(recovered.exercises[1].slots[0].draft.resolved()?.weightKg == 60)
  }

  @Test("Sets written before the plan-row column existed land in exactly one block")
  func legacySetsAreClaimedOnce() throws {
    let (database, logger, _, exercise, _) = try fixture()
    let session = try logger.startSession(at: now)
    try database.write { db in
      // Two plan rows for the same movement, and a set that predates `sessionExerciseID`.
      for position in 0..<2 {
        try SessionExercise.insert {
          SessionExercise.Draft(
            sessionID: session.rawValue, exerciseID: exercise.rawValue,
            position: position, plannedSets: 1
          )
        }
        .execute(db)
      }
      try LoggedSet.insert {
        LoggedSet.Draft(
          sessionID: session.rawValue, exerciseID: exercise.rawValue,
          sessionExerciseID: nil, setOrdinal: 0, weightKg: 100, reps: 8, completedAt: now
        )
      }
      .execute(db)
    }

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    let counts = recovered.exercises.map(\.loggedCount)
    #expect(counts.reduce(0, +) == 1, "one stored set, attributed once — got \(counts)")
  }

  // MARK: - Stored order survives a recovery

  @Test("Logging out of order then recovering does not reissue an ordinal")
  func ordinalsStayUniqueAcrossRecovery() throws {
    let (_, logger, _, exercise, _) = try fixture()
    let live = try SessionCoordinator.start(
      store: logger,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)],
      now: { self.now }
    )
    // The lifter logs the third row first — every row has its own log control.
    log(live, exercise: 0, slot: 2, kg: 100, reps: 5)

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    for index in 1..<recovered.exercises[0].slots.count {
      log(recovered, exercise: 0, slot: index, kg: 100, reps: 6)
    }

    let ordinals = try logger.sets(in: recovered.sessionID).map(\.setOrdinal).sorted()
    // Recovery renumbers slots, so an ordinal taken from the slot index collided with one already
    // written and the performed order stopped being recoverable.
    #expect(Set(ordinals).count == ordinals.count, "duplicate ordinals \(ordinals)")
  }

  // MARK: - The machine's own load step

  @Test("The stack increment comes from the machine, on start as well as resume")
  func incrementIsReadFromStorageOnStart() throws {
    let (_, logger, gyms, exercise, gym) = try fixture()
    let machine = try gyms.createMachine(
      at: gym, name: "Leg Press", stackIncrementKg: 10, now: now
    )

    // Nothing in the app supplies `machineIncrementKg`, which is the realistic call.
    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", plannedSets: 1
        )
      ],
      now: { self.now }
    )
    #expect(live.exercises[0].machineIncrementKg == 10)

    // The value a restart produces must be the same one, or a load flips between "record" and
    // "not a record" purely because the app was relaunched.
    log(live, exercise: 0, slot: 0, kg: 100, reps: 8)
    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(recovered.exercises[0].machineIncrementKg == live.exercises[0].machineIncrementKg)
  }

  @Test("Adding an exercise mid-session reads its machine's increment too")
  func incrementIsReadFromStorageOnAdd() throws {
    let (_, logger, gyms, exercise, gym) = try fixture()
    let machine = try gyms.createMachine(
      at: gym, name: "Leg Press", stackIncrementKg: 2.5, now: now
    )
    let live = try SessionCoordinator.start(store: logger, plan: [], now: { self.now })
    #expect(
      live.addExercise(
        exerciseID: exercise, exerciseName: "Leg Press", machineID: machine, plannedSets: 1
      )
    )
    #expect(live.exercises[0].machineIncrementKg == 2.5)
  }

  @Test("Moving to a different machine adopts that machine's increment")
  func incrementFollowsAMachineChange() throws {
    let (_, logger, gyms, exercise, gym) = try fixture()
    let plates = try gyms.createMachine(
      at: gym, name: "Plate Leg Press", stackIncrementKg: 2.5, now: now
    )
    let stack = try gyms.createMachine(
      at: gym, name: "Stack Leg Press", stackIncrementKg: 10, now: now
    )
    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: plates, exerciseName: "Leg Press", plannedSets: 2
        )
      ],
      now: { self.now }
    )
    #expect(live.exercises[0].machineIncrementKg == 2.5)
    #expect(
      live.changeMachine(
        to: stack, machineName: "Stack Leg Press", inExercise: live.exercises[0].id
      )
    )
    // Carrying 2.5 kg onto a 10 kg stack announces records the equipment cannot justify.
    #expect(live.exercises[0].machineIncrementKg == 10)
  }
}

/// A finish that fails must not look like a finish that worked.
@Suite("A refused finish leaves a reachable session")
@MainActor
struct FailedFinishTests {
  let now = Date(timeIntervalSince1970: 18_000_000)

  @Test("A session whose finish was refused is still the open session, holding its sets")
  func refusedFinishKeepsTheSessionOpen() throws {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let logger = LoggerStore(database: database)
    let live = try SessionCoordinator.start(
      store: logger,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 1)],
      now: { self.now }
    )
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))

    // A device clock correction can put "now" before the session started, which SessionTimeline
    // refuses. `LiveSessionScreen.finish` used to swallow this and advance anyway, so the root view
    // dropped the coordinator, the user started a new session, and the first one's sets became
    // unreachable — openSession() returns only the newest, and history lists finished sessions only.
    let rewound = SessionCoordinator(
      store: logger, sessionID: live.sessionID, exercises: live.exercises,
      now: { self.now.addingTimeInterval(-60) }
    )
    #expect(throws: SessionTimelineError.finishedBeforeStart) { try rewound.finish() }

    // Still open, so the screen can be re-entered and the sets are not stranded.
    #expect(try logger.openSession()?.id == live.sessionID)
    #expect(try logger.sets(in: live.sessionID).count == 1)
    // And it does finish once the clock is sane again.
    #expect(throws: Never.self) { try live.finish() }
    #expect(try logger.openSession() == nil)
  }
}
