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

  // MARK: - Tagging a movement with the muscles it trains

  @Test("A movement created with a choice stores the primary, the secondaries and the equipment")
  func createWithAttributionStoresPrimaryAndSecondaries() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let attribution = try #require(
      CustomAttribution(primary: .lats, secondary: [.biceps], modality: .machine))

    let entry = try seeder.createCustomExercise(
      named: "Nautilus lever row", attribution: attribution, now: now)

    let row = try #require(try database.read { db in
      try Exercise.where { $0.id.eq(entry.id.rawValue) }.fetchOne(db)
    })
    #expect(row.primaryMuscle == "lats")
    #expect(row.modality == "machine")
    #expect(!row.isCurated)
    let stored = MuscleColumn.decodeContributions(row.secondaryMusclesJSON).contributions
    #expect(stored.map(\.key.storedValue) == ["lats", "biceps"])
    #expect(stored.map(\.role) == [.direct, .indirect])
    #expect(stored.allSatisfy { $0.certainty == .moderate && $0.sourceID == "user" })
    #expect(!entry.isUnattributed)
    #expect(entry.modality == .machine)
  }

  @Test("A name that already exists returns the existing movement, whatever the new choice says")
  func existingNameReturnedUnchanged() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let first = try seeder.createCustomExercise(named: "Nautilus lever row", now: now)
    let attribution = try #require(CustomAttribution(primary: .lats))

    let again = try seeder.createCustomExercise(
      named: "nautilus LEVER row", attribution: attribution, now: now)

    #expect(again.id == first.id)
    #expect(again.isUnattributed)
  }

  @Test("Retagging a custom movement replaces its muscles and may rename it")
  func updateRetagsCustomMovement() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let entry = try seeder.createCustomExercise(named: "Lever row", now: now)
    let attribution = try #require(
      CustomAttribution(primary: .upperBack, secondary: [.rearDelts], modality: .machine))

    let updated = try seeder.updateCustomExercise(
      entry.id, name: "  Nautilus   lever row ", attribution: attribution)

    #expect(updated.id == entry.id)
    #expect(updated.name == "Nautilus lever row")
    #expect(updated.primaryMuscle.storedValue == "upperBack")
    #expect(updated.contributions.map(\.key.storedValue) == ["rearDelts", "upperBack"])
    #expect(updated.modality == .machine)
    let reread = try seeder.selectableExercises().first { $0.id == entry.id }
    #expect(reread == updated)
  }

  @Test("Retagging with no equipment named leaves the equipment as it was")
  func updateKeepsModalityWhenNoneGiven() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let entry = try seeder.createCustomExercise(
      named: "Lever row", attribution: CustomAttribution(primary: .lats, modality: .cable),
      now: now)

    let updated = try seeder.updateCustomExercise(
      entry.id, name: "Lever row", attribution: try #require(CustomAttribution(primary: .upperBack)))

    #expect(updated.modality == .cable)
    #expect(updated.primaryMuscle.storedValue == "upperBack")
  }

  @Test("A curated movement cannot be retagged")
  func updateRefusesCurated() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed([legPress], now: now)
    let curated = try #require(try seeder.selectableExercises().first { $0.isCurated })
    let attribution = try #require(CustomAttribution(primary: .chest))

    #expect(throws: CatalogSeederError.curatedNotEditable) {
      try seeder.updateCustomExercise(curated.id, name: "Mine now", attribution: attribution)
    }
    let after = try #require(try seeder.selectableExercises().first { $0.id == curated.id })
    #expect(after.name == "Leg Press")
    #expect(after.primaryMuscle.storedValue == "quadriceps")
  }

  @Test("Renaming onto another live movement's name is refused, ignoring case")
  func updateRefusesDuplicateName() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    _ = try seeder.createCustomExercise(named: "Lever Row", now: now)
    let other = try seeder.createCustomExercise(named: "Hip Adduction", now: now)
    let attribution = try #require(CustomAttribution(primary: .lats))

    #expect(throws: CatalogSeederError.duplicateName) {
      try seeder.updateCustomExercise(other.id, name: "lever row", attribution: attribution)
    }
    // Keeping its own name, in another case, is not a duplicate of itself.
    let renamed = try seeder.updateCustomExercise(
      other.id, name: "hip adduction", attribution: attribution)
    #expect(renamed.name == "hip adduction")
  }

  @Test("A blank name, or a movement that is not there, is refused")
  func updateRefusesBlankAndMissing() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let entry = try seeder.createCustomExercise(named: "Lever row", now: now)
    let attribution = try #require(CustomAttribution(primary: .lats))

    #expect(throws: CatalogSeederError.blankName) {
      try seeder.updateCustomExercise(entry.id, name: "  ", attribution: attribution)
    }
    #expect(throws: CatalogSeederError.notFound) {
      try seeder.updateCustomExercise(ExerciseID(), name: "Ghost", attribution: attribution)
    }
  }

  @Test("Sets already logged on a movement are counted once it is tagged")
  func volumeCountsNewlyTaggedMovement() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let store = LoggerStore(database: database)
    let volume = VolumeStore(database: database)
    let entry = try seeder.createCustomExercise(named: "Lever row", now: now)
    let session = try store.startSession(at: now)
    for ordinal in 0..<3 {
      _ = try store.logSet(
        sessionID: session, exerciseID: entry.id,
        draft: SetEntryDraft(weightKg: 40, reps: 10), setOrdinal: ordinal,
        at: now.addingTimeInterval(Double(ordinal + 1) * 60))
    }
    try store.finishSession(session, at: now.addingTimeInterval(1_800))
    let window = (from: now.addingTimeInterval(-3_600), to: now.addingTimeInterval(3_600))
    let before = try volume.report(from: window.from, to: window.to)
    #expect(before.unattributedHardSets == 3)
    #expect(before.sets(for: .lats) == 0)

    _ = try seeder.updateCustomExercise(
      entry.id, name: "Lever row",
      attribution: try #require(CustomAttribution(primary: .lats, secondary: [.biceps])))

    let after = try volume.report(from: window.from, to: window.to)
    #expect(after.unattributedHardSets == 0)
    #expect(after.sets(for: .lats) == 3)
    #expect(after.sets(for: .biceps) == 1.5)
  }

  /// A movement the lifter just wrote belongs where they will look for it: first in their own
  /// group, newest first. Filing it alphabetically hid it below older creations.
  @Test("Newest user-created movements sort first")
  func newestCustomMovementFirst() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    _ = try seeder.createCustomExercise(named: "Zercher Squat", now: now)
    _ = try seeder.createCustomExercise(named: "Alpha Raise", now: now.addingTimeInterval(60))

    #expect(try seeder.selectableExercises().map(\.name) == ["Alpha Raise", "Zercher Squat"])
  }
}
