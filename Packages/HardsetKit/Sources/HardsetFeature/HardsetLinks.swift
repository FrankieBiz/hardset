import Foundation

/// The two pages Hardset publishes, which Settings links to so a lifter can read the policy or get
/// help without leaving the app to find an address.
///
/// One table rather than a literal in each row: the site these are published from is checked in
/// under `site/`, and a row that spelled its own address could drift from it. The rows read this
/// type; no view holds a URL string of its own.
///
/// The address is kept as a string and turned into a `URL` on demand, so a row can hide itself if
/// an address is ever left blank rather than offer a link that goes nowhere.
///
/// `nonisolated` because a table of addresses has no actor affinity, and because this target
/// otherwise defaults to `MainActor`: a test, or any nonisolated caller, should not have to hop to
/// read a constant.
nonisolated enum HardsetLinks {
  static let privacyPolicy = "https://frankiebiz.github.io/hardset/privacy.html"
  static let support = "https://frankiebiz.github.io/hardset/support.html"

  /// `nil` when the address is blank, which is what hides its row.
  static var privacyPolicyURL: URL? { url(for: privacyPolicy) }
  static var supportURL: URL? { url(for: support) }

  /// `nil` for a blank address as well as for one that is not a URL.
  static func url(for address: String) -> URL? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return URL(string: trimmed)
  }
}
