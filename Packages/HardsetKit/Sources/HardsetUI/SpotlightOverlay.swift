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
    ZStack {
      // What is seen: the scrim with its rounded hole, drawn and never hit.
      SpotlightShape(hole: hole ?? .zero, cornerRadius: Self.holeRadius)
        .fill(Tokens.Color.canvas.opacity(0.7), style: FillStyle(eoFill: true))
        .opacity(target == nil ? 0 : 1)
        .allowsHitTesting(false)
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: hole)
      // What is touched: four blockers around the hole, so a touch in it reaches the control below
      // and a touch anywhere else stops here. An even-odd content shape was tried for this first and
      // left the real check unreachable, so the hole is simply a gap between views.
      if swallowsTouches, let hole {
        TouchBlockers(hole: hole)
      }
    }
    .accessibilityHidden(true)
  }

  /// The hole's corners follow the control radius, grown by the air around the target.
  private static var holeRadius: CGFloat { Tokens.Radius.control + Tokens.Spacing.snug }

  /// A little air around the target, so the hole does not hug its edge.
  private static func padded(_ rect: CGRect) -> CGRect {
    rect.insetBy(dx: -Tokens.Spacing.snug, dy: -Tokens.Spacing.snug)
  }
}

/// The whole rectangle with a rounded hole cut from it, filled with the even-odd rule.
struct SpotlightShape: Shape {
  var hole: CGRect
  /// Passed in rather than read from `Tokens`, because a shape's path is drawn off the main actor.
  let cornerRadius: CGFloat

  var animatableData: CGRect.AnimatableData {
    get { hole.animatableData }
    set { hole.animatableData = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path(rect)
    if !hole.isEmpty {
      path.addRoundedRect(
        in: hole,
        cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
    }
    return path
  }
}

/// Four transparent views that cover everything but `hole`, in the space they are drawn in.
private struct TouchBlockers: View {
  let hole: CGRect

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let top = min(max(hole.minY, 0), size.height)
      let bottom = min(max(hole.maxY, top), size.height)
      let left = min(max(hole.minX, 0), size.width)
      let right = min(max(hole.maxX, left), size.width)
      ZStack(alignment: .topLeading) {
        blocker(x: 0, y: 0, width: size.width, height: top)
        blocker(x: 0, y: bottom, width: size.width, height: size.height - bottom)
        blocker(x: 0, y: top, width: left, height: bottom - top)
        blocker(x: right, y: top, width: size.width - right, height: bottom - top)
      }
    }
  }

  private func blocker(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
    Color.clear
      .frame(width: max(0, width), height: max(0, height))
      .contentShape(Rectangle())
      .offset(x: x, y: y)
  }
}
