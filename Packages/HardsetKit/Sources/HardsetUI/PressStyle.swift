import SwiftUI

// MARK: - Press style

/// Press feedback for a control that draws its own shape and fill: a chip, a segment, a dashed
/// slot, a header circle.
///
/// The same 0.97 sink on `Motion.press` as `HardsetButtonStyle`, with opacity standing in for a
/// pressed fill because each of these controls owns its fill. With Reduce Motion the scale is
/// dropped and only the opacity changes. It never dims a disabled control, so an inert title keeps
/// its measured contrast.
public struct HardsetPressStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    HardsetPressBody(configuration: configuration)
  }
}

private struct HardsetPressBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}
