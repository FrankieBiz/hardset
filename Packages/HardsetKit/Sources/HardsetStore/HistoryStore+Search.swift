import Foundation
import HardsetCore
import SQLiteData

/// Finding an old workout by what was done and where.
///
/// A query is matched against three kinds of name: the movement, the machine and the gym. Each
/// match leads to finished workouts through an index, and the answer is those workouts, newest
/// first, in the same summary the list shows.
///
/// The work is kept off the large tables on purpose. The names live in three small tables, so they
/// are read whole and matched in Swift, by the same rules the movement picker uses
/// (`CatalogSearch`: case, hyphens, plurals, "ohp" and "rdl"). Only then does the search touch a
/// set or a session, and only by key: sets by exercise or by machine, sessions by gym or by id. No
/// statement here scans `loggedSets` or `sessions`, and none sorts in SQLite; the order is applied
/// to the matched workouts in Swift. `HistorySearchTests` reads the plan of every statement the
/// search really emits, and `Tools/check_query_performance.py` holds the same shapes to the gate.
nonisolated extension HistoryStore {
  /// The fewest letters or digits a query needs before it searches. One character begins nearly
  /// every movement name, so it would read nearly every set on a keystroke.
  public static let minimumSearchLength = 2

  /// Whether `query` is long enough to search, ignoring spaces and punctuation. A query of "--" or
  /// "  " has no word to find, and `CatalogSearch` would answer such a query with everything.
  public static func isSearchable(_ query: String) -> Bool {
    query.filter { $0.isLetter || $0.isNumber }.count >= minimumSearchLength
  }

  /// Finished workouts whose movements, machines or gym match `query`, newest first, at most
  /// `limit` of them, and how many matched in all, from one snapshot.
  ///
  /// A query that matches nothing, or is too short to search, returns an empty page rather than
  /// failing: no result is an answer, not an error.
  public func searchHistory(_ query: String, limit: Int) async throws -> HistoryPage {
    try Task.checkCancellation()
    let page = try await database.read { db in try Self.readSearch(query, limit: limit, in: db) }
    try Task.checkCancellation()
    return page
  }

  /// SQLite rejects a statement with too many bound values on older builds. Every `IN` list here is
  /// read in slices well under that.
  private static let sliceSize = 500

  private static func readSearch(_ query: String, limit: Int, in db: Database) throws -> HistoryPage {
    guard isSearchable(query) else { return HistoryPage(sessions: [], totalCount: 0) }

    // Names, whole: a few hundred movements, a few dozen machines, a handful of gyms. Archived and
    // imported rows are included, because history keeps the sets of a movement or machine that was
    // archived afterwards.
    let movements = try Exercise.all.fetchAll(db).map(CatalogEntry.init(row:))
    let movementIDs = CatalogSearch.rank(movements, query: query).map(\.id.rawValue)
    let machineIDs = matching(
      try Machine.all.fetchAll(db).map { (id: $0.id, name: MachineRecord(row: $0).displayName) },
      query: query)
    let gymIDs = matching(try Gym.all.fetchAll(db).map { (id: $0.id, name: $0.name) }, query: query)

    // The sessions those names lead to, each found by an index: sets by exercise (the existing
    // exercise indexes), sets by machine (`loggedSets_on_machineID_sessionID`) and sessions by gym
    // (`sessions_on_gymID`). A session holding several matching sets appears once.
    var found = Set<UUID>()
    for slice in slices(of: movementIDs) {
      found.formUnion(try LoggedSet.where { $0.exerciseID.in(slice) }.select { $0.sessionID }.fetchAll(db))
    }
    // Both columns are nullable, so the values are widened to match.
    for slice in slices(of: machineIDs) {
      let wanted = slice.map { Optional($0) }
      found.formUnion(try LoggedSet.where { $0.machineID.in(wanted) }.select { $0.sessionID }.fetchAll(db))
    }
    for slice in slices(of: gymIDs) {
      let wanted = slice.map { Optional($0) }
      found.formUnion(try Session.where { $0.gymID.in(wanted) }.select { $0.id }.fetchAll(db))
    }

    // Only finished workouts are history, and the start time orders them, so both are read for
    // the matched ids alone, by primary key.
    var finished: [(id: UUID, startedAt: Date)] = []
    for slice in slices(of: Array(found)) {
      let rows: [(UUID, Date)] = try Session
        .where { $0.id.in(slice) && $0.finishedAt.isNot(nil) }
        .select { ($0.id, $0.startedAt) }
        .fetchAll(db)
      finished.append(contentsOf: rows.map { (id: $0.0, startedAt: $0.1) })
    }
    guard !finished.isEmpty else { return HistoryPage(sessions: [], totalCount: 0) }

    // The list's order: newest start first, the id breaking a tie so a page boundary is stable.
    finished.sort {
      $0.startedAt != $1.startedAt
        ? $0.startedAt > $1.startedAt
        : $0.id.uuidString.lowercased() > $1.id.uuidString.lowercased()
    }
    let pageIDs = finished.prefix(max(limit, 0)).map(\.id)
    var byID: [UUID: Session] = [:]
    for slice in slices(of: pageIDs) {
      for session in try Session.where({ $0.id.in(slice) }).fetchAll(db) { byID[session.id] = session }
    }
    let sessions = pageIDs.compactMap { byID[$0] }
    return HistoryPage(sessions: try summaries(of: sessions, in: db), totalCount: finished.count)
  }

  /// The ids whose name answers `query` by the movement picker's rules, best match first.
  ///
  /// Machines and gyms are matched by lending `CatalogSearch` a name to rank, so a machine named
  /// "Hammer Strength Chest Press" is found by "chest press" and "hammer" exactly as a movement is,
  /// and there is one set of spelling rules in the app rather than two.
  private static func matching(_ named: [(id: UUID, name: String)], query: String) -> [UUID] {
    let entries = named.map {
      CatalogEntry(
        id: ExerciseID(rawValue: $0.id), name: $0.name, slug: nil, isCurated: false,
        modality: nil, primaryMuscle: MuscleKey(stored: MuscleKey.notAttributedRawValue),
        contributions: [])
    }
    return CatalogSearch.rank(entries, query: query).map(\.id.rawValue)
  }

  private static func slices(of ids: [UUID]) -> [[UUID]] {
    stride(from: 0, to: ids.count, by: sliceSize).map {
      Array(ids[$0..<min($0 + sliceSize, ids.count)])
    }
  }
}
