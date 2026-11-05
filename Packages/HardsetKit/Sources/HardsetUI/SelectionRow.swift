import SwiftUI

/// A tactile, high-density selection row for gym-floor interaction.
///
/// Used across movement, machine, and gym selection. Enforces the 56 pt logger tap target,
/// dark-slate surface styling with charcoal borders, clear hierarchy, and accessible traits.
public struct SelectionRow: View {
  private let title: String
  private let subtitle: String?
  private let badge: String?
  private let leadingIcon: String?
  private let isSelected: Bool
  private let action: () -> Void

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
      HStack(spacing: Tokens.Spacing.regular) {
        if let leadingIcon {
          Image(systemName: leadingIcon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isSelected ? Tokens.Color.accent : Tokens.Color.textSecondary)
            .frame(width: 24)
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          Text(title)
            .font(Tokens.Text.rowTitle)
            .foregroundStyle(Tokens.Color.textPrimary)
            .lineLimit(1)

          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: Tokens.Spacing.snug)

        if let badge, !badge.isEmpty {
          Text(badge)
            .font(Tokens.Text.caption.weight(.medium))
            .foregroundStyle(Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Spacing.snug)
            .padding(.vertical, 3)
            .background(
              Tokens.Color.surfaceRaised,
              in: RoundedRectangle(cornerRadius: Tokens.Radius.control / 2)
            )
            .overlay(
              RoundedRectangle(cornerRadius: Tokens.Radius.control / 2)
                .strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline)
            )
        }

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Tokens.Color.accent)
        }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .frame(minHeight: Tokens.loggerTapTarget)
      .contentShape(Rectangle())
      .hardsetCard(selected: isSelected, cornerRadius: Tokens.Radius.control)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
  }

  private var accessibilityLabel: String {
    var parts = [title]
    if let subtitle, !subtitle.isEmpty { parts.append(subtitle) }
    if let badge, !badge.isEmpty { parts.append(badge) }
    if isSelected { parts.append("selected") }
    return parts.joined(separator: ", ")
  }
}

#if DEBUG
  #Preview("Selection Row") {
    VStack(spacing: Tokens.Spacing.snug) {
      SelectionRow(
        title: "Barbell Bench Press",
        subtitle: "also Triceps, Front delts",
        badge: "Barbell",
        isSelected: true,
        action: {}
      )

      SelectionRow(
        title: "Hammer Strength Leg Press",
        subtitle: "moves in 10 kg steps",
        badge: "Plate loaded",
        isSelected: false,
        action: {}
      )

      SelectionRow(
        title: "Metroflex Gym",
        leadingIcon: "mappin.and.ellipse",
        isSelected: false,
        action: {}
      )
    }
    .padding()
    .background(Tokens.Color.background)
  }
#endif
