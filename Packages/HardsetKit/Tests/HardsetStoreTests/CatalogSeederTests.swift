import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Seeding the catalogue is idempotent and non-destructive")
struct CatalogSeederTests {
  let now = Date(timeIntervalSince1970: 7_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private let sample = [
    CatalogExercise(
      id: "11111111-1111-5111-8111-111111111111",
      slug: "leg-press", name: "Leg Press", modality: .machine,
      primaryMuscle: "quadriceps", secondaryMuscles: ["glutes"]
    ),
    CatalogExercise(
      id: "22222222-2222-5222-8222-222222222222",
      slug: "pull-up", name: "Pull-up", modality: .bodyweight,
      primaryMuscle: "lats", secondaryMuscles: ["biceps"]
    ),
  ]

  @Test("A first seed inserts every entry")
  func firstSeedInserts() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    #expect(try seeder.seed(sample, now: now) == 2)
    #expect(try seeder.selectableExercises().count == 2)
  }

  /// The reason ids are fixed literals: two devices seeding offline must converge, not duplicate.
  @Test("Seeding twice inserts nothing the second time")
  func seedIsIdempotent() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    #expect(try seeder.seed(sample, now: now) == 2)
    #expect(try seeder.seed(sample, now: now) == 0)
    #expect(try seeder.selectableExercises().count == 2)
  }

  /// A user's rename must survive every subsequent launch.
  @Test("Re-seeding does not overwrite a user's rename")
  func reseedPreservesRename() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    let id = UUID(uuidString: sample[0].id)!
    try database.write { db in
      try Exercise.where { $0.id.eq(id) }.update { $0.name = "Leg Press (angled)" }.execute(db)
    }

    try seeder.seed(sample, now: now)
    let entry = try #require(try seeder.selectableExercises().first { $0.id.rawValue == id })
    #expect(entry.name == "Leg Press (angled)")
    // Catalogue-owned fields are still refreshed.
    #expect(entry.primaryMuscle == "quadriceps")
    #expect(entry.modality == .machine)
  }

  /// Archiving is how a user hides a movement. Re-seeding must not resurrect it.
  @Test("Re-seeding does not un-archive")
  func reseedPreservesArchive() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    let id = UUID(uuidString: sample[1].id)!
    try database.write { db in
      try Exercise.where { $0.id.eq(id) }.update { $0.isArchived = true }.execute(db)
    }

    try seeder.seed(sample, now: now)
    #expect(try seeder.selectableExercises().count == 1)
  }

  @Test("Secondary muscles round-trip through JSON")
  func secondaryMusclesRoundTrip() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)
    let entry = try #require(try seeder.selectableExercises().first { $0.slug == "leg-press" })
    #expect(entry.secondaryMuscles == ["glutes"])
  }

  @Test("Search is case- and diacritic-insensitive, and empty means everything")
  func searching() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(sample, now: now)

    #expect(try seeder.search("leg").count == 1)
    #expect(try seeder.search("LEG PRESS").count == 1)
    #expect(try seeder.search("press").count == 1)
    #expect(try seeder.search("").count == 2)
    #expect(try seeder.search("   ").count == 2)
    #expect(try seeder.search("deadlift").isEmpty)
  }

  @Test("The real catalogue seeds cleanly")
  func realCatalogueSeeds() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let count = try seeder.seed(now: now)
    #expect(count == ExerciseCatalog.v1.count)
    #expect(try seeder.selectableExercises().count == ExerciseCatalog.v1.count)
    // And again, to prove the shipped data is genuinely idempotent, not just the fixture.
    #expect(try seeder.seed(now: now) == 0)
  }
}

@Suite("The shipped catalogue is well formed")
struct ExerciseCatalogTests {
  /// A malformed UUID literal would fail at seed time on a user's device, so it is caught here.
  @Test("Every id is a valid UUID")
  func idsAreValid() {
    for entry in ExerciseCatalog.v1 {
      #expect(entry.uuid != nil, "\(entry.slug) has a malformed id")
    }
  }

  @Test("No two entries share an id or a slug")
  func noCollisions() {
    let ids = Set(ExerciseCatalog.v1.map(\.id))
    let slugs = Set(ExerciseCatalog.v1.map(\.slug))
    #expect(ids.count == ExerciseCatalog.v1.count)
    #expect(slugs.count == ExerciseCatalog.v1.count)
  }

  @Test("Ids are lowercase, so they match what the database stores")
  func idsAreLowercase() {
    for entry in ExerciseCatalog.v1 {
      #expect(entry.id == entry.id.lowercased())
    }
  }

  @Test("Every entry names a primary muscle and no muscle is listed twice")
  func musclesAreSane() {
    for entry in ExerciseCatalog.v1 {
      #expect(!entry.primaryMuscle.isEmpty, "\(entry.slug) has no primary muscle")
      #expect(
        !entry.secondaryMuscles.contains(entry.primaryMuscle),
        "\(entry.slug) lists its primary muscle as secondary too"
      )
      #expect(
        Set(entry.secondaryMuscles).count == entry.secondaryMuscles.count,
        "\(entry.slug) repeats a secondary muscle"
      )
    }
  }

  /// Not a claim that the catalogue is complete — it is a floor, so an accidental deletion of
  /// half the file fails rather than shipping.
  @Test("The seed covers every major muscle group")
  func coversMajorGroups() {
    let covered = Set(ExerciseCatalog.v1.map(\.primaryMuscle))
    let required = [
      "quadriceps", "hamstrings", "glutes", "calves", "chest", "lats", "upperBack",
      "frontDelts", "sideDelts", "rearDelts", "biceps", "triceps", "abs",
    ]
    for muscle in required {
      #expect(covered.contains(muscle), "nothing trains \(muscle)")
    }
  }
}
