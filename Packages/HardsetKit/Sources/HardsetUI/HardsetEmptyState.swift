import SwiftUI

/// An honest, high-density empty state replacing generic `ContentUnavailableView`.
///
/// Drawn as an empty slot rather than a dialog: the symbol sits in a dashed socket, which is the
/// one place a dashed outline appears in the app and it always means "nothing here yet". Then a
/// plain-English statement of what is missing, and, when there is one, the action that fills it.
///
/// The words and symbol read as one VoiceOver element; the action stays its own button, so it can
/// be found and activated rather than being folded into a sentence.
public struct HardsetEmptyState: View {
  private let title: String
  private let detail: String?
  private let systemImage: String
  private let actionTitle: String?
  private let actionSystemImage: String
  private let action: (() -> Void)?

  /// - Parameter actionSystemImage: The action's symbol. A plus by default, because most empty
  ///   states are filled by adding something; a retry passes `arrow.clockwise`.
  public init(
    title: String,
    detail: String? = nil,
    systemImage: String,
    actionTitle: String? = nil,
    actionSystemImage: String = "plus",
    action: (() -> Void)? = nil
  ) {
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
    self.actionTitle = actionTitle
    self.actionSystemImage = actionSystemImage
    self.action = action
  }

  public var body: some View {
    VStack(spacing: Tokens.Spacing.loose) {
      VStack(spacing: Tokens.Spacing.regular) {
        Image(systemName: systemImage)
          .font(Tokens.Text.title)
          .foregroundStyle(Tokens.Color.textSecondary)
          .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
          .background(
            Tokens.Color.surfaceRaised,
            in: RoundedRectangle(cornerRadius: Tokens.Radius.card)
          )
          .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.card)
              .strokeBorder(
                Tokens.Color.controlBorder,
                style: StrokeStyle(lineWidth: Tokens.Stroke.hairline, dash: [4, 3])
              )
          )

        VStack(spacing: Tokens.Spacing.tight) {
          Text(title)
            .font(Tokens.Text.headline)
            .foregroundStyle(Tokens.Color.textPrimary)
            .multilineTextAlignment(.center)

          if let detail, !detail.isEmpty {
            Text(detail)
              .font(Tokens.Text.label)
              .foregroundStyle(Tokens.Color.textSecondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .accessibilityElement(children: .combine)

      if let actionTitle, let action {
        Button(action: action) {
          Label(actionTitle, systemImage: actionSystemImage)
        }
        .buttonStyle(HardsetButtonStyle(.primary, fullWidth: false))
      }
    }
    .padding(.vertical, Tokens.Spacing.section)
    .padding(.horizontal, Tokens.Spacing.section)
    .frame(maxWidth: .infinity)
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
