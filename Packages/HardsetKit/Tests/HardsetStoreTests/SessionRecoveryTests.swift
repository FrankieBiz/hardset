import Foundation
import GRDB
import HardsetCore
import SQLiteData
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
}
