import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

@Suite("A rest choice is remembered per exercise, on this device")
struct RestPreferencesTests {
  private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "hardset.tests.\(UUID().uuidString)")!
  }

  @Test("Nothing chosen reads as nil, not as a default")
  func nothingChosen() {
    let store = UserDefaultsRestPreferences(defaults: freshDefaults())
    #expect(store.rest(for: ExerciseID()) == nil)
  }

  @Test("A choice round-trips and is per exercise")
  func roundTrip() {
    let defaults = freshDefaults()
    let a = ExerciseID(), b = ExerciseID()
    UserDefaultsRestPreferences(defaults: defaults).setRest(.seconds(150), for: a)
    let reread = UserDefaultsRestPreferences(defaults: defaults)
    #expect(reread.rest(for: a) == .seconds(150))
    #expect(reread.rest(for: b) == nil)
  }

  @Test("Turning rest off forgets the choice")
  func offForgets() {
    let store = UserDefaultsRestPreferences(defaults: freshDefaults())
    let a = ExerciseID()
    store.setRest(.seconds(90), for: a)
    store.setRest(nil, for: a)
    #expect(store.rest(for: a) == nil)
  }
}
