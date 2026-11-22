import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// A workout import creates movements with no body part and no equipment. The Library is the only
/// place either can be given, so these tests hold that an imported movement can be described there,
/// that describing it changes what Progress and Volume say, and that it is still never offered for
/// logging today's sets.
@Suite("An imported movement can be described like any other, and still is not loggable")
struct ImportedMovementTests {
  private let utc = TimeZone(secondsFromGMT: 0)!
  private let importedName = "Bench Press (Barbell) (Imported • Strong)"

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// A Strong export of one movement, one set on each of the given days.
  private func strongCSV(_ movement: String = "Bench Press (Barbell)", days: [String]) -> String {
    "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n"
      + days.map { "\($0) 10:00:00,Push,1h,\(movement),1,100,5\n" }.joined()
  }

  private func importCSV(_ database: any DatabaseWriter, _ csv: String) async throws {
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms, timeZone: utc)
    _ = try await DataTransferStore(database: database).commit(preview)
  }

  private func importedEntry(_ seeder: CatalogSeeder) throws -> CatalogEntry {
    try #require(try seeder.libraryExercises().first { $0.isImported })
  }

  @Test("The Library lists an imported movement and says it was imported; the picker still does not")
  func libraryListsImportedMovements() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01"]))
    let own = try seeder.createCustomExercise(named: "Pendulum squat")

    let library = try seeder.libraryExercises()
    let imported = try importedEntry(seeder)

    #expect(imported.name == importedName)
    #expect(imported.isUnattributed)
    #expect(imported.modality == nil)
    #expect(Set(library.map(\.id)) == [imported.id, own.id])
    #expect(!own.isImported)
    // The picker, search and recent list are for logging today's sets, which an imported copy
    // beside the catalogue's own entry would let a lifter do and earn no volume for.
    #expect(try seeder.selectableExercises().map(\.id) == [own.id])
    #expect(try seeder.search("bench").isEmpty)
    #expect(try seeder.recent(limit: 5).isEmpty)
  }

  @Test("Archived movements stay out of the Library, imported or not")
  func libraryLeavesOutArchived() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01"]))
    let imported = try importedEntry(seeder)
    try await database.write { db in
      try Exercise.where { $0.id.eq(imported.id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }

    #expect(try seeder.libraryExercises().isEmpty)
  }

  @Test("Giving an imported movement a body part keeps its name, its provenance and its equipment unknown")
  func retaggingKeepsWhatItShould() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01"]))
    let imported = try importedEntry(seeder)
    let notesBefore = try await database.read { db in
      try #require(try Exercise.where { $0.id.eq(imported.id.rawValue) }.fetchOne(db)).notes
    }

    let updated = try seeder.updateCustomExercise(
      imported.id, name: imported.name,
      attribution: try #require(CustomAttribution(primary: .chest, secondary: [.triceps])))

    #expect(updated.id == imported.id)
    #expect(updated.name == importedName)
    #expect(updated.isImported)
    #expect(updated.primaryMuscle.storedValue == "chest")
    #expect(updated.contributions.map(\.key.storedValue).sorted() == ["chest", "triceps"])
    // No equipment was named, so none was declared: the estimate stays unavailable.
    #expect(updated.modality == nil)
    let row = try await database.read { db in
      try #require(try Exercise.where { $0.id.eq(imported.id.rawValue) }.fetchOne(db))
    }
    #expect(row.modality == "unknown")
    #expect(row.notes == notesBefore)
    #expect(!row.isCurated)
    // Described, not made loggable.
    #expect(try seeder.selectableExercises().isEmpty)
    #expect(try seeder.search("bench").isEmpty)
  }

  @Test("An imported movement cannot be renamed, and a refused rename writes nothing")
  func importedNameCannotChange() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01"]))
    let imported = try importedEntry(seeder)
    let attribution = try #require(CustomAttribution(primary: .chest, modality: .barbell))

    #expect(throws: CatalogSeederError.importedNotRenamable) {
      try seeder.updateCustomExercise(imported.id, name: "Bench Press", attribution: attribution)
    }

    let after = try importedEntry(seeder)
    #expect(after.name == importedName)
    #expect(after.isUnattributed)
    #expect(after.modality == nil)
    // Its own name in another case is the same name, kept exactly as stored.
    let same = try seeder.updateCustomExercise(
      imported.id, name: importedName.uppercased(), attribution: attribution)
    #expect(same.name == importedName)
  }

  @Test("A curated movement and a missing one are still refused")
  func curatedAndMissingStillRefused() throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed()
    let curated = try #require(try seeder.libraryExercises().first { $0.isCurated })
    let attribution = try #require(CustomAttribution(primary: .chest))

    #expect(throws: CatalogSeederError.curatedNotEditable) {
      try seeder.updateCustomExercise(curated.id, name: curated.name, attribution: attribution)
    }
    #expect(throws: CatalogSeederError.notFound) {
      try seeder.updateCustomExercise(ExerciseID(), name: "Ghost", attribution: attribution)
    }
  }

  @Test("Tagging an imported movement files it under its body part and credits its sets to Volume")
  func taggingChangesWhatProgressAndVolumeSay() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01", "2026-09-03"]))
    let imported = try importedEntry(seeder)
    let window = (
      from: ISO8601DateFormatter().date(from: "2026-08-31T00:00:00Z")!,
      to: ISO8601DateFormatter().date(from: "2026-09-10T00:00:00Z")!)
    let volume = VolumeStore(database: database)

    let before = try volume.report(from: window.from, to: window.to)
    #expect(before.unattributedHardSets == 2)
    #expect(before.sets(for: .chest) == 0)
    let boardBefore = try await ProgressBoardStore(database: database).loadBoard()
    #expect(boardBefore.sections.map(\.category) == [nil])

    _ = try seeder.updateCustomExercise(
      imported.id, name: imported.name,
      attribution: try #require(CustomAttribution(primary: .chest)))

    let after = try volume.report(from: window.from, to: window.to)
    #expect(after.unattributedHardSets == 0)
    #expect(after.sets(for: .chest) == 2)
    let boardAfter = try await ProgressBoardStore(database: database).loadBoard()
    #expect(boardAfter.sections.map(\.category) == [.chest])
    #expect(boardAfter.sections.first?.rows.first?.exerciseName == importedName)
  }

  @Test("A later import of the same movement continues the tagged one instead of starting another")
  func laterImportKeepsTheTags() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01"]))
    let imported = try importedEntry(seeder)
    _ = try seeder.updateCustomExercise(
      imported.id, name: imported.name,
      attribution: try #require(CustomAttribution(primary: .chest, modality: .barbell)))

    // Strong exports the whole history every time, so the next file repeats the first workout.
    try await importCSV(database, strongCSV(days: ["2026-09-01", "2026-09-08"]))

    let library = try seeder.libraryExercises()
    #expect(library.count == 1)
    #expect(library.first?.id == imported.id)
    #expect(library.first?.primaryMuscle.storedValue == "chest")
    #expect(library.first?.modality == .barbell)
    let sets = try await database.read { db in
      try LoggedSet.where { $0.exerciseID.eq(imported.id.rawValue) }.fetchAll(db).count
    }
    #expect(sets == 2)
  }

  @Test("After the last import is undone its movements stay in the Library, tags and all, as the dialog says")
  func undoLeavesTheMovementsAndTheirTags() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let transfer = DataTransferStore(database: database)
    try await importCSV(database, strongCSV(days: ["2026-09-01"]))
    let imported = try importedEntry(seeder)
    _ = try seeder.updateCustomExercise(
      imported.id, name: imported.name,
      attribution: try #require(CustomAttribution(primary: .chest, modality: .barbell)))
    let undo = try #require(try await transfer.lastImportUndo())

    #expect(undo.confirmationMessage.contains("The movements it created stay in Library"))
    #expect(undo.confirmationMessage.contains("with any body part or equipment you gave them"))
    #expect(undo.confirmationMessage.hasSuffix("This cannot be undone."))
    try await transfer.undoLastImport(undo)

    let sets = try await database.read { try LoggedSet.fetchAll($0).count }
    #expect(sets == 0)
    let kept = try #require(try seeder.libraryExercises().first { $0.id == imported.id })
    #expect(kept.isImported)
    #expect(kept.primaryMuscle.storedValue == "chest")
    #expect(kept.modality == .barbell)
  }
}
