import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Corrections are written first, shown second, and never celebrated")
@MainActor
struct SetCorrectionCoordinatorTests {
  let start = Date(timeIntervalSince1970: 24_000_000)

  /// A clock the test can move, for the undo window.
  private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// One exercise with a week-old 100 × 8, so there is something to beat.
  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let store = LoggerStore(database: database)
    let past = start.addingTimeInterval(-7 * 86_400)
    let session = try store.startSession(at: past)
    _ = try store.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: past)
    try store.finishSession(session, at: past.addingTimeInterval(3_600))
    return (database, store, exercise)
  }

  private func session(
    _ store: LoggerStore, _ exercise: ExerciseID, clock: Clock
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)],
      now: { clock.now }
    )
  }

  @discardableResult
  private func log(_ c: SessionCoordinator, row: Int, _ weight: Double, _ reps: Int) -> Bool {
    c.exercises[0].slots[row].draft = SetEntryDraft(weightKg: weight, reps: reps)
    return c.logSet(slotID: c.exercises[0].slots[row].id, inExercise: c.exercises[0].id)
  }

  private func edit(_ c: SessionCoordinator, row: Int, _ weight: Double?, _ reps: Int) -> Bool {
    c.editSet(
      slotID: c.exercises[0].slots[row].id, inExercise: c.exercises[0].id,
      to: SetEntryDraft(weightKg: weight, reps: reps))
  }

  // MARK: Edit

  @Test("An edit is written, then shown")
  func editWritesFirst() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)

    #expect(edit(c, row: 0, 102.5, 8))

    #expect(c.exercises[0].slots[0].draft.weightKg == 102.5)
    #expect(c.exercises[0].slots[0].isLogged)
    #expect(try store.sets(in: c.sessionID).first?.weightKg == 102.5)
    #expect(c.lastError == nil)
  }

  @Test("A refused edit changes nothing, on screen or on disk, and says why")
  func refusedEditChangesNothing() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)

    #expect(!edit(c, row: 0, nil, 8))

    #expect((c.lastError as? LoggerStoreError) == .incompleteSet)
    #expect(c.feedback?.event == .error)
    #expect(c.exercises[0].slots[0].draft.weightKg == 100)
    #expect(try store.sets(in: c.sessionID).first?.weightKg == 100)
  }

  @Test("An unlogged row is not edited through the store; it is typed into")
  func unloggedRowIsNotEdited() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    #expect(!edit(c, row: 1, 100, 8))
    #expect((c.lastError as? SessionCoordinatorError) == .slotNotLogged)
  }

  /// Review Focus: an edit is not a moment, though the summary may list what it now supports.
  @Test("Editing a set past the record announces nothing; the summary recomputes")
  func editNeverAnnounces() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    let beforeEdit = c.feedback

    #expect(edit(c, row: 0, 120, 8))

    #expect(c.recordsBySlot.isEmpty)
    #expect(c.lastRecords.isEmpty)
    #expect(c.feedback == beforeEdit)
    let setID = try #require(c.exercises[0].slots[0].loggedSetID)
    #expect(try store.recordsBySet(in: c.sessionID)[setID]?.isEmpty == false)
  }

  /// Review Focus: the typo that earned a trophy loses it when corrected.
  @Test("Correcting a typo'd record takes its trophy away")
  func typoRecordRetracted() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 1_000, 8)
    let row = c.exercises[0].slots[0].id
    #expect(c.recordsBySlot[row] != nil)

    #expect(edit(c, row: 0, 100, 8))

    #expect(c.recordsBySlot[row] == nil)
    #expect(try store.recordsBySet(in: c.sessionID).isEmpty)
  }

  @Test("A trophy the corrected set still earns stays")
  func earnedTrophySurvivesEdit() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 110, 8)
    let row = c.exercises[0].slots[0].id

    #expect(edit(c, row: 0, 110, 9))

    #expect(c.recordsBySlot[row]?.contains { $0.kind == .heaviestLoad } == true)
    #expect(c.recordsBySlot[row]?.first { $0.kind == .heaviestLoad }?.reps == 9)
  }

  // MARK: Delete and undo

  @Test("Delete is written first; Undo inside the window puts the row back where it was")
  func deleteThenUndo() throws {
    let (_, store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try session(store, exercise, clock: clock)
    log(c, row: 0, 100, 8)
    log(c, row: 1, 110, 8)
    let deleted = c.exercises[0].slots[1]
    #expect(c.recordsBySlot[deleted.id] != nil)

    #expect(c.deleteSet(slotID: deleted.id, inExercise: c.exercises[0].id))

    #expect(c.exercises[0].slots.count == 2)
    #expect(!c.exercises[0].slots.contains { $0.id == deleted.id })
    #expect(try store.sets(in: c.sessionID).count == 1)
    #expect(c.recordsBySlot[deleted.id] == nil)
    #expect(c.undoableDeletion?.slot.id == deleted.id)

    clock.now = start.addingTimeInterval(4)
    #expect(c.undoDelete())

    #expect(c.exercises[0].slots.count == 3)
    let restored = c.exercises[0].slots[1]
    #expect(restored.id == deleted.id)
    #expect(restored.isLogged)
    #expect(restored.loggedSetID != deleted.loggedSetID)
    #expect(try store.sets(in: c.sessionID).count == 2)
    #expect(c.recordsBySlot[deleted.id] != nil)
    #expect(c.undoableDeletion == nil)
  }

  /// Review Focus: a stale Undo button must not resurrect a set.
  @Test("Undo at or after five seconds does nothing, and the set stays deleted")
  func undoExpires() throws {
    let (_, store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try session(store, exercise, clock: clock)
    log(c, row: 0, 100, 8)
    #expect(c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))

    clock.now = start.addingTimeInterval(5)

    #expect(!c.undoDelete())
    #expect(c.undoableDeletion == nil)
    #expect(try store.sets(in: c.sessionID).isEmpty)
  }

  @Test("Once the toast has expired, Undo does nothing")
  func expiredUndoIsGone() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id)

    c.expireUndo()

    #expect(!c.undoDelete())
    #expect(try store.sets(in: c.sessionID).isEmpty)
  }

  @Test("Finishing ends the chance to undo")
  func finishEndsUndo() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    log(c, row: 1, 100, 8)
    c.deleteSet(slotID: c.exercises[0].slots[1].id, inExercise: c.exercises[0].id)

    try c.finish()

    #expect(c.undoableDeletion == nil)
    #expect(!c.undoDelete())
    #expect(try store.sets(in: c.sessionID).count == 1)
  }

  @Test("A delete the store refuses leaves the row on screen")
  func failedDeleteKeepsTheRow() throws {
    let (database, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    let setID = try #require(c.exercises[0].slots[0].loggedSetID)
    try database.write { db in
      try LoggedSet.where { $0.id.eq(setID.rawValue) }.delete().execute(db)
    }

    #expect(!c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))

    #expect(c.exercises[0].slots.count == 3)
    #expect((c.lastError as? LoggerStoreError) == .setNotFound)
    #expect(c.undoableDeletion == nil)
  }

  // MARK: Finish and discard

  @Test("Finishing with prefilled rows never logged asks, with the count")
  func finishDecisionCountsUnlogged() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    // Three rows, all prefilled at 100 × 8 from last week.
    log(c, row: 0, 100, 8)
    #expect(c.finishDecision == .confirmUnlogged(count: 2))
  }

  @Test("A workout with nothing logged is discarded, plan rows and all")
  func discardEmpty() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    #expect(c.finishDecision == .discardEmpty)

    #expect(c.discard())

    #expect(c.isDiscarded)
    #expect(try store.openSession() == nil)
  }

  @Test("A workout with a logged set is never discarded")
  func discardRefusedWithLoggedSet() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)

    #expect(!c.discard())

    #expect(!c.isDiscarded)
    #expect((c.lastError as? LoggerStoreError) == .sessionNotEmpty)
    #expect(try store.openSession()?.id == c.sessionID)
  }

  /// Review Focus: memory says empty; the database knows better, and wins.
  @Test("Discard is refused when the database holds a set the screen never saw")
  func discardRefusedWhenDatabaseDisagrees() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    _ = try store.logSet(
      sessionID: c.sessionID, exerciseID: exercise, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start)
    #expect(c.loggedSetCount == 0)

    #expect(!c.discard())

    #expect((c.lastError as? LoggerStoreError) == .sessionNotEmpty)
    #expect(try store.sets(in: c.sessionID).count == 1)
    #expect(try store.openSession()?.id == c.sessionID)
  }

  // MARK: Binding notes: the Undo's edges, trophies, and refusals

  /// Logging into the movement takes the deleted set's place in its order, so putting the deleted
  /// set back afterwards would issue the same ordinal twice.
  @Test("Logging a set for the same movement ends the Undo, so no ordinal is issued twice")
  func newSetEndsUndo() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    log(c, row: 1, 100, 8)
    #expect(c.deleteSet(slotID: c.exercises[0].slots[1].id, inExercise: c.exercises[0].id))

    // Row 1 is now what was row 2.
    #expect(log(c, row: 1, 100, 8))

    #expect(c.undoableDeletion == nil)
    #expect(!c.undoDelete())
    #expect(try store.sets(in: c.sessionID).map(\.setOrdinal) == [0, 1])
  }

  /// Ordinals are counted per movement in the session, not per block, so the second block of the
  /// same movement collides just as the first would.
  @Test("Logging into another block of the same movement also ends the Undo")
  func otherBlockEndsUndo() throws {
    let (_, store, exercise) = try fixture()
    let c = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 1),
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 1),
      ],
      now: { self.start }
    )
    c.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(c.logSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))
    #expect(c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))

    c.exercises[1].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(c.logSet(slotID: c.exercises[1].slots[0].id, inExercise: c.exercises[1].id))

    #expect(c.undoableDeletion == nil)
    #expect(!c.undoDelete())
    #expect(try store.sets(in: c.sessionID).map(\.setOrdinal) == [0])
  }

  @Test("Logging a different movement leaves the Undo open")
  func otherMovementKeepsUndo() throws {
    let (database, store, exercise) = try fixture()
    let other = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: other.rawValue, name: "Chest Press") }.execute(db)
    }
    let clock = Clock(start)
    let c = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 1),
        PlannedExercise(exerciseID: other, exerciseName: "Chest Press", plannedSets: 1),
      ],
      now: { clock.now }
    )
    c.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(c.logSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))
    let deleted = c.exercises[0].slots[0].id
    #expect(c.deleteSet(slotID: deleted, inExercise: c.exercises[0].id))

    c.exercises[1].slots[0].draft = SetEntryDraft(weightKg: 50, reps: 10)
    #expect(c.logSet(slotID: c.exercises[1].slots[0].id, inExercise: c.exercises[1].id))

    #expect(c.undoableDeletion?.slot.id == deleted)
    #expect(c.undoDelete())
    #expect(c.exercises[0].slots.first?.id == deleted)
    #expect(try store.sets(in: c.sessionID).count == 2)
  }

  /// A discarded workout has no session to put a set back into, so an Undo left over would fail
  /// forever while its copy said "tap to try again".
  @Test("Discard ends a pending Undo and every trophy")
  func discardEndsUndoAndTrophies() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 110, 8)
    #expect(!c.recordsBySlot.isEmpty)
    #expect(c.deleteSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id))
    #expect(c.undoableDeletion != nil)

    #expect(c.discard())

    #expect(c.undoableDeletion == nil)
    #expect(c.recordsBySlot.isEmpty)
    #expect(c.lastRecords.isEmpty)
    #expect(!c.undoDelete())
    #expect(c.lastError == nil)
    #expect(try store.openSession() == nil)
  }

  @Test("An Undo the store refuses keeps the deletion, says why, and can be retried in the window")
  func failedUndoCanBeRetried() throws {
    let (database, store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try session(store, exercise, clock: clock)
    log(c, row: 0, 100, 8)
    let deleted = c.exercises[0].slots[0]
    #expect(c.deleteSet(slotID: deleted.id, inExercise: c.exercises[0].id))
    try database.write { db in
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER "refuseInsert" BEFORE INSERT ON "loggedSets"
          BEGIN SELECT RAISE(ABORT, 'refused'); END
          """)
    }
    let pulses = c.feedback?.sequence ?? 0

    clock.now = start.addingTimeInterval(1)
    #expect(!c.undoDelete())

    #expect(c.lastError != nil)
    #expect(c.feedback?.event == .error)
    #expect(c.feedback?.sequence == pulses + 1)
    #expect(c.undoableDeletion?.slot.id == deleted.id)
    #expect(c.exercises[0].slots.count == 2)
    #expect(try store.sets(in: c.sessionID).isEmpty)

    try database.write { db in try db.execute(sql: #"DROP TRIGGER "refuseInsert""#) }
    clock.now = start.addingTimeInterval(2)
    #expect(c.undoDelete())

    #expect(c.exercises[0].slots[0].id == deleted.id)
    #expect(c.lastError == nil)
    #expect(try store.sets(in: c.sessionID).count == 1)
  }

  /// The edit re-judges every row from the database: an earlier set raised past a later record
  /// takes that record away, and earns nothing itself.
  @Test("An edit that raises the bar takes a later row's trophy and adds none")
  func editRejudgesOtherRows() throws {
    let (_, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 100, 8)
    log(c, row: 1, 110, 8)
    #expect(c.recordsBySlot[c.exercises[0].slots[1].id] != nil)
    let beforeEdit = c.feedback

    #expect(edit(c, row: 0, 120, 8))

    #expect(c.recordsBySlot.isEmpty)
    #expect(c.feedback == beforeEdit)
    let edited = try #require(c.exercises[0].slots[0].loggedSetID)
    #expect(try store.recordsBySet(in: c.sessionID)[edited]?.isEmpty == false)
  }

  /// A row edited while another was deleted can take away what the deleted set had beaten.
  @Test("Undo brings a trophy back only while the database still supports it")
  func undoneTrophyRejudged() throws {
    let (_, store, exercise) = try fixture()
    let clock = Clock(start)
    let c = try session(store, exercise, clock: clock)
    log(c, row: 0, 100, 8)
    log(c, row: 1, 110, 8)
    let deleted = c.exercises[0].slots[1].id
    #expect(c.deleteSet(slotID: deleted, inExercise: c.exercises[0].id))
    #expect(edit(c, row: 0, 120, 8))

    #expect(c.undoDelete())

    #expect(c.exercises[0].slots[1].id == deleted)
    #expect(c.recordsBySlot.isEmpty)
  }

  @Test("A refused edit, delete or discard plays one error pulse and leaves memory as it was")
  func refusalsPulseAndChangeNothing() throws {
    let (database, store, exercise) = try fixture()
    let c = try session(store, exercise, clock: Clock(start))
    log(c, row: 0, 110, 8)
    let row = c.exercises[0].slots[0]
    let setID = try #require(row.loggedSetID)
    let trophies = c.recordsBySlot
    #expect(!trophies.isEmpty)
    try database.write { db in
      try LoggedSet.where { $0.id.eq(setID.rawValue) }.delete().execute(db)
    }
    let pulses = c.feedback?.sequence ?? 0

    #expect(!edit(c, row: 0, 120, 8))
    #expect((c.lastError as? LoggerStoreError) == .setNotFound)
    #expect(c.feedback?.event == .error)
    #expect(c.feedback?.sequence == pulses + 1)

    #expect(!c.deleteSet(slotID: row.id, inExercise: c.exercises[0].id))
    #expect(c.feedback?.event == .error)
    #expect(c.feedback?.sequence == pulses + 2)

    // Memory still shows a logged row, so discard is refused before the store is asked.
    #expect(!c.discard())
    #expect((c.lastError as? LoggerStoreError) == .sessionNotEmpty)
    #expect(c.feedback?.event == .error)
    #expect(c.feedback?.sequence == pulses + 3)

    #expect(c.exercises[0].slots[0] == row)
    #expect(c.recordsBySlot == trophies)
    #expect(c.undoableDeletion == nil)
    #expect(!c.isDiscarded)
  }
}
