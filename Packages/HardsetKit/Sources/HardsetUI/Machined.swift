import SwiftUI

/// A raised, machined surface: a steel face with a light-catching top edge and a shadowed bottom
/// edge, so a control reads as a part that stands proud of the canvas.
///
/// Pressing the control drops the edge entirely and swaps to the pressed fill. Losing the edge is
/// what makes the key read as having gone down, and it needs no motion, so Reduce Motion users
/// get the same cue. `outlined` adds the 3:1 `controlEdge` on top of the edge gradient for
/// surfaces that must be identifiable as tappable by their boundary alone.
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
          shape.strokeBorder(
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

  /// Gives the view the pressed face: the pressed fill with no edge, as if the key had gone down.
  func machinedPressed<S: InsettableShape>(_ shape: S) -> some View {
    modifier(MachinedModifier(shape: shape, isPressed: true, outlined: false))
  }
}
