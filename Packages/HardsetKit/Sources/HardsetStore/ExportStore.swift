import Foundation
import HardsetCore
import SQLiteData

/// Everything the lifter has logged, as a file they can keep.
///
/// This exists because a training log the owner cannot get out of the app is a hostage, and
/// because "data loss / no export" is one of the loudest complaints in this category's reviews
/// (`docs/research/prior-research.md:576`). It is also the honest consequence of the app's own
/// claim: if these numbers are worth trusting, they are worth owning.
///
/// **One row per logged set, and nothing derived.** No fractional credit, no estimated one-rep
/// max, no weekly totals. Those are all computed from these rows by code whose conventions are
/// stated elsewhere and may be revised; exporting them would freeze a convention into a file that
/// outlives it. What is exported is what the lifter actually did, which cannot go stale.
public nonisolated struct ExportStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Column order is part of the contract: append only, never reorder or rename.
  ///
  /// Somebody's spreadsheet will have formulas pointing at these positions, and a reordered
  /// column silently changes what every one of them reads.
  static let header = [
    "session_id", "session_title", "session_started_at", "session_finished_at",
    "exercise", "machine", "set_ordinal", "set_kind",
    "weight_kg", "reps", "rpe", "completed_at",
  ]

  /// Every logged set, oldest first, as RFC 4180 CSV.
  ///
  /// Ordered oldest-first rather than newest-first because a file is read forwards and a training
  /// history reads as a sequence. Sets from an unfinished workout are included — they happened,
  /// and excluding them would mean an export taken at the gym silently omits today.
  ///
  /// **Weights are kilograms**, always, matching how they are stored. The display unit is a
  /// display preference, and converting on the way out would put the lifter's rounding into their
  /// own archive; `weight_kg` says so in the column name so nobody has to guess.
  public func workoutCSV() throws -> String {
    let rows = try database.read { db -> [(LoggedSet, Session?, String, String?)] in
      let sets = try LoggedSet.order { $0.completedAt }.fetchAll(db)
      guard !sets.isEmpty else { return [] }

      let sessions = try Session
        .where { $0.id.in(Array(Set(sets.map(\.sessionID)))) }
        .fetchAll(db)
        .reduce(into: [UUID: Session]()) { $0[$1.id] = $1 }
      let exercises = try Exercise
        .where { $0.id.in(Array(Set(sets.map(\.exerciseID)))) }
        .fetchAll(db)
        .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

      let machineIDs = Array(Set(sets.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

      return sets.map {
        (
          $0, sessions[$0.sessionID],
          // A movement whose row is gone should still export its sets rather than dropping them.
          exercises[$0.exerciseID] ?? "Unknown movement",
          $0.machineID.flatMap { machines[$0] }
        )
      }
    }

    var out = CSV.row(Self.header)
    for (set, session, exerciseName, machineName) in rows {
      out += CSV.row([
        set.sessionID.uuidString,
        session?.title ?? "",
        session.map { CSV.timestamp($0.startedAt) } ?? "",
        // Empty rather than a placeholder: an unfinished workout has no end, and inventing one is
        // the bug that shipped 9,749-minute sessions in the ancestor.
        session?.finishedAt.map(CSV.timestamp) ?? "",
        exerciseName,
        // Empty means no machine was recorded, which is a real state and not a gap.
        machineName ?? "",
        String(set.setOrdinal),
        SetKind(isWarmup: set.isWarmup, isDropSet: set.isDropSet).rawValue,
        CSV.number(set.weightKg),
        String(set.reps),
        set.rpe.map(CSV.number) ?? "",
        CSV.timestamp(set.completedAt),
      ])
    }
    return out
  }

  /// How many sets an export would contain, for the label on the button.
  ///
  /// Read separately so the sheet can say "Export 412 sets" rather than offering a file of unknown
  /// size — and so an empty log offers nothing at all instead of a file with only a header.
  public func loggedSetCount() throws -> Int {
    try database.read { db in try LoggedSet.fetchCount(db) }
  }

  /// A filename that sorts chronologically and says what it is.
  public static func filename(on date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return "hardset-\(formatter.string(from: date)).csv"
  }
}
