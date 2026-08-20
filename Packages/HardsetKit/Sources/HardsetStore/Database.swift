import Foundation
import SQLiteData

/// Database and sync wiring.
// `nonisolated` is deliberate. This module defaults to MainActor isolation, which is right
// for view-facing types and wrong for this: schema work runs on GRDB's database queues and
// these declarations are pure. Isolating them to the main actor would both mislead and
// force every caller -- including the test suite -- to hop actors for no reason.
public nonisolated enum HardsetDatabase {
  /// Opens the on-disk database and runs migrations.
  ///
  /// Must be called exactly once per process, from `App.init()`.
  public static func open(containerIdentifier: String? = nil) throws -> any DatabaseWriter {
    var configuration = Configuration()
    // Required for ON DELETE CASCADE / SET NULL to actually fire.
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
      // Attaches SQLiteData's sync metadatabase under the `sqlitedata_icloud` schema.
      try db.attachMetadatabase(containerIdentifier: containerIdentifier)
    }

    // Spelled with the module prefix on purpose: inside a `DependencyValues` extension the
    // bare name resolves to the dependency property instead of this function.
    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    return database
  }

  /// Constructs the sync engine with the account-change delegate installed.
  ///
  /// The `delegate:` argument is not optional here even though SQLiteData's parameter
  /// defaults to `nil`, because that default is what erases local data on sign-out. Making it
  /// a required argument of our own wrapper is the cheapest possible guard against the
  /// most expensive mistake in the codebase.
  ///
  /// `bodyweightEntries` is deliberately absent from the synchronized set -- see
  /// `HardsetMigrations.deferredSyncTableNames` for why.
  ///
  /// ## The returned engine MUST be retained for the process lifetime
  ///
  /// This is not a style preference. `SyncEngine` installs triggers on every synchronized table
  /// that call `sqlitedata_icloud_didUpdate`, and that SQL function is an instance method on the
  /// engine, held weakly to break a retain cycle. Drop the engine and the triggers survive with a
  /// dead function behind them, so the next INSERT into ANY synchronized table fails with
  /// `_DatabaseFunctionDeallocated`.
  ///
  /// That is exactly what shipped: the result was discarded, the engine deallocated at the end of
  /// the launch task, and from then on the app could not write a gym, a machine, a session or a
  /// set. Nothing surfaced it, because the failure is a thrown error inside a trigger and every
  /// caller used `try?`. `@discardableResult` is therefore deliberately absent -- ignoring the
  /// return value is now a compiler warning.
  /// - Parameter containerIdentifier: Pass `nil` in production to use the container from the
  ///   entitlement. Tests pass a unique identifier so each gets its own metadatabase -- the
  ///   metadatabase path derives from this, and sharing one across parallel tests deadlocks
  ///   SQLite.
  public static func makeSyncEngine(
    for database: any DatabaseWriter,
    delegate: HardsetSyncDelegate,
    containerIdentifier: String? = nil
  ) throws -> SyncEngine {
    try SyncEngine(
      for: database,
      tables: Exercise.self,
      Gym.self,
      Machine.self,
      MachineExercise.self,
      Session.self,
      SessionExercise.self,
      LoggedSet.self,
      containerIdentifier: containerIdentifier,
      delegate: delegate
    )
  }
}
