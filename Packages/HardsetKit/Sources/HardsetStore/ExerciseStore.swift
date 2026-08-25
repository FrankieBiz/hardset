import Foundation
import HardsetCore
import SQLiteData

/// Creating and retiring the lifter's own movements.
///
/// Nothing outside `CatalogSeeder` ever inserted an `exercises` row, so a movement the shipped
/// catalogue does not have could not be logged at all. The catalogue is 81 entries against a
/// defensible v1 of roughly 240, so that is not an edge case: it is the cable machine at your gym
/// with a name nobody else uses, and every variation you do that nobody wrote down.
///
/// It also left a run of built machinery unreachable. `exercises.isCurated` had a rendering path in
/// the picker ("your own movement") that no row could satisfy; `curatedName` and the seeder's
/// rename-detection branch exist to stop a catalogue correction overwriting a name the lifter
/// changed, which no screen could change; `isArchived` was read to filter the picker and set by
/// nothing.
public nonisolated struct ExerciseStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Records a movement the lifter defines themselves.
  ///
  /// The muscle is required, and that is a deliberate cost. A row with no attribution is *counted*
  /// but not *attributed*: its sets land in `unattributedHardSets`, the week becomes a lower bound,
  /// and every per-muscle figure carries a "≥". Asking for one muscle turns that into a real credit.
  /// One is asked for rather than several because the lifter is standing in a gym, and the app has no
  /// basis for guessing the rest.
  ///
  /// The chosen muscle is written as `direct` with `low` certainty, which is the honest reading: the
  /// role is what the lifter says the movement trains, and the confidence is that of a single
  /// person's judgement rather than of the literature the curated rows cite. Certainty does not
  /// change what a set counts -- `setWeight` reads the role alone -- so this labels the claim without
  /// quietly discounting the lifter's own work.
  ///
  /// # Inheriting from a movement it resembles
  ///
  /// `inheriting` carries the contributions of a curated movement the lifter picked as a template,
  /// and is the fix for a movement that credits one muscle when it plainly trains four. The
  /// rewrite that makes it honest -- user source, no citation, certainty capped -- happens **here**
  /// rather than in the sheet that collects it, so no future caller can write an inherited
  /// attribution that still claims the trial's provenance. `InheritedAttribution` is a pure
  /// function in Core precisely so this boundary has one rule to apply and a test can pin it.
  ///
  /// Pass the contributions the lifter left in place, not the template's whole list: the sheet
  /// shows them as removable rows, and a muscle they removed must not arrive here.
  ///
  /// - Returns: the new movement's id, or throws if the name is blank.
  @discardableResult
  public func createExercise(
    name: String,
    modality: ExerciseModality?,
    primaryMuscle: Muscle,
    inheriting: [MuscleContribution] = [],
    now: Date = Date()
  ) throws -> ExerciseID {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ExerciseStoreError.blankName }

    let id = ExerciseID()
    let contributions = InheritedAttribution.inherited(
      from: inheriting, primary: primaryMuscle
    )

    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(
          id: id.rawValue,
          name: trimmed,
          // Empty for a user row, which is exactly what the seeder's rename detection keys on: a
          // movement with no curated name was never shipped, so no catalogue correction owns it.
          curatedName: "",
          catalogSlug: nil,
          isCurated: false,
          modality: modality?.rawValue ?? "unknown",
          primaryMuscle: MuscleKey(primaryMuscle).storedValue,
          secondaryMusclesJSON: MuscleColumn.encode(contributions),
          notes: "",
          isArchived: false,
          createdAt: now
        )
      }
      .execute(db)
    }
    return id
  }

  /// Renames a movement the lifter owns.
  ///
  /// Curated rows are refused. Their names come from the catalogue and are compared against
  /// `curatedName` on every seed, so renaming one here would either be reverted on the next launch
  /// or would silently opt that row out of future corrections.
  public func rename(_ exerciseID: ExerciseID, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ExerciseStoreError.blankName }

    try database.write { db in
      guard let row = try Exercise.where { $0.id.eq(exerciseID.rawValue) }.fetchOne(db) else {
        throw ExerciseStoreError.notFound
      }
      guard !row.isCurated else { throw ExerciseStoreError.curatedRowIsNotEditable }
      try Exercise
        .where { $0.id.eq(exerciseID.rawValue) }
        .update { $0.name = #bind(trimmed) }
        .execute(db)
    }
  }

  /// Retires a movement so it leaves the picker.
  ///
  /// A soft delete, and the reason is the same one that makes `deleteSession` cascade: sets already
  /// logged against this movement are real training and stay exactly where they are. Archiving means
  /// "stop offering me this", never "pretend I did not do it". The weekly report reads archived rows
  /// as unattributed rather than as zero, which is why that distinction is worth keeping.
  public func setArchived(_ archived: Bool, for exerciseID: ExerciseID) throws {
    try database.write { db in
      try Exercise
        .where { $0.id.eq(exerciseID.rawValue) }
        .update { $0.isArchived = #bind(archived) }
        .execute(db)
    }
  }

  /// Whether a movement row exists at all, archived or not.
  public func exists(_ exerciseID: ExerciseID) throws -> Bool {
    try database.read { db in
      try Exercise.where { $0.id.eq(exerciseID.rawValue) }.fetchOne(db) != nil
    }
  }

  /// The name as stored, or `nil` when there is no such movement.
  public func name(of exerciseID: ExerciseID) throws -> String? {
    try database.read { db in
      try Exercise.where { $0.id.eq(exerciseID.rawValue) }.fetchOne(db)?.name
    }
  }

  /// Marks the lifter's own attribution, so a test can tell it from a cited one.
  ///
  /// Defined in Core now that two paths write it -- a movement typed from scratch and one
  /// inherited from a template. Kept here as the name the existing tests already use.
  static let userSourceID = MuscleContribution.userSourceID
}

public enum ExerciseStoreError: Error, Equatable, Sendable {
  case blankName
  case notFound
  /// A curated movement's name belongs to the catalogue, which compares it on every seed.
  case curatedRowIsNotEditable
}
