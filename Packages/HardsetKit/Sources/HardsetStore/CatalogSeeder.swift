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
        } else {
          // Deliberately does not touch `notes` or `isArchived`: those are the user's, and
          // overwriting them on every launch would silently undo their edits.
          //
          // `name` is a three-way merge rather than either extreme. Never writing it meant a
          // curated correction could not reach any install that had already seeded, so two
          // installs disagreed forever about what the same movement is called while their
          // muscles and modality updated normally. Always writing it would erase a user's
          // rename on the next launch. So: adopt the new name only when the stored one is still
          // exactly what the catalogue last shipped.
          //
          // An empty `curatedName` means a row written before this column existed, which can
          // only predate any rename UI -- so it counts as untouched.
          let storedName = existing?.name ?? ""
          let lastCurated = existing?.curatedName ?? ""
          let userRenamedIt = !lastCurated.isEmpty && storedName != lastCurated
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

  /// Case- and diacritic-insensitive substring match across name, muscle and equipment.
  ///
  /// An empty query returns everything rather than nothing, so clearing the search box restores
  /// the list instead of emptying it.
  ///
  /// Name alone was not enough. The list is *grouped* by muscle and labelled with equipment, so
  /// those are the words a lifter can see and would reasonably type -- and "quads", "cable" and
  /// "bodyweight" all returned nothing, on a catalogue where the whole reason to search is that
  /// eighty-one entries do not fit on a screen. Squats are found by typing "quads" now.
  ///
  /// Muscles include the credited secondaries, so "triceps" finds the presses that train them
  /// indirectly. That matches what the row already prints underneath the name.
  public func search(_ query: String) throws -> [CatalogEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let all = try selectableExercises()
    guard !trimmed.isEmpty else { return all }
    return all.filter { Self.matches($0, query: trimmed) }
  }

  /// Whether one entry answers a query. Static and internal so the rule is testable directly.
  static func matches(_ entry: CatalogEntry, query: String) -> Bool {
    func contains(_ haystack: String) -> Bool {
      haystack.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    if contains(entry.name) { return true }
    if let modality = entry.modality, contains(modality.label) { return true }
    // The muscle vocabulary as the picker prints it -- "Front delts", not "frontDelts".
    if contains(MuscleVocabulary.displayName(entry.primaryMuscle)) { return true }
    return entry.creditedMuscles.contains {
      contains(MuscleVocabulary.displayName($0.key))
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
