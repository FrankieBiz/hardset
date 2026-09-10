import Foundation

/// The app's own identity and the links App Review expects to find inside the binary.
///
/// # Why these are optional, and why nothing invents one
///
/// A privacy policy URL is required in App Store Connect, and a Terms of Use (EULA) link is
/// required **inside the app** the moment an auto-renewable subscription ships — Guideline 3.1.2.
/// None of those public pages exist yet, and a link to a page that does not exist is worse than no
/// link: App Review taps every one of them, and a 404 is a rejection with a slower turnaround than
/// a missing feature. The app still ships an offline-readable privacy policy in Settings.
///
/// So each external link is `URL?`, and the one place to fill them in is `LegalLinks.live` below.
/// `submissionBlockers` names what is still missing in the same words the checklist uses, so "are
/// we ready" has one answer rather than a memory of one.
public struct LegalLinks: Sendable, Hashable {
  public let privacyPolicy: URL?
  public let termsOfUse: URL?
  public let support: URL?

  public init(privacyPolicy: URL? = nil, termsOfUse: URL? = nil, support: URL? = nil) {
    self.privacyPolicy = privacyPolicy
    self.termsOfUse = termsOfUse
    self.support = support
  }

  /// **Fill these in before the first TestFlight build that leaves your own devices.**
  ///
  /// Set each to a real, reachable page and nothing else has to change: optional web rows appear
  /// on their own and the bundled privacy screen gains its canonical web link. See
  /// `DEVICE-CHECKLIST.md` §E.
  public static let live = LegalLinks(
    privacyPolicy: nil,
    termsOfUse: nil,
    support: nil
  )

  /// What still has to exist before submission, in plain words.
  ///
  /// Support is not listed: App Store Connect takes a support URL as metadata, so the in-app row
  /// is a courtesy rather than a gate. The other two are gates — the privacy policy always, and
  /// the terms as soon as anything is sold.
  public var submissionBlockers: [String] {
    var missing: [String] = []
    if privacyPolicy == nil { missing.append("Privacy policy URL") }
    if termsOfUse == nil { missing.append("Terms of Use (EULA) URL — required once a subscription ships") }
    return missing
  }
}

/// Version and build, read from the bundle rather than duplicated in Swift.
///
/// Duplicating the version in code is how an app ships a Settings screen claiming 1.0 from a
/// binary marked 1.2 — the two drift the first time only one is bumped.
public struct AppVersion: Sendable, Hashable {
  public let shortVersion: String
  public let build: String

  public init(shortVersion: String, build: String) {
    self.shortVersion = shortVersion
    self.build = build
  }

  /// `nil` when the bundle carries neither key, which happens in previews and test hosts. Rendered
  /// as an absence rather than as "0.0", for the same reason every other unknown here is.
  public static func current(bundle: Bundle = .main) -> AppVersion? {
    let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    guard short != nil || build != nil else { return nil }
    return AppVersion(shortVersion: short ?? "—", build: build ?? "—")
  }

  public var displayString: String { "\(shortVersion) (\(build))" }
}
