import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

/// The logger's write path and its single read.
///
/// No `SyncEngine` here and therefore no metadatabase, so these need neither a container
/// identifier nor serialisation — a migrated in-memory queue is the whole fixture.
@Suite("The logger writes only complete sets and reads history once")
struct LoggerStoreTests {
  let start = Date(timeIntervalSince1970: 4_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// Foreign keys are on, so referenced rows have to exist.
  private func seedExercise(_ database: any DatabaseWriter, name: String = "Leg Press") throws
    -> ExerciseID
  {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  private func seedMachine(
    _ database: any DatabaseWriter, gym: GymID, name: String
  ) throws -> MachineID {
    let id = MachineID()
    try database.write { db in
      try Machine.insert {
        Machine.Draft(id: id.rawValue, gymID: gym.rawValue, name: name)
      }
      .execute(db)
    }
    return id
  }

  private func seedGym(_ database: any DatabaseWriter) throws -> GymID {
    let id = GymID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: id.rawValue, name: "Test Gym") }.execute(db)
    }
    return id
  }

  // MARK: - Write path

  @Test("Finished workouts reject set, plan, and equipment mutations",
        arguments: ["set", "plan", "machine"])
  func closedWorkoutRejectsMutations(command: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gym = try seedGym(database)
    let machine = try seedMachine(database, gym: gym, name: "Press")
    let session = try store.startSession(gymID: gym, at: start)
    let row = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    try store.finishSession(session, at: start.addingTimeInterval(600))
    #expect(throws: LoggerStoreError.sessionClosed) {
      switch command {
      case "set":
        _ = try store.logSet(sessionID: session, exerciseID: exercise,
                             draft: SetEntryDraft(weightKg: 100, reps: 8), at: start.addingTimeInterval(700))
      case "plan":
        _ = try store.addExercise(to: session, exerciseID: exercise, position: 1)
      default:
        try store.setSessionExerciseMachine(rowID: row, machineID: machine)
      }
    }
    let saved = try store.sessionExercises(in: session)
    #expect(saved.count == 1)
    #expect(saved[0].machineID == nil)
    #expect(try store.sets(in: session).isEmpty)
  }

  @Test("A logged set must match the supplied plan row's session, exercise, and machine",
        arguments: ["session", "exercise", "machine", "missing"])
  func setRejectsMismatchedPlan(context: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let otherExercise = try seedExercise(database, name: "Curl")
    let gym = try seedGym(database)
    let machine = try seedMachine(database, gym: gym, name: "Press")
    let session = try store.startSession(gymID: gym, at: start)
    let otherSession = try store.startSession(gymID: gym, at: start)
    let row = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    let expected: LoggerStoreError = context == "missing" ? .sessionExerciseNotFound : .sessionExerciseMismatch
    #expect(throws: expected) {
      _ = try store.logSet(
        sessionID: context == "session" ? otherSession : session,
        exerciseID: context == "exercise" ? otherExercise : exercise,
        machineID: context == "machine" ? machine : nil,
        sessionExerciseID: context == "missing" ? UUID() : row,
        draft: SetEntryDraft(weightKg: 100, reps: 8), at: start
      )
    }
    #expect(try store.sets(in: session).isEmpty)
    #expect(try store.sets(in: otherSession).isEmpty)
  }

  @Test("Local commands reject a machine at a different known gym",
        arguments: ["start", "plan", "set", "machine"])
  func rejectsWrongGymMachine(command: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gym = try seedGym(database)
    let otherGym = try seedGym(database)
    let machine = try seedMachine(database, gym: otherGym, name: "Other gym press")
    let session = try store.startSession(gymID: gym, at: start)
    let row = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    #expect(throws: LoggerStoreError.machineGymMismatch) {
      switch command {
      case "start":
        _ = try store.startSession(gymID: gym, title: "Invalid plan", at: start,
                                  plan: [PlannedExercise(exerciseID: exercise, machineID: machine,
                                                         exerciseName: "Press")])
      case "plan":
        _ = try store.addExercise(to: session, exerciseID: exercise, machineID: machine, position: 1)
      case "set":
        _ = try store.logSet(sessionID: session, exerciseID: exercise, machineID: machine,
                             draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
      default:
        try store.setSessionExerciseMachine(rowID: row, machineID: machine)
      }
    }
    let saved = try store.sessionExercises(in: session)
    #expect(saved.count == 1)
    #expect(saved[0].machineID == nil)
    #expect(try store.sets(in: session).isEmpty)
    let sessions = try database.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM sessions") }
    #expect(sessions == 1)
  }

  @Test("A missing plan row cannot report a successful machine change")
  func missingPlanCannotChangeMachine() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    #expect(throws: LoggerStoreError.sessionExerciseNotFound) {
      try store.setSessionExerciseMachine(rowID: UUID(), machineID: nil)
    }
  }

  @Test("Ignored local writes cannot report success",
        arguments: ["start", "plan", "set", "machine", "finish"])
  func ignoredWriteFails(command: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    let row = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    let table = command == "start" || command == "finish" ? "sessions"
      : command == "set" ? "loggedSets" : "sessionExercises"
    let operation = command == "machine" || command == "finish" ? "UPDATE" : "INSERT"
    try database.write { db in
      try db.execute(sql: "CREATE TEMP TRIGGER ignore_command BEFORE \(operation) ON \(table) BEGIN SELECT RAISE(IGNORE); END")
    }
    #expect(throws: LoggerStoreError.writeNotApplied) {
      switch command {
      case "start": _ = try store.startSession(at: start)
      case "plan": _ = try store.addExercise(to: session, exerciseID: exercise, position: 1)
      case "set":
        _ = try store.logSet(sessionID: session, exerciseID: exercise,
                             draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
      case "machine": try store.setSessionExerciseMachine(rowID: row, machineID: nil)
      default: try store.finishSession(session, at: start.addingTimeInterval(600))
      }
    }
    #expect(try store.openSession()?.id == session)
    #expect(try store.sessionExercises(in: session).count == 1)
    #expect(try store.sets(in: session).isEmpty)
  }

  @Test("Missing local references return explicit errors without partial writes",
        arguments: ["session", "exercise", "gym", "machine"])
  func missingReferencesFail(context: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    let expected: LoggerStoreError
    switch context {
    case "session": expected = .sessionNotFound
    case "exercise": expected = .exerciseNotFound
    case "gym": expected = .gymNotFound
    default: expected = .machineNotFound
    }
    #expect(throws: expected) {
      switch context {
      case "session":
        _ = try store.logSet(sessionID: SessionID(), exerciseID: exercise,
                             draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
      case "exercise":
        _ = try store.addExercise(to: session, exerciseID: ExerciseID(), position: 0)
      case "gym": _ = try store.startSession(gymID: GymID(), at: start)
      default:
        _ = try store.logSet(sessionID: session, exerciseID: exercise, machineID: MachineID(),
                             draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
      }
    }
    #expect(try store.sets(in: session).isEmpty)
    #expect(try store.sessionExercises(in: session).isEmpty)
    let sessions = try database.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM sessions") }
    #expect(sessions == 1)
  }

  @Test("A complete draft is written")
  func logsACompleteSet() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)

    _ = try store.logSet(
      sessionID: session,
      exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 100, reps: 8),
      setOrdinal: 0,
      at: start.addingTimeInterval(60)
    )

    let sets = try store.sets(in: session)
    #expect(sets.count == 1)
    #expect(sets[0].weightKg == 100)
    #expect(sets[0].reps == 8)
  }

  /// The defect this whole layer exists to prevent: the reference app accepted an empty
  /// weight field and persisted 0 kg, so a row visibly reading "60" contributed no volume.
  @Test("An incomplete draft is refused rather than written as 0 kg")
  func refusesIncompleteDraft() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)

    #expect(throws: LoggerStoreError.incompleteSet) {
      _ = try store.logSet(
        sessionID: session,
        exerciseID: exercise,
        draft: SetEntryDraft(weightKg: nil, reps: 8),
        setOrdinal: 0,
        at: start
      )
    }
    #expect(try store.sets(in: session).isEmpty)
  }

  @Test("Zero reps is refused")
  func refusesZeroReps() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)

    #expect(throws: LoggerStoreError.incompleteSet) {
      _ = try store.logSet(
        sessionID: session,
        exerciseID: exercise,
        draft: SetEntryDraft(weightKg: 60, reps: 0),
        setOrdinal: 0,
        at: start
      )
    }
  }

  /// Zero *added load* is a real set. The guard is against missing input, not against zero,
  /// which is only distinguishable because the draft holds optionals.
  @Test("Zero added load with real reps is written")
  func writesBodyweightSet() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database, name: "Pull-up")
    let session = try store.startSession(at: start)

    _ = try store.logSet(
      sessionID: session,
      exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 0, reps: 12),
      setOrdinal: 0,
      at: start
    )
    #expect(try store.sets(in: session).count == 1)
  }

  // MARK: - Duration

  @Test("Compact record comparisons agree with complete-history detection across load and rep boundaries")
  func compactRecordsMatchFullHistory() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    let weights: [Double] = [0, 50, 99.99, 99.995, 100, 100.005, 100.01, 100.015, 110, 999, 1000, 1001]
    let historicalReps = [12, 12, 8, 8, 8, 9, 10, 7, 1, 13, 20, 1]
    try database.write { db in
      for (ordinal, weight) in weights.enumerated() {
        try LoggedSet.insert {
          LoggedSet.Draft(sessionID: session.rawValue, exerciseID: exercise.rawValue,
                         setOrdinal: ordinal, weightKg: weight, reps: historicalReps[ordinal],
                         completedAt: self.start)
        }.execute(db)
      }
    }
    let key = ProgressionKey(exerciseID: exercise)
    var observedKinds = Set<PersonalRecordKind>()
    for weight in weights + [1100] {
      for reps in [1, 8, 12, 13, 21] {
        let history = try store.completedSets(for: key, limit: Int.max)
        let candidate = PersonalRecordDetector.Candidate(weightKg: weight, reps: reps)
        let expected = PersonalRecordDetector.records(for: candidate, history: history, increment: 2.5)
        let saved = try store.logSet(
          sessionID: session, exerciseID: exercise,
          draft: SetEntryDraft(weightKg: weight, reps: reps),
          recordIncrement: 2.5, at: start.addingTimeInterval(100)
        )
        #expect(saved.records == expected, "Mismatch at \(weight) kg × \(reps)")
        observedKinds.formUnion(expected.map(\.kind))
      }
    }
    #expect(observedKinds == Set(PersonalRecordKind.allCases))
  }

  @Test("Real record-comparison point queries use the rep index without sorting history")
  func recordPointQueriesUseIndex() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    _ = try store.logSet(sessionID: session, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
    let statements = Mutex<[String]>([])
    try database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") {
          statements.withLock { $0.append(statement.expandedSQL) }
        }
      }
    }
    _ = try store.logSet(sessionID: session, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 110, reps: 8),
                         recordIncrement: nil, at: start.addingTimeInterval(60))
    let pointQueries = statements.withLock { $0.filter { $0.contains("\"reps\") =") } }
    #expect(pointQueries.count == StrengthMath.maximumEstimableReps)
    try database.read { db in
      for query in pointQueries {
        let plan = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query)
          .compactMap { $0["detail"] as String? }
        let usesRepIndex = plan.contains { $0.contains("loggedSets_on_workingReps") }
        let sortsHistory = plan.contains { $0.contains("TEMP B-TREE") }
        #expect(usesRepIndex)
        #expect(!sortsHistory)
      }
    }
  }

  @Test("Finishing stores an instant, and duration is derived from the two instants")
  func finishDerivesDuration() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)
    let end = start.addingTimeInterval(3600)

    try store.finishSession(session, at: end)

    let row = try #require(try database.read { db in
      try Session.where { $0.id.eq(session.rawValue) }.fetchOne(db)
    })
    #expect(row.finishedAt == end)
    let timeline = SessionTimeline(startedAt: row.startedAt, finishedAt: row.finishedAt)
    #expect(timeline.duration == .seconds(3600))
  }

  @Test("Open-workout lookup searches only open sessions through finish and reopen")
  func openSessionUsesPartialIndex() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    // Multiple open rows can arrive through sync. A newer finished row must
    // never mask them, and finishing the newest open row reveals the older one.
    let older = try store.startSession(at: start)
    let newer = try store.startSession(at: start.addingTimeInterval(60))
    let finished = try store.startSession(at: start.addingTimeInterval(120))
    try store.finishSession(finished, at: start.addingTimeInterval(180))
    let statements = Mutex<[String]>([])
    try database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") {
          statements.withLock { $0.append(statement.expandedSQL) }
        }
      }
    }
    #expect(try store.openSession()?.id == newer)
    try store.finishSession(newer, at: start.addingTimeInterval(240))
    #expect(try store.openSession()?.id == older)
    try store.finishSession(older, at: start.addingTimeInterval(300))
    #expect(try store.openSession() == nil)
    let reopened = try store.startSession(at: start.addingTimeInterval(360))
    #expect(try store.openSession()?.id == reopened)
    let queries = statements.withLock { $0.filter {
      $0.contains("FROM \"sessions\"") && $0.contains("ORDER BY")
    } }
    #expect(queries.count == 4)
    try database.read { db in
      for query in queries {
        let plan = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query)
          .compactMap { $0["detail"] as String? }
        #expect(plan.contains { $0.contains("SEARCH sessions USING INDEX sessions_on_openStartedAt") })
        #expect(!plan.contains { $0.contains("SCAN ") || $0.contains("TEMP B-TREE") })
      }
    }
  }

  @Test("An open session has no duration rather than a growing one")
  func openSessionHasNoDuration() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)

    let row = try #require(try store.openSession())
    #expect(row.id == session)
    #expect(row.timeline.duration == nil)
  }

  @Test("A finished session cannot be re-finished, so finishedAt cannot drift")
  func refusesDoubleFinish() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)
    try store.finishSession(session, at: start.addingTimeInterval(600))

    #expect(throws: SessionTimelineError.alreadyFinished) {
      try store.finishSession(session, at: start.addingTimeInterval(9_999))
    }
  }

  @Test("Finishing before the start is refused")
  func refusesFinishBeforeStart() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)

    #expect(throws: SessionTimelineError.finishedBeforeStart) {
      try store.finishSession(session, at: start.addingTimeInterval(-1))
    }
  }

  @Test("Once finished, no session is open")
  func noOpenSessionAfterFinish() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: start)
    try store.finishSession(session, at: start.addingTimeInterval(60))
    #expect(try store.openSession() == nil)
  }

  // MARK: - The hoisted read

  /// Insert a large history in one fixture transaction, without timing hundreds
  /// of unrelated logging writes in the history-selection regression tests.
  private func seedWorkingSets(
    _ database: any DatabaseWriter,
    session: SessionID,
    exercise: ExerciseID,
    weights: [Double],
    machineID: MachineID? = nil,
    at date: Date
  ) throws {
    try database.write { db in
      for (ordinal, weight) in weights.enumerated() {
        try LoggedSet.insert {
          LoggedSet.Draft(
            sessionID: session.rawValue, exerciseID: exercise.rawValue,
            machineID: machineID?.rawValue,
            setOrdinal: ordinal, weightKg: weight, reps: 8,
            completedAt: date.addingTimeInterval(Double(ordinal))
          )
        }
        .execute(db)
      }
    }
  }

  @Test("A frequently trained movement cannot hide another movement's prior session")
  func snapshotDoesNotStarveAnExercise() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let quiet = try seedExercise(database, name: "Curl")
    let busy = try seedExercise(database, name: "Press")
    let old = try store.startSession(at: start)
    try seedWorkingSets(database, session: old, exercise: quiet, weights: [25, 30], at: start)
    let recent = try store.startSession(at: start.addingTimeInterval(1000))
    try seedWorkingSets(database, session: recent, exercise: busy,
                        weights: Array(repeating: 50, count: 501), at: start.addingTimeInterval(1000))
    let key = ProgressionKey(exerciseID: quiet)
    let snapshot = try store.priorPerformanceSnapshot(
      for: [ProgressionKey(exerciseID: busy), key], asOf: start.addingTimeInterval(2000)
    )
    #expect(snapshot.prior(for: key)?.lastSets.map(\.weightKg) == [25, 30])
  }

  @Test("A busy machine cannot hide another machine's exact-key history")
  func snapshotDoesNotStarveAMachine() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let gym = try seedGym(database)
    let quiet = try seedMachine(database, gym: gym, name: "Quiet machine")
    let busy = try seedMachine(database, gym: gym, name: "Busy machine")
    let old = try store.startSession(at: start)
    try seedWorkingSets(database, session: old, exercise: exercise,
                        weights: [80, 85], machineID: quiet, at: start)
    let recent = try store.startSession(at: start.addingTimeInterval(1000))
    try seedWorkingSets(database, session: recent, exercise: exercise,
                        weights: Array(repeating: 50, count: 501), machineID: busy,
                        at: start.addingTimeInterval(1000))
    let key = ProgressionKey(exerciseID: exercise, machineID: quiet)
    let snapshot = try store.priorPerformanceSnapshot(for: [key], asOf: start.addingTimeInterval(2000))
    #expect(snapshot.prior(for: key)?.lastSets.map(\.weightKg) == [80, 85])
    #expect(snapshot.prior(for: key)?.heaviestSet?.weightKg == 85)
  }

  @Test("Snapshot selection keeps the complete latest session beyond the old row cap")
  func snapshotKeepsCompleteSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    let weights = (0..<501).map { Double($0) }
    try seedWorkingSets(database, session: session, exercise: exercise, weights: weights, at: start)
    let key = ProgressionKey(exerciseID: exercise)
    let snapshot = try store.priorPerformanceSnapshot(for: [key], asOf: start.addingTimeInterval(1000))
    #expect(snapshot.prior(for: key)?.lastSets.map(\.weightKg) == weights)
  }

  @Test("The heaviest snapshot set comes from all history rather than the latest row window")
  func snapshotKeepsOlderBest() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let old = try store.startSession(at: start)
    try seedWorkingSets(database, session: old, exercise: exercise, weights: [150], at: start)
    let recent = try store.startSession(at: start.addingTimeInterval(1000))
    try seedWorkingSets(database, session: recent, exercise: exercise,
                        weights: Array(repeating: 50, count: 501), at: start.addingTimeInterval(1000))
    let key = ProgressionKey(exerciseID: exercise)
    let snapshot = try store.priorPerformanceSnapshot(for: [key], asOf: start.addingTimeInterval(2000))
    #expect(snapshot.prior(for: key)?.heaviestSet?.weightKg == 150)
  }

  @Test("An excluded live session cannot consume the prior-history row budget")
  func excludedSessionDoesNotHideHistory() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let old = try store.startSession(at: start)
    try seedWorkingSets(database, session: old, exercise: exercise, weights: [90, 95], at: start)
    let live = try store.startSession(at: start.addingTimeInterval(1000))
    try seedWorkingSets(database, session: live, exercise: exercise,
                        weights: Array(repeating: 50, count: 501), at: start.addingTimeInterval(1000))
    let key = ProgressionKey(exerciseID: exercise)
    let snapshot = try store.priorPerformanceSnapshot(
      for: [key], excluding: live, asOf: start.addingTimeInterval(2000)
    )
    #expect(snapshot.prior(for: key)?.lastSets.map(\.weightKg) == [90, 95])
    #expect(snapshot.prior(for: key)?.heaviestSet?.weightKg == 95)
  }

  @Test("The real snapshot benchmark query uses its index without sorting history")
  func snapshotBenchmarkUsesIndex() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    try seedWorkingSets(database, session: session, exercise: exercise, weights: [100, 50], at: start)
    let statements = Mutex<[String]>([])
    try database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") {
          // Expanded SQL stays inside this fixture test to replay its actual
          // bound query through EXPLAIN; it is never logged by production code.
          statements.withLock { $0.append(statement.expandedSQL) }
        }
      }
    }
    let snapshot = try store.priorPerformanceSnapshot(
      for: [ProgressionKey(exerciseID: exercise)], asOf: start
    )
    #expect(snapshot.count == 1)
    let benchmarkSQL = try #require(statements.withLock { statements in
      statements.first { sql in
        guard let order = sql.range(of: "ORDER BY") else { return false }
        return sql[order.upperBound...].contains("weightKg")
      }
    })
    let plan = try database.read { db in
      try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + benchmarkSQL)
        .compactMap { $0["detail"] as String? }
    }
    let usesBenchmarkIndex = plan.contains { $0.contains("loggedSets_on_workingBenchmark") }
    let sortsHistory = plan.contains { $0.contains("TEMP B-TREE") }
    #expect(usesBenchmarkIndex)
    #expect(!sortsHistory)
  }

  @Test("Prefill comes from the most recent session's sets, in performed order")
  func snapshotPrefillsFromLastSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    // An older session, then a newer one. Only the newer should drive prefill.
    let old = try store.startSession(at: start)
    for (i, w) in [90.0, 90.0].enumerated() {
      _ = try store.logSet(
        sessionID: old, exerciseID: exercise,
        draft: SetEntryDraft(weightKg: w, reps: 10),
        setOrdinal: i, at: start.addingTimeInterval(Double(i) * 60)
      )
    }
    try store.finishSession(old, at: start.addingTimeInterval(3600))

    let recentStart = start.addingTimeInterval(7 * 86_400)
    let recent = try store.startSession(at: recentStart)
    for (i, w) in [100.0, 105.0].enumerated() {
      _ = try store.logSet(
        sessionID: recent, exerciseID: exercise,
        draft: SetEntryDraft(weightKg: w, reps: 8),
        setOrdinal: i, at: recentStart.addingTimeInterval(Double(i) * 60)
      )
    }
    try store.finishSession(recent, at: recentStart.addingTimeInterval(3600))

    let key = ProgressionKey(exerciseID: exercise)
    let snapshot = try store.priorPerformanceSnapshot(for: [key], asOf: recentStart)
    let prior = try #require(snapshot.prior(for: key))

    #expect(prior.lastSets.map(\.weightKg) == [100, 105])
    #expect(prior.suggestion(forSetIndex: 0)?.weightKg == 100)
    #expect(prior.suggestion(forSetIndex: 1)?.weightKg == 105)
    // Past the end of the recorded sets, the last set is the honest fallback.
    #expect(prior.suggestion(forSetIndex: 5)?.weightKg == 105)
    #expect(prior.heaviestSet?.weightKg == 105)
  }

  /// A warm-up load must never pre-fill a working set.
  @Test("Warm-ups are excluded from history")
  func snapshotExcludesWarmups() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)

    _ = try store.logSet(
      sessionID: session, exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 40, reps: 15),
      setOrdinal: 0, isWarmup: true, at: start
    )
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 120, reps: 5),
      setOrdinal: 1, at: start.addingTimeInterval(120)
    )
    try store.finishSession(session, at: start.addingTimeInterval(1800))

    let key = ProgressionKey(exerciseID: exercise)
    let snapshot = try store.priorPerformanceSnapshot(for: [key], asOf: start)
    let prior = try #require(snapshot.prior(for: key))
    #expect(prior.lastSets.map(\.weightKg) == [120])
  }

  /// Without this, a recovered session would suggest values from its own sets.
  @Test("The session being logged is excluded from its own history")
  func snapshotExcludesCurrentSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)

    _ = try store.logSet(
      sessionID: session, exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 80, reps: 8),
      setOrdinal: 0, at: start
    )

    let key = ProgressionKey(exerciseID: exercise)
    let snapshot = try store.priorPerformanceSnapshot(
      for: [key], excluding: session, asOf: start
    )
    #expect(snapshot.prior(for: key) == nil)
  }

  /// Machine-level progression is the differentiator: the same exercise on different
  /// equipment is a different load history and must not be averaged together.
  @Test("The same exercise on two machines keeps two histories")
  func snapshotSeparatesMachines() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gym = try seedGym(database)
    let exercise = try seedExercise(database)
    let hammer = try seedMachine(database, gym: gym, name: "Hammer Strength")
    let cybex = try seedMachine(database, gym: gym, name: "Cybex")

    let session = try store.startSession(gymID: gym, at: start)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, machineID: hammer,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: start
    )
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, machineID: cybex,
      draft: SetEntryDraft(weightKg: 70, reps: 8), setOrdinal: 1,
      at: start.addingTimeInterval(300)
    )
    try store.finishSession(session, at: start.addingTimeInterval(3600))

    let hammerKey = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let cybexKey = ProgressionKey(exerciseID: exercise, machineID: cybex)
    let snapshot = try store.priorPerformanceSnapshot(
      for: [hammerKey, cybexKey], asOf: start
    )

    #expect(snapshot.prior(for: hammerKey)?.lastSets.first?.weightKg == 100)
    #expect(snapshot.prior(for: cybexKey)?.lastSets.first?.weightKg == 70)
    #expect(snapshot.count == 2)
  }

  @Test("Asking for nothing returns an empty snapshot")
  func emptyKeysReturnEmptySnapshot() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let snapshot = try store.priorPerformanceSnapshot(for: [], asOf: start)
    #expect(snapshot.count == 0)
  }
}
