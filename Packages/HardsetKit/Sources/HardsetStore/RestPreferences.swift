import Foundation
import HardsetCore

/// The rest the lifter last chose for each movement, so it can be offered as a one-tap start the
/// next time.
///
/// Remembered, never invented. A movement with no remembered rest returns `nil`, and the UI asks
/// as it always has: a rest prescription is a training decision, and a built-in 90 seconds would
/// be the app asserting something it has no basis for. What is offered back is only ever a value
/// the lifter picked themselves.
///
/// A device preference rather than training data, so it lives in `UserDefaults` and is not
/// synchronized: it changes nothing that was logged, and losing it costs one extra tap.
@MainActor
public struct RestPreferences {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The rest last chosen for this movement, or `nil` when there is none to offer.
  ///
  /// A stored value that is not a positive, finite number of seconds is treated as absent
  /// rather than offered: a broken preference must not start a broken timer.
  public func lastRest(for exerciseID: ExerciseID) -> Duration? {
    let key = Self.key(for: exerciseID)
    guard defaults.object(forKey: key) != nil else { return nil }
    let seconds = defaults.double(forKey: key)
    guard seconds.isFinite, seconds > 0 else { return nil }
    return .seconds(seconds)
  }

  /// Remembers the rest the lifter chose for this movement. A zero or negative duration is not a
  /// rest and is ignored, leaving any earlier choice in place.
  public func remember(_ duration: Duration, for exerciseID: ExerciseID) {
    let seconds = duration.seconds
    guard seconds.isFinite, seconds > 0 else { return }
    defaults.set(seconds, forKey: Self.key(for: exerciseID))
  }

  /// One key per movement, namespaced so it cannot collide with another preference.
  nonisolated static func key(for exerciseID: ExerciseID) -> String {
    "hardset.rest.lastDuration." + exerciseID.rawValue.uuidString.lowercased()
  }
}
