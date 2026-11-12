import SwiftUI

/// A knurl: two families of fine parallel lines at plus and minus 45 degrees, like the grip cut
/// into a bar or a dial.
///
/// It is drawn with a `Canvas` rather than a Metal shader because a `.metal` file in a package
/// target needs a resource bundle, which this package avoids. Every line goes into one path and
/// one stroke, so it stays cheap on a static surface.
///
/// The pattern is texture for the edges of a control, never a backdrop for text. Never place it
/// behind body text, values or labels: even at low opacity it costs contrast the palette
/// guarantees.
public struct KnurlPattern: View {
  public let pitch: CGFloat
  public let opacity: Double

  public init(pitch: CGFloat = 3, opacity: Double = 0.08) {
    self.pitch = pitch
    self.opacity = opacity
  }

  public var body: some View {
    // Resolve everything the renderer needs before the closure: it may run off the main actor,
    // so it must not touch `Tokens` or read this view's properties.
    let step = pitch
    let stroke = Tokens.Color.chalk.opacity(opacity)
    Canvas { context, size in
      guard step > 0, size.width > 0, size.height > 0 else { return }
      var path = Path()
      for offset in stride(from: -size.height, through: size.width, by: step) {
        // Rising at +45 degrees: bottom-left to top-right.
        path.move(to: CGPoint(x: offset, y: size.height))
        path.addLine(to: CGPoint(x: offset + size.height, y: 0))
        // Falling at -45 degrees: top-left to bottom-right.
        path.move(to: CGPoint(x: offset, y: 0))
        path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
      }
      context.stroke(path, with: .color(stroke), lineWidth: 0.5)
    }
    .accessibilityHidden(true)
  }
}

public extension View {
  /// Overlays a knurl on the view, clipped to the view's rectangular bounds and transparent to
  /// touches so it never changes what a tap hits. A view with a rounded shape must clip itself
  /// with `clipShape` so the pattern does not show past the corners. Do not use it on a view that
  /// carries body text.
  func knurl(opacity: Double = 0.08) -> some View {
    overlay(KnurlPattern(opacity: opacity).clipped().allowsHitTesting(false))
  }
}
