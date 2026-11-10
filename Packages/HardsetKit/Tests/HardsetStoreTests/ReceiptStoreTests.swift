import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Receipts preserve machine identity and record honesty")
struct ReceiptStoreTests {
  @Test("A PR compares only the same machine, with no history row cap")
  func records() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let exercise = ExerciseID(), gym = UUID(), a = MachineID(), b = MachineID()
    let now = Date(timeIntervalSince1970: 10000)
    let old = SessionID(), current = SessionID()
    try await db.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute(db)
      try Gym.insert { Gym.Draft(id: gym, name: "Gym") }.execute(db)
      try Machine.insert { Machine.Draft(id: a.rawValue, gymID: gym, name: "Sled A", stackIncrementKg: 5) }.execute(db)
      try Machine.insert { Machine.Draft(id: b.rawValue, gymID: gym, name: "Sled B", stackIncrementKg: 5) }.execute(db)
      try Session.insert { Session.Draft(id: old.rawValue, startedAt: now.addingTimeInterval(-5000), finishedAt: now.addingTimeInterval(-1000)) }.execute(db)
      try Session.insert { Session.Draft(id: current.rawValue, startedAt: now, finishedAt: now.addingTimeInterval(600)) }.execute(db)
      for index in 0..<1005 {
        try LoggedSet.insert {
          LoggedSet.Draft(id: UUID(), sessionID: old.rawValue, exerciseID: exercise.rawValue, machineID: a.rawValue,
            setOrdinal: index, weightKg: index == 0 ? 120 : 60, reps: 8, completedAt: now.addingTimeInterval(Double(index - 4000)))
        }.execute(db)
      }
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: old.rawValue, exerciseID: exercise.rawValue, machineID: b.rawValue,
          weightKg: 200, reps: 8, completedAt: now.addingTimeInterval(-1000))
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: current.rawValue, exerciseID: exercise.rawValue, machineID: a.rawValue,
          weightKg: 100, reps: 8, completedAt: now.addingTimeInterval(60))
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: current.rawValue, exerciseID: exercise.rawValue, machineID: a.rawValue,
          setOrdinal: 1, weightKg: 130, reps: 8, completedAt: now.addingTimeInterval(120))
      }.execute(db)
    }
    let receipt = try await ReceiptStore(database: db).load(current)
    #expect(receipt.lines.count == 2)
    #expect(receipt.lines[0].records.allSatisfy { $0.kind != .heaviestLoad })
    #expect(receipt.lines[1].records.contains { $0.kind == .heaviestLoad })
    #expect(receipt.lines.allSatisfy { $0.machineName == "Sled A" })
    #expect(receipt.text(unit: .kilograms).contains("not independently verified"))
  }

  @Test("Imported equipment remains unevaluated in a shareable receipt")
  func imported() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let csv = "Date,Workout Name,Duration,Exercise Name,Weight,Reps\n2026-11-01 10:00:00,Push,3600,Press,100,8\n"
    let transfer = DataTransferStore(database: db)
    _ = try await transfer.importWorkouts(WorkoutCSVImport.preview(csv, strongUnit: .kilograms))
    let id = try #require(try await db.read { try Session.fetchOne($0)?.id })
    let receipt = try await ReceiptStore(database: db).load(SessionID(rawValue: id))
    #expect(receipt.lines.allSatisfy { $0.isImported && $0.machineName == nil && $0.records.isEmpty })
    #expect(receipt.text(unit: .kilograms).contains("Unevaluated Machine"))
  }

  @Test("An unfinished workout cannot be shared as a finished receipt")
  func openWorkout() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let session = try LoggerStore(database: db).startSession(at: .now)
    await #expect(throws: ReceiptError.self) { try await ReceiptStore(database: db).load(session) }
  }

  // MARK: - Order

  /// Each movement numbers its own sets from zero, so ordering a whole session by ordinal
  /// interleaved two movements into a superset that never happened.
  @Test("Sets read in the order they were performed, not interleaved by ordinal")
  func performedOrder() async throws {
    let (db, logger, bench, row) = try Self.fixture()
    let start = Date(timeIntervalSince1970: 20_000)
    let session = try logger.startSession(at: start)
    for (index, exercise) in [bench, bench, bench, row, row, row].enumerated() {
      _ = try logger.logSet(
        sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: 60, reps: 10),
        at: start.addingTimeInterval(Double(index + 1) * 90))
    }
    try logger.finishSession(session, at: start.addingTimeInterval(3600))
    let receipt = try await ReceiptStore(database: db).load(session)
    #expect(receipt.lines.map(\.exerciseName) == ["Bench", "Bench", "Bench", "Row", "Row", "Row"])
    #expect(receipt.lines.map(\.exerciseID) == [bench, bench, bench, row, row, row])
    #expect(receipt.blocks.count == 2)
    #expect(receipt.movements.map(\.exerciseID) == [bench, row])
  }

  /// A receipt opens each movement's load history, so its store must read the same history.
  @Test("A receipt's load-history reader sees the receipt's own sets")
  func loadHistoryFromReceipt() async throws {
    let (db, logger, bench, _) = try Self.fixture()
    let session = try Self.finishedSession(logger, bench, weight: 100, at: Date(timeIntervalSince1970: 20_000))
    let store = ReceiptStore(database: db)
    let movement = try #require(try await store.load(session).movements.first)
    let history = try await store.progression.loadHistory(for: movement.exerciseID)
    #expect(history.series.flatMap(\.points).map(\.heaviestLoadKg) == [100])
    #expect(history.label(for: try #require(history.series.first).key) == "Free weight")
  }

  // MARK: - Equipment and records

  /// A barbell set with no machine is free-weight work, and the live logger celebrates its records.
  /// The receipt for the same workout must say the same thing about the same sets.
  @Test("Free-weight records match the live logger's, and the receipt is evaluated")
  func freeWeightRecords() async throws {
    let (db, logger, bench, _) = try Self.fixture()
    let start = Date(timeIntervalSince1970: 20_000)
    let earlier = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: earlier, exerciseID: bench, draft: SetEntryDraft(weightKg: 100, reps: 5),
      at: start.addingTimeInterval(60))
    try logger.finishSession(earlier, at: start.addingTimeInterval(600))

    let later = try logger.startSession(at: start.addingTimeInterval(86_400))
    let live = try logger.logSet(
      sessionID: later, exerciseID: bench, draft: SetEntryDraft(weightKg: 110, reps: 5),
      recordIncrement: nil, at: start.addingTimeInterval(86_460))
    try logger.finishSession(later, at: start.addingTimeInterval(87_000))
    #expect(live.records.contains { $0.kind == .heaviestLoad })

    let receipt = try await ReceiptStore(database: db).load(later)
    let line = try #require(receipt.lines.first)
    #expect(line.equipment == .freeWeight)
    #expect(line.equipmentLabel == "Free weight")
    #expect(Set(line.records.map(\.kind)) == Set(live.records.map(\.kind)))
    #expect(receipt.certainty == .high)
    #expect(!receipt.text(unit: .kilograms).contains("Unevaluated"))
  }

  /// A leg press with no machine recorded is unknown equipment. Its records are still the logger's
  /// (the same comparison is made live), but the receipt does not vouch for the equipment.
  @Test("A machine movement with no machine recorded is unevaluated, not called free weight")
  func unrecordedMachine() async throws {
    let (db, logger, _, row) = try Self.fixture()
    let start = Date(timeIntervalSince1970: 20_000)
    let session = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: session, exerciseID: row, draft: SetEntryDraft(weightKg: 70, reps: 10),
      at: start.addingTimeInterval(60))
    try logger.finishSession(session, at: start.addingTimeInterval(600))
    let receipt = try await ReceiptStore(database: db).load(session)
    #expect(receipt.lines.first?.equipment == .unrecorded)
    #expect(receipt.lines.first?.equipmentLabel == "No machine recorded")
    #expect(receipt.certainty == .unevaluated)
  }

  // MARK: - Deleting a workout

  @Test("Deleting a workout removes it, its sets and its plan from every read")
  func deleteWorkout() async throws {
    let (db, logger, bench, row) = try Self.fixture()
    let start = Date(timeIntervalSince1970: 20_000)
    let keep = try Self.finishedSession(logger, bench, weight: 100, at: start)
    let mistake = try logger.startSession(at: start.addingTimeInterval(86_400))
    try logger.addExercise(to: mistake, exerciseID: row, position: 0)
    _ = try logger.logSet(
      sessionID: mistake, exerciseID: bench, draft: SetEntryDraft(weightKg: 800, reps: 8),
      at: start.addingTimeInterval(86_460))
    try logger.finishSession(mistake, at: start.addingTimeInterval(87_000))

    try await ReceiptStore(database: db).deleteSession(mistake)

    let counts = try await db.read { db in
      (
        try Session.where { $0.id.eq(mistake.rawValue) }.fetchCount(db),
        try LoggedSet.where { $0.sessionID.eq(mistake.rawValue) }.fetchCount(db),
        try SessionExercise.where { $0.sessionID.eq(mistake.rawValue) }.fetchCount(db),
        try LoggedSet.where { $0.sessionID.eq(keep.rawValue) }.fetchCount(db)
      )
    }
    #expect(counts.0 == 0 && counts.1 == 0 && counts.2 == 0)
    #expect(counts.3 == 1)
    #expect(try HistoryStore(database: db).recentSessions().map(\.id) == [keep])
    let volume = try VolumeStore(database: db).report(from: start, to: start.addingTimeInterval(200_000))
    #expect(volume.hardSets == 1)
    let history = try ProgressionStore(database: db).history(for: bench)
    #expect(history.series.flatMap(\.points).map(\.heaviestLoadKg) == [100])
  }

  @Test("An open workout cannot be deleted from history, and a missing one says so")
  func deleteWorkoutRefusals() async throws {
    let (db, logger, bench, _) = try Self.fixture()
    let open = try logger.startSession(at: Date(timeIntervalSince1970: 20_000))
    _ = try logger.logSet(
      sessionID: open, exerciseID: bench, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: Date(timeIntervalSince1970: 20_060))
    let store = ReceiptStore(database: db)
    await #expect(throws: ReceiptError.sessionNotFinished) { try await store.deleteSession(open) }
    await #expect(throws: ReceiptError.sessionNotFound) { try await store.deleteSession(SessionID()) }
    let remaining = try await db.read { try LoggedSet.where { $0.sessionID.eq(open.rawValue) }.fetchCount($0) }
    #expect(remaining == 1)
  }

  // MARK: - Deleting a set

  /// One typed 800 instead of 80 used to block every future heaviest-weight record on that lift,
  /// because each new set had to beat 800 by 2.5%.
  @Test("Deleting a mis-logged set removes it and restores the record baseline")
  func deleteSetRestoresBaseline() async throws {
    let (db, logger, bench, _) = try Self.fixture()
    let start = Date(timeIntervalSince1970: 20_000)
    let past = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: past, exerciseID: bench, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start.addingTimeInterval(60))
    let typo = try logger.logSet(
      sessionID: past, exerciseID: bench, draft: SetEntryDraft(weightKg: 800, reps: 8),
      at: start.addingTimeInterval(120))
    try logger.finishSession(past, at: start.addingTimeInterval(600))

    let store = ReceiptStore(database: db)
    try await store.deleteSet(typo, inSession: past)

    let receipt = try await store.load(past)
    #expect(receipt.lines.map(\.weightKg) == [100])
    let next = try logger.startSession(at: start.addingTimeInterval(86_400))
    let live = try logger.logSet(
      sessionID: next, exerciseID: bench, draft: SetEntryDraft(weightKg: 105, reps: 8),
      recordIncrement: nil, at: start.addingTimeInterval(86_460))
    #expect(live.records.contains { $0.kind == .heaviestLoad })
  }

  @Test("A set is deleted only from its own finished workout")
  func deleteSetRefusals() async throws {
    let (db, logger, bench, _) = try Self.fixture()
    let start = Date(timeIntervalSince1970: 20_000)
    let finished = try logger.startSession(at: start)
    let set = try logger.logSet(
      sessionID: finished, exerciseID: bench, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start.addingTimeInterval(60))
    try logger.finishSession(finished, at: start.addingTimeInterval(600))
    let other = try Self.finishedSession(logger, bench, weight: 90, at: start.addingTimeInterval(86_400))
    let open = try logger.startSession(at: start.addingTimeInterval(2 * 86_400))
    let openSet = try logger.logSet(
      sessionID: open, exerciseID: bench, draft: SetEntryDraft(weightKg: 100, reps: 8),
      at: start.addingTimeInterval(2 * 86_400 + 60))

    let store = ReceiptStore(database: db)
    await #expect(throws: ReceiptError.setNotFound) { try await store.deleteSet(set, inSession: other) }
    await #expect(throws: ReceiptError.setNotFound) { try await store.deleteSet(SetID(), inSession: finished) }
    await #expect(throws: ReceiptError.sessionNotFinished) { try await store.deleteSet(openSet, inSession: open) }
    await #expect(throws: ReceiptError.sessionNotFound) { try await store.deleteSet(set, inSession: SessionID()) }
    let total = try await db.read { try LoggedSet.fetchCount($0) }
    #expect(total == 3)
  }

  // MARK: - Fixtures

  /// Bench is a barbell movement, Row a machine movement; neither has a machine recorded.
  private static func fixture() throws -> (DatabaseQueue, LoggerStore, ExerciseID, ExerciseID) {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let bench = ExerciseID(), row = ExerciseID()
    try db.write { db in
      try Exercise.insert { Exercise.Draft(id: bench.rawValue, name: "Bench", modality: "barbell") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: row.rawValue, name: "Row", modality: "machine") }.execute(db)
    }
    return (db, LoggerStore(database: db), bench, row)
  }

  private static func finishedSession(
    _ logger: LoggerStore, _ exercise: ExerciseID, weight: Double, at start: Date
  ) throws -> SessionID {
    let session = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, draft: SetEntryDraft(weightKg: weight, reps: 8),
      at: start.addingTimeInterval(60))
    try logger.finishSession(session, at: start.addingTimeInterval(600))
    return session
  }
}
