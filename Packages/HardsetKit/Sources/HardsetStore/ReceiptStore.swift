import Foundation
import HardsetCore
import SQLiteData

public nonisolated struct ReceiptStore: Sendable {
  private let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  /// Load history over the same database, so a receipt can open each movement's chart without
  /// its caller wiring a second store.
  public var progression: ProgressionStore { ProgressionStore(database: database) }

  /// Uses complete prior history with no row cap. The receipt is a deliberate read,
  /// independent of logging and never an extra query during a row's render.
  public func load(_ id: SessionID) async throws -> WorkoutReceipt {
    try Task.checkCancellation()
    return try await database.read { db in
      guard let session = try Session.where({ $0.id.eq(id.rawValue) }).fetchOne(db),
        let end = session.finishedAt else { throw ReceiptError.unfinishedOrMissing }
      // In the order performed. Each movement numbers its own sets from zero, so ordering by
      // ordinal first interleaved two movements into a superset that never happened. Imported
      // sets share one completion time and keep file order through their ordinal.
      let sets = try LoggedSet.where { $0.sessionID.eq(id.rawValue) }
        .order { ($0.completedAt, $0.setOrdinal, $0.id) }.fetchAll(db)
      let exerciseIDs = Set(sets.map(\.exerciseID))
      let exercises = try Exercise.where { $0.id.in(exerciseIDs) }.fetchAll(db)
      let names = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.name) })
      let modalities = Dictionary(uniqueKeysWithValues: exercises.map {
        ($0.id, ExerciseModality(rawValue: $0.modality))
      })
      let machines = try Machine.fetchAll(db)
      let machineIndex = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
      let prior = try LoggedSet.where { $0.exerciseID.in(exerciseIDs) }
        .where { !$0.isWarmup && $0.completedAt < session.startedAt }
        .where { $0.sessionID.neq(id.rawValue) }.fetchAll(db)
      var history = Dictionary(grouping: prior) {
        ProgressionKey(exerciseID: ExerciseID(rawValue: $0.exerciseID), machineID: $0.machineID.map(MachineID.init(rawValue:)))
      }.mapValues { $0.map { PriorSetRecord(weightKg: $0.weightKg, reps: $0.reps, completedAt: $0.completedAt) } }
      // The live logger's first-session rule: a lift with no working set from an earlier session
      // has no baseline, so this session's own ramp makes no claim on it.
      let establishedKeys = Set(history.keys)
      let imported = session.notes.hasPrefix("Imported from ")
      var lines: [WorkoutReceipt.Line] = []
      for set in sets {
        let key = ProgressionKey(exerciseID: ExerciseID(rawValue: set.exerciseID), machineID: set.machineID.map(MachineID.init(rawValue:)))
        let machine = set.machineID.flatMap { machineIndex[$0] }
        // The live logger's rule: a set with no machine is compared against the same movement's
        // other no-machine sets, with the detector's default plate step. Only imports, which never recorded
        // equipment, and a set whose machine row is missing make no claim.
        let unknownMachine = set.machineID != nil && machine == nil
        let records = imported || unknownMachine || !establishedKeys.contains(key) ? [] : PersonalRecordDetector.records(
          for: .init(weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup),
          history: history[key] ?? [], increment: machine?.stackIncrementKg,
          estimatesOneRepMax: (modalities[set.exerciseID] ?? nil)?.estimatesOneRepMax ?? true)
        let machineName = machine.map { [$0.brand, $0.name].filter { !$0.isEmpty }.joined(separator: " ") }
        lines.append(.init(id: SetID(rawValue: set.id), exerciseID: ExerciseID(rawValue: set.exerciseID),
          exerciseName: names[set.exerciseID] ?? "Unknown movement",
          equipment: unknownMachine
            ? .unrecorded
            : WorkoutReceipt.Equipment(machineName: machineName, modality: modalities[set.exerciseID] ?? nil),
          weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup, records: records, isImported: imported))
        if !set.isWarmup {
          history[key, default: []].append(.init(weightKg: set.weightKg, reps: set.reps, completedAt: set.completedAt))
        }
      }
      return WorkoutReceipt(id: id, title: session.title, startedAt: session.startedAt,
        finishedAt: end, lines: lines, notes: session.notes)
    }
  }

  // MARK: - Corrections

  /// Deletes a finished workout with all of its sets and its plan, in one transaction.
  ///
  /// Sets stay immutable: a mistaken workout is removed, never edited. Children are deleted
  /// explicitly before the session rather than left to the schema's cascade, so the write states
  /// everything it removes. History, weekly volume, load history and record baselines all read
  /// the remaining rows, so each reflects the deletion on its next load. A copy already sent to
  /// Apple Health is not this store's to remove.
  ///
  /// - Throws: `ReceiptError.sessionNotFound`, or `.sessionNotFinished` for an open workout,
  ///   which belongs to the live session's own discard path.
  public func deleteSession(_ id: SessionID) async throws {
    try Task.checkCancellation()
    try await database.write { db in
      try Self.requireFinishedSession(id, in: db)
      try LoggedSet.where { $0.sessionID.eq(id.rawValue) }.delete().execute(db)
      try SessionExercise.where { $0.sessionID.eq(id.rawValue) }.delete().execute(db)
      try Session.where { $0.id.eq(id.rawValue) }.delete().execute(db)
      guard db.changesCount == 1 else { throw ReceiptError.sessionNotFound }
    }
  }

  /// Deletes one mis-logged set from a finished workout, in one transaction.
  ///
  /// The workout itself stays, even when this was its last set, so removing a typo never removes
  /// the record that the lifter trained that day.
  ///
  /// - Throws: `ReceiptError.sessionNotFound`, `.sessionNotFinished`, or `.setNotFound` when the
  ///   set does not exist or belongs to a different workout.
  public func deleteSet(_ setID: SetID, inSession sessionID: SessionID) async throws {
    try Task.checkCancellation()
    try await database.write { db in
      try Self.requireFinishedSession(sessionID, in: db)
      try LoggedSet
        .where { $0.id.eq(setID.rawValue) }
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .delete()
        .execute(db)
      guard db.changesCount == 1 else { throw ReceiptError.setNotFound }
    }
  }

  private static func requireFinishedSession(_ id: SessionID, in db: Database) throws {
    let isOpen = try Session.where { $0.id.eq(id.rawValue) }
      .select { $0.finishedAt.is(nil) }.fetchOne(db)
    guard let isOpen else { throw ReceiptError.sessionNotFound }
    guard !isOpen else { throw ReceiptError.sessionNotFinished }
  }
}

public nonisolated enum ReceiptError: Error, Sendable, Hashable {
  /// The receipt was asked for a workout that is still open, or does not exist.
  case unfinishedOrMissing
  /// No workout has this id.
  case sessionNotFound
  /// The workout is still open; corrections to it belong to the live session.
  case sessionNotFinished
  /// No set with this id belongs to this workout.
  case setNotFound
}
