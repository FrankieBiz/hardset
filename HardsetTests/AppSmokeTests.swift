import HardsetFeature
import HardsetStore
// For `DatabaseQueue`, which SQLiteData re-exports from GRDB. The app target reaches GRDB the same
// way, so this adds no module the app does not already import.
import SQLiteData
import Testing

/// The app target's own suite.
///
/// It is deliberately thin: the engine, store and schema suites live in the HardsetKit package
/// where they run on the host in milliseconds without a simulator. This target exists for the
/// things that genuinely need an app bundle -- and for now, to prove the target graph builds
/// and links.
///
/// The app's own `RootView` is private and needs a live sync delegate and rest timer, so the test
/// builds what it wraps: `HardsetRootView` over a migrated, empty, in-memory database.
@Suite("App target builds and links")
@MainActor
struct AppSmokeTests {
  @Test("The root view is constructible against a migrated database")
  func rootViewExists() throws {
    let queue = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(queue)
    _ = HardsetRootView(environment: HardsetEnvironment(database: queue))
  }
}
