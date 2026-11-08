import Foundation
import HardsetCore
import SQLiteData

public nonisolated struct ReceiptStore: Sendable {
  private let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  /// Uses complete prior history with no row cap. The receipt is a deliberate read,
  /// independent of logging and never an extra query during a row's render.
  public func load(_ id: SessionID) async throws -> WorkoutReceipt {
    try Task.checkCancellation()
    return try await database.read { db in
      guard let session = try Session.where({ $0.id.eq(id.rawValue) }).fetchOne(db),
        let end = session.finishedAt else { throw ReceiptError.unfinishedOrMissing }
      let sets = try LoggedSet.where { $0.sessionID.eq(id.rawValue) }
        .order { ($0.setOrdinal, $0.completedAt, $0.id) }.fetchAll(db)
      let exerciseIDs = Set(sets.map(\.exerciseID))
      let exercises = try Exercise.where { $0.id.in(exerciseIDs) }.fetchAll(db)
      let names = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.name) })
      let machines = try Machine.fetchAll(db)
      let machineIndex = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
      let prior = try LoggedSet.where { $0.exerciseID.in(exerciseIDs) }
        .where { !$0.isWarmup && $0.completedAt < session.startedAt }
        .where { $0.sessionID.neq(id.rawValue) }.fetchAll(db)
      var history = Dictionary(grouping: prior) {
        ProgressionKey(exerciseID: ExerciseID(rawValue: $0.exerciseID), machineID: $0.machineID.map(MachineID.init(rawValue:)))
      }.mapValues { $0.map { PriorSetRecord(weightKg: $0.weightKg, reps: $0.reps, completedAt: $0.completedAt) } }
      let imported = session.notes.hasPrefix("Imported from ")
      var lines: [WorkoutReceipt.Line] = []
      for set in sets {
        let key = ProgressionKey(exerciseID: ExerciseID(rawValue: set.exerciseID), machineID: set.machineID.map(MachineID.init(rawValue:)))
        let machine = set.machineID.flatMap { machineIndex[$0] }
        let records = imported || machine == nil ? [] : PersonalRecordDetector.records(
          for: .init(weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup),
          history: history[key] ?? [], increment: machine?.stackIncrementKg)
        lines.append(.init(id: SetID(rawValue: set.id), exerciseName: names[set.exerciseID] ?? "Unknown movement",
          machineName: machine.map { [$0.brand, $0.name].filter { !$0.isEmpty }.joined(separator: " ") },
          weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup, records: records, isImported: imported))
        if !set.isWarmup {
          history[key, default: []].append(.init(weightKg: set.weightKg, reps: set.reps, completedAt: set.completedAt))
        }
      }
      return WorkoutReceipt(id: id, title: session.title, startedAt: session.startedAt,
        finishedAt: end, lines: lines, notes: session.notes)
    }
  }
}

public nonisolated enum ReceiptError: Error, Sendable { case unfinishedOrMissing }
