import Foundation
import HardsetCore
import SQLiteData

/// Reads every trained movement into the Progress tab's board.
///
/// One read of the working sets, grouped by movement and machine, and one trend per group. The
/// board does this for every movement at once, so each trend replays only the sessions that decide
/// a stall instead of the whole history (see `ProgressTrendAnalyzer.trend`). The work happens
/// inside the read, on the database's own queue, so opening the tab never holds up the main actor.
public nonisolated struct ProgressBoardStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func loadBoard() async throws -> ProgressBoard {
    try Task.checkCancellation()
    let board = try await database.read { db in
      try Self.readBoard(in: db)
    }
    try Task.checkCancellation()
    return board
  }

  private static func readBoard(in db: Database) throws -> ProgressBoard {
    // Archived movements are retired. Imported equipment stays an explicitly unknown series.
    let exercises = try Exercise.where { !$0.isArchived }.fetchAll(db)
    guard !exercises.isEmpty else { return .empty }
    let byExercise = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })

    let sets: [(UUID, UUID?, UUID, Double, Int, Date)] = try LoggedSet
      .where { !$0.isWarmup }
      .select { ($0.exerciseID, $0.machineID, $0.sessionID, $0.weightKg, $0.reps, $0.completedAt) }
      .fetchAll(db)
    let sessionIDs = Array(Set(sets.map { $0.2 }))
    let imported = Set(try Session.where { $0.id.in(sessionIDs) && $0.notes.like("Imported from %") }
      .select(\.id).fetchAll(db))
    var grouped: [ProgressionKey: [ProgressionSample]] = [:]
    for (exerciseID, machineID, sessionID, weightKg, reps, completedAt) in sets
    where byExercise[exerciseID] != nil {
      let isImported = imported.contains(sessionID)
        || byExercise[exerciseID]?.notes.hasPrefix(CatalogSeeder.importedNotesPrefix) == true
      let key = ProgressionKey(
        exerciseID: ExerciseID(rawValue: exerciseID), machineID: machineID.map(MachineID.init(rawValue:)),
        isImported: isImported)
      grouped[key, default: []].append(
        ProgressionSample(
          sessionID: SessionID(rawValue: sessionID), machineID: key.machineID, weightKg: weightKg,
          reps: reps, completedAt: completedAt, isImported: isImported))
    }
    guard !grouped.isEmpty else { return .empty }

    let machineIDs = Array(Set(grouped.keys.compactMap { $0.machineID?.rawValue }))
    let machines =
      machineIDs.isEmpty
      ? [:]
      : Dictionary(
        uniqueKeysWithValues: try Machine.where { $0.id.in(machineIDs) }.fetchAll(db)
          .map { ($0.id, $0) })

    var entries: [ProgressBoard.Entry] = []
    for (key, samples) in grouped {
      guard let exercise = byExercise[key.exerciseID.rawValue] else { continue }
      let machine = key.machineID.flatMap { machines[$0.rawValue] }
      // Unknown modality cannot establish that the entered load is the whole load moved.
      let modality = ExerciseModality(rawValue: exercise.modality)
      let estimates = modality?.estimatesOneRepMax ?? false
      guard
        let trend = ProgressTrendAnalyzer.trend(
          key: key, samples: samples, incrementKg: machine?.stackIncrementKg,
          estimatesOneRepMax: estimates, assumesAddedLoad: modality == nil)
      else { continue }
      let machineLabel: String?
      if key.isImported { machineLabel = ProgressCopy.importedHistory }
      else if let machine { machineLabel = MachineRecord(row: machine).displayName }
      else if key.machineID == nil && (modality == .machine || modality == .cable) {
        machineLabel = ProgressCopy.noMachineRecorded
      } else { machineLabel = nil }
      entries.append(
        ProgressBoard.Entry(
          row: ProgressBoard.Row(
            trend: trend, exerciseName: exercise.name,
            machineName: machineLabel),
          bodyPart: MuscleFilterCategory.category(for: MuscleKey(stored: exercise.primaryMuscle))
        ))
    }
    return ProgressBoard.make(entries)
  }
}
