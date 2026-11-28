import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The Library reads native working sets apart from imported ones")
struct LibraryUsageStoreTests {
  let now = ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z")!

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// Seeds the shipped catalogue, so these run against real movements rather than a fixture.
  private func seeded() throws -> (any DatabaseWriter, CatalogSeeder, LoggerStore) {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(now: now)
    return (database, seeder, LoggerStore(database: database))
  }

  private func exerciseID(_ database: any DatabaseWriter, slug: String) throws -> ExerciseID {
    let row = try database.read { db in
      try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(db)
    }
    return ExerciseID(rawValue: try #require(row).id)
  }

  /// Opens a session, optionally with notes such as the import marker.
  private func startSession(
    _ logger: LoggerStore, in database: any DatabaseWriter, notes: String? = nil
  ) throws -> SessionID {
    let session = try logger.startSession(at: now.addingTimeInterval(-90 * 86_400))
    if let notes {
      try database.write { db in
        try Session.where { $0.id.eq(session.rawValue) }
          .update { $0.notes = #bind(notes) }
          .execute(db)
      }
    }
    return session
  }

  private func log(
    _ store: LoggerStore, _ session: SessionID, _ exercise: ExerciseID,
    sets: Int, at date: Date, isWarmup: Bool = false
  ) throws {
    for index in 0..<sets {
      try store.logSet(
        sessionID: session, exerciseID: exercise,
        draft: SetEntryDraft(weightKg: 100, reps: 8),
        isWarmup: isWarmup, at: date.addingTimeInterval(Double(index) * 60)
      )
    }
  }

  @Test("Warm-ups are excluded and the newest working set is the last done")
  func nativeWorkingSetsExcludeWarmups() throws {
    let (database, seeder, logger) = try seeded()
    let squat = try exerciseID(database, slug: "barbell-back-squat")
    let session = try startSession(logger, in: database)
    let base = now.addingTimeInterval(-3 * 3_600)
    try log(logger, session, squat, sets: 3, at: base)
    try log(logger, session, squat, sets: 1, at: now, isWarmup: true)

    let usage = try #require(try seeder.libraryUsage(asOf: now)[squat])
    #expect(usage.workingSets == 3)
    #expect(usage.importedSets == 0)
    #expect(usage.lastDoneAt == base.addingTimeInterval(120))
  }

  @Test("Imported-only history counts no working sets and claims no last done")
  func importedOnly() throws {
    let (database, seeder, logger) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try startSession(
      logger, in: database, notes: "Imported from Strong • 2026-01-01")
    try log(logger, session, bench, sets: 2, at: now.addingTimeInterval(-2 * 86_400))

    let usage = try #require(try seeder.libraryUsage(asOf: now)[bench])
    #expect(usage.workingSets == 0)
    #expect(usage.importedSets == 2)
    #expect(usage.lastDoneAt == nil)
  }

  @Test("Native and imported sets on one movement keep their own counts and native date")
  func mixedNativeAndImported() throws {
    let (database, seeder, logger) = try seeded()
    let squat = try exerciseID(database, slug: "barbell-back-squat")
    let nativeSession = try startSession(logger, in: database)
    let nativeBase = now.addingTimeInterval(-4 * 86_400)
    try log(logger, nativeSession, squat, sets: 2, at: nativeBase)
    let importedSession = try startSession(
      logger, in: database, notes: "Imported from Strong • 2026-01-01")
    // Newer than every native set, to prove the date never comes from imported history.
    try log(logger, importedSession, squat, sets: 3, at: now.addingTimeInterval(-86_400))

    let usage = try #require(try seeder.libraryUsage(asOf: now)[squat])
    #expect(usage.workingSets == 2)
    #expect(usage.importedSets == 3)
    #expect(usage.lastDoneAt == nativeBase.addingTimeInterval(60))
  }

  @Test("A future-dated set is counted but never in last done (D31)")
  func futureDatedSets() throws {
    let (database, seeder, logger) = try seeded()
    let squat = try exerciseID(database, slug: "barbell-back-squat")
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try startSession(logger, in: database)
    let past = now.addingTimeInterval(-3_600)
    try log(logger, session, squat, sets: 1, at: past)
    try log(logger, session, squat, sets: 1, at: now.addingTimeInterval(2 * 86_400))
    try log(logger, session, bench, sets: 1, at: now.addingTimeInterval(2 * 86_400))

    let usage = try seeder.libraryUsage(asOf: now)
    let squatUsage = try #require(usage[squat])
    #expect(squatUsage.workingSets == 2)
    #expect(squatUsage.lastDoneAt == past)
    let benchUsage = try #require(usage[bench])
    #expect(benchUsage.workingSets == 1)
    #expect(benchUsage.lastDoneAt == nil)
  }

  @Test("An empty history has no entries, including movements that exist but hold no sets")
  func emptyHistory() throws {
    let (database, seeder, _) = try seeded()
    let squat = try exerciseID(database, slug: "barbell-back-squat")
    let usage = try seeder.libraryUsage(asOf: now)
    #expect(usage.isEmpty)
    #expect(usage[squat] == nil)
  }

  @Test("Only notes that begin 'Imported from ' mark a session imported")
  func importedPrefixIsExact() throws {
    let (database, seeder, logger) = try seeded()
    let squat = try exerciseID(database, slug: "barbell-back-squat")
    // "Imported from " appears, but not at the start: this is the lifter's own session.
    let native = try startSession(
      logger, in: database, notes: "Backfilled: Imported from a paper log")
    try log(logger, native, squat, sets: 2, at: now.addingTimeInterval(-2 * 86_400))
    let imported = try startSession(
      logger, in: database, notes: "Imported from Strong • 2026-01-01")
    try log(logger, imported, squat, sets: 1, at: now.addingTimeInterval(-86_400))

    let usage = try #require(try seeder.libraryUsage(asOf: now)[squat])
    #expect(usage.workingSets == 2)
    #expect(usage.importedSets == 1)
    #expect(usage.lastDoneAt == now.addingTimeInterval(-2 * 86_400 + 60))
  }
}
