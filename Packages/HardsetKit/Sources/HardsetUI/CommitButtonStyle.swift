import HardsetCore
import SwiftUI

/// A button that acknowledges on touch-*down* and commits with the weight of the set behind it.
///
/// Two things it exists for, both from `docs/UI-GUIDELINES.md` §5:
///
/// 1. **Acknowledge within 100 ms, on press rather than on action.** `Button`'s action fires on
///    release, so a view that only reacts to the action leaves the first ~100 ms of every tap
///    silent. `isPressed` is the only way to respond to the finger landing, and doing so is the
///    single largest perceived-quality lever in the app -- it is what "instant" actually is.
/// 2. **Mass.** The spring is scaled by `intensity`, so a near-max set depresses and returns
///    solidly while a light set is springier. `nil` intensity means unknown, and yields the plain
///    `tap` spring rather than a guessed middle.
public struct CommitButtonStyle: ButtonStyle {
  private let intensity: Double?
  private let pressedScale: CGFloat

  /// - Parameter intensity: `LoadIntensity.fraction(weightKg:heaviestKg:)`, or `nil` if unknown.
  public init(intensity: Double? = nil, pressedScale: CGFloat = 0.94) {
    self.intensity = intensity
    self.pressedScale = pressedScale
  }

  public func makeBody(configuration: Configuration) -> some View {
    // Routed through a nested `View` because `@Environment` is not read reliably on a
    // `ButtonStyle` itself -- the style is not a node in the view graph. Without this the
    // accessibility setting below is simply never consulted, which is exactly the bug the
    // previous version of this file had while its comment claimed otherwise.
    PressFeedback(
      configuration: configuration,
      intensity: intensity,
      pressedScale: pressedScale
    )
  }

  private struct PressFeedback: View {
    let configuration: ButtonStyleConfiguration
    let intensity: Double?
    let pressedScale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        // Under Reduce Motion the scale is dropped entirely: that is the movement, and movement
        // is what the setting objects to.
        .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
        // The dim survives, because the acknowledgement is information rather than decoration --
        // guideline M7. Reduce Motion means "stop moving things", not "stop telling me anything".
        // It deepens to the 0.7 §5.3 specifies for that setting, because with the scale gone the
        // dim is the whole acknowledgement and 0.82 was calibrated as one cue of two.
        .opacity(configuration.isPressed ? (reduceMotion ? 0.7 : 0.82) : 1)
        .animation(
          reduceMotion
            // A crossfade, not a spring: a spring is a statement about mass and there is no mass
            // to convey once the movement is gone.
            ? .linear(duration: 0.08)
            : Tokens.Motion.commit(intensity: intensity),
          value: configuration.isPressed
        )
    }
  }
}
