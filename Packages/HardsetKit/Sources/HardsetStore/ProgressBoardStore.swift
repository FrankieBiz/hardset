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

    let grouped = try groupedSamples(of: byExercise, isWarmup: false, exerciseID: nil, in: db)
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

  /// The working sets (or warm-ups) of the given movements, grouped into the series the board draws:
  /// one per movement, machine and imported-or-not. The board and the account of a row's change both
  /// read their sets here, so a change and its explanation start from the same sets.
  private static func groupedSamples(
    of byExercise: [UUID: Exercise], isWarmup: Bool, exerciseID: UUID?, in db: Database
  ) throws -> [ProgressionKey: [ProgressionSample]] {
    var query = LoggedSet.where { $0.isWarmup.eq(isWarmup) }
    if let exerciseID { query = query.where { $0.exerciseID.eq(exerciseID) } }
    let sets: [(UUID, UUID?, UUID, Double, Int, Date)] =
      try query
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
    return grouped
  }

  // MARK: - The working behind a row's change

  /// The account behind one row's six-week change, for its "Worked from" control.
  ///
  /// Read when it is asked for, from the same sets and through the same functions the row's figure
  /// came from (`groupedSamples`, then `ProgressTrendAnalyzer.comparison`), so the sheet cannot say
  /// what the row did not do. `nil` when the row has no change to explain.
  public func loadChangeWorking(
    for key: ProgressionKey, format: WorkedFromFormat
  ) async throws -> WorkedFromAccount? {
    try Task.checkCancellation()
    let account = try await database.read { db in
      try Self.readChangeWorking(for: key, format: format, in: db)
    }
    try Task.checkCancellation()
    return account
  }

  private static func readChangeWorking(
    for key: ProgressionKey, format: WorkedFromFormat, in db: Database
  ) throws -> WorkedFromAccount? {
    let id = key.exerciseID.rawValue
    guard let exercise = try Exercise.where({ $0.id.eq(id) && !$0.isArchived }).fetchOne(db) else {
      return nil
    }
    let byExercise = [id: exercise]
    // Every series of the movement, so the sets on other equipment in the same sessions are counted
    // as left out. `ChangeWorking` picks the row's own series by key.
    let samples = try groupedSamples(of: byExercise, isWarmup: false, exerciseID: id, in: db)
      .values.flatMap { $0 }
    let warmups = try groupedSamples(of: byExercise, isWarmup: true, exerciseID: id, in: db)
      .values.flatMap { $0 }
    let machineIDs = Array(Set(samples.compactMap { $0.machineID?.rawValue }))
    let machines =
      machineIDs.isEmpty
      ? [:]
      : Dictionary(
        uniqueKeysWithValues: try Machine.where { $0.id.in(machineIDs) }.fetchAll(db).map { ($0.id, $0) })
    let modality = ExerciseModality(rawValue: exercise.modality)
    // The board's own names for a series, so the sheet names the row it was opened from.
    func label(_ key: ProgressionKey) -> String {
      if key.isImported { return ProgressCopy.importedHistory }
      if let machine = key.machineID.flatMap({ machines[$0.rawValue] }) {
        return MachineRecord(row: machine).displayName
      }
      if key.machineID == nil && (modality == .machine || modality == .cable) {
        return ProgressCopy.noMachineRecorded
      }
      return key.machineID == nil ? "Free weight" : "Unnamed machine"
    }
    return ChangeWorking.sixWeek(
      key: key, samples: samples, warmups: warmups, estimatesOneRepMax: modality?.estimatesOneRepMax ?? false,
      assumesAddedLoad: modality == nil, label: label
    )?.account(format: format)
  }
}
