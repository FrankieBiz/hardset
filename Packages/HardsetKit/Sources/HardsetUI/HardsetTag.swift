import SwiftUI

/// A non-interactive label on a row: a modality, "Recent", "Custom".
///
/// Filled but never outlined. The outline is what tells the lifter something can be tapped, so a
/// tag that wore one would be claiming to be a control it is not. It has no edge light either: a
/// tag is flat `steelRaised`, never a machined face.
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
    .background(Tokens.Color.steelRaised, in: Capsule())
  }
}

/// The name this view had before it became public. Call sites keep compiling through it until the
/// rename is finished.
typealias SelectionTag = HardsetTag
