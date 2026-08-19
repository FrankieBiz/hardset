import Foundation
import GRDB
import HardsetCore
import SQLiteData
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
