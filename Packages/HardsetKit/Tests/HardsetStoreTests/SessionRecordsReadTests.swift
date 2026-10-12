import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Records read back from the database agree with the moment they were announced")
@MainActor
struct SessionRecordsReadTests {
  let start = Date(timeIntervalSince1970: 21_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
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

  /// A finished workout `daysAgo` before `start`, its sets logged a minute apart.
  @discardableResult
  private func workout(
    _ store: LoggerStore, _ exercise: ExerciseID, machine: MachineID? = nil,
    sets: [(Double, Int)], daysAgo: Double
  ) throws -> SessionID {
    let date = start.addingTimeInterval(-daysAgo * 86_400)
    let session = try store.startSession(at: date)
    for (index, set) in sets.enumerated() {
      _ = try store.logSet(
        sessionID: session, exerciseID: exercise, machineID: machine,
        draft: SetEntryDraft(weightKg: set.0, reps: set.1),
        at: date.addingTimeInterval(Double(index) * 60))
    }
    try store.finishSession(session, at: date.addingTimeInterval(3_600))
    return session
  }

  @Test("What the coordinator announced is what the database says")
  func agreesWithLiveDetection() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: start)
    let machine = try gyms.createMachine(
      at: gym, name: "Leg Press", stackIncrementKg: 5, now: start)
    try workout(store, exercise, machine: machine, sets: [(100, 8), (100, 8)], daysAgo: 7)

    let coordinator = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", plannedSets: 3)
      ],
      now: { self.start }
    )
    let state = coordinator.exercises[0]
    var announced: [SetID: Set<PersonalRecordKind>] = [:]
    for (index, set) in [(101.0, 8), (106.0, 8), (106.0, 9)].enumerated() {
      coordinator.exercises[0].slots[index].draft = SetEntryDraft(weightKg: set.0, reps: set.1)
      #expect(coordinator.logSet(slotID: state.slots[index].id, inExercise: state.id))
      let setID = try #require(coordinator.exercises[0].slots[index].loggedSetID)
      let kinds = Set(coordinator.lastRecords.map(\.kind))
      if !kinds.isEmpty { announced[setID] = kinds }
    }

    let read = try store.recordsBySet(in: coordinator.sessionID).mapValues { Set($0.map(\.kind)) }
    #expect(!read.isEmpty)
    #expect(read == announced)
  }

  @Test("A workout is judged against what came before it, never after")
  func laterWorkoutsDoNotCount() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let judged = try workout(store, exercise, sets: [(110, 8)], daysAgo: 3)
    try workout(store, exercise, sets: [(120, 8)], daysAgo: 1)

    let records = try store.recordsBySet(in: judged)
    #expect(records.values.contains { $0.contains { $0.kind == .heaviestLoad } })
  }

  @Test("A corrected set is judged on what it says now")
  func correctedSetRejudged() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let session = try store.startSession(at: start)
    let typo = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 1000, reps: 8),
      at: start)
    #expect(try store.recordsBySet(in: session)[typo] != nil)

    try store.updateSet(typo, to: SetEntryDraft(weightKg: 100, reps: 8))

    #expect(try store.recordsBySet(in: session).isEmpty)
  }

  @Test("A deleted set is not judged, and no longer raises the bar for the sets after it")
  func deletedSetIsGone() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let session = try store.startSession(at: start)
    let first = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 110, reps: 8),
      at: start)
    let second = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 112, reps: 8),
      at: start.addingTimeInterval(60))
    // 112 does not beat 110 by max(2.75, 2.5) kg, nor its estimate by 2.5%.
    #expect(try store.recordsBySet(in: session)[second] == nil)

    try store.deleteSet(first)

    let records = try store.recordsBySet(in: session)
    #expect(records[first] == nil)
    #expect(records[second]?.contains { $0.kind == .heaviestLoad } == true)
  }

  @Test("A workout with no sets has no records, and an unknown one is reported")
  func emptyAndUnknown() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)
    #expect(try store.recordsBySet(in: session).isEmpty)
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.recordsBySet(in: SessionID()) }
  }

  @Test("Two sets with the same completion time are judged in setOrdinal order")
  func sameTimestampTieBreak() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try workout(store, exercise, sets: [(100, 8)], daysAgo: 7)
    let session = try store.startSession(at: start)
    // Logged out of ordinal order, at one instant: the 120 is ordinal 1, the 110 ordinal 0.
    let heavy = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 120, reps: 8),
      setOrdinal: 1, at: start)
    let light = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 110, reps: 8),
      setOrdinal: 0, at: start)

    let records = try store.recordsBySet(in: session)
    #expect(records[light]?.contains { $0.kind == .heaviestLoad } == true)
    #expect(records[heavy]?.contains { $0.kind == .heaviestLoad } == true)
  }

  /// `logSet` judges against the newest 1,000 sets of the movement and machine. A replay that read
  /// every set ever logged saw an older, heavier one and took a trophy away on resume.
  @Test("Past 1,000 prior sets the replay judges against the same window the moment did")
  func replayUsesTheMomentsWindow() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: start)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", stackIncrementKg: 5, now: start)
    let other = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: start)

    let past = try store.startSession(at: start.addingTimeInterval(-90 * 86_400))
    try database.write { db in
      // The all-time best is the oldest set, 1,001st from the newest.
      var drafts = [LoggedSet.Draft(
        sessionID: past.rawValue, exerciseID: exercise.rawValue, machineID: machine.rawValue,
        setOrdinal: 0, weightKg: 200, reps: 5,
        completedAt: start.addingTimeInterval(-80 * 86_400))]
      for index in 1...1_000 {
        drafts.append(LoggedSet.Draft(
          sessionID: past.rawValue, exerciseID: exercise.rawValue, machineID: machine.rawValue,
          setOrdinal: index, weightKg: 100, reps: 8,
          completedAt: start.addingTimeInterval(-70 * 86_400 + Double(index))))
      }
      // The other machine's heavy set must not leak into this machine's history.
      drafts.append(LoggedSet.Draft(
        sessionID: past.rawValue, exerciseID: exercise.rawValue, machineID: other.rawValue,
        setOrdinal: 2_000, weightKg: 300, reps: 5,
        completedAt: start.addingTimeInterval(-60 * 86_400)))
      try LoggedSet.insert { drafts }.execute(db)
    }
    try store.finishSession(past, at: start.addingTimeInterval(-60 * 86_400 + 3_600))

    let coordinator = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [
        PlannedExercise(
          exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", plannedSets: 1)
      ],
      now: { self.start }
    )
    let state = coordinator.exercises[0]
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 150, reps: 5)
    #expect(coordinator.logSet(slotID: state.slots[0].id, inExercise: state.id))
    let setID = try #require(coordinator.exercises[0].slots[0].loggedSetID)
    let announced = Set(coordinator.lastRecords.map(\.kind))
    #expect(!announced.isEmpty)

    let read = try store.recordsBySet(in: coordinator.sessionID)
    #expect(Set((read[setID] ?? []).map(\.kind)) == announced)
  }
}
