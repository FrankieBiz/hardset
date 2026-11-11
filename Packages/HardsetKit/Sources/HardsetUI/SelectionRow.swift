import SwiftUI

/// A tactile, high-density selection row for gym-floor interaction.
///
/// Used across machine and gym selection. Enforces the 56 pt logger tap target, the card surface
/// with a decorative hairline, clear hierarchy, and accessible traits. Selected rows take the
/// accent ring and tint, and the indicator on the right swaps an empty ring for a filled check, so
/// the choice is carried by shape as well as colour.
public struct SelectionRow: View {
  private let title: String
  private let subtitle: String?
  private let badge: String?
  private let leadingIcon: String?
  private let isSelected: Bool
  private let action: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(
    title: String,
    subtitle: String? = nil,
    badge: String? = nil,
    leadingIcon: String? = nil,
    isSelected: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.subtitle = subtitle
    self.badge = badge
    self.leadingIcon = leadingIcon
    self.isSelected = isSelected
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: Tokens.Spacing.regular) {
        if let leadingIcon {
          SelectionIconSquare(systemImage: leadingIcon, isSelected: isSelected)
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(title)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.textPrimary)

          if let visibleSubtitle {
            Text(visibleSubtitle)
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.textSecondary)
          }

          // At accessibility text sizes the tag moves under the title instead of squeezing it
          // into a column one word wide.
          if stacksTag, let visibleBadge {
            SelectionTag(visibleBadge)
              .padding(.top, Tokens.Spacing.tight)
          }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        if !stacksTag, let visibleBadge {
          SelectionTag(visibleBadge)
        }

        SelectionIndicator(isSelected: isSelected)
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      // Inside the label, so the 56 pt frame and the tappable shape are the same rectangle.
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
    }
    .buttonStyle(SelectionCardButtonStyle(isSelected: isSelected))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(spokenLabel)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
  }

  private var visibleSubtitle: String? {
    guard let subtitle, !subtitle.isEmpty else { return nil }
    return subtitle
  }

  private var visibleBadge: String? {
    guard let badge, !badge.isEmpty else { return nil }
    return badge
  }

  private var stacksTag: Bool { dynamicTypeSize.isAccessibilitySize }

  /// The selected state is spoken by the `.isSelected` trait, so it is not repeated here.
  private var spokenLabel: String {
    var parts = [title]
    if let visibleSubtitle { parts.append(visibleSubtitle) }
    if let visibleBadge { parts.append(visibleBadge) }
    return parts.joined(separator: ", ")
  }
}

// MARK: - Shared picker parts

// Internal rather than private: the exercise, machine and gym pickers draw the same card, tag and
// indicator, and a second copy of each would drift the first time one of them was adjusted.

/// The press and selection treatment for a tappable card in a picker.
///
/// Draws the card itself, so the pressed fill can sit between the card and its content, and the
/// selected ring stays on top of both. Pressed rows scale to 0.98 and take the pressed fill; with
/// Reduce Motion on, only the fill changes.
struct SelectionCardButtonStyle: ButtonStyle {
  let isSelected: Bool
  var cornerRadius: CGFloat = Tokens.Radius.control

  func makeBody(configuration: Configuration) -> some View {
    SelectionCardBody(
      configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius
    )
  }
}

private struct SelectionCardBody: View {
  let configuration: ButtonStyleConfiguration
  let isSelected: Bool
  let cornerRadius: CGFloat

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    configuration.label
      .background {
        if configuration.isPressed {
          RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Tokens.Color.surfacePressed)
        }
      }
      .hardsetCard(selected: isSelected, cornerRadius: cornerRadius)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .opacity(isEnabled ? 1 : 0.4)
      .animation(
        Tokens.Motion.adaptive(Tokens.Motion.press, reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}

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

/// The ring-or-check at the end of a choice.
///
/// Both symbols are always laid out and only their opacity and scale change, so selecting a row
/// never shifts its text. With Reduce Motion on the swap is immediate.
struct SelectionIndicator: View {
  let isSelected: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Image(systemName: "circle")
        .foregroundStyle(Tokens.Color.controlBorder)
        .opacity(isSelected ? 0 : 1)
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(Tokens.Color.accent)
        .opacity(isSelected ? 1 : 0)
        .scaleEffect(isSelected || reduceMotion ? 1 : 0.6)
    }
    .font(Tokens.Text.title)
    .animation(
      Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion),
      value: isSelected
    )
    .accessibilityHidden(true)
  }
}

extension View {
  /// The one way out of a selection sheet that does not choose anything.
  ///
  /// Tapping a row is the confirmation in every picker, so a picker has no confirm button: only
  /// "Cancel", in the cancellation position. Drawn here rather than by each caller, because three
  /// callers drew three conventions ("Done" on the cancel side, "Done" on the confirm side, and
  /// "Cancel"). Nothing is added when `onCancel` is `nil`, so a caller that still draws its own
  /// toolbar does not get a second button.
  func pickerCancelAction(_ onCancel: (() -> Void)?) -> some View {
    modifier(PickerCancelAction(onCancel: onCancel))
  }
}

private struct PickerCancelAction: ViewModifier {
  let onCancel: (() -> Void)?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let onCancel {
      content.toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
    } else {
      content
    }
  }
}

/// A row's leading symbol, set in a small raised square so it reads as an icon rather than text.
private struct SelectionIconSquare: View {
  let systemImage: String
  let isSelected: Bool

  var body: some View {
    Image(systemName: systemImage)
      .font(Tokens.Text.headline)
      .foregroundStyle(isSelected ? Tokens.Color.accent : Tokens.Color.textSecondary)
      // A minimum rather than a fixed size, so the square grows with the symbol at large text.
      .frame(
        minWidth: Tokens.minimumTapTarget - Tokens.Spacing.snug,
        minHeight: Tokens.minimumTapTarget - Tokens.Spacing.snug
      )
      .background(
        Tokens.Color.surfaceRaised,
        in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
      )
      .accessibilityHidden(true)
  }
}

#if DEBUG
  #Preview("Selection row") {
    ScrollView {
      VStack(spacing: Tokens.Spacing.snug) {
        SelectionRow(
          title: "Hammer Strength Leg Press",
          subtitle: "moves in 10 kg steps",
          badge: "Recent",
          isSelected: true,
          action: {}
        )

        SelectionRow(
          title: "Cybex Leg Press",
          subtitle: "moves in 5 kg steps",
          isSelected: false,
          action: {}
        )

        SelectionRow(
          title: "Metroflex Gym",
          leadingIcon: "mappin.and.ellipse",
          isSelected: true,
          action: {}
        )

        SelectionRow(
          title: "Not recorded",
          subtitle: "History is kept for the movement, not a machine",
          leadingIcon: "slash.circle",
          isSelected: false,
          action: {}
        )

        SelectionRow(
          title: "The plate-loaded hack squat by the window, second from the end",
          badge: "Plate loaded",
          action: {}
        )
      }
      .padding(Tokens.Spacing.loose)
    }
    .background(Tokens.Color.background)
  }
#endif
