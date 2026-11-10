import Foundation
import HardsetCore
import SQLiteData

/// Writes the curated catalogue into the database, and answers queries against it.
///
/// Seeding is **idempotent by primary key**, which is the whole reason `CatalogExercise` carries
/// a fixed UUID literal. Two devices that both seed offline write identical rows and converge on
/// sync; there is no uniqueness constraint to lean on, because SQLiteData forbids `UNIQUE` on
/// anything but the primary key for synchronized tables.
///
/// It is also **non-destructive**. A user who renames or archives a curated movement keeps that
/// change: seeding refreshes only the fields the catalogue owns, and never resurrects something
/// the user archived. Re-running it on every launch is therefore safe and is the intended usage.
public nonisolated struct CatalogSeeder: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Inserts anything missing and refreshes catalogue-owned fields on what exists.
  ///
  /// Returns the number of rows newly inserted, so a caller can tell a first launch from a
  /// subsequent one without guessing.
  @discardableResult
  public func seed(_ catalogue: [CatalogExercise] = ExerciseCatalog.v1, now: Date = Date()) throws
    -> Int
  {
    try database.write { db in try Self.seed(catalogue, now: now, in: db) }
  }

  /// The same atomic, idempotent seed while the caller suspends for database work.
  @discardableResult
  public func loadCatalog(_ catalogue: [CatalogExercise] = ExerciseCatalog.v1, now: Date = Date())
    async throws -> Int
  {
    try Task.checkCancellation()
    return try await database.write { db in try Self.seed(catalogue, now: now, in: db) }
  }

  private static func seed(_ catalogue: [CatalogExercise], now: Date, in db: Database) throws -> Int {
    var inserted = 0
    for entry in catalogue {
      guard let uuid = entry.uuid else {
        // A malformed literal is a programmer error, caught by `ExerciseCatalogTests`. Skipping is
        // still better than trapping in a user's launch path.
        continue
      }
      let existing = try Exercise.where { $0.id.eq(uuid) }.fetchOne(db)
      // The object grammar, always. The previous reader was a bare `[String]` decode, which
      // throws on the whole array for one non-string element and therefore returns []. A build
      // shipped with that reader would see every object-grammar row as "no muscles at all",
      // silently zeroing every indirect credit, permanently, for those installs.
      let attributionJSON = MuscleColumn.encode(entry.contributions)

      if let existing {
        // An UPDATE fires row triggers even when its values are identical. Skip it
        // when the catalogue-owned fields and merged name already match.
        // Only adopt a corrected name if the user kept the previous curated name.
        // An empty curatedName has unknown provenance: preserve nonempty user names.
        // Notes, archive state and creation time always remain user-owned.
        let userRenamedIt = existing.name != existing.curatedName
        let mergedName = userRenamedIt ? existing.name : entry.name
        guard existing.name != mergedName
          || existing.curatedName != entry.name
          || existing.catalogSlug != entry.slug
          || !existing.isCurated
          || existing.modality != entry.modality.rawValue
          || existing.primaryMuscle != entry.primaryMuscle.rawValue
          || existing.secondaryMusclesJSON != attributionJSON
        else { continue }

        try Exercise
          .where { $0.id.eq(uuid) }
          .update {
            if !userRenamedIt { $0.name = #bind(entry.name) }
            $0.curatedName = #bind(entry.name)
            $0.catalogSlug = #bind(entry.slug)
            $0.isCurated = #bind(true)
            $0.modality = #bind(entry.modality.rawValue)
            $0.primaryMuscle = #bind(entry.primaryMuscle.rawValue)
            $0.secondaryMusclesJSON = #bind(attributionJSON)
          }
          .execute(db)
      } else {
        try Exercise.insert {
          Exercise.Draft(
            id: uuid,
            name: entry.name,
            curatedName: entry.name,
            catalogSlug: entry.slug,
            isCurated: true,
            modality: entry.modality.rawValue,
            primaryMuscle: entry.primaryMuscle.rawValue,
            secondaryMusclesJSON: attributionJSON,
            notes: "",
            isArchived: false,
            createdAt: now
          )
        }
        .execute(db)
        inserted += 1
      }
    }
    return inserted
  }

  // MARK: - Custom movements

  /// Saves a movement the catalogue does not ship, so a lifter at an unlisted machine can log it.
  ///
  /// The name is trimmed and its inner whitespace collapsed; a blank name throws
  /// `CatalogSeederError.blankName`. A live movement whose name matches ignoring case and
  /// diacritics is returned instead of a duplicate, preferring a curated one, so a retap or a
  /// typed catalogue name cannot split history across two identities.
  ///
  /// Nothing is inferred from the name. The row is uncurated with an unknown modality and the
  /// "unknown" primary muscle, so volume reports it as not attributed rather than inventing
  /// muscles; attribution is a later, explicit choice.
  public func createCustomExercise(named name: String, now: Date = Date()) throws -> CatalogEntry {
    let cleaned = Self.normalized(name)
    guard !cleaned.isEmpty else { throw CatalogSeederError.blankName }
    return try database.write { db in
      let existing = try Exercise
        .where { !$0.isArchived }
        .order { ($0.isCurated.desc(), $0.createdAt, $0.id) }
        .fetchAll(db)
        .first {
          !Self.isImported($0)
            && Self.normalized($0.name).compare(
              cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
      if let existing { return CatalogEntry(row: existing) }

      let id = UUID()
      try Exercise.insert { Exercise.Draft(id: id, name: cleaned, createdAt: now) }.execute(db)
      guard let inserted = try Exercise.where({ $0.id.eq(id) }).fetchOne(db) else {
        throw CatalogSeederError.notSaved
      }
      return CatalogEntry(row: inserted)
    }
  }

  // MARK: - Queries

  /// Selectable movements, newest user-created first, then curated alphabetically.
  ///
  /// Archived rows are excluded — that is what archiving is for — and the sort puts a movement
  /// the user just created where they will look for it.
  ///
  /// Movements created by a CSV import are excluded too. They carry no attribution and no
  /// verified equipment, and the import promises they stay separate from machine-level history;
  /// offered beside the catalogue's own entry, a lifter could log today's sets against the copy
  /// and earn no volume for them. Their history stays visible in History and progress screens,
  /// which read sets directly.
  public func selectableExercises() throws -> [CatalogEntry] {
    try database.read { db in
      try Exercise
        .where { !$0.isArchived }
        .where { !$0.notes.like(Self.importedNotesPattern) }
        .order { ($0.isCurated, $0.name) }
        .fetchAll(db)
        .map(CatalogEntry.init(row:))
    }
  }

  /// Movements most recently logged, newest first, each once, at most `limit` of them.
  ///
  /// Only movements the picker would offer: archived and imported ones are skipped. Read from
  /// what was saved rather than stored as a preference, so there is nothing to go stale.
  public func recent(limit: Int) throws -> [CatalogEntry] {
    guard limit > 0 else { return [] }
    return try database.read { db -> [CatalogEntry] in
      let query = LoggedSet
        .group { $0.exerciseID }
        .select { ($0.exerciseID, $0.completedAt.max()) }
      let grouped: [(UUID, Date?)] = try query.fetchAll(db)
      var latest: [(id: UUID, at: Date)] = []
      for (id, at) in grouped {
        if let at { latest.append((id: id, at: at)) }
      }
      latest.sort { $0.at != $1.at ? $0.at > $1.at : $0.id.uuidString < $1.id.uuidString }
      guard !latest.isEmpty else { return [] }
      let ids = latest.map(\.id)
      let rows: [Exercise] = try Exercise
        .where { $0.id.in(ids) }
        .where { !$0.isArchived }
        .fetchAll(db)
      var byID: [UUID: Exercise] = [:]
      for row in rows where !Self.isImported(row) { byID[row.id] = row }
      var entries: [CatalogEntry] = []
      for item in latest {
        guard entries.count < limit else { break }
        if let row = byID[item.id] { entries.append(CatalogEntry(row: row)) }
      }
      return entries
    }
  }

  /// Movements matching the names lifters type, best first, by `CatalogSearch`: case,
  /// diacritics, hyphens, spacing and plurals are folded, curated aliases and abbreviations
  /// ("rdl", "ohp", "db") are recognised, and a literal substring of the name still matches.
  ///
  /// An empty query returns everything rather than nothing, so clearing the search box restores
  /// the list instead of emptying it.
  public func search(_ query: String) throws -> [CatalogEntry] {
    CatalogSearch.rank(try selectableExercises(), query: query)
  }

  // MARK: - Imported movements

  /// The notes prefix `DataTransferStore.importWorkouts` writes on every movement it creates.
  static let importedNotesPrefix = "Imported • "
  /// The same marker as a `LIKE` pattern. The prefix holds no `%` or `_`, so it matches literally.
  private static let importedNotesPattern = importedNotesPrefix + "%"

  private static func isImported(_ row: Exercise) -> Bool {
    row.notes.hasPrefix(importedNotesPrefix)
  }

  /// Trimmed, with each run of inner whitespace collapsed to one space.
  private static func normalized(_ name: String) -> String {
    name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}

public nonisolated enum CatalogSeederError: Error, Equatable, Sendable {
  /// A custom movement needs a name with something other than whitespace in it.
  case blankName
  /// The insert completed but the row could not be read back. Nothing is returned to log
  /// against, because an entry the database does not hold would fail at the first set.
  case notSaved
}

/// Maps a stored row into the shared `CatalogEntry` value.
///
/// The value itself lives in `HardsetCore` so the picker can render it without `HardsetUI`
/// depending on storage; this is the only place that knows about columns.
extension CatalogEntry {
  nonisolated init(row: Exercise) {
    let decoded = MuscleColumn.decodeContributions(row.secondaryMusclesJSON)
    self.init(
      id: ExerciseID(rawValue: row.id),
      name: row.name,
      slug: row.catalogSlug,
      isCurated: row.isCurated,
      modality: ExerciseModality(rawValue: row.modality),
      primaryMuscle: MuscleColumn.decodePrimary(row.primaryMuscle),
      contributions: decoded.contributions,
      // Carried, not dropped. The decoder is only safe because its failures travel with the value.
      unreadableEntryCount: decoded.unreadableEntryCount
    )
  }
}
