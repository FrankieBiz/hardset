import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

/// The rest a lifter last chose for a movement is remembered and offered back, and nothing is
/// ever invented in its place.
@Suite("Rest choices are remembered per movement, never invented")
@MainActor
struct RestPreferencesTests {
  /// A private suite per test, removed afterwards, so nothing leaks into the real defaults or
  /// between tests.
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let name = "hardset.tests.rest.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
  }

  @Test("A movement with no remembered rest has none, rather than a default")
  func nothingRemembered() throws {
    try withDefaults { defaults in
      #expect(RestPreferences(defaults: defaults).lastRest(for: ExerciseID()) == nil)
    }
  }

  @Test("The last chosen rest is offered back for that movement only")
  func remembersPerMovement() throws {
    try withDefaults { defaults in
      let press = ExerciseID()
      let curl = ExerciseID()
      let preferences = RestPreferences(defaults: defaults)
      preferences.remember(.seconds(120), for: press)
      #expect(preferences.lastRest(for: press) == .seconds(120))
      #expect(preferences.lastRest(for: curl) == nil)

      // The latest choice wins, and a new value survives a new instance on the same store.
      preferences.remember(.seconds(90), for: press)
      #expect(RestPreferences(defaults: defaults).lastRest(for: press) == .seconds(90))
    }
  }

  @Test("A zero or negative rest is not remembered", arguments: [0.0, -30.0])
  func rejectsNonPositive(seconds: Double) throws {
    try withDefaults { defaults in
      let press = ExerciseID()
      let preferences = RestPreferences(defaults: defaults)
      preferences.remember(.seconds(seconds), for: press)
      #expect(preferences.lastRest(for: press) == nil)
      preferences.remember(.seconds(60), for: press)
      preferences.remember(.seconds(seconds), for: press)
      #expect(preferences.lastRest(for: press) == .seconds(60))
    }
  }

  @Test("A corrupt stored value is ignored rather than offered")
  func ignoresCorruptValue() throws {
    try withDefaults { defaults in
      let press = ExerciseID()
      defaults.set(-5.0, forKey: RestPreferences.key(for: press))
      #expect(RestPreferences(defaults: defaults).lastRest(for: press) == nil)
      defaults.set("ninety", forKey: RestPreferences.key(for: press))
      #expect(RestPreferences(defaults: defaults).lastRest(for: press) == nil)
    }
  }
}
