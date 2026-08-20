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
public nonisolated struct CatalogSeeder {
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
    var inserted = 0
    try database.write { db in
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

        if existing == nil {
          try Exercise.insert {
            Exercise.Draft(
              id: uuid,
              name: entry.name,
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
        } else {
          // Deliberately does not touch `name`, `notes` or `isArchived`: those are the user's,
          // and overwriting them on every launch would silently undo their edits.
          try Exercise
            .where { $0.id.eq(uuid) }
            .update {
              $0.catalogSlug = #bind(entry.slug)
              $0.isCurated = #bind(true)
              $0.modality = #bind(entry.modality.rawValue)
              $0.primaryMuscle = #bind(entry.primaryMuscle.rawValue)
              $0.secondaryMusclesJSON = #bind(attributionJSON)
            }
            .execute(db)
        }
      }
    }
    return inserted
  }

  // MARK: - Queries

  /// Selectable movements, newest user-created first, then curated alphabetically.
  ///
  /// Archived rows are excluded — that is what archiving is for — and the sort puts a movement
  /// the user just created where they will look for it.
  public func selectableExercises() throws -> [CatalogEntry] {
    try database.read { db in
      try Exercise
        .where { !$0.isArchived }
        .order { ($0.isCurated, $0.name) }
        .fetchAll(db)
        .map(CatalogEntry.init(row:))
    }
  }

  /// Case- and diacritic-insensitive prefix/substring match on the name.
  ///
  /// An empty query returns everything rather than nothing, so clearing the search box restores
  /// the list instead of emptying it.
  public func search(_ query: String) throws -> [CatalogEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let all = try selectableExercises()
    guard !trimmed.isEmpty else { return all }
    return all.filter {
      $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

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
