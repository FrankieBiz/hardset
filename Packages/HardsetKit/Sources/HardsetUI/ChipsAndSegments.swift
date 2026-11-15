import SwiftUI

// MARK: - Chip

/// A filter or tag chip. Capsule, outlined, and filled with the accent when selected.
///
/// The visible capsule is compact so a rail of them reads as one control, but the tappable region
/// is the full 44 pt minimum.
public struct HardsetChip: View {
  private let title: String
  private let isSelected: Bool
  private let action: () -> Void

  public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
    self.title = title
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Text(title)
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(isSelected ? Tokens.Color.onAccent : Tokens.Color.textPrimary)
        .lineLimit(1)
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
        .background(isSelected ? Tokens.Color.accentFill : Tokens.Color.surfaceRaised, in: Capsule())
        .overlay(
          Capsule().strokeBorder(
            isSelected ? Tokens.Color.accentFill : Tokens.Color.controlBorder,
            lineWidth: Tokens.Stroke.hairline
          )
        )
        .frame(minHeight: Tokens.minimumTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(HardsetPressStyle())
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

// MARK: - Segmented control

/// One option in a `HardsetSegmentedControl`.
///
/// `nonisolated` so its computed `id` satisfies `Identifiable` without depending on isolated
/// conformance inference, as `SettingsSheet`'s `Disclosure` does.
public nonisolated struct HardsetSegment<Value: Hashable>: Identifiable {
  public let title: String
  public let value: Value
  public var id: Value { value }

  public init(_ title: String, value: Value) {
    self.title = title
    self.value = value
  }
}

/// Replaces the system segmented picker, which renders identically in every app and in a shade of
/// grey that does not meet this app's contrast floor.
///
/// Each segment is a full-height 44 pt button with the selected trait, and the indicator slides
/// between them on `Motion.state` -- or simply moves, with Reduce Motion on.
public struct HardsetSegmentedControl<Value: Hashable>: View {
  @Binding private var selection: Value
  private let segments: [HardsetSegment<Value>]
  @Namespace private var indicator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(selection: Binding<Value>, segments: [HardsetSegment<Value>]) {
    self._selection = selection
    self.segments = segments
  }

  public var body: some View {
    HStack(spacing: Tokens.Spacing.hairline) {
      ForEach(segments) { segment in
        Button {
          withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
            selection = segment.value
          }
        } label: {
          Text(segment.title)
            .font(Tokens.Text.label.weight(.semibold))
            .foregroundStyle(
              segment.value == selection ? Tokens.Color.onAccent : Tokens.Color.textPrimary
            )
            // One line at ordinary sizes. At accessibility sizes a segment wraps instead of
            // truncating, because "Heaviest l…" no longer says which metric is selected.
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Tokens.Spacing.snug)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Tokens.Spacing.tight : 0)
            // As tall as the tallest segment, so a wrapped label never leaves its neighbour's
            // indicator shorter than its own.
            .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget, maxHeight: .infinity)
            .background {
              if segment.value == selection {
                RoundedRectangle(cornerRadius: Tokens.Radius.control - Tokens.Spacing.hairline)
                  .fill(Tokens.Color.accentFill)
                  .matchedGeometryEffect(id: "indicator", in: indicator)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HardsetPressStyle())
        .accessibilityAddTraits(segment.value == selection ? [.isSelected] : [])
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(Tokens.Spacing.hairline)
    .background(
      Tokens.Color.surfaceRaised,
      in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Tokens.Radius.control)
        .strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline)
    )
  }
}
