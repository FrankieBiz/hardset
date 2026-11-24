import Foundation
import GRDB
import HardsetCore
import SQLiteData

/// One read of everything the muscle history sheet draws: the per-movement counts over the whole
/// history, twelve seven-day windows, and the attribution those are credited through.
///
/// The readers are `VolumeStore`'s, made `static` so the archive and attribution rules are shared
/// rather than copied. The sheet's lifetime total and its twelve-week shape therefore agree about a
/// set by construction, which is the thing most likely to drift silently (D24 §5.2).
public nonisolated struct MuscleHistoryStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// The history as of `now`, read from one consistent, cancellable snapshot.
  ///
  /// Every window ends at `now`, so a set dated after it is in no window and in no date; it is in
  /// the lifetime total only (D31).
  public func load(endingAt now: Date, calendar: Calendar = .current) async throws
    -> MuscleHistoryReading
  {
    try Task.checkCancellation()
    let reading = try await database.read { db in
      try Self.read(endingAt: now, calendar: calendar, in: db)
    }
    try Task.checkCancellation()
    return reading
  }

  /// The same read, synchronously, for the store's own tests and for a caller already on the queue.
  static func read(endingAt now: Date, calendar: Calendar = .current, in db: Database) throws
    -> MuscleHistoryReading
  {
    // One row per movement. The first count is the lifetime one; the filtered count and dates are
    // the part that can be placed in time, so a future-dated set is in the total and in neither
    // "last trained" nor the first-set date.
    let grouped: [(UUID, Int, Int, Date?, Date?)] = try LoggedSet
      .where { !$0.isWarmup }
      .group { $0.exerciseID }
      .select {
        (
          $0.exerciseID, $0.exerciseID.count(),
          $0.exerciseID.count(filter: $0.completedAt <= now),
          $0.completedAt.max(filter: $0.completedAt <= now),
          $0.completedAt.min(filter: $0.completedAt <= now)
        )
      }
      .fetchAll(db)
    let counts = grouped.map { row in
      MuscleHistoryCount(
        exerciseID: ExerciseID(rawValue: row.0), setCount: row.1, pastSetCount: row.2,
        lastAt: row.3, firstAt: row.4)
    }
    let entries = try VolumeStore.readAttributionEntries(in: db)
    let movements = try VolumeStore.readMovements(in: db)
    let attribution = AttributionIndex(entries: entries)
    var weeks: [MuscleHistoryWeek] = []
    weeks.reserveCapacity(12)
    for weeksBack in 0..<12 {
      let range = VolumeWindowRange(endingAt: now, weeksBack: weeksBack, calendar: calendar)
      let sets = try VolumeStore.readCountableSets(from: range.start, to: range.end, in: db)
      weeks.append(
        MuscleHistoryWeek(
          start: range.start, end: range.end, lastDay: range.lastDay,
          report: VolumeAnalyzer.report(sets: sets, attribution: attribution), sets: sets))
    }
    let history = MuscleHistoryAnalyzer.history(
      counts: counts, weeks: weeks, attribution: attribution,
      imported: movements.imported, names: movements.names)
    return MuscleHistoryReading(
      history: history, attribution: attribution, exerciseNames: movements.names,
      importedMovements: movements.imported)
  }
}

/// The history and the inputs its figures were counted from, read together.
///
/// The attribution and the names travel with it so a figure on the sheet opens its own working
/// without a second read, and the account cannot describe a different snapshot.
public nonisolated struct MuscleHistoryReading: Sendable {
  public let history: MuscleHistory
  public let attribution: AttributionIndex
  public let exerciseNames: [ExerciseID: String]
  public let importedMovements: Set<ExerciseID>

  public init(
    history: MuscleHistory, attribution: AttributionIndex,
    exerciseNames: [ExerciseID: String], importedMovements: Set<ExerciseID>
  ) {
    self.history = history
    self.attribution = attribution
    self.exerciseNames = exerciseNames
    self.importedMovements = importedMovements
  }

  /// A movement's name, or the same words the history uses for one that no longer exists.
  public func name(for id: ExerciseID) -> String { exerciseNames[id] ?? "Unknown movement" }
}
