import SwiftUI

/// An honest, high-density empty state replacing generic `ContentUnavailableView`.
///
/// Designed with Hardset's dark-slate aesthetic: a contained surface card with subtle charcoal
/// border, restrained iconography, clear plain-English explanation, and an optional direct action.
/// Accessible as a single combined VoiceOver element.
public struct HardsetEmptyState: View {
  private let title: String
  private let detail: String?
  private let systemImage: String
  private let actionTitle: String?
  private let action: (() -> Void)?

  public init(
    title: String,
    detail: String? = nil,
    systemImage: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    VStack(spacing: Tokens.Spacing.regular) {
      ZStack {
        Circle()
          .fill(Tokens.Color.surfaceRaised)
          .frame(width: 52, height: 52)
          .overlay(
            Circle()
              .strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline)
          )

        Image(systemName: systemImage)
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(Tokens.Color.textSecondary)
      }

      VStack(spacing: Tokens.Spacing.tight) {
        Text(title)
          .font(Tokens.Text.labelEmphasis)
          .foregroundStyle(Tokens.Color.textPrimary)
          .multilineTextAlignment(.center)

        if let detail, !detail.isEmpty {
          Text(detail)
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
        }
      }

      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle)
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.background)
            .padding(.horizontal, Tokens.Spacing.loose)
            .frame(minHeight: Tokens.minimumTapTarget)
            .background(Tokens.Color.accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
        .padding(.top, Tokens.Spacing.tight)
      }
    }
    .padding(Tokens.Spacing.section)
    .frame(maxWidth: .infinity)
    .hardsetCard()
    .padding(.horizontal, Tokens.Spacing.loose)
    .accessibilityElement(children: .combine)
  }
}

#if DEBUG
  #Preview("Hardset Empty State") {
    VStack(spacing: 20) {
      HardsetEmptyState(
        title: "No movement found",
        detail: "Nothing in the catalogue matches “deficit deadlift”.",
        systemImage: "magnifyingglass",
        actionTitle: "Add as custom movement",
        action: {}
      )

      HardsetEmptyState(
        title: "No workout in progress",
        detail: "Start an empty workout and add movements as you go.",
        systemImage: "figure.strengthtraining.traditional"
      )
    }
    .padding()
    .background(Tokens.Color.background)
  }
#endif
