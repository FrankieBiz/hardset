import Testing

@testable import Hardset

/// The app target's own suite.
///
/// It is deliberately thin: the engine, store and schema suites live in the HardsetKit package
/// where they run on the host in milliseconds without a simulator. This target exists for the
/// things that genuinely need an app bundle -- and for now, to prove the target graph builds
/// and links.
@Suite("App target builds and links")
struct AppSmokeTests {
  /// Names the entry point rather than constructing a view. The root view is private to the app
  /// file and takes the database and rest timer, so `RootView()` here stopped compiling when
  /// startup gained its own resources; the target's purpose -- proving the graph builds and
  /// links -- only needs the app type itself.
  @Test("The app's entry point links")
  func appEntryPointLinks() {
    _ = HardsetApp.self
  }
}
