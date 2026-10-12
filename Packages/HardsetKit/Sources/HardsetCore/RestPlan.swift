import Foundation

/// Rest between sets, as the lifter chose it.
///
/// There is deliberately no default. A rest prescription is a training decision, and an app that
/// starts a 90-second timer nobody asked for is asserting something it has no basis for
/// (`HANDOFF.md` §6). The presets below are choices offered in a menu; none is preselected, and
/// `restAfterLogging` returns nil until the lifter has picked one.
public enum RestPlan {
  /// What the rest menu offers. A list to choose from, not a recommendation.
  public static let presets: [Duration] = [60, 90, 120, 180, 240, 300].map { .seconds($0) }

  /// The range a custom rest may take. Outside it the value is refused rather than clamped, so a
  /// typo never becomes a silently different rest.
  public static let allowedRange: ClosedRange<Duration> = .seconds(15) ... .seconds(1800)

  /// `duration` if it is a whole number of seconds in `allowedRange`, otherwise nil. Every
  /// surface offers whole seconds, so a fraction is refused, never rounded.
  public static func validated(_ duration: Duration) -> Duration? {
    guard duration.components.attoseconds == 0 else { return nil }
    return allowedRange.contains(duration) ? duration : nil
  }

  /// The rest to request after a set is logged, or nil to start nothing.
  ///
  /// Warm-ups never rest: the lifter is still warming up.
  public static func restAfterLogging(isWarmup: Bool, choice: Duration?) -> Duration? {
    guard !isWarmup else { return nil }
    return choice
  }

  /// "Off", or the clock time, for the exercise's rest chip.
  public static func label(for choice: Duration?) -> String {
    choice?.clockString ?? "Off"
  }
}
