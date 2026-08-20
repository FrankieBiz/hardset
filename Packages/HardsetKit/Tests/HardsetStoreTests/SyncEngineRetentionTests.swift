import CloudKit
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import HardsetStore

/// Blocker: a released `SyncEngine` silently breaks every write.
///
/// The app discarded the engine returned at launch. `SyncEngine` installs triggers on every
/// synchronized table that call `sqlitedata_icloud_didUpdate`, an instance method held weakly to
/// break a retain cycle, so once the engine deallocated the triggers remained with nothing behind
/// them. Every INSERT into a synchronized table then threw `_DatabaseFunctionDeallocated` — no
/// gyms, no machines, no sessions, no sets — and every call site used `try?`, so the app looked
/// like buttons that did nothing.
///
/// The durable guard is the compiler: `makeSyncEngine` is deliberately not `@discardableResult`.
/// This suite exists so the reason is written down as an executable fact rather than a comment
/// someone can delete.
@Suite("A SyncEngine must outlive the writes it enables", .serialized)
struct SyncEngineRetentionTests {
  private func uniqueContainer() -> String { "iCloud.hardset.tests.\(UUID().uuidString)" }

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    // As in `SyncDelegateTests`: the engine attaches its own in-memory metadatabase in a
    // non-live context, so attaching one here as well throws `.metadatabaseMismatch`.
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func insertGym(_ database: any DatabaseWriter) throws {
    try database.write { db in
      try Gym.insert { Gym.Draft(id: UUID(), name: "Iron Works") }.execute(db)
    }
  }

  @Test("A retained engine leaves synchronized tables writable")
  func retainedEngineAllowsWrites() async throws {
    try await withDependencies {
      $0.context = .test
    } operation: {
      let database = try migratedDatabase()
      let delegate = HardsetSyncDelegate()
      let engine = try HardsetDatabase.makeSyncEngine(
        for: database, delegate: delegate, containerIdentifier: uniqueContainer()
      )

      try insertGym(database)
      let count = try database.read { try Gym.count().fetchOne($0) }
      #expect(count == 1)

      // Kept alive to the end of the test on purpose: releasing it here is the bug this suite is
      // about, and `withExtendedLifetime` states that rather than leaving it to ARC's discretion.
      withExtendedLifetime(engine) {}
    }
  }

  @Test("A released engine leaves them unwritable, which is why the app must hold it")
  func releasedEngineBreaksWrites() async throws {
    try await withDependencies {
      $0.context = .test
    } operation: {
      let database = try migratedDatabase()
      let delegate = HardsetSyncDelegate()
      do {
        let engine = try HardsetDatabase.makeSyncEngine(
          for: database, delegate: delegate, containerIdentifier: uniqueContainer()
        )
        try insertGym(database)
        withExtendedLifetime(engine) {}
      }
      // The engine is gone; its triggers are not.
      #expect(throws: (any Error).self) {
        try insertGym(database)
      }
      let count = try database.read { try Gym.count().fetchOne($0) }
      #expect(count == 1, "the second write did not land, which is the whole point")
    }
  }
}
