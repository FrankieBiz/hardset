import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

/// The app was killed mid-workout. What comes back has to be what was written — no more, no
/// less, and nothing closed on the app's initiative.
@Suite("An interrupted workout is recovered from what was written")
@MainActor
struct SessionRecoveryTests {
  let start = Date(timeIntervalSince1970: 9_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(
    _ database: any DatabaseWriter, _ name: String
  ) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  private func seedGymAndMachine(
    _ database: any DatabaseWriter, machine name: String
  ) throws -> (GymID, MachineID) {
    let gym = GymID()
    let machine = MachineID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: gym.rawValue, name: "Test Gym") }.execute(db)
      try Machine.insert {
        Machine.Draft(id: machine.rawValue, gymID: gym.rawValue, name: name)
      }
      .execute(db)
    }
    return (gym, machine)
  }

  @Test("With nothing open, recovery returns nothing")
  func nothingToRecover() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    #expect(try SessionCoordinator.resume(store: store, now: { self.start }) == nil)
  }

  @Test("Recovery loads the workout in one read transaction")
  func recoveryUsesOneReadTransaction() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database, "Press")
    _ = try SessionCoordinator.start(
      store: store, plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Press")],
      now: { self.start }
    )
    let statements = Mutex<[String]>([])
    try database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event {
          statements.withLock { $0.append(statement.sql) }
        }
      }
    }
    let recovered = try SessionCoordinator.resume(store: store, now: { self.start })
    #expect(recovered != nil)
    let begins = statements.withLock { $0.filter { $0.hasPrefix("BEGIN") }.count }
    #expect(begins == 1)
  }

  @Test("A concurrent writer cannot mix recovery's plan, sets, and prior performance")
  func recoveryHasConsistentReadSnapshot() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hardset-recovery-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let reader = try DatabaseQueue(path: path, configuration: configuration)
    defer { try? reader.close() }
    try reader.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
    try HardsetMigrations.migrator().migrate(reader)
    let writer = try DatabaseQueue(path: path, configuration: configuration)
    defer { try? writer.close() }
    let store = LoggerStore(database: reader)
    let a = try seedExercise(reader, "Movement A")
    let b = try seedExercise(reader, "Movement B")
    let (gym, machine) = try seedGymAndMachine(reader, machine: "Shared station")
    let past = try store.startSession(gymID: gym, at: start.addingTimeInterval(-1000))
    for (exercise, weight) in [(a, 80.0), (b, 50.0)] {
      _ = try store.logSet(sessionID: past, exerciseID: exercise, machineID: machine,
                           draft: SetEntryDraft(weightKg: weight, reps: 8), at: start.addingTimeInterval(-900))
    }
    try store.finishSession(past, at: start.addingTimeInterval(-500))
    let live = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [PlannedExercise(exerciseID: a, machineID: machine, exerciseName: "Movement A", plannedSets: 2)],
      now: { self.start }
    )
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    let plan = try #require(try store.sessionExercises(in: live.sessionID).first)
    let fired = Mutex(false)
    let writeError = Mutex<String?>(nil)
    try reader.writeWithoutTransaction { db in
      db.trace(options: .profile) { event in
        guard case .profile(let statement, _) = event,
          statement.sql.contains("FROM \"machines\"")
        else { return }
        let shouldWrite = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        guard shouldWrite else { return }
        do {
          // A separate WAL connection can commit while the reader's snapshot
          // remains open. Trigger exactly after its plan metadata was fetched.
          try writer.write { other in
            try #sql("UPDATE sessionExercises SET exerciseID = \(b.rawValue) WHERE id = \(plan.id)").execute(other)
            try #sql("UPDATE loggedSets SET exerciseID = \(b.rawValue), weightKg = 900 WHERE sessionExerciseID = \(plan.id)").execute(other)
            try #sql("UPDATE loggedSets SET weightKg = 200 WHERE sessionID = \(past.rawValue) AND exerciseID = \(a.rawValue)").execute(other)
            try #sql("UPDATE loggedSets SET weightKg = 300 WHERE sessionID = \(past.rawValue) AND exerciseID = \(b.rawValue)").execute(other)
          }
        } catch {
          writeError.withLock { $0 = String(describing: error) }
        }
      }
    }
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))
    #expect(fired.withLock { $0 })
    #expect(writeError.withLock { $0 } == nil)
    let recoveredExercise = try #require(recovered.exercises.first)
    #expect(recoveredExercise.exerciseID == a)
    #expect(recoveredExercise.slots.first?.draft.weightKg == 100)
    #expect(recoveredExercise.slots.last?.draft.weightKg == 80)
    // A later load sees the whole newly committed version, proving recovery
    // isn't passing by ignoring the writer or keeping an application cache.
    let refreshed = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))
    let refreshedExercise = try #require(refreshed.exercises.first)
    #expect(refreshedExercise.exerciseID == b)
    #expect(refreshedExercise.slots.first?.draft.weightKg == 900)
    #expect(refreshedExercise.slots.last?.draft.weightKg == 300)
  }

  @Test("Next-set equipment provenance agrees before and after recovery",
        arguments: [false, true])
  func recoveryPreservesNextSetEquipment(startedOnMachine: Bool) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database, "Press")
    let (gym, currentMachine) = try seedGymAndMachine(database, machine: "Current press")
    let otherMachine = try GymStore(database: database).createMachine(at: gym, name: "Other press")
    let originalMachine = startedOnMachine ? otherMachine : nil
    let past = try store.startSession(gymID: gym, at: start.addingTimeInterval(-1000))
    _ = try store.logSet(sessionID: past, exerciseID: exercise, machineID: currentMachine,
                         draft: SetEntryDraft(weightKg: 30, reps: 10), at: start.addingTimeInterval(-900))
    try store.finishSession(past, at: start.addingTimeInterval(-500))
    let live = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, machineID: originalMachine,
                            exerciseName: "Press", plannedSets: 1)], now: { self.start }
    )
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(live.changeMachine(to: currentMachine, machineName: "Current press", inExercise: state.id))
    live.addSet(inExercise: state.id)
    #expect(live.exercises[0].slots.last?.draft.weightKg == 30)
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))
    #expect(recovered.exercises[0].slots[0].loggedMachineID == originalMachine)
    recovered.addSet(inExercise: recovered.exercises[0].id)
    #expect(recovered.exercises[0].slots.last?.draft.weightKg == 30)
    let written = try store.sets(in: live.sessionID)
    #expect(written.map(\.machineID) == [originalMachine])
  }

  @Test("Save order and timestamps drive next-set prefill through recovery")
  func recoveryPreservesLatestSavedValues() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database, "Press")
    let (gym, machine) = try seedGymAndMachine(database, machine: "Press")
    var clock = start
    let live = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, machineID: machine,
                            exerciseName: "Press", plannedSets: 2)], now: { clock }
    )
    let state = live.exercises[0]
    live.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 150, reps: 6)
    #expect(live.logSet(slotID: state.slots[1].id, inExercise: state.id))
    clock = start.addingTimeInterval(60)
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 120, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    live.addSet(inExercise: state.id)
    #expect(live.exercises[0].slots.last?.draft.weightKg == 120)
    #expect(live.exercises[0].slots.last?.draft.suggestion?.completedAt == clock)
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { clock }))
    recovered.addSet(inExercise: recovered.exercises[0].id)
    #expect(recovered.exercises[0].slots.last?.draft.weightKg == 120)
    #expect(recovered.exercises[0].slots.last?.draft.suggestion?.completedAt == clock)
    let saved = try store.sets(in: live.sessionID)
    #expect(saved.map(\.weightKg) == [150, 120])
  }

  @Test("A killed session comes back with its written sets already ticked")
  func recoversWrittenSets() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, "Leg Press")

    // Session one, in the past, so there is real history.
    let past = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(
      sessionID: past, exerciseID: press,
      draft: SetEntryDraft(weightKg: 100, reps: 10), setOrdinal: 0,
      at: start.addingTimeInterval(-86_400)
    )
    try store.finishSession(past, at: start.addingTimeInterval(-82_800))

    // Session two: two of three sets written, then the app dies.
    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Leg Press", plannedSets: 3)],
      now: { self.start }
    )
    for index in 0..<2 {
      live.exercises[0].slots[index].draft = SetEntryDraft(weightKg: 120, reps: 6)
      #expect(live.logSet(slotID: live.exercises[0].slots[index].id, inExercise: live.exercises[0].id))
    }

    // A fresh launch.
    let recovered = try #require(
      try SessionCoordinator.resume(store: store, now: { self.start.addingTimeInterval(600) })
    )
    #expect(recovered.sessionID == live.sessionID)
    #expect(recovered.exercises.count == 1)
    #expect(recovered.exercises[0].slots.count == 3)
    #expect(recovered.loggedSetCount == 2)
    #expect(recovered.exercises[0].slots[0].draft.weightKg == 120)
    #expect(!recovered.exercises[0].slots[2].isLogged)
    // The open row is prefilled from prior history, not from thin air.
    #expect(recovered.exercises[0].slots[2].draft.weightKg == 100)
  }

  /// The bug the ancestor app shipped: recovery must not decide the workout ended now.
  @Test("Recovery does not close the session")
  func recoveryDoesNotClose() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, "Leg Press")
    _ = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Leg Press")],
      now: { self.start }
    )

    // Recovered a day later; still open, and no duration has been invented.
    let recovered = try #require(
      try SessionCoordinator.resume(store: store, now: { self.start.addingTimeInterval(86_400) })
    )
    #expect(!recovered.isFinished)
    let row = try #require(try store.openSession())
    #expect(row.timeline.isOpen)
    #expect(row.timeline.duration == nil)
  }

  @Test("Machine identity survives recovery, so progression stays per-machine")
  func machineSurvives() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, "Leg Press")
    let (gym, machine) = try seedGymAndMachine(database, machine: "Hammer Strength")

    let live = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [
        PlannedExercise(
          exerciseID: press, machineID: machine, exerciseName: "Leg Press",
          machineName: "Hammer Strength", plannedSets: 2
        )
      ],
      now: { self.start }
    )
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 90, reps: 10)
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))

    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))
    #expect(recovered.exercises[0].machineID == machine)
    #expect(recovered.exercises[0].machineName == "Hammer Strength")
  }

  @Test("Exercise order is preserved")
  func orderPreserved() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let a = try seedExercise(database, "Leg Press")
    let b = try seedExercise(database, "Leg Curl")
    let c = try seedExercise(database, "Calf Raise")

    _ = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: a, exerciseName: "Leg Press"),
        PlannedExercise(exerciseID: b, exerciseName: "Leg Curl"),
        PlannedExercise(exerciseID: c, exerciseName: "Calf Raise"),
      ],
      now: { self.start }
    )

    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))
    #expect(recovered.exercises.map(\.exerciseName) == ["Leg Press", "Leg Curl", "Calf Raise"])
  }

  // MARK: - Adding mid-workout

  @Test("A movement added mid-workout appears with its history")
  func addMidWorkout() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, "Leg Press")
    let curl = try seedExercise(database, "Leg Curl")

    // History for the movement that is not on today's plan.
    let past = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(
      sessionID: past, exerciseID: curl,
      draft: SetEntryDraft(weightKg: 45, reps: 12), setOrdinal: 0,
      at: start.addingTimeInterval(-86_400)
    )
    try store.finishSession(past, at: start.addingTimeInterval(-82_800))

    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Leg Press")],
      now: { self.start }
    )

    let entry = CatalogEntry(
      id: curl, name: "Leg Curl", slug: "seated-leg-curl", isCurated: true,
      modality: .machine, primaryMuscle: MuscleKey(.hamstrings),
      contributions: [.init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy)]
    )
    #expect(live.addExercise(entry, plannedSets: 2))
    #expect(live.exercises.count == 2)
    #expect(live.exercises[1].exerciseName == "Leg Curl")
    #expect(live.exercises[1].slots.count == 2)
    #expect(live.exercises[1].slots[0].draft.weightKg == 45)

    // And it survives a recovery, at the right position.
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.start }))
    #expect(recovered.exercises.map(\.exerciseName) == ["Leg Press", "Leg Curl"])
  }

  @Test("Adding an unknown exercise fails and is reported")
  func addUnknownExerciseFails() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, "Leg Press")
    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Leg Press")],
      now: { self.start }
    )

    // No such row, so the foreign key refuses it. The session must not gain a phantom exercise.
    #expect(!live.addExercise(exerciseID: ExerciseID(), exerciseName: "Ghost Lift"))
    #expect(live.exercises.count == 1)
    #expect(live.lastError != nil)
  }

  /// Review focus: a workout killed mid-session must not forget its plan. The rep range is on the
  /// session's own rows, so the open rows get their targets back without the template.
  @Test("A restarted workout rebuilds its targets from the session's own rep range")
  func resumeRebuildsTargets() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database, "Chest Press")
    let (gym, machine) = try seedGymAndMachine(database, machine: "Press")
    let earlier = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [PlannedExercise(
        exerciseID: exercise, machineID: machine, exerciseName: "Chest Press", plannedSets: 2)],
      now: { self.start.addingTimeInterval(-86_400) }
    )
    for (index, set) in [(40.0, 10), (40.0, 9)].enumerated() {
      earlier.exercises[0].slots[index].draft = SetEntryDraft(weightKg: set.0, reps: set.1)
      #expect(earlier.logSet(slotID: earlier.exercises[0].slots[index].id, inExercise: earlier.exercises[0].id))
    }
    try earlier.finish()

    let range = try #require(RepRange(lower: 8, upper: 12))
    let live = try SessionCoordinator.start(
      store: store, gymID: gym, title: "Upper A",
      plan: [PlannedExercise(
        exerciseID: exercise, machineID: machine, exerciseName: "Chest Press", plannedSets: 3,
        repRange: range)],
      templateID: TemplateID(), weightUnit: .kilograms, now: { self.start }
    )
    #expect(live.exercises[0].slots.map { $0.draft.reps } == [11, 10, 10])
    #expect(live.logSet(slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id))

    let recovered = try #require(
      try SessionCoordinator.resume(store: store, weightUnit: .kilograms, now: { self.start }))

    let state = recovered.exercises[0]
    #expect(state.repRange == range)
    #expect(state.slots[0].isLogged)
    #expect(state.slots[0].draft.target == nil)
    #expect(state.slots[1].draft.target != nil)
    #expect(state.slots[2].draft.target != nil)
    #expect(state.slots[1].draft.reps == 10)
    // The set logged before the restart still compares with its partner from last time.
    #expect(recovered.comparison(forSlotID: state.slots[0].id, inExercise: state.id)
      == .beat(addedKg: 0, addedReps: 1))
  }

  @Test("A bodyweight movement recovered after a restart still only adds reps")
  func resumeKeepsBodyweightTargetsRepsOnly() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: exercise.rawValue, name: "Pull-up", modality: "bodyweight")
      }
      .execute(db)
    }
    let earlier = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Pull-up", plannedSets: 2)],
      now: { self.start.addingTimeInterval(-86_400) }
    )
    for index in 0..<2 {
      earlier.exercises[0].slots[index].draft = SetEntryDraft(weightKg: 0, reps: 12)
      #expect(earlier.logSet(slotID: earlier.exercises[0].slots[index].id, inExercise: earlier.exercises[0].id))
    }
    try earlier.finish()
    let range = try #require(RepRange(lower: 8, upper: 12))
    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(
        exerciseID: exercise, exerciseName: "Pull-up", plannedSets: 2, repRange: range)],
      templateID: TemplateID(), weightUnit: .kilograms, now: { self.start }
    )
    #expect(live.exercises[0].slots.map { $0.draft.reps } == [13, 13])

    let recovered = try #require(
      try SessionCoordinator.resume(store: store, weightUnit: .kilograms, now: { self.start }))

    #expect(recovered.exercises[0].slots.map { $0.draft.reps } == [13, 13])
    #expect(recovered.exercises[0].slots.map { $0.draft.weightKg } == [0, 0])
  }

  /// Review focus: a pound lifter with no saved machine step gets a one-plate step of 5 lb, and a
  /// restart must not turn it into 2.5 kg. The unit is the one thing resume cannot read back.
  @Test("A restarted workout builds its assumed one-plate step in the lifter's unit")
  func resumeUsesTheLiftersUnitForTheAssumedStep() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database, "Chest Press")
    let earlier = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Chest Press", plannedSets: 2)],
      now: { self.start.addingTimeInterval(-86_400) }
    )
    for index in 0..<2 {
      earlier.exercises[0].slots[index].draft = SetEntryDraft(weightKg: 40, reps: 12)
      #expect(earlier.logSet(slotID: earlier.exercises[0].slots[index].id, inExercise: earlier.exercises[0].id))
    }
    try earlier.finish()
    let range = try #require(RepRange(lower: 8, upper: 12))
    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(
        exerciseID: exercise, exerciseName: "Chest Press", plannedSets: 2, repRange: range)],
      templateID: TemplateID(), weightUnit: .pounds, now: { self.start }
    )
    let plate = 40 + 2.26796185
    #expect(abs((live.exercises[0].slots[0].draft.weightKg ?? 0) - plate) < 1e-6)

    let inPounds = try #require(
      try SessionCoordinator.resume(store: store, weightUnit: .pounds, now: { self.start }))
    let inKilograms = try #require(
      try SessionCoordinator.resume(store: store, weightUnit: .kilograms, now: { self.start }))

    #expect(abs((inPounds.exercises[0].slots[0].draft.weightKg ?? 0) - plate) < 1e-6)
    #expect(inKilograms.exercises[0].slots[0].draft.weightKg == 42.5)
  }
}
