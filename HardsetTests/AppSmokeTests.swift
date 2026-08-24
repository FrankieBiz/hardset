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
  /// Proves the app module builds, links, and exposes its entry point.
  ///
  /// It used to construct `RootView()`. That could never have compiled: `RootView` is `private` to
  /// `HardsetApp.swift`, so `@testable import` cannot see it, and it takes a sync delegate and a rest
  /// timer with no defaults. The target has therefore never been buildable -- which is also why
  /// nothing caught it, since the package suite runs on the host and never touches this target.
  ///
  /// Kept to the entry point deliberately. Anything with behaviour worth asserting belongs in
  /// `Packages/HardsetKit`, where it runs in milliseconds without a simulator.
  @Test("The app module links and exposes its entry point")
  func appEntryPointExists() {
    #expect(HardsetApp.self == HardsetApp.self)
  }
}
