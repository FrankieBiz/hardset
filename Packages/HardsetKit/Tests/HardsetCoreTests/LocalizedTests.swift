import Foundation
import Testing

@testable import HardsetCore

@Suite("Core copy goes through one door, and comes out as the same English on every platform")
struct LocalizedTests {
  @Test("A fixed sentence comes back as written")
  func fixed() {
    #expect(localized("Not evaluated", comment: "test") == "Not evaluated")
  }

  @Test("Interpolated words and counts come back in place")
  func interpolated() {
    let count = 3
    let total = 5
    #expect(localized("\(count) of \(total) logged", comment: "test") == "3 of 5 logged")
    let name = "Leg Press, 50%"
    #expect(localized("New record on \(name).", comment: "test") == "New record on Leg Press, 50%.")
  }

  @Test("A keyed lookup falls back to its English")
  func keyed() {
    #expect(localized(key: "muscle.chest", default: "Chest", comment: "test") == "Chest")
  }

  @Test("The catalog is valid, in English, and ships with Core")
  func catalog() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/HardsetCore/Resources/Localizable.xcstrings")
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    let catalog = try #require(object as? [String: Any])
    #expect(catalog["sourceLanguage"] as? String == "en")
    #expect(catalog["version"] as? String == "1.0")
    #expect(catalog["strings"] is [String: Any])
  }
}
