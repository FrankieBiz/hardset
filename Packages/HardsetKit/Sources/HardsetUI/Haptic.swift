import SwiftUI

extension Tokens {
  /// The haptic vocabulary: the only feedback values call sites may pass to `.sensoryFeedback`.
  ///
  /// Naming them here keeps the app's restraint auditable in one place. `DESIGN.md` says which
  /// interaction earns which one: `success` belongs to the log tap alone, `error` follows every
  /// failed command, `selection` answers the machine step and the rest controls, and `warning`
  /// marks a rest that ran out with no alarm to say so.
  public enum Haptic {
    /// A heavy, full-strength impact for a weighty physical moment. The richer CoreHaptics
    /// transient-plus-rumble pattern is deferred to the welcome bar, where a `HapticEngine`
    /// wrapper will own `CHHapticEngine`; until then this is the system impact.
    public static let clank: SensoryFeedback = .impact(weight: .heavy, intensity: 1.0)
    /// A set was logged.
    public static let success: SensoryFeedback = .success
    /// A command failed.
    public static let error: SensoryFeedback = .error
    /// A step or tap that changed a value the lifter is watching.
    public static let selection: SensoryFeedback = .selection
    /// A caveat the lifter should feel without looking, such as a rest that ended silently.
    public static let warning: SensoryFeedback = .warning
  }
}
