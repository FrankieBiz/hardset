import Foundation
import HardsetCore
import SQLiteData

/// Reads the sets and the attribution a volume report needs.
///
/// Two queries, both bounded by a date window, and then pure arithmetic in `VolumeAnalyzer`. The
/// counting itself has no database handle, so a volume figure cannot depend on when it was asked
/// for — which is what makes the report reproducible from the same window.
public nonisolated struct VolumeStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Completed sets in `[from, to)`.
  ///
  /// Half-open on purpose. A closed range double-counts any set landing exactly on a week boundary
  /// when two adjacent weeks are compared, which shows up as a phantom set in both.
  public func countableSets(from: Date, to: Date) throws -> [CountableSet] {
    try database.read { db in
      try LoggedSet
        .where { $0.completedAt >= from }
        .where { $0.completedAt < to }
        .order { $0.completedAt }
        .fetchAll(db)
        .map { CountableSet(exerciseID: ExerciseID(rawValue: $0.exerciseID), isWarmup: $0.isWarmup) }
    }
  }

  /// Attribution for every exercise that is not archived.
  ///
  /// Read from the database rather than from `ExerciseCatalog`, so a user's own exercises and any
  /// row a newer app version wrote are both included. An exercise whose stored attribution is
  /// unreadable is deliberately absent, which makes its sets *unattributed* rather than silently
  /// zero — the distinction the report is built on.
  public func attributionIndex() throws -> AttributionIndex {
    let entries = try database.read { db in
      try Exercise.where { !$0.isArchived }.fetchAll(db).map(CatalogEntry.init(row:))
    }
    return AttributionIndex(entries: entries)
  }

  /// The report for one window.
  public func report(from: Date, to: Date) throws -> MuscleVolumeReport {
    VolumeAnalyzer.report(
      sets: try countableSets(from: from, to: to),
      attribution: try attributionIndex()
    )
  }

  /// The report for the seven days ending at `now`.
  ///
  /// A rolling window, not a calendar week. A calendar week makes Monday morning look like a
  /// catastrophic drop in volume, which is an artefact of the boundary rather than anything about
  /// the training. If a calendar week is ever wanted it should be a separate, named function so
  /// the two can never be confused.
  public func rollingWeek(endingAt now: Date) throws -> MuscleVolumeReport {
    try report(from: now.addingTimeInterval(-7 * 86_400), to: now)
  }
}

/// Reads load history for one exercise, per machine.
public nonisolated struct ProgressionStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Completed working sets for one exercise, across every machine, oldest first.
  ///
  /// Warm-ups are excluded in SQL. A warm-up reaching the analyser would be a bug, so it is not
  /// filtered defensively there — that would hide it.
  public func samples(for exerciseID: ExerciseID, limit: Int = 2_000) throws
    -> [ProgressionSample]
  {
    try database.read { db in
      try LoggedSet
        .where { $0.exerciseID.eq(exerciseID.rawValue) }
        .where { !$0.isWarmup }
        .order { $0.completedAt }
        .limit(limit)
        .fetchAll(db)
        .map {
          ProgressionSample(
            sessionID: SessionID(rawValue: $0.sessionID),
            machineID: $0.machineID.map(MachineID.init(rawValue:)),
            weightKg: $0.weightKg,
            reps: $0.reps,
            completedAt: $0.completedAt
          )
        }
    }
  }

  /// Machine names, for labelling the series. A machine the user deleted resolves to `nil` and the
  /// series is labelled generically rather than dropped — the sets were still performed.
  public func machineNames(_ ids: [MachineID]) throws -> [MachineID: String] {
    guard !ids.isEmpty else { return [:] }
    let raws = ids.map(\.rawValue)
    return try database.read { db in
      try Machine
        .where { $0.id.in(raws) }
        .fetchAll(db)
        .reduce(into: [MachineID: String]()) { $0[MachineID(rawValue: $1.id)] = $1.name }
    }
  }

  /// Everything a load-history chart needs for one exercise.
  public func history(for exerciseID: ExerciseID) throws -> ProgressionHistory {
    let samples = try samples(for: exerciseID)
    let series = ProgressionAnalyzer.series(from: samples, exerciseID: exerciseID)
    let changes = ProgressionAnalyzer.machineChanges(from: samples)
    let names = try machineNames(series.compactMap(\.key.machineID))
    return ProgressionHistory(series: series, machineChanges: changes, machineNames: names)
  }
}

/// One exercise's load history, ready to plot.
public nonisolated struct ProgressionHistory: Hashable, Sendable {
  public let series: [ProgressionSeries]
  public let machineChanges: [MachineChange]
  public let machineNames: [MachineID: String]

  public init(
    series: [ProgressionSeries],
    machineChanges: [MachineChange],
    machineNames: [MachineID: String]
  ) {
    self.series = series
    self.machineChanges = machineChanges
    self.machineNames = machineNames
  }

  /// Label for a series. Free-weight work and a deleted machine are named rather than blank.
  public func label(for key: ProgressionKey) -> String {
    guard let machineID = key.machineID else { return "Free weight" }
    return machineNames[machineID] ?? "Unnamed machine"
  }

  public var isEmpty: Bool { series.isEmpty }
}
