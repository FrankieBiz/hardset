import CloudKit
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import HardsetStore

/// Blocker 1: iCloud sign-out must not erase local data.
///
/// ## Why these tests are behavioural rather than structural
///
/// The brief asked for "a test asserting the delegate is installed". That test cannot be
/// written, and would not be worth much if it could:
///
/// * `SyncEngine.delegate` is an internal, non-`public` `let` (SyncEngine.swift:37), so there
///   is no public API to read it back and assert on it.
/// * More importantly, installing a delegate is *not sufficient*. `SyncEngineDelegate` ships a
///   default implementation of `syncEngine(_:accountChanged:)` that calls
///   `deleteLocalData()`, and Swift supplies that default silently when a conformance omits
///   the method -- no warning, no error. A structural "is a delegate present?" assertion would
///   pass while the data was still being destroyed.
///
/// So the property under test is the one that matters: after a sign-out event, the rows are
/// still there.
@Suite("Signing out of iCloud preserves local data", .serialized)
struct SyncDelegateTests {
  /// A unique container per test. The metadatabase path derives from this identifier, so
  /// sharing one across tests makes them fight over the same SQLite file.
  private func uniqueContainer() -> String { "iCloud.hardset.tests.\(UUID().uuidString)" }

  /// Builds a migrated in-memory database.
  ///
  /// `DatabaseQueue()` is constructed directly rather than via `defaultDatabase()`, which
  /// returns a temp-file `DatabasePool` even in test contexts.
  private func migratedDatabase(container: String) throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    // Deliberately NOT calling `attachMetadatabase` here, unlike production.
    //
    // In a non-live context `SyncEngine.init` prepares its own in-memory metadatabase at
    // `file:sqlitedata_icloud?mode=memory&cache=shared`, and attaching one in
    // `prepareDatabase` as well throws `.metadatabaseMismatch`. SQLiteData's own suite
    // suppresses the attach with a `package` task local (`$attachMetadatabase.set(false)`)
    // that is not reachable from outside the package, so the equivalent here is simply to
    // let the engine do the attaching.
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seed(_ database: any DatabaseWriter) throws {
    try database.write { db in
      try Gym.insert { Gym.Draft(id: UUID(), name: "Test Gym") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: UUID(), name: "Incline Press") }.execute(db)
    }
  }

  private func counts(_ database: any DatabaseWriter) throws -> (gyms: Int, exercises: Int) {
    try database.read { db in
      (
        try Gym.count().fetchOne(db) ?? -1,
        try Exercise.count().fetchOne(db) ?? -1
      )
    }
  }

  private var previousUser: CKRecord.ID { CKRecord.ID(recordName: "previousUser") }
  private var currentUser: CKRecord.ID { CKRecord.ID(recordName: "currentUser") }

  @Test("Our delegate keeps every local row when the user signs out")
  func signOutPreservesData() async throws {
    try await withDependencies {
      $0.context = .test
    } operation: {
      let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
      try seed(database)
      let delegate = HardsetSyncDelegate()
      let engine = try HardsetDatabase.makeSyncEngine(
          for: database, delegate: delegate, containerIdentifier: container)

      let before = try counts(database)
      #expect(before.gyms == 1)
      #expect(before.exercises == 1)

      await delegate.syncEngine(engine, accountChanged: .signOut(previousUser: previousUser))

      let after = try counts(database)
      #expect(after.gyms == 1, "sign-out deleted gyms -- the account-change override is gone")
      #expect(after.exercises == 1, "sign-out deleted exercises -- the override is gone")
    }
  }

  @Test("Our delegate keeps every local row when the user switches accounts")
  func switchAccountsPreservesData() async throws {
    try await withDependencies {
      $0.context = .test
    } operation: {
      let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
      try seed(database)
      let delegate = HardsetSyncDelegate()
      let engine = try HardsetDatabase.makeSyncEngine(
          for: database, delegate: delegate, containerIdentifier: container)

      await delegate.syncEngine(
        engine,
        accountChanged: .switchAccounts(previousUser: previousUser, currentUser: currentUser)
      )

      let after = try counts(database)
      #expect(after.gyms == 1)
      #expect(after.exercises == 1)
    }
  }

  @Test("The account change is surfaced so the app can tell the user")
  func accountChangeIsReported() async throws {
    try await withDependencies {
      $0.context = .test
    } operation: {
      let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
      let delegate = HardsetSyncDelegate()
      let engine = try HardsetDatabase.makeSyncEngine(
          for: database, delegate: delegate, containerIdentifier: container)

      #expect(delegate.lastChange == nil)
      await delegate.syncEngine(engine, accountChanged: .signOut(previousUser: previousUser))
      #expect(delegate.lastChange == .signedOut)

      await delegate.syncEngine(engine, accountChanged: .signIn(currentUser: currentUser))
      #expect(delegate.lastChange == .signedIn)
    }
  }

  /// A canary for the library's default behaviour, not a test of our code.
  ///
  /// `EmptyDelegate` conforms to `SyncEngineDelegate` without implementing anything, which is
  /// exactly the mistake this whole file exists to prevent. If this test ever *fails* -- that
  /// is, if the rows survive -- then upstream has changed its default and the guard in
  /// `HardsetSyncDelegate` can be reconsidered. Until then it documents why the guard is
  /// needed, with executable evidence rather than a comment.
  @Test(
    "Canary: the library's default delegate really does erase local data",
    .disabled(
      """
      Cannot run under `swift test` on the host. `deleteLocalData()` throws       `.metadatabaseMismatch` because a non-live `SyncEngine` prepares an in-memory       metadatabase at a fixed shared-cache path, and nothing outside the package can reset it       between constructions. Kept as source because it documents the exact failure mode the       override exists to prevent; run it on device, or against a package fork with       `$attachMetadatabase` exposed, to close the gap.
      """
    )
  )
  func defaultDelegateErasesData() async throws {
    final class EmptyDelegate: SyncEngineDelegate {}

    try await withDependencies {
      $0.context = .test
    } operation: {
      let container = uniqueContainer()
      let database = try migratedDatabase(container: container)
      try seed(database)
      let delegate = EmptyDelegate()
      // Constructed directly rather than through `HardsetDatabase.makeSyncEngine`, whose
      // `delegate:` parameter is deliberately typed to `HardsetSyncDelegate` so production
      // code cannot install a delegate that lacks the override.
      let engine = try SyncEngine(
        for: database,
        tables: Exercise.self,
        Gym.self,
        Machine.self,
        MachineExercise.self,
        Session.self,
        SessionExercise.self,
        LoggedSet.self,
        containerIdentifier: container,
        delegate: delegate
      )

      #expect(try counts(database).gyms == 1)

      await delegate.syncEngine(engine, accountChanged: .signOut(previousUser: previousUser))

      let after = try counts(database)
      #expect(
        after.gyms == 0 && after.exercises == 0,
        """
        The default SyncEngineDelegate implementation no longer erases local data on sign-out. \
        Re-read SyncEngineDelegate.swift before relying on this.
        """
      )
    }
  }
}
