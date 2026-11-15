import SwiftUI

/// A non-interactive label on a row: a modality, "Recent", "Custom".
///
/// Filled but never outlined. The outline is what tells the lifter something can be tapped, so a
/// tag that wore one would be claiming to be a control it is not.
struct SelectionTag: View {
  private let title: String
  private let systemImage: String?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(_ title: String, systemImage: String? = nil) {
    self.title = title
    self.systemImage = systemImage
  }

  /// One unbroken line at ordinary sizes. At accessibility sizes a tag such as "Plate loaded" is
  /// wider than the stacked row, and held to one line it ran into the selection indicator, so it
  /// wraps within the row instead.
  var body: some View {
    let isLarge = dynamicTypeSize.isAccessibilitySize
    HStack(spacing: Tokens.Spacing.tight) {
      if let systemImage {
        Image(systemName: systemImage)
          .accessibilityHidden(true)
      }
      Text(title)
    }
    .font(Tokens.Text.caption.weight(.semibold))
    .foregroundStyle(Tokens.Color.textSecondary)
    .lineLimit(isLarge ? nil : 1)
    .fixedSize(horizontal: !isLarge, vertical: true)
    .padding(.horizontal, Tokens.Spacing.snug)
    .padding(.vertical, Tokens.Spacing.tight)
    .background(Tokens.Color.surfaceRaised, in: Capsule())
  }
}
