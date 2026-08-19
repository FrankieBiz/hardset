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
  @Test("The app's root view is constructible")
  func rootViewExists() {
    _ = RootView()
  }
}
