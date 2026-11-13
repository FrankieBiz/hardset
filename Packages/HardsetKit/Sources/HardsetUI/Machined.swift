import SwiftUI

/// A raised, machined surface: a steel face with a light-catching top edge and a shadowed bottom
/// edge, so a control reads as a part that stands proud of the canvas.
///
/// Pressing the control drops the edge light and swaps to the pressed fill. Losing the edge light
/// is what makes the key read as having gone down, and it needs no motion, so Reduce Motion users
/// get the same cue. `outlined` adds the 3:1 `controlEdge` at the boundary for surfaces that must
/// be identifiable as tappable by their boundary alone; it applies in both states, so the
/// measured boundary never disappears under a finger. When outlined, the edge light is drawn one
/// hairline inside the control edge so the opaque outline does not cover it.
public struct MachinedModifier<S: InsettableShape>: ViewModifier {
  public let shape: S
  public let isPressed: Bool
  public let outlined: Bool

  public init(shape: S, isPressed: Bool, outlined: Bool) {
    self.shape = shape
    self.isPressed = isPressed
    self.outlined = outlined
  }

  public func body(content: Content) -> some View {
    content
      .background(shape.fill(isPressed ? Tokens.Color.steelPressed : Tokens.Color.steelRaised))
      .overlay {
        if !isPressed {
          shape
            .inset(by: outlined ? Tokens.Stroke.hairline : 0)
            .strokeBorder(
              LinearGradient(
                colors: [Tokens.Color.edgeLight, Tokens.Color.edgeShadow],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: Tokens.Stroke.hairline
            )
        }
      }
      .overlay {
        if outlined {
          shape.strokeBorder(Tokens.Color.controlEdge, lineWidth: Tokens.Stroke.hairline)
        }
      }
      .contentShape(shape)
  }
}

public extension View {
  /// Gives the view a raised machined face. Pass `outlined` for controls that need the 3:1
  /// boundary as well as the edge light.
  func machinedRaised<S: InsettableShape>(_ shape: S, outlined: Bool = false) -> some View {
    modifier(MachinedModifier(shape: shape, isPressed: false, outlined: outlined))
  }

  /// Gives the view the pressed face: the pressed fill with no edge light, as if the key had gone
  /// down. Pass `outlined` for controls that keep the 3:1 boundary while pressed.
  func machinedPressed<S: InsettableShape>(_ shape: S, outlined: Bool = false) -> some View {
    modifier(MachinedModifier(shape: shape, isPressed: true, outlined: outlined))
  }
}
