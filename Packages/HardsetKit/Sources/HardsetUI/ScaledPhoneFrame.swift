import SwiftUI

/// A real screen shown as a small phone: the content is laid out at the size of a phone, then
/// scaled down to whatever width the frame is offered, on a steel plate with a light-catching rim.
///
/// The first-launch tour uses it to stage the app's own screens, built from `TourFixtures`, so the
/// tour shows what the product really draws rather than a picture of it. Laying the content out at
/// full phone size, and scaling afterwards, is what keeps a screen's layout, wrapping and Dynamic
/// Type behaviour exactly as it is on a device; only the pixels shrink.
///
/// A frame that is not interactive is inert: its content takes no touches and is hidden from
/// VoiceOver, so a lifter cannot wander into the staged screen and a screen reader does not read a
/// preview as if it were the app. An interactive frame, used for the tour steps that ask the lifter
/// to tap something, leaves both alone, apart from naming itself as a container so a screen reader
/// says what it has entered. The frame takes no animation of its own.
public struct ScaledPhoneFrame<Content: View>: View {
  /// The logical phone the content is laid out at: the iPhone 17 screen, 402 by 874 points.
  public static var phoneSize: CGSize { CGSize(width: 402, height: 874) }

  /// The share of the screen's width the tour gives the staged phone. The frame fills the width it
  /// is offered; the tour page applies this fraction when it sizes the frame.
  public static var screenWidthFraction: CGFloat { 0.78 }

  private let isInteractive: Bool
  private let content: Content

  /// - Parameter isInteractive: Whether the staged screen answers to touch and to VoiceOver.
  ///   Defaults to inert.
  public init(isInteractive: Bool = false, @ViewBuilder content: () -> Content) {
    self.isInteractive = isInteractive
    self.content = content()
  }

  public var body: some View {
    GeometryReader { proxy in
      let scale = proxy.size.width / Self.phoneSize.width
      content
        .frame(width: Self.phoneSize.width, height: Self.phoneSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
    .aspectRatio(Self.phoneSize.width / Self.phoneSize.height, contentMode: .fit)
    .allowsHitTesting(isInteractive)
    // `accessibilityHidden` alone did not reach the staged roots' UIKit-hosted tab content, which an
    // audit and VoiceOver still listed. An inert frame is first made one leaf, so nothing under it
    // is a node of its own, and that leaf is hidden. The behaviour is a value, not a branch, so the
    // frame keeps one identity as it turns inert and the staged apps inside it keep their state;
    // an interactive frame is a labelled container and its content is as reachable as ever.
    .accessibilityElement(children: isInteractive ? .contain : .ignore)
    .accessibilityLabel("Staged preview of the app")
    .accessibilityHidden(!isInteractive)
    .padding(Tokens.Spacing.snug)
    .background(Tokens.Color.steel, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
    .overlay {
      RoundedRectangle(cornerRadius: Tokens.Radius.card)
        .strokeBorder(Tokens.Color.edgeLight, lineWidth: Tokens.Stroke.hairline)
    }
  }
}

#if DEBUG
  #Preview("Staged phone, inert") {
    ScaledPhoneFrame {
      ZStack {
        Tokens.Color.canvas
        Text("A screen at phone size")
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.chalk)
      }
    }
    .padding(Tokens.Spacing.loose)
    .frame(width: 360)
    .background(Tokens.Color.canvas)
  }
#endif
