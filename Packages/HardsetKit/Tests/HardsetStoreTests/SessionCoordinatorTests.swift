import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

/// The coordinator's ordering guarantees: nothing is marked logged, and no rest starts, until
/// the write has actually succeeded.
@Suite("A live session persists before it claims to")
@MainActor
struct SessionCoordinatorTests {
  let start = Date(timeIntervalSince1970: 6_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(
    _ database: any DatabaseWriter, name: String = "Leg Press"
  ) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  /// Records what rest was asked for, so the assertion is about behaviour and not about
  /// AlarmKit — which does not exist on the host.
  private final class RestSpy {
    var requests: [(Duration, RestMetadata)] = []
  }

  // MARK: - Starting

  @Test("A failed or ignored plan insert leaves no partial workout or exercise rows",
        arguments: ["ABORT", "IGNORE"])
  func failedStartRollsBackPlan(failure: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    // Reject the second plan row after the first has been inserted. This also
    // covers failures occurring during the write, after startup reads succeeded.
    let rejection = failure == "IGNORE" ? "RAISE(IGNORE)" : "RAISE(ABORT, 'injected plan failure')"
    try database.write { db in
      try db.execute(sql: """
        CREATE TEMP TRIGGER fail_second_plan BEFORE INSERT ON sessionExercises
        WHEN NEW.position = 1 BEGIN
          SELECT \(rejection);
        END
        """)
    }
    #expect(throws: (any Error).self) {
      _ = try SessionCoordinator.start(
        store: store,
        plan: [
          PlannedExercise(exerciseID: exercise, exerciseName: "First block"),
          PlannedExercise(exerciseID: exercise, exerciseName: "Second block"),
        ],
        now: { self.start }
      )
    }
    try database.read { db in
      let sessions = try Int.fetchOne(db, sql: "SELECT count(*) FROM sessions")
      let exercises = try Int.fetchOne(db, sql: "SELECT count(*) FROM sessionExercises")
      #expect(sessions == 0)
      #expect(exercises == 0)
    }
  }

