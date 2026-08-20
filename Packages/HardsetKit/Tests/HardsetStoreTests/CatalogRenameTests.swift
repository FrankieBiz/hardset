import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The catalogue must be able to correct itself without overwriting the user.
@Suite("Catalogue renames versus user renames")
struct CatalogRenameTests {
  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private let id = "3f2b6c1a-0000-4000-8000-000000000001"

  private func entry(named name: String) -> CatalogExercise {
    CatalogExercise(
      id: id, slug: "leg-press", name: name, modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        MuscleContribution(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy)
      ]
    )
  }

  @Test("A corrected catalogue name reaches an install that already seeded")
  func renameReachesExistingInstall() throws {
    let seeder = CatalogSeeder(database: try migratedDatabase())
    #expect(try seeder.seed([entry(named: "Leg Press")]) == 1)
    // Same permanent id, name corrected in a later app version.
    #expect(try seeder.seed([entry(named: "Machine Leg Press")]) == 0)

    let stored = try seeder.selectableExercises()
    #expect(stored.count == 1)
    // Never writing `name` meant two installs disagreed forever about what one movement is
    // called, while their muscles and modality updated normally.
    #expect(stored[0].name == "Machine Leg Press")
  }

  @Test("A user's own rename survives every later seed")
  func userRenameIsNotOverwritten() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    #expect(try seeder.seed([entry(named: "Leg Press")]) == 1)

    try database.write { db in
      try Exercise.where { $0.id.eq(UUID(uuidString: self.id)!) }
        .update { $0.name = #bind("The Sled") }
        .execute(db)
    }
    // Two more launches, one of them carrying a catalogue rename.
    #expect(try seeder.seed([entry(named: "Leg Press")]) == 0)
    #expect(try seeder.seed([entry(named: "Machine Leg Press")]) == 0)

    let stored = try seeder.selectableExercises()
    #expect(stored[0].name == "The Sled")
  }
}
