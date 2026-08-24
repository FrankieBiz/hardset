import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Moving machine mid-exercise, which is what happens when your usual station is occupied.
@Suite("Changing machine re-prefills from that machine's history")
@MainActor
struct MachineChangeTests {
  let now = Date(timeIntervalSince1970: 17_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws
    -> (any DatabaseWriter, LoggerStore, GymStore, ExerciseID, MachineID, MachineID)
  {
    let database = try migratedDatabase()
    let logger = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let gym = try gyms.createGym(name: "Gym", now: now)
    let hammer = try gyms.createMachine(at: gym, name: "Hammer Strength Leg Press", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex Leg Press", now: now)
    return (database, logger, gyms, exercise, hammer, cybex)
  }

  /// History on each machine, so a change has something to prefill from.
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

  @Test("Unlogged rows re-prefill from the new machine")
  func unloggedRowsReprefill() throws {
    let (_, logger, _, exercise, hammer, cybex) = try fixture()
    try seedHistory(logger, exercise, hammer, weight: 120, daysAgo: 7)
    try seedHistory(logger, exercise, cybex, weight: 80, daysAgo: 5)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press",
          machineName: "Hammer Strength Leg Press", plannedSets: 3
        )
      ],
      now: { self.now }
    )
    #expect(live.exercises[0].slots[0].draft.weightKg == 120)

    // Occupied. Move to the Cybex.
    #expect(live.changeMachine(
      to: cybex, machineName: "Cybex Leg Press", inExercise: live.exercises[0].id
    ))

    #expect(live.exercises[0].machineID == cybex)
    #expect(live.exercises[0].machineName == "Cybex Leg Press")
    // Prefilled from the Cybex's own history, not carried over from the Hammer.
    for slot in live.exercises[0].slots {
      #expect(slot.draft.weightKg == 80)
    }
  }

  /// Those sets were performed on the previous machine. Rewriting them would falsify the record.
  @Test("Already-logged rows keep the machine they were performed on")
  func loggedRowsAreUntouched() throws {
    let (_, logger, _, exercise, hammer, cybex) = try fixture()
    try seedHistory(logger, exercise, hammer, weight: 120, daysAgo: 7)
    try seedHistory(logger, exercise, cybex, weight: 80, daysAgo: 5)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 3
        )
      ],
      now: { self.now }
    )
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))

    #expect(live.changeMachine(to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id))

    // The logged row keeps its value...
    #expect(live.exercises[0].slots[0].draft.weightKg == 120)
    #expect(live.exercises[0].slots[0].isLogged)
    // ...and in storage it still points at the Hammer.
    let stored = try logger.sets(in: live.sessionID)
    #expect(stored.count == 1)
    #expect(stored[0].machineID == hammer)
    // While the unlogged rows moved on.
    #expect(live.exercises[0].slots[1].draft.weightKg == 80)
  }

  @Test("Sets logged after the change record the new machine")
  func newSetsRecordNewMachine() throws {
    let (_, logger, _, exercise, hammer, cybex) = try fixture()
    try seedHistory(logger, exercise, hammer, weight: 120, daysAgo: 7)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 2
        )
      ],
      now: { self.now }
    )
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))
    #expect(live.changeMachine(to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id))
    live.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 85, reps: 8)
    #expect(live.logSet(slotID: live.exercises[0].slots[1].id, inExercise: live.exercises[0].id))

    let stored = try logger.sets(in: live.sessionID).sorted { $0.setOrdinal < $1.setOrdinal }
    #expect(stored.map(\.machineID) == [hammer, cybex])
  }

  /// Moving to equipment with no history borrows and says so, rather than silently keeping the old
  /// machine's numbers.
  @Test("A machine with no history borrows, labelled")
  func borrowsAndLabels() throws {
    let (_, logger, gyms, exercise, hammer, _) = try fixture()
    try seedHistory(logger, exercise, hammer, weight: 120, daysAgo: 7)
    let brandNew = try gyms.createMachine(
      at: try gyms.gyms()[0].id, name: "Panatta Leg Press", now: now
    )

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 2
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(to: brandNew, machineName: "Panatta", inExercise: live.exercises[0].id))

    #expect(live.exercises[0].priorNote == "From another machine")
    #expect(live.exercises[0].slots[0].draft.weightKg == 120)
  }

  @Test("Moving to no machine clears the selection")
  func clearingMachine() throws {
    let (_, logger, _, exercise, hammer, _) = try fixture()
    try seedHistory(logger, exercise, hammer, weight: 120, daysAgo: 7)

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 1
        )
      ],
      now: { self.now }
    )
    #expect(live.changeMachine(to: nil, machineName: nil, inExercise: live.exercises[0].id))
    #expect(live.exercises[0].machineID == nil)
    #expect(live.exercises[0].machineName == nil)
  }

  @Test("An unknown exercise is reported rather than trapping")
  func unknownExercise() throws {
    let (_, logger, _, exercise, hammer, cybex) = try fixture()
    let live = try SessionCoordinator.start(
      store: logger,
      plan: [PlannedExercise(exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press")],
      now: { self.now }
    )
    #expect(!live.changeMachine(to: cybex, machineName: "Cybex", inExercise: UUID()))
    #expect(live.lastError as? SessionCoordinatorError == .unknownExercise)
  }

  /// A warm-up above a working row must not shift which historical set the working row prefills
  /// from.
  @Test("Warm-ups do not shift the prefill index after a change")
  func warmupsDoNotShiftPrefill() throws {
    let (_, logger, _, exercise, hammer, cybex) = try fixture()
    // Two sets on the Cybex, at different loads, so an off-by-one would be visible.
    let start = now.addingTimeInterval(-5 * 86_400)
    let session = try logger.startSession(at: start)
    for (index, weight) in [80.0, 90.0].enumerated() {
      _ = try logger.logSet(
        sessionID: session, exerciseID: exercise, machineID: cybex,
        draft: SetEntryDraft(weightKg: weight, reps: 8), setOrdinal: index,
        at: start.addingTimeInterval(Double(index) * 60)
      )
    }
    try logger.finishSession(session, at: start.addingTimeInterval(3600))

    let live = try SessionCoordinator.start(
      store: logger,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: hammer, exerciseName: "Leg Press", plannedSets: 2
        )
      ],
      now: { self.now }
    )
    live.addSet(inExercise: live.exercises[0].id, isWarmup: true)
    // Move the warm-up to the front so it precedes both working rows.
    let warmup = live.exercises[0].slots.removeLast()
    live.exercises[0].slots.insert(warmup, at: 0)

    #expect(live.changeMachine(to: cybex, machineName: "Cybex", inExercise: live.exercises[0].id))

    // The two working rows get the first and second historical sets, not the second and third.
    let working = live.exercises[0].slots.filter { !$0.isWarmup }
    #expect(working.map(\.draft.weightKg) == [80, 90])
  }
}