  @Test("A startup history-read failure does not create an abandoned workout")
  func failedHistoryReadDoesNotCreateSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    try database.write { db in
      try db.execute(sql: "DROP TABLE loggedSets")
    }
    #expect(throws: (any Error).self) {
      _ = try SessionCoordinator.start(
        store: store,
        plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
        now: { self.start }
      )
    }
    #expect(try store.openSession() == nil)
  }

  @Test("A twelve-exercise workout starts with one write transaction")
  func startUsesOneWriteTransaction() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let statements = Mutex<[String]>([])
    database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event {
          statements.withLock { $0.append(statement.sql) }
        }
      }
    }
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: (0..<12).map { index in
        PlannedExercise(exerciseID: exercise, exerciseName: "Block \(index)", plannedSets: index + 1)
      },
      now: { self.start }
    )
    let writes = statements.withLock { rows in
      rows.filter { $0.hasPrefix("BEGIN IMMEDIATE") }.count
    }
    #expect(writes == 1)
    let saved = try store.sessionExercises(in: coordinator.sessionID)
    #expect(saved.map(\.position) == Array(0..<12))
    #expect(saved.map(\.plannedSets) == (1...12).map { Optional($0) })
    #expect(coordinator.exercises.map { $0.slots.count } == Array(1...12))
  }

  @Test("A failed movement history read leaves both memory and the saved plan unchanged")
  func failedAddDoesNotPersistMovement() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(store: store, plan: [], now: { self.start })
    try database.write { db in
      try db.execute(sql: "DROP TABLE loggedSets")
    }
    let added = coordinator.addExercise(exerciseID: exercise, exerciseName: "Leg Press")
    #expect(!added)
    #expect(coordinator.lastError != nil)
    #expect(coordinator.exercises.isEmpty)
    #expect(try store.sessionExercises(in: coordinator.sessionID).isEmpty)
  }

  @Test("Starting a session opens it and builds a row per planned set")
  func startBuildsPlan() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)
      ],
      now: { self.start }
    )

    #expect(coordinator.exercises.count == 1)
    #expect(coordinator.exercises[0].slots.count == 3)
    // No history exists, so nothing is prefilled and nothing is loggable yet.
    let anyLoggable = coordinator.exercises[0].slots.contains { $0.draft.isLoggable }
    #expect(!anyLoggable)
    #expect(try store.openSession()?.id == coordinator.sessionID)
  }

  /// A resumed session must not suggest values from its own sets.
  @Test("The new session is excluded from its own history")
  func excludesOwnSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    // A completed prior session, so there is real history to prefill from.
    let previous = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(
      sessionID: previous, exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 90, reps: 10), setOrdinal: 0,
      at: start.addingTimeInterval(-86_400)
    )
    try store.finishSession(previous, at: start.addingTimeInterval(-82_800))

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    #expect(coordinator.exercises[0].slots[0].draft.weightKg == 90)
  }

  // MARK: - Logging order

  @Test("A stale plan cannot half-apply an equipment change",
        arguments: ["deleted", "ignored", "session", "exercise", "closed"])
  func stalePlanLeavesMachineStateUntouched(context: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Gym")
    let machine = try gyms.createMachine(at: gym, name: "Press")
    let live = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Press")], now: { self.start }
    )
    let plan = try #require(try store.sessionExercises(in: live.sessionID).first)
    let before = live.exercises
    let expected: LoggerStoreError
    switch context {
    case "deleted":
      try database.write { db in
        try db.execute(sql: "DELETE FROM sessionExercises WHERE id = ?", arguments: [plan.id.uuidString.lowercased()])
      }
      expected = .sessionExerciseNotFound
    case "ignored":
      try database.write { db in
        try db.execute(sql: "CREATE TEMP TRIGGER ignore_machine BEFORE UPDATE ON sessionExercises BEGIN SELECT RAISE(IGNORE); END")
      }
      expected = .writeNotApplied
    case "session":
      let other = try store.startSession(gymID: gym, at: start)
      try database.write { db in
        try db.execute(sql: "UPDATE sessionExercises SET sessionID = ? WHERE id = ?",
                       arguments: [other.rawValue.uuidString.lowercased(), plan.id.uuidString.lowercased()])
      }
      expected = .sessionExerciseMismatch
    case "exercise":
      let other = try seedExercise(database, name: "Curl")
      try database.write { db in
        try db.execute(sql: "UPDATE sessionExercises SET exerciseID = ? WHERE id = ?",
                       arguments: [other.rawValue.uuidString.lowercased(), plan.id.uuidString.lowercased()])
      }
      expected = .sessionExerciseMismatch
    default:
      try store.finishSession(live.sessionID, at: start.addingTimeInterval(600))
      expected = .sessionClosed
    }
    #expect(!live.changeMachine(to: machine, machineName: "Press", inExercise: before[0].id))
    #expect(live.lastError as? LoggerStoreError == expected)
    #expect(live.exercises == before)
    let savedMachine = try database.read { db in
      try SessionExercise.where { $0.id.eq(plan.id) }.fetchOne(db)?.machineID
    }
    #expect(savedMachine == nil)
  }

  @Test("A workout or plan changed by another writer cannot claim a saved set",
        arguments: ["closed", "plan", "machine"])
  func staleLoggingContextDoesNotClaimSet(context: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Gym")
    let machine = try gyms.createMachine(at: gym, name: "Press")
    let spy = RestSpy()
    let live = try SessionCoordinator.start(
      store: store, gymID: gym,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Press")],
      now: { self.start }, restAfterSet: .seconds(60),
      onStartRest: { spy.requests.append(($0, $1)) }
    )
    let plan = try #require(try store.sessionExercises(in: live.sessionID).first)
    let expected: LoggerStoreError
    if context == "closed" {
      try store.finishSession(live.sessionID, at: start.addingTimeInterval(600))
      #expect(!live.addExercise(exerciseID: exercise, exerciseName: "Press"))
      #expect(live.exercises.count == 1)
      expected = .sessionClosed
    } else if context == "plan" {
      try database.write { db in
        try db.execute(sql: "DELETE FROM sessionExercises WHERE id = ?", arguments: [plan.id.uuidString.lowercased()])
      }
      expected = .sessionExerciseNotFound
    } else {
      try store.setSessionExerciseMachine(rowID: plan.id, machineID: machine)
      expected = .sessionExerciseMismatch
    }
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(!live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(live.lastError as? LoggerStoreError == expected)
    #expect(!live.exercises[0].slots[0].isLogged)
    #expect(live.lastRecords.isEmpty)
    #expect(spy.requests.isEmpty)
    #expect(try store.sets(in: live.sessionID).isEmpty)
  }

  @Test("All-time record claims retain benchmarks older than a thousand sets",
        arguments: PersonalRecordKind.allCases)
  func recordsKeepOlderBenchmarks(kind: PersonalRecordKind) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let past = try store.startSession(at: start.addingTimeInterval(-10000))
    let oldWeight: Double = kind == .heaviestLoad ? 200 : 100
    let recentWeight: Double = kind == .repsAtLoad ? 100 : 50
    try database.write { db in
      try LoggedSet.insert {
        LoggedSet.Draft(sessionID: past.rawValue, exerciseID: exercise.rawValue,
                       weightKg: oldWeight, reps: 12, completedAt: self.start.addingTimeInterval(-10000))
      }.execute(db)
      for ordinal in 1...1001 {
        try LoggedSet.insert {
          LoggedSet.Draft(sessionID: past.rawValue, exerciseID: exercise.rawValue,
                         setOrdinal: ordinal, weightKg: recentWeight, reps: 5,
                         completedAt: self.start.addingTimeInterval(Double(ordinal) - 9000))
        }.execute(db)
      }
    }
    try store.finishSession(past, at: start.addingTimeInterval(-1000))
    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(
      weightKg: kind == .repsAtLoad ? 100 : 110, reps: kind == .repsAtLoad ? 10 : 3
    )
    let logged = live.logSet(slotID: state.slots[0].id, inExercise: state.id)
    #expect(logged)
    let claimed = live.lastRecords.contains { $0.kind == kind }
    #expect(!claimed)
  }

  @Test("A failed set save cannot publish a new record or leave the previous celebration visible")
  func failedSaveDoesNotAnnounceRecords() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let previous = try store.startSession(at: start.addingTimeInterval(-1000))
    _ = try store.logSet(sessionID: previous, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 90, reps: 8), at: start.addingTimeInterval(-900))
    try store.finishSession(previous, at: start.addingTimeInterval(-500))
    let spy = RestSpy()
    let live = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 2)],
      now: { self.start }, restAfterSet: .seconds(60),
      onStartRest: { spy.requests.append(($0, $1)) }
    )
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(!live.lastRecords.isEmpty)
    try database.write { db in
      try db.execute(sql: """
        CREATE TEMP TRIGGER refuse_set BEFORE INSERT ON loggedSets BEGIN
          SELECT RAISE(ABORT, 'injected set save failure');
        END
        """)
    }
    live.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 110, reps: 8)
    #expect(!live.logSet(slotID: state.slots[1].id, inExercise: state.id))
    #expect(live.lastRecords.isEmpty)
    #expect(!live.exercises[0].slots[1].isLogged)
    #expect(live.lastError != nil)
    #expect(spy.requests.count == 1)
    #expect(try store.sets(in: live.sessionID).count == 1)
  }

  @Test("Record comparison reads and the set save share one transaction",
        arguments: [false, true])
  func comparisonsShareSaveTransaction(isWarmup: Bool) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let live = try SessionCoordinator.start(
      store: store, plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Press")],
      now: { self.start }
    )
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    live.exercises[0].slots[0].isWarmup = isWarmup
    let statements = Mutex<[String]>([])
    database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event {
          statements.withLock { $0.append(statement.sql) }
        }
      }
    }
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    let sql = statements.withLock { $0 }
    let begin = try #require(sql.firstIndex { $0.hasPrefix("BEGIN IMMEDIATE") })
    let commit = try #require(sql.lastIndex { $0 == "COMMIT TRANSACTION" || $0 == "COMMIT" })
    let reads = sql.indices.filter { sql[$0].hasPrefix("SELECT") }
    let readsInsideSave = reads.allSatisfy { $0 > begin && $0 < commit }
    #expect(readsInsideSave)
    // Three primary-key reads validate session, exercise, and plan. Empty
    // history needs one benchmark probe; warm-ups skip it. Both read one ordinal.
    // The command identity probe is a separate primary-key read in this same transaction.
    let identityReads = reads.filter { sql[$0].contains("WHERE ((\"loggedSets\".\"id\") =") }
    #expect(identityReads.count == 1)
    #expect(reads.count - identityReads.count == (isWarmup ? 4 : 5))
  }

  @Test("Unreadable record history suppresses claims while a valid new set still saves")
  func unreadableRecordHistoryDoesNotLoseSet() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let past = try store.startSession(at: start.addingTimeInterval(-1000))
    _ = try store.logSet(sessionID: past, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: start.addingTimeInterval(-900))
    let live = try SessionCoordinator.start(
      store: store, plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Press")],
      now: { self.start }
    )
    // A bad imported date makes full comparison-row decoding fail. The new
    // set and its scalar ordinal lookup remain independently readable/writable.
    try database.write { db in
      try db.execute(sql: "UPDATE loggedSets SET completedAt = 'unreadable' WHERE sessionID = ?",
                     arguments: [past.rawValue.uuidString.lowercased()])
    }
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 110, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    #expect(live.lastRecords.isEmpty)
    #expect(live.exercises[0].slots[0].isLogged)
    #expect(try store.sets(in: live.sessionID).count == 1)
  }

  @Test("A successful write marks the row and requests rest")
  func successMarksAndRests() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(
          exerciseID: exercise, exerciseName: "Leg Press",
          machineName: "Hammer Strength", plannedSets: 2
        )
      ],
      now: { self.start },
      restAfterSet: .seconds(120),
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )

    let state = coordinator.exercises[0]
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    let didLog = coordinator.logSet(slotID: state.slots[0].id, inExercise: state.id)

    #expect(didLog)
    #expect(coordinator.exercises[0].slots[0].isLogged)
    #expect(coordinator.loggedSetCount == 1)
    #expect(coordinator.lastError == nil)
    #expect(try store.sets(in: coordinator.sessionID).count == 1)

    #expect(spy.requests.count == 1)
    #expect(spy.requests[0].0 == .seconds(120))
    #expect(spy.requests[0].1.exerciseName == "Leg Press")
    #expect(spy.requests[0].1.machineName == "Hammer Strength")
    #expect(spy.requests[0].1.setLabel == "Set 1 of 2")
  }

  /// The guarantee that matters: an incomplete row must not show a check mark, and must not
  /// start a rest timer for a set that was never saved.
  @Test("A refused write leaves the row unlogged and starts no rest")
  func failureLeavesRowAlone() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restAfterSet: .seconds(120),
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )

    let state = coordinator.exercises[0]
    // Draft is empty — there is no history and nothing was typed.
    let didLog = coordinator.logSet(slotID: state.slots[0].id, inExercise: state.id)

    #expect(!didLog)
    #expect(!coordinator.exercises[0].slots[0].isLogged)
    #expect(coordinator.loggedSetCount == 0)
    #expect(coordinator.lastError as? LoggerStoreError == .incompleteSet)
    #expect(spy.requests.isEmpty)
    #expect(try store.sets(in: coordinator.sessionID).isEmpty)
  }

  @Test("A warm-up is written but starts no rest")
  func warmupStartsNoRest() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restAfterSet: .seconds(120),
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )
    coordinator.addSet(inExercise: coordinator.exercises[0].id, isWarmup: true)
    let warmupSlot = coordinator.exercises[0].slots.last!
    coordinator.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 40, reps: 15)

    #expect(coordinator.logSet(slotID: warmupSlot.id, inExercise: coordinator.exercises[0].id))
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
    #expect(spy.requests.isEmpty)
  }

  @Test("With no rest prescription, nothing is invented")
  func noRestByDefault() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(coordinator.logSet(
      slotID: coordinator.exercises[0].slots[0].id,
      inExercise: coordinator.exercises[0].id
    ))
    #expect(spy.requests.isEmpty)
  }

  @Test("Logging the same row twice writes once")
  func doubleLogIsIdempotent() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    let slotID = coordinator.exercises[0].slots[0].id
    let stateID = coordinator.exercises[0].id

    #expect(coordinator.logSet(slotID: slotID, inExercise: stateID))
    #expect(coordinator.logSet(slotID: slotID, inExercise: stateID))
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
  }

  @Test("An unknown slot is reported rather than trapping")
  func unknownSlot() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    #expect(!coordinator.logSet(slotID: UUID(), inExercise: coordinator.exercises[0].id))
    #expect(coordinator.lastError as? SessionCoordinatorError == .unknownSlot)
  }

  // MARK: - Finishing

  @Test("Finishing closes the session once")
  func finishing() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start.addingTimeInterval(0) }
    )

    try coordinator.finish()
    #expect(coordinator.isFinished)
    #expect(try store.openSession() == nil)

    // The second attempt is refused by the same invariant the store enforces.
    #expect(throws: SessionTimelineError.alreadyFinished) {
      try coordinator.finish()
    }
  }
}
