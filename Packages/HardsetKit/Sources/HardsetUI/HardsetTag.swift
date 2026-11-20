import SwiftUI

/// A non-interactive label on a row: a modality, "Recent", "Custom".
///
/// Filled but never outlined, in any setting. An outline is what tells the lifter something can
/// be tapped, so a tag that wore one, even under Increase Contrast or Button Shapes, would be
/// claiming to be a control it is not. A tag is flat `steelRaised`.
///
/// A capsule at ordinary sizes. At accessibility sizes a long tag wraps to several lines, and a
/// capsule's corner radius, half its height, then pushes the wrapped text across its edge, so there
/// the fill takes the control radius instead. Only the shape changes: the fill and padding are the
/// same at every size.
public struct HardsetTag: View {
  private let title: String
  private let systemImage: String?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(_ title: String, systemImage: String? = nil) {
    self.title = title
    self.systemImage = systemImage
  }

  /// One unbroken line at ordinary sizes. At accessibility sizes a tag such as "Plate loaded" is
  /// wider than the stacked row, and held to one line it ran into the selection indicator, so it
  /// wraps within the row instead.
  public var body: some View {
    let isLarge = dynamicTypeSize.isAccessibilitySize
    HStack(spacing: Tokens.Spacing.tight) {
      if let systemImage {
        Image(systemName: systemImage)
          .accessibilityHidden(true)
      }
      Text(title)
    }
    .hardsetText(.caption, weight: .semibold)
    .foregroundStyle(Tokens.Color.chalkDim)
    .lineLimit(isLarge ? nil : 1)
    .fixedSize(horizontal: !isLarge, vertical: true)
    .padding(.horizontal, Tokens.Spacing.snug)
    .padding(.vertical, Tokens.Spacing.tight)
    .background {
      if isLarge {
        Tokens.Shape.control.fill(Tokens.Color.steelRaised)
      } else {
        Capsule().fill(Tokens.Color.steelRaised)
      }
    }
  }
}
