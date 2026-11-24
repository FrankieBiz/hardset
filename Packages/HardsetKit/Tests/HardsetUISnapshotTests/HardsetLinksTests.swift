import Foundation
import Testing

@testable import HardsetFeature

/// The two published pages Settings links to.
///
/// Pinned because a mistyped address would be a dead link, and nothing else in the suite would
/// notice: the rows are drawn from this table, so the table is the only place it can go wrong.
@Suite("The published pages Settings links to")
struct HardsetLinksTests {
  @Test("The addresses are exactly the pages the site is published at")
  func addresses() throws {
    #expect(HardsetLinks.privacyPolicy == "https://frankiebiz.github.io/hardset/privacy.html")
    #expect(HardsetLinks.support == "https://frankiebiz.github.io/hardset/support.html")

    let privacy = try #require(HardsetLinks.privacyPolicyURL)
    let support = try #require(HardsetLinks.supportURL)
    #expect(privacy.absoluteString == "https://frankiebiz.github.io/hardset/privacy.html")
    #expect(support.absoluteString == "https://frankiebiz.github.io/hardset/support.html")
    // Opened in the browser, so the address has to be one the system will hand to it.
    #expect(privacy.scheme == "https")
    #expect(support.scheme == "https")
  }

  /// The rule that lets a row hide itself rather than offer a link to nowhere.
  @Test("A blank address is no URL at all", arguments: ["", " ", "\n", "   \t "])
  func blankAddress(address: String) {
    #expect(HardsetLinks.url(for: address) == nil)
  }

  @Test("Stray whitespace around an address does not make it unusable")
  func trimsSurroundingWhitespace() throws {
    let url = try #require(HardsetLinks.url(for: " https://frankiebiz.github.io/hardset/support.html "))
    #expect(url.absoluteString == "https://frankiebiz.github.io/hardset/support.html")
  }
}
