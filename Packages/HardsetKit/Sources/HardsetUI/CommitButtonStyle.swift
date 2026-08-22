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
    configuration.label
      .scaleEffect(configuration.isPressed ? pressedScale : 1)
      // Reduce Motion keeps the acknowledgement -- it is information, not decoration -- but
      // expresses it as opacity, since the objection is to movement rather than to feedback.
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(Tokens.Motion.commit(intensity: intensity), value: configuration.isPressed)
  }
}
