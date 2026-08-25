import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Records are detected against real history, after the write")
@MainActor
struct RecordDetectionTests {
  let start = Date(timeIntervalSince1970: 11_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(_ database: any DatabaseWriter) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: "Leg Press") }.execute(db)
    }
    return id
  }

  /// Logs a finished session of working sets, so there is history to beat.
  private func seedHistory(
    _ store: LoggerStore, exercise: ExerciseID, sets: [(Double, Int)], at date: Date
  ) throws {
    let session = try store.startSession(at: date)
    for (index, set) in sets.enumerated() {
      _ = try store.logSet(
        sessionID: session, exerciseID: exercise,
        draft: SetEntryDraft(weightKg: set.0, reps: set.1),
        setOrdinal: index, at: date.addingTimeInterval(Double(index) * 60)
      )
    }
    try store.finishSession(session, at: date.addingTimeInterval(3600))
  }

  private func coordinator(
    _ store: LoggerStore, exercise: ExerciseID, increment: Double? = nil
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(
          exerciseID: exercise, exerciseName: "Leg Press",
          machineIncrementKg: increment, plannedSets: 3
        )
      ],
      now: { self.start }
    )
  }

  private func log(
    _ coordinator: SessionCoordinator, slot index: Int, _ weight: Double, _ reps: Int,
    isWarmup: Bool = false
  ) -> Bool {
    coordinator.exercises[0].slots[index].kind = isWarmup ? .warmup : .working
    coordinator.exercises[0].slots[index].draft = SetEntryDraft(weightKg: weight, reps: reps)
    return coordinator.logSet(
      slotID: coordinator.exercises[0].slots[index].id, inExercise: coordinator.exercises[0].id
    )
  }

  /// The trap: querying history after the write would compare the new set against itself, so a
  /// genuine best could never win.
  @Test("A new best is detected, not compared against itself")
  func newBestIsDetected() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(100, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise)
    #expect(log(live, slot: 0, 110, 8))
    #expect(live.lastRecords.map(\.kind).contains(.heaviestLoad))
  }

  @Test("Repeating a previous best is not a record")
  func repeatIsNotARecord() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(100, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise)
    #expect(log(live, slot: 0, 100, 8))
    #expect(live.lastRecords.isEmpty)
  }

  @Test("The very first set of a brand new lift is not a record")
  func firstEverSetIsNotARecord() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    let live = try coordinator(store, exercise: exercise)
    #expect(log(live, slot: 0, 200, 5))
    #expect(live.lastRecords.isEmpty)
  }

  /// Sets logged earlier in the same workout are history too.
  @Test("A set beats what was logged earlier in the same session")
  func beatsEarlierInSameSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(90, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise)
    #expect(log(live, slot: 0, 100, 8))
    #expect(live.lastRecords.map(\.kind).contains(.heaviestLoad))

    // Now beat the set just logged, within the same session.
    #expect(log(live, slot: 1, 110, 8))
    #expect(live.lastRecords.map(\.kind).contains(.heaviestLoad))
    let record = try #require(live.lastRecords.first { $0.kind == .heaviestLoad })
    #expect(record.previousWeightKg == 100)
  }

  /// A celebration must not linger onto a set that did not earn it.
  @Test("Records are cleared by the next non-record set")
  func recordsAreCleared() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(90, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise)
    #expect(log(live, slot: 0, 110, 8))
    #expect(!live.lastRecords.isEmpty)

    #expect(log(live, slot: 1, 80, 8))
    #expect(live.lastRecords.isEmpty)
  }

  @Test("A warm-up sets no records")
  func warmupSetsNoRecords() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(90, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise)
    #expect(log(live, slot: 0, 200, 5, isWarmup: true))
    #expect(live.lastRecords.isEmpty)
  }

  /// A warm-up in history must not become the benchmark to beat.
  @Test("Warm-ups in history are not benchmarks")
  func warmupsAreNotBenchmarks() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    // A heavy "warm-up" plus a light working set, in a finished session.
    let past = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(
      sessionID: past, exerciseID: exercise, draft: SetEntryDraft(weightKg: 300, reps: 1),
      setOrdinal: 0, isWarmup: true, at: start.addingTimeInterval(-86_400)
    )
    _ = try store.logSet(
      sessionID: past, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      setOrdinal: 1, at: start.addingTimeInterval(-86_000)
    )
    try store.finishSession(past, at: start.addingTimeInterval(-82_800))

    #expect(try store.completedSets(for: ProgressionKey(exerciseID: exercise)).count == 1)

    let live = try coordinator(store, exercise: exercise)
    // Beats the 100 kg working set even though a 300 kg warm-up exists.
    #expect(log(live, slot: 0, 110, 8))
    #expect(live.lastRecords.map(\.kind).contains(.heaviestLoad))
  }

  /// Machine-level progression: another machine's history is a different lift.
  @Test("History is per machine")
  func historyIsPerMachine() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gym = GymID()
    let machine = MachineID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: gym.rawValue, name: "Gym") }.execute(db)
      try Machine.insert {
        Machine.Draft(id: machine.rawValue, gymID: gym.rawValue, name: "Hammer Strength")
      }
      .execute(db)
    }
    try seedHistory(store, exercise: exercise, sets: [(200, 8)], at: start.addingTimeInterval(-86_400))

    // The free-weight history is 200 kg, but this machine has none, so nothing to beat.
    let live = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", plannedSets: 2
        )
      ],
      now: { self.start }
    )
    #expect(try store.completedSets(
      for: ProgressionKey(exerciseID: exercise, machineID: machine)
    ).isEmpty)
    #expect(log(live, slot: 0, 100, 8))
    #expect(live.lastRecords.isEmpty)
  }

  @Test("A machine's real increment governs the margin")
  func incrementGovernsMargin() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(100, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise, increment: 10)
    // +5 kg does not clear a 10 kg stack step.
    #expect(log(live, slot: 0, 105, 8))
    #expect(!live.lastRecords.map(\.kind).contains(.heaviestLoad))
  }

  @Test("A refused write announces nothing")
  func refusedWriteAnnouncesNothing() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try seedHistory(store, exercise: exercise, sets: [(90, 8)], at: start.addingTimeInterval(-86_400))

    let live = try coordinator(store, exercise: exercise)
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: nil, reps: 8)
    #expect(!live.logSet(
      slotID: live.exercises[0].slots[0].id, inExercise: live.exercises[0].id
    ))
    #expect(live.lastRecords.isEmpty)
  }
}
