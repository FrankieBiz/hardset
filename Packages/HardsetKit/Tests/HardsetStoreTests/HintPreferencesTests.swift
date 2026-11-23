import Foundation
import Testing

@testable import HardsetStore

/// A hint is said once. These hold the half of that promise the store owns: what was seen stays
/// seen across a relaunch, and nothing is seen that was not marked.
@Suite("A hint is shown once and then stays spent")
@MainActor
struct HintPreferencesTests {
  /// A private suite per test, removed afterwards, so nothing leaks into the real defaults or
  /// between tests.
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let name = "hardset.tests.hints.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
  }

  @Test("A fresh install has seen no hint")
  func nothingSeen() throws {
    try withDefaults { defaults in
      let hints = HintPreferences(defaults: defaults)
      for hint in HintPreferences.Hint.allCases {
        #expect(!hints.hasSeen(hint))
      }
    }
  }

  @Test("A hint that was drawn stays spent, including in a new instance on the same store")
  func seenStaysSeen() throws {
    try withDefaults { defaults in
      HintPreferences(defaults: defaults).markSeen(.correctSavedSet)
      #expect(HintPreferences(defaults: defaults).hasSeen(.correctSavedSet))

      // Marking again changes nothing: drawing the line twice in one session is harmless.
      HintPreferences(defaults: defaults).markSeen(.correctSavedSet)
      #expect(HintPreferences(defaults: defaults).hasSeen(.correctSavedSet))
    }
  }

  @Test("Every hint has its own namespaced key")
  func keysAreDistinct() {
    let keys = HintPreferences.Hint.allCases.map(HintPreferences.key(for:))
    #expect(Set(keys).count == keys.count)
    #expect(keys.allSatisfy { $0.hasPrefix("hardset.hint.seen.") })
  }
}
