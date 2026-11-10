import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Movements the catalogue does not ship, recent movements for the picker, and keeping imported
/// history out of live logging.
@Suite("The picker can create, recall and exclude movements honestly")
struct CustomExerciseTests {
  let now = Date(timeIntervalSince1970: 7_500_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private let legPress = CatalogExercise(
    id: "11111111-1111-5111-8111-111111111111",
    slug: "leg-press", name: "Leg Press", modality: .machine,
    primaryMuscle: .quadriceps,
    contributions: [.init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy)]
  )

  // MARK: - Creating

  @Test("A custom movement is saved trimmed, uncurated and unattributed")
  func createsUnattributedMovement() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let entry = try seeder.createCustomExercise(named: "  Hip   Adduction \n", now: now)
    #expect(entry.name == "Hip Adduction")
    #expect(!entry.isCurated)
    #expect(entry.slug == nil)
    #expect(entry.isUnattributed)
    #expect(entry.contributions.isEmpty)
    let row = try #require(try database.read { db in
      try Exercise.where { $0.id.eq(entry.id.rawValue) }.fetchOne(db)
    })
    #expect(row.modality == "unknown")
    #expect(row.primaryMuscle == "unknown")
    #expect(row.curatedName == "")
    #expect(row.createdAt == now)
    #expect(try seeder.search("adduction").map(\.id) == [entry.id])
  }

  @Test("A blank name is refused", arguments: ["", "   ", "\n\t"])
  func blankNameRefused(name: String) throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    #expect(throws: CatalogSeederError.blankName) {
      try seeder.createCustomExercise(named: name)
    }
    #expect(try seeder.selectableExercises().isEmpty)
  }

  @Test("A name that already exists returns that movement instead of a duplicate",
        arguments: ["leg press", "LEG  PRESS", "Lég Press"])
  func existingNameIsReused(name: String) throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed([legPress], now: now)
    let entry = try seeder.createCustomExercise(named: name)
    #expect(entry.slug == "leg-press")
    #expect(entry.isCurated)
    #expect(try seeder.selectableExercises().count == 1)
  }

  @Test("Re-creating a custom movement returns the first one")
  func customNameIsReused() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let first = try seeder.createCustomExercise(named: "Hip Adduction")
    let again = try seeder.createCustomExercise(named: "hip adduction")
    #expect(again.id == first.id)
    #expect(try seeder.selectableExercises().count == 1)
  }

  @Test("Seeding leaves a custom movement untouched")
  func seedLeavesCustomAlone() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let custom = try seeder.createCustomExercise(named: "Hip Adduction", now: now)
    #expect(try seeder.seed([legPress], now: now) == 1)
    let stored = try #require(try seeder.selectableExercises().first { $0.id == custom.id })
    #expect(stored == custom)
  }

  // MARK: - Imported history

  @Test("Imported movements are kept out of live search but their history stays")
  func importedMovementsExcluded() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed([legPress], now: now)
    let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n"
      + "2026-11-01 10:00:00,Legs,1h 2m,Leg Press,1,100,8,,\n"
    let preview = try WorkoutCSVImport.preview(
      csv, strongUnit: .kilograms, timeZone: TimeZone(secondsFromGMT: 0)!
    )
    #expect(try await DataTransferStore(database: database).importWorkouts(preview) == 1)

    #expect(try seeder.search("leg press").map(\.name) == ["Leg Press"])
    #expect(try seeder.selectableExercises().map(\.name) == ["Leg Press"])
    #expect(try seeder.recent(limit: 5).isEmpty)
    let importedSets = try await database.read { try LoggedSet.fetchAll($0).count }
    #expect(importedSets == 1)
    // A movement the lifter creates with the imported name is a new, live one.
    let created = try seeder.createCustomExercise(named: "Leg Press (Imported • Strong)")
    #expect(try seeder.search("imported").map(\.id) == [created.id])
  }

  // MARK: - Recent

  @Test("Recent movements are newest first, once each, live only, and limited")
  func recentMovements() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let store = LoggerStore(database: database)
    let squat = try seeder.createCustomExercise(named: "Squat")
    let curl = try seeder.createCustomExercise(named: "Curl")
    let row = try seeder.createCustomExercise(named: "Row")
    let retired = try seeder.createCustomExercise(named: "Retired")
    _ = try seeder.createCustomExercise(named: "Never done")
    #expect(try seeder.recent(limit: 5).isEmpty)

    let session = try store.startSession(at: now)
    for (offset, exercise) in [squat, curl, squat, row, retired].enumerated() {
      _ = try store.logSet(sessionID: session, exerciseID: exercise.id,
                           draft: SetEntryDraft(weightKg: 50, reps: 8),
                           at: now.addingTimeInterval(Double(offset) * 60))
    }
    try database.write { db in
      try Exercise.where { $0.id.eq(retired.id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }

    #expect(try seeder.recent(limit: 5).map(\.name) == ["Row", "Squat", "Curl"])
    #expect(try seeder.recent(limit: 2).map(\.name) == ["Row", "Squat"])
    #expect(try seeder.recent(limit: 0).isEmpty)
  }
}
