import SwiftUI

/// A scrim over a screen with one rounded hole in it, which the tour moves between targets.
///
/// The scrim is `canvas` at 70%, so the rest of the screen stays readable but quiet. The hole moves
/// on `Motion.state`: one shape travelling from one target to the next, drawn, never laid out, so
/// nothing under it moves. Touches outside the hole are swallowed, so a staged screen cannot be
/// wandered off; touches inside it reach the real control, which is how the one interactive step
/// works. With Reduce Motion the hole jumps.
public struct SpotlightOverlay: View {
  private let target: CGRect?
  private let swallowsTouches: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// - Parameters:
  ///   - target: The region to leave clear, in this view's coordinates. `nil` shows no scrim, as
  ///     while the screen it points at is still loading.
  ///   - swallowsTouches: Whether touches outside the hole stop here. Off when the staged screen is
  ///     already inert.
  public init(target: CGRect?, swallowsTouches: Bool = true) {
    self.target = target
    self.swallowsTouches = swallowsTouches
  }

  public var body: some View {
    let hole = target.map(Self.padded)
    SpotlightShape(hole: hole ?? .zero)
      .fill(Tokens.Color.canvas.opacity(0.7), style: FillStyle(eoFill: true))
      .opacity(target == nil ? 0 : 1)
      .contentShape(SpotlightShape(hole: hole ?? .zero), eoFill: true)
      .allowsHitTesting(swallowsTouches && target != nil)
      .animation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: hole)
      .accessibilityHidden(true)
  }

  /// A little air around the target, so the hole does not hug its edge.
  private static func padded(_ rect: CGRect) -> CGRect {
    rect.insetBy(dx: -Tokens.Spacing.snug, dy: -Tokens.Spacing.snug)
  }
}

/// The whole rectangle with a rounded hole cut from it, filled with the even-odd rule.
struct SpotlightShape: Shape {
  var hole: CGRect

  var animatableData: CGRect.AnimatableData {
    get { hole.animatableData }
    set { hole.animatableData = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path(rect)
    if !hole.isEmpty {
      path.addRoundedRect(
        in: hole,
        cornerSize: CGSize(
          width: Tokens.Radius.control + Tokens.Spacing.snug,
          height: Tokens.Radius.control + Tokens.Spacing.snug))
    }
    return path
  }
}
