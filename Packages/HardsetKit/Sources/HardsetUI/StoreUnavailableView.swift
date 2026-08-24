import SwiftUI

/// What the app shows when it cannot open the training history at all.
///
/// This screen exists because the alternative is far worse than an error. `HardsetApp` opens the
/// database in `init` and, on failure, called `assertionFailure` -- a no-op in release -- and left
/// `defaultDatabase` unassigned. The app then launched against an empty fallback store and rendered
/// perfectly: no gyms, no history, no sets, an inviting "Start workout" button. A lifter with two
/// years of training would see a brand-new app, log a session into a store that is discarded on
/// quit, and have no way to know either had happened.
///
/// An app whose entire claim is calibrated honesty cannot present an empty log over an unknown
/// failure. So the failure is the screen. It says nothing has been deleted, because that is true and
/// it is the first thing the reader needs; it does not offer a "reset" or "start fresh" button,
/// because a store that failed to open once may open next launch and destroying it is irreversible.
public struct StoreUnavailableView: View {
  private let detail: String
  private let onRetry: (() -> Void)?

  public init(detail: String, onRetry: (() -> Void)? = nil) {
    self.detail = detail
    self.onRetry = onRetry
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Image(systemName: "exclamationmark.triangle")
            .font(Tokens.Text.hero)
            .foregroundStyle(Tokens.Color.statusLow)
          Text("Can't open your training history")
            .font(Tokens.Text.hero)
            .tracking(Tokens.Tracking.hero)
            .foregroundStyle(Tokens.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          // The first thing the reader needs, and it is true: a store that will not open is not a
          // store that has been erased.
          Text("Nothing has been deleted.")
            .font(Tokens.Text.title)
            .foregroundStyle(Tokens.Color.textPrimary)
          Text(
            "Your workouts are still on this device. Hardset could not open them this time, and it "
              + "will not show you an empty log and let you train into it as though this were a "
              + "fresh install."
          )
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textSecondary)
          .fixedSize(horizontal: false, vertical: true)

          Text("Try quitting Hardset and opening it again. If this keeps happening, the detail below is what a bug report needs.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let onRetry {
          Button(action: onRetry) {
            Text("Try again")
              .font(Tokens.Text.label.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Tokens.Color.ground)
          .background(Tokens.Color.accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
          Text("What went wrong")
            .font(Tokens.Text.label.weight(.semibold))
            .foregroundStyle(Tokens.Color.textPrimary)
          // Selectable, because the only use for this text is pasting it into a bug report.
          Text(detail)
            .font(Tokens.Text.mono)
            .foregroundStyle(Tokens.Color.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Tokens.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
            )
        }
      }
      .padding(.horizontal, Tokens.Spacing.edge)
      .padding(.vertical, Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.ground)
  }
}

#if DEBUG
  #Preview("Store unavailable") {
    StoreUnavailableView(
      detail: "SQLite error 11: database disk image is malformed",
      onRetry: {}
    )
  }
#endif
