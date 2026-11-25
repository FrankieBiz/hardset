import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The muscle-history sheet's read, as the sheet drives it: one `SnapshotLoader` read, re-run when
/// the purchase gate opens the sheet and again from the failure state's "Try again".
///
/// What the purchase itself does cannot be proven here: no test on this host can complete a
/// StoreKit purchase, and the sheet's `.task(id:)` is SwiftUI runtime behaviour. These pin the two
/// halves underneath it — a repeated read returns the same figures, and a read that genuinely
/// fails is reported as a failure rather than as an empty history.
@Suite("The muscle-history sheet can read again and fails honestly")
struct MuscleHistorySheetReadTests {
  /// A Thursday, so every seeded set falls inside the window the sheet reads.
  let now = ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z")!

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  @Test("Reading again returns the same figures, with no failure")
  @MainActor
  func repeatedReadIsIdempotent() async throws {
    let database = try migratedDatabase()
    try CatalogSeeder(database: database).seed(now: now)
    let row = try await database.read { db in
      try Exercise.where { $0.catalogSlug.eq("barbell-bench-press") }.fetchOne(db)
    }
    let bench = try #require(row)
    let logger = LoggerStore(database: database)
    let session = try logger.startSession(at: now.addingTimeInterval(-86_400))
    for index in 0..<3 {
      _ = try logger.logSet(
        sessionID: session, exerciseID: ExerciseID(rawValue: bench.id),
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: index,
        at: now.addingTimeInterval(-86_400 + Double(index) * 60))
    }
    try logger.finishSession(session, at: now)

    let store = MuscleHistoryStore(database: database)
    let loader = SnapshotLoader<MuscleHistoryReading>()
    await loader.load { try await store.load(endingAt: now) }
    let first = try #require(loader.value)
    #expect(!loader.loadFailed)
    #expect(first.history.lifetimeSets(for: .chest) == 3)

    // The retry path: the same read, on the same loader, a second time.
    await loader.load { try await store.load(endingAt: now) }
    #expect(!loader.loadFailed)
    let second = try #require(loader.value)
    #expect(second.history.lifetimeSets(for: .chest) == first.history.lifetimeSets(for: .chest))
    #expect(second.history.currentSets(for: .chest) == first.history.currentSets(for: .chest))
    #expect(second.exerciseNames == first.exerciseNames)
  }

  @Test("A failed read is a failure with no value, and retrying recovers")
  @MainActor
  func failedReadSurfacesAndRecovers() async throws {
    // A database without the app's migrations: the sheet's own read throws rather than returning a
    // reading with nothing in it.
    let database = try DatabaseQueue()
    let store = MuscleHistoryStore(database: database)
    let loader = SnapshotLoader<MuscleHistoryReading>()

    await loader.load { try await store.load(endingAt: now) }
    #expect(loader.loadFailed)
    #expect(loader.value == nil)

    // "Try again" after the cause is fixed: the loader clears the failure and carries the reading.
    try HardsetMigrations.migrator().migrate(database)
    await loader.load { try await store.load(endingAt: now) }
    #expect(!loader.loadFailed)
    #expect(loader.value != nil)
  }
}
