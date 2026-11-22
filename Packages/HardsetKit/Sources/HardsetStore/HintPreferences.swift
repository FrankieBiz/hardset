import Foundation

/// Lines the app has told the lifter once and does not say again.
///
/// A hint is shown the first time it is useful and is then spent, however the lifter met it: a
/// line that came back every session would be the app nagging, and one that never came would leave
/// the thing it explains undiscovered. Spent is recorded when the hint was actually drawn, not when
/// it was dismissed, so a lifter who swipes past it without reading it is not asked again and one
/// who never reached the moment it needed still gets it.
///
/// A device preference rather than training data, so it lives in `UserDefaults` and is not
/// synchronized: it changes nothing that was logged, and losing it costs one more showing.
@MainActor
public struct HintPreferences {
  /// The hints the app has. One case per line it says, so a new hint is a new case and never a
  /// reuse of an old key.
  public nonisolated enum Hint: String, CaseIterable, Sendable {
    /// A saved weight or rep count can be tapped to correct it.
    case correctSavedSet
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Whether this hint has already been drawn for the lifter.
  public func hasSeen(_ hint: Hint) -> Bool {
    defaults.bool(forKey: Self.key(for: hint))
  }

  /// Records that the hint was drawn. Idempotent, and never undone by the app.
  public func markSeen(_ hint: Hint) {
    defaults.set(true, forKey: Self.key(for: hint))
  }

  /// One key per hint, namespaced so it cannot collide with another preference.
  nonisolated static func key(for hint: Hint) -> String {
    "hardset.hint.seen." + hint.rawValue
  }
}
