import SwiftUI

// MARK: - Chip

/// A filter or tag chip. A capsule: unselected it is a flat raised fill with no outline, and
/// selected it is a flat `plateBlueFill`. The fill steps off whatever the chip sits on, `canvas` or
/// a card, and the outline comes back under Increase Contrast or Button Shapes.
///
/// The visible capsule is compact so a rail of them reads as one control, but the tappable region
/// is at least 44 by 44 pt, so a short chip such as "All" is as easy to hit as a long one.
/// Unselected, a press sinks the face to `steelPressed`; selected, it swaps to
/// `plateBlueFillPressed`. Neither dims, so a boundary that is drawn never fades under a finger.
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
    }
    .buttonStyle(HardsetChipStyle(isSelected: isSelected))
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

/// A chip's face in a given state. Shared by `HardsetChip` and the chip catalogue, because a
/// `ButtonStyle` cannot be forced pressed in a render. Each branch is one view whose pressed state
/// only changes its arguments, so the label keeps its identity across a press.
///
/// The selected face is a plain `plateBlueFill`, about 8:1 against either surface, so it needs no
/// outline in any setting.
///
/// The face owns the chip's hit region: after the surface it applies a frame of at least 44 by
/// 44 pt and a rectangular content shape, so the compact capsule sits inside a full-size target.
struct HardsetChipFace<Label: View>: View {
  private let isSelected: Bool
  private let isPressed: Bool
  private let label: Label

  init(isSelected: Bool, isPressed: Bool, @ViewBuilder label: () -> Label) {
    self.isSelected = isSelected
    self.isPressed = isPressed
    self.label = label()
  }

  var body: some View {
    surface(
      label
        .hardsetText(.caption, weight: .semibold)
        .foregroundStyle(isSelected ? Tokens.Color.onPlateBlue : Tokens.Color.chalk)
        .lineLimit(1)
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
    )
    .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func surface<Content: View>(_ content: Content) -> some View {
    if isSelected {
      content.background(
        isPressed ? Tokens.Color.plateBlueFillPressed : Tokens.Color.plateBlueFill,
        in: Capsule()
      )
    } else {
      content.modifier(
        ControlFaceModifier(shape: Capsule(), isPressed: isPressed, outline: .onRequest))
    }
  }
}

/// The chip's button style: feeds `configuration.isPressed` into `HardsetChipFace`, sinks to 0.97
/// on `Motion.press` unless Reduce Motion is on, and never reads `isEnabled`, so a disabled chip is
/// not dimmed. It is not `HardsetPressStyle`, which dims, nor `ControlPressStyle`, which has no
/// selected variant: a chip is a raised fill when unselected and a plate-blue fill when selected.
private struct HardsetChipStyle: ButtonStyle {
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    HardsetChipBody(configuration: configuration, isSelected: isSelected)
  }
}

private struct HardsetChipBody: View {
  let configuration: ButtonStyleConfiguration
  let isSelected: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HardsetChipFace(isSelected: isSelected, isPressed: configuration.isPressed) {
      configuration.label
    }
    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
      value: configuration.isPressed
    )
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
/// The track is a static raised fill, outlined under Increase Contrast or Button Shapes. Each
/// segment is a full-height 44 pt button with the selected trait, and the `plateBlueFill`
/// indicator slides between them on `Motion.state` -- or simply moves, with Reduce Motion on. A
/// segment draws its own fill, so a press dims it through `HardsetPressStyle` rather than sinking
/// a flat face.
public struct HardsetSegmentedControl<Value: Hashable>: View {
  @Binding private var selection: Value
  private let segments: [HardsetSegment<Value>]
  @Namespace private var indicator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
          HardsetSegmentFace(isSelected: segment.value == selection, indicator: indicator) {
            Text(segment.title)
          }
        }
        .buttonStyle(HardsetPressStyle())
        .accessibilityAddTraits(segment.value == selection ? [.isSelected] : [])
      }
    }
    .hardsetSegmentTrack()
  }
}

/// A segment's face in a given selection state: the label, wrapping at accessibility sizes, over
/// the `plateBlueFill` indicator when selected. It has no press state of its own. The live segment
/// takes `HardsetPressStyle`, and the catalogue draws a pressed segment by wrapping this face in
/// `HardsetPressFace(isPressed: true, reduceMotion: false)`.
///
/// With a namespace the indicator is the shared geometry that slides between segments; without
/// one, as in the catalogue, it is drawn in place.
struct HardsetSegmentFace<Label: View>: View {
  private let isSelected: Bool
  private let indicator: Namespace.ID?
  private let label: Label

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(isSelected: Bool, @ViewBuilder label: () -> Label) {
    self.isSelected = isSelected
    self.indicator = nil
    self.label = label()
  }

  init(isSelected: Bool, indicator: Namespace.ID, @ViewBuilder label: () -> Label) {
    self.isSelected = isSelected
    self.indicator = indicator
    self.label = label()
  }

  var body: some View {
    label
      .font(Tokens.Text.label.weight(.semibold))
      .foregroundStyle(isSelected ? Tokens.Color.onPlateBlue : Tokens.Color.chalk)
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
        if isSelected {
          indicatorShape
        }
      }
      .contentShape(Rectangle())
  }

  @ViewBuilder
  private var indicatorShape: some View {
    let fill = Tokens.Shape.rounded(Tokens.Radius.control - Tokens.Spacing.hairline)
      .fill(Tokens.Color.plateBlueFill)
    if let indicator {
      fill.matchedGeometryEffect(id: "indicator", in: indicator)
    } else {
      fill
    }
  }
}

extension View {
  /// The segmented control's track: a static raised fill that steps off its surface, outlined
  /// when the lifter has asked for boundaries. The indicator inside it is inset by the track's
  /// padding, so its radius stays concentric with the track's. Shared by
  /// `HardsetSegmentedControl` and the chip catalogue's pressed segments.
  func hardsetSegmentTrack() -> some View {
    fixedSize(horizontal: false, vertical: true)
      .padding(Tokens.Spacing.hairline)
      .modifier(
        ControlFaceModifier(shape: Tokens.Shape.control, isPressed: false, outline: .onRequest)
      )
  }
}
