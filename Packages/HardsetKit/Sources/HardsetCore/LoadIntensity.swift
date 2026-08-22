import Foundation

/// How heavy a set is, relative to the heaviest the lifter has actually done on the movement.
///
/// This exists to drive the motion layer, not to be displayed. A set near someone's own best
/// commits solidly and almost without overshoot; a light set is quicker and springier. The app
/// is about weight, so it should feel heavier when the weight is heavier.
///
/// It is deliberately **not** a `Claim`. `Claim` is for numbers the app shows a person, and it
/// carries an `EvidenceSource` because App Review guideline 1.4.1 asks for one. A spring
/// parameter is read by nobody and asserts nothing about anyone's training, so inventing a
/// methodology string for it would be ceremony rather than honesty. What the honesty rule *does*
/// require is the case below: when there is nothing to measure against, this returns `nil`, and
/// the motion layer must then apply no intensity at all rather than guessing a middle. Absence of
/// a signal has to mean absence of an effect -- a mid-weight feel would be the same neutral-70
/// fallback that this codebase exists to avoid, just expressed in physics instead of numerals.
public enum LoadIntensity {
  /// This set's load as a fraction of `heaviestKg`, clamped to `0...1`.
  ///
  /// Returns `nil` -- meaning "unknown", never "medium" -- when:
  /// - there is no history for the movement, so there is no denominator;
  /// - the heaviest recorded load is zero or negative, which is bodyweight-only history and
  ///   cannot form a ratio;
  /// - the candidate load is negative, which is not a real set.
  ///
  /// A load *above* the previous best clamps to `1`, so beating a record automatically produces
  /// the most solid commit in the app. That falls out of the arithmetic rather than being a
  /// celebration bolted on, which is the only kind of reward this app is willing to give.
  ///
  /// Zero is a legitimate result: a bodyweight set has no added load, and bodyweight work is a
  /// real set. It is the lightest thing you can lift, and it is allowed to feel like it.
  public static func fraction(weightKg: Double, heaviestKg: Double?) -> Double? {
    guard let heaviestKg, heaviestKg > 0 else { return nil }
    guard weightKg >= 0, weightKg.isFinite else { return nil }
    return min(1, weightKg / heaviestKg)
  }

  // MARK: - Commit shape

  /// The spring shape a set's commit animation should use, as plain numbers.
  ///
  /// These are presentation values and they live in the engine anyway, deliberately: HardsetUI has
  /// no test target, and the invariants below are worth pinning rather than leaving as unchecked
  /// constants in a view. `HardsetUI` turns this into a SwiftUI `Animation`; nothing here imports
  /// SwiftUI, so `HardsetCore` stays Foundation-only.
  public struct CommitShape: Hashable, Sendable {
    /// Perceptual duration, seconds.
    public let duration: Double
    /// SwiftUI's bounce: damping ratio is `1 - bounce`, so a larger value overshoots more.
    public let bounce: Double

    public init(duration: Double, bounce: Double) {
      self.duration = duration
      self.bounce = bounce
    }
  }

  /// What an unknown or zero intensity feels like, and the floor of the range.
  public static let baseShape = CommitShape(duration: 0.09, bounce: 0.18)

  /// The hard ceiling on commit duration. Heavier must never mean laggier: a heavy plate does not
  /// wobble, and it does not arrive late either. The whole range is 50 ms wide, and what the hand
  /// actually reads is the loss of overshoot.
  public static let maximumCommitDuration = 0.14

  /// Interpolates the commit spring from a set's intensity.
  ///
  /// Heavier sets damp harder and gain a little inertia; a light set is quick and springy. `nil`
  /// returns `baseShape` unchanged -- an unknown intensity applies no effect rather than guessing
  /// a middle, which is the whole point of `fraction` returning an optional.
  public static func commitShape(intensity: Double?) -> CommitShape {
    guard let intensity else { return baseShape }
    let f = min(1, max(0, intensity))
    return CommitShape(
      duration: baseShape.duration + (maximumCommitDuration - baseShape.duration) * f,
      bounce: baseShape.bounce - 0.14 * f
    )
  }
}
