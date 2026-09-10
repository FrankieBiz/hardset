import CloudKit
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A lifter can permanently delete all of their data")
struct DataDeletionStoreTests {
  private let now = Date(timeIntervalSince1970: 12_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func populate(_ database: any DatabaseWriter) throws {
    try CatalogSeeder(database: database).seed(now: now)
    let catalogueRow = try database.read { db in
      let row = try Exercise.where { $0.catalogSlug.eq("chest-press-machine") }.fetchOne(db)
      return try #require(row)
    }
    let catalogueID = ExerciseID(rawValue: catalogueRow.id)

    _ = try ExerciseStore(database: database).createExercise(
      name: "My Press", modality: .machine, primaryMuscle: .chest, now: now
    )
    let gymStore = GymStore(database: database)
    let gymID = try gymStore.createGym(name: "Home", now: now)
    _ = try gymStore.createMachine(
      at: gymID, name: "Press A", forExercise: catalogueID, now: now
    )

    let logger = LoggerStore(database: database)
    let sessionID = try logger.startSession(title: "Push", at: now)
    _ = try logger.logSet(
      sessionID: sessionID,
      exerciseID: catalogueID,
      draft: SetEntryDraft(weightKg: 80, reps: 8),
      setOrdinal: 0,
      kind: .working,
      at: now
    )

    try database.write { db in
      let splitID = UUID()
      let dayID = UUID()
      try Split.insert {
        Split.Draft(id: splitID, name: "Upper", isArchived: false, createdAt: now)
      }
      .execute(db)
      try SplitDay.insert {
        SplitDay.Draft(id: dayID, splitID: splitID, name: "Push", position: 0, createdAt: now)
      }
      .execute(db)
      try SplitEntry.insert {
        SplitEntry.Draft(
          id: UUID(), splitDayID: dayID, exerciseID: catalogueRow.id,
          machineID: nil, position: 0, createdAt: now
        )
      }
      .execute(db)

      // User-owned fields on bundled content are user data too, even though the row itself is not.
      try Exercise.where { $0.id.eq(catalogueRow.id) }.update {
        $0.notes = "Seat at 4"
        $0.isArchived = true
      }
      .execute(db)

      try DeviceHealthSample.insert {
        DeviceHealthSample.Draft(
          id: UUID(), kind: "sample", value: 1, unit: "count", startedAt: now
        )
      }
      .execute(db)
      try DeviceRestTimer.insert {
        DeviceRestTimer.Draft(id: UUID(), endsAt: now, updatedAt: now)
      }
      .execute(db)
    }
    _ = try BodyweightStore(database: database).record(weightKg: 82, at: now)
  }

  @Test("Every user-data table is emptied and the bundled catalogue is restored")
  func deletesEveryUserDataTable() throws {
    let database = try migratedDatabase()
    try populate(database)

    let summary = try DataDeletionStore(database: database).deleteAllUserData()
    #expect(summary.synchronizedRows > 0)
    #expect(summary.deviceOnlyRows == 3)

    try database.read { db in
      #expect(try LoggedSet.count().fetchOne(db) == 0)
      #expect(try SessionExercise.count().fetchOne(db) == 0)
      #expect(try Session.count().fetchOne(db) == 0)
      #expect(try SplitEntry.count().fetchOne(db) == 0)
      #expect(try SplitDay.count().fetchOne(db) == 0)
      #expect(try Split.count().fetchOne(db) == 0)
      #expect(try MachineExercise.count().fetchOne(db) == 0)
      #expect(try Machine.count().fetchOne(db) == 0)
      #expect(try Gym.count().fetchOne(db) == 0)
      #expect(try BodyweightEntry.count().fetchOne(db) == 0)
      #expect(try DeviceHealthSample.count().fetchOne(db) == 0)
      #expect(try DeviceRestTimer.count().fetchOne(db) == 0)

      let exercises = try Exercise.all.fetchAll(db)
      #expect(exercises.count == ExerciseCatalog.v1.count)
      let allAreCurated = exercises.allSatisfy { $0.isCurated }
      let allCustomizationsAreReset = exercises.allSatisfy {
        $0.notes.isEmpty && !$0.isArchived
      }
      #expect(allAreCurated)
      #expect(allCustomizationsAreReset)

      let storedPress = try Exercise
        .where { $0.catalogSlug.eq("chest-press-machine") }
        .fetchOne(db)
      let press = try #require(storedPress)
      #expect(press.name == press.curatedName)
    }
  }

  @Test("Deleting an already-empty store succeeds")
  func emptyStoreIsStillADeletionSuccess() throws {
    let database = try migratedDatabase()
    try CatalogSeeder(database: database).seed(now: now)
    let summary = try DataDeletionStore(database: database).deleteAllUserData()
    #expect(summary == DataDeletionSummary(synchronizedRows: 0, deviceOnlyRows: 0))
  }
}

/// Runs alone: SQLiteData's test-context SyncEngine uses a process-global in-memory metadatabase.
@Suite("Full deletion creates CloudKit tombstones", .serialized)
struct DataDeletionCloudKitTests {
  @Test("Synchronized rows are tombstoned rather than merely removed locally")
  func deletionCreatesCloudKitTombstones() throws {
    try withDependencies {
      $0.context = .test
    } operation: {
      var configuration = Configuration()
      configuration.foreignKeysEnabled = true
      let database = try DatabaseQueue(configuration: configuration)
      try HardsetMigrations.migrator().migrate(database)

      let engine = try HardsetDatabase.makeSyncEngine(
        for: database,
        delegate: HardsetSyncDelegate(),
        containerIdentifier: "iCloud.hardset.tests.\(UUID().uuidString)"
      )
      // Keep the triggers installed but prevent the mock engine from immediately consuming the
      // metadata. SQLiteData documents that edits made while stopped are queued for the next start.
      engine.stop()

      try CatalogSeeder(database: database).seed()
      let customID = try ExerciseStore(database: database).createExercise(
        name: "My Row", modality: .cable, primaryMuscle: .lats
      )
      let gymID = try GymStore(database: database).createGym(name: "Garage")
      _ = try LoggerStore(database: database).startSession(title: "Pull", at: Date())

      try DataDeletionStore(database: database).deleteAllUserData()

      let tombstonedTypes = try database.read { db in
        try String.fetchAll(
          db,
          sql: """
            SELECT "recordType"
            FROM "sqlitedata_icloud"."sqlitedata_icloud_metadata"
            WHERE "_isDeleted" = 1
            ORDER BY "recordType"
            """
        )
      }
      #expect(tombstonedTypes.contains("exercises"), "missing custom exercise tombstone \(customID)")
      #expect(tombstonedTypes.contains("gyms"), "missing gym tombstone \(gymID)")
      #expect(tombstonedTypes.contains("sessions"))

      withExtendedLifetime(engine) {}
    }
  }
}
