import SwiftUI

/// An empty or unavailable state whose typography and targets remain under Hardset's control.
///
/// `ContentUnavailableView` looks appropriate, but on iOS 26 it exposes its description to the
/// accessibility runtime as fixed-size text. These are often the first instructions a new lifter
/// sees, so failing Dynamic Type here is worse than failing it in a secondary caption.
public struct UnavailableStateView<Actions: View>: View {
  private let title: String
  private let systemImage: String
  private let message: String
  private let actions: Actions

  public init(
    title: String,
    systemImage: String,
    message: String,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.systemImage = systemImage
    self.message = message
    self.actions = actions()
  }

  public var body: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      Image(systemName: systemImage)
        .font(Tokens.Text.hero)
        .foregroundStyle(Tokens.Color.textSecondary)
        .accessibilityHidden(true)
      Text(title)
        .font(Tokens.Text.title)
        .foregroundStyle(Tokens.Color.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Text(message)
        .font(Tokens.Text.label)
        .foregroundStyle(Tokens.Color.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      actions
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Tokens.Spacing.section)
    .padding(.vertical, Tokens.Spacing.loose)
  }
}

extension UnavailableStateView where Actions == EmptyView {
  public init(title: String, systemImage: String, message: String) {
    self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
  }
}

#if DEBUG
  #Preview("Unavailable") {
    UnavailableStateView(
      title: "No workouts yet",
      systemImage: "clock.arrow.circlepath",
      message: "Finished workouts appear here."
    )
    .preferredColorScheme(.dark)
  }
#endif
