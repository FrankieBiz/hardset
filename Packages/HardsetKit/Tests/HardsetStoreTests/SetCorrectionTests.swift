import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A written set can be corrected, removed and put back, and nothing else changes")
struct SetCorrectionTests {
  let start = Date(timeIntervalSince1970: 20_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    return (database, LoggerStore(database: database), exercise)
  }

  @Test("A correction changes weight and reps and nothing else")
  func updateChangesOnlyTheLoad() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let planRow = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, sessionExerciseID: planRow,
      draft: SetEntryDraft(weightKg: 1000, reps: 8), at: start.addingTimeInterval(60)
    )
    let fetched = try store.loggedSet(id)
    let before = try #require(fetched)

    let after = try store.updateSet(id, to: SetEntryDraft(weightKg: 100, reps: 9))

    #expect(after.weightKg == 100)
    #expect(after.reps == 9)
    #expect(after.id == before.id)
    #expect(after.completedAt == before.completedAt)
    #expect(after.setOrdinal == before.setOrdinal)
    #expect(after.sessionExerciseID == planRow)
    #expect(after.isWarmup == before.isWarmup)
    #expect(try store.loggedSet(id) == after)
  }

  @Test(
    "A correction the logger could not have written is refused, and the set is untouched",
    arguments: [
      SetEntryDraft(weightKg: nil, reps: 8),
      SetEntryDraft(weightKg: 100, reps: 0),
      SetEntryDraft(weightKg: -5, reps: 8),
    ]
  )
  func incompleteRefused(draft: SetEntryDraft) throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)
    #expect(throws: LoggerStoreError.incompleteSet) { try store.updateSet(id, to: draft) }
    let fetched = try store.loggedSet(id)
    #expect(fetched?.weightKg == 100)
    #expect(fetched?.reps == 8)
  }

  @Test("Correcting or deleting a set that is not stored says so")
  func missingSet() throws {
    let (_, store, _) = try fixture()
    #expect(throws: LoggerStoreError.setNotFound) {
      try store.updateSet(SetID(), to: SetEntryDraft(weightKg: 100, reps: 8))
    }
    #expect(throws: LoggerStoreError.setNotFound) { try store.deleteSet(SetID()) }
  }

  @Test("Deleting removes the set and returns it as it was")
  func deleteReturnsTheRow() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)

    let removed = try store.deleteSet(id)

    #expect(removed.id == id)
    #expect(removed.weightKg == 100)
    #expect(try store.loggedSet(id) == nil)
    #expect(try store.sets(in: session).isEmpty)
  }

  @Test("Undo puts the set back exactly, under a new id")
  func restoreUnderANewID() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let planRow = try store.addExercise(to: session, exerciseID: exercise, position: 0)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, sessionExerciseID: planRow,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: start)
    let second = try store.logSet(
      sessionID: session, exerciseID: exercise, sessionExerciseID: planRow,
      draft: SetEntryDraft(weightKg: 105, reps: 6), at: start.addingTimeInterval(120))
    let removed = try store.deleteSet(second)

    let restoredID = try store.restoreSet(removed)

    #expect(restoredID != second)
    let fetched = try store.loggedSet(restoredID)
    let restored = try #require(fetched)
    #expect(restored.weightKg == 105)
    #expect(restored.reps == 6)
    #expect(restored.setOrdinal == removed.setOrdinal)
    #expect(restored.completedAt == removed.completedAt)
    #expect(restored.sessionExerciseID == planRow)
    #expect(!restored.isWarmup)
    // History sees it again, so anything judged against it is judged as before.
    #expect(try store.completedSets(for: ProgressionKey(exerciseID: exercise)).count == 2)
  }

  @Test("Undo into a workout that no longer exists is refused")
  func restoreNeedsTheSession() throws {
    let (database, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    let id = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)
    let removed = try store.deleteSet(id)
    try database.write { db in
      try Session.where { $0.id.eq(session.rawValue) }.delete().execute(db)
    }
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.restoreSet(removed) }
  }

  @Test("An empty open workout is discarded with its plan rows")
  func discardEmpty() throws {
    let (database, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    _ = try store.addExercise(to: session, exerciseID: exercise, position: 0)

    try store.discardEmptySession(session)

    #expect(try store.openSession() == nil)
    let planRows = try database.read { db in
      try SessionExercise.where { $0.sessionID.eq(session.rawValue) }.fetchAll(db)
    }
    #expect(planRows.isEmpty)
  }

  /// Review Focus: the check is against storage, so a set the screen never saw still stops it.
  @Test("A workout with any logged set is never discarded, and a warm-up counts")
  func discardRefusesLoggedWork() throws {
    let (_, store, exercise) = try fixture()
    let session = try store.startSession(at: start)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 40, reps: 10),
      isWarmup: true, at: start)

    #expect(throws: LoggerStoreError.sessionNotEmpty) { try store.discardEmptySession(session) }
    #expect(try store.openSession()?.id == session)
    #expect(try store.sets(in: session).count == 1)
  }

  @Test("A finished workout is history and is never discarded")
  func discardRefusesFinished() throws {
    let (database, store, _) = try fixture()
    let session = try store.startSession(at: start)
    try store.finishSession(session, at: start.addingTimeInterval(3_600))

    #expect(throws: LoggerStoreError.sessionNotOpen) { try store.discardEmptySession(session) }
    #expect(try HistoryStore(database: database).recentSessions().count == 1)
  }

  @Test("Discarding a workout that does not exist says so")
  func discardUnknown() throws {
    let (_, store, _) = try fixture()
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.discardEmptySession(SessionID()) }
  }
}
