import Foundation
import SQLiteData

/// What one confirmed full deletion removed.
///
/// Counts are useful to the caller for diagnostics, but the UI deliberately does not turn them
/// into a success score: zero rows is still a successful deletion on a fresh install.
public nonisolated struct DataDeletionSummary: Equatable, Sendable {
  public let synchronizedRows: Int
  public let deviceOnlyRows: Int

  public init(synchronizedRows: Int, deviceOnlyRows: Int) {
    self.synchronizedRows = synchronizedRows
    self.deviceOnlyRows = deviceOnlyRows
  }
}

/// Permanently removes everything the lifter created while preserving the bundled catalogue.
///
/// The deletes intentionally go through the normal synchronized tables while the app's retained
/// `SyncEngine` is alive. SQLiteData's delete triggers mark the matching metadata as deleted and
/// enqueue CloudKit record deletions; bypassing those triggers, replacing the database file, or
/// calling `SyncEngine.deleteLocalData()` would erase only this device and let iCloud resurrect the
/// rows later.
///
/// Curated exercises are app content, not user data. Their fixed IDs are referenced by every log,
/// and deleting then immediately reseeding them would race a CloudKit tombstone against a new row
/// with the same ID. They therefore stay in place while user-owned notes and archive state reset.
public nonisolated struct DataDeletionStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Deletes all user data in one transaction.
  ///
  /// Child tables are explicit and child-first. Relying only on cascades would currently work,
  /// but spelling the inventory out makes a newly added user-data table fail review visibly rather
  /// than surviving a control whose label promises "all".
  @discardableResult
  public func deleteAllUserData() throws -> DataDeletionSummary {
    try database.write { db in
      // One statement each also keeps Swift's type checker from having to solve a very large
      // generic StructuredQueries expression joined by integer operators.
      var synchronizedRows = 0
      synchronizedRows += try LoggedSet.count().fetchOne(db) ?? 0
      synchronizedRows += try SessionExercise.count().fetchOne(db) ?? 0
      synchronizedRows += try Session.count().fetchOne(db) ?? 0
      synchronizedRows += try SplitEntry.count().fetchOne(db) ?? 0
      synchronizedRows += try SplitDay.count().fetchOne(db) ?? 0
      synchronizedRows += try Split.count().fetchOne(db) ?? 0
      synchronizedRows += try MachineExercise.count().fetchOne(db) ?? 0
      synchronizedRows += try Machine.count().fetchOne(db) ?? 0
      synchronizedRows += try Gym.count().fetchOne(db) ?? 0
      synchronizedRows += try Exercise.where { !$0.isCurated }.count().fetchOne(db) ?? 0

      var deviceOnlyRows = 0
      deviceOnlyRows += try BodyweightEntry.count().fetchOne(db) ?? 0
      deviceOnlyRows += try DeviceHealthSample.count().fetchOne(db) ?? 0
      deviceOnlyRows += try DeviceRestTimer.count().fetchOne(db) ?? 0

      // Training history.
      try LoggedSet.delete().execute(db)
      try SessionExercise.delete().execute(db)
      try Session.delete().execute(db)

      // Plans.
      try SplitEntry.delete().execute(db)
      try SplitDay.delete().execute(db)
      try Split.delete().execute(db)

      // Learned equipment and user-created movements.
      try MachineExercise.delete().execute(db)
      try Machine.delete().execute(db)
      try Gym.delete().execute(db)
      try Exercise.where { !$0.isCurated }.delete().execute(db)

      // Keep the shipped catalogue IDs, but remove every user-owned field on those rows.
      try Exercise
        .where { $0.isCurated }
        .update {
          $0.name = $0.curatedName
          $0.notes = ""
          $0.isArchived = false
        }
        .execute(db)

      // These tables never participate in CloudKit and disappear locally in the same transaction.
      try BodyweightEntry.delete().execute(db)
      try DeviceHealthSample.delete().execute(db)
      try DeviceRestTimer.delete().execute(db)

      return DataDeletionSummary(
        synchronizedRows: synchronizedRows,
        deviceOnlyRows: deviceOnlyRows
      )
    }
  }
}
