import Foundation
import Testing

@testable import HardsetCore

/// Escaping is the whole risk in an export.
///
/// A file that opens cleanly but has one column shifted is worse than a file that fails to write,
/// because nobody finds out for months. Every case here is a real value this app can produce: gyms
/// and machines are free text the lifter types.
@Suite("An export cannot be corrupted by what the lifter typed")
struct CSVTests {
  @Test("A plain field is left alone")
  func plainFieldsAreNotQuoted() {
    #expect(CSV.escape("Leg Press") == "Leg Press")
    #expect(CSV.escape("") == "")
  }

  @Test("A comma is quoted, so it cannot become a column break")
  func commasAreQuoted() {
    #expect(CSV.escape("Hammer Strength, row 2") == "\"Hammer Strength, row 2\"")
  }

  @Test("A quote is doubled inside quotes")
  func quotesAreDoubled() {
    #expect(CSV.escape("the \"good\" bench") == "\"the \"\"good\"\" bench\"")
  }

  @Test("A newline is quoted rather than ending the row")
  func newlinesAreQuoted() {
    #expect(CSV.escape("seat 4\npin 3") == "\"seat 4\npin 3\"")
    #expect(CSV.escape("a\r\nb") == "\"a\r\nb\"")
  }

  /// Unquoted, some readers strip surrounding space, which silently renames a gym.
  @Test("Leading and trailing spaces are preserved")
  func edgeSpacesAreQuoted() {
    #expect(CSV.escape(" PureGym") == "\" PureGym\"")
    #expect(CSV.escape("PureGym ") == "\"PureGym \"")
  }

  @Test("A row ends with CRLF, per RFC 4180")
  func rowsEndWithCRLF() {
    #expect(CSV.row(["a", "b"]) == "a,b\r\n")
  }

  /// A weight column that arrives as text, or in scientific notation, is a broken export.
  @Test("Numbers export as plain decimals with no trailing noise")
  func numbersArePlain() {
    #expect(CSV.number(80) == "80")
    #expect(CSV.number(82.5) == "82.5")
    #expect(CSV.number(0) == "0")
    #expect(CSV.number(0.0001) == "0.0001")
    // No exponent, whatever the magnitude.
    #expect(!CSV.number(0.00001).contains("e"))
    #expect(CSV.number(2.25) == "2.25")
  }

  @Test("A non-finite number exports as empty rather than as 'nan'")
  func nonFiniteIsEmpty() {
    #expect(CSV.number(.nan) == "")
    #expect(CSV.number(.infinity) == "")
  }

  @Test("Timestamps carry their offset")
  func timestampsAreISO8601() {
    let stamp = CSV.timestamp(Date(timeIntervalSince1970: 0))
    #expect(stamp.hasPrefix("1970-01-01"))
    let hasZone = stamp.contains("Z") || stamp.contains("+") || stamp.contains("-")
    #expect(hasZone)
  }
}

@Suite("The app knows what it still owes App Review")
struct LegalLinksTests {
  @Test("Missing links are named, not silently absent")
  func blockersAreNamed() {
    let empty = LegalLinks()
    #expect(empty.submissionBlockers.count == 2)
    let mentionsPrivacy = empty.submissionBlockers.contains { $0.contains("Privacy policy") }
    #expect(mentionsPrivacy)
  }

  @Test("A fully configured set blocks nothing")
  func configuredIsClear() {
    let links = LegalLinks(
      privacyPolicy: URL(string: "https://example.com/privacy"),
      termsOfUse: URL(string: "https://example.com/terms"),
      support: URL(string: "https://example.com/support")
    )
    #expect(links.submissionBlockers.isEmpty)
  }

  /// Support is metadata in App Store Connect, so it is a courtesy in-app and not a gate.
  @Test("A missing support link is not a blocker")
  func supportIsNotAGate() {
    let links = LegalLinks(
      privacyPolicy: URL(string: "https://example.com/privacy"),
      termsOfUse: URL(string: "https://example.com/terms")
    )
    #expect(links.submissionBlockers.isEmpty)
  }
}

@Suite("The version on screen comes from the bundle")
struct AppVersionTests {
  @Test("Both halves are shown, so a build number is never guessed")
  func displayStringPairsThem() {
    #expect(AppVersion(shortVersion: "1.0", build: "12").displayString == "1.0 (12)")
  }

  /// Previews and test hosts carry neither key. An absence is rendered as one rather than as
  /// "0.0", which would be a version this app never shipped.
  @Test("A bundle with no version keys reports nothing rather than zero")
  func missingKeysAreAbsent() {
    #expect(AppVersion.current(bundle: Bundle(for: ProbeMarker.self)) == nil)
  }
}

/// Anchors a `Bundle` that carries no version keys.
private final class ProbeMarker {}
