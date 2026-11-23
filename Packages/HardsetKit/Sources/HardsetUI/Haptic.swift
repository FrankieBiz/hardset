import SwiftUI

extension Tokens {
  /// The haptic vocabulary: the only feedback values call sites may pass to `.sensoryFeedback`.
  ///
  /// Naming them here keeps the app's restraint auditable in one place. `DESIGN.md` says which
  /// interaction earns which one: the clank belongs to the log tap alone and is its only haptic,
  /// `error` follows every failed command, `selection` answers the machine step and the rest
  /// controls, and `warning` marks a rest that ran out with no alarm to say so. There is no
  /// `success` here on purpose: a saved set used to play it under the clank, two patterns on one
  /// instant, and the log moment (`LogMoment`) has one haptic. Adding it back is a visible edit to
  /// this list and to `Tools/check_interaction_rules.py`.
  public enum Haptic {
    /// The heavy, full-strength system impact that stands in for the CoreHaptics `clank` when the
    /// engine is unavailable. The product path plays the richer transient-plus-rumble pattern
    /// directly through `ClankPlayer`; this value names the same moment for a view that triggers
    /// feedback through `.sensoryFeedback`.
    public static let clank: SensoryFeedback = .impact(weight: .heavy, intensity: 1.0)
    /// A command failed.
    public static let error: SensoryFeedback = .error
    /// A step or tap that changed a value the lifter is watching.
    public static let selection: SensoryFeedback = .selection
    /// A caveat the lifter should feel without looking, such as a rest that ended silently.
    public static let warning: SensoryFeedback = .warning
  }
}
