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

  @Test("A failed plan insert leaves no partial workout or exercise rows")
  func failedStartRollsBackPlan() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    // Reject the second plan row after the first has been inserted. This also
    // covers failures occurring during the write, after startup reads succeeded.
    try database.write { db in
      try db.execute(sql: """
        CREATE TEMP TRIGGER fail_second_plan BEFORE INSERT ON sessionExercises
        WHEN NEW.position = 1 BEGIN
          SELECT RAISE(ABORT, 'injected plan failure');
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
    try database.writeWithoutTransaction { db in
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
