import HardsetUI
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// The rest timer's problem, stated above every tab with the action that can fix it.
///
/// Each issue gets its own words. Alarms turned off is the lifter's own setting, so it is a caveat
/// with a way to Settings rather than an error with a Retry: iOS asks for alarm permission once,
/// and a retry only hears "denied" again. Failures a retry can fix keep the retry. An unreadable
/// saved rest also offers a reset, because re-reading the same row fails the same way every time.
///
/// Appears and disappears without animation, like the banner it replaces, so Reduce Motion needs
/// no separate path.
///
/// It sits in a top inset that does not scroll, above every tab. At accessibility text sizes the
/// full message and its buttons filled most of the screen, and at the largest sizes pushed the
/// fixing button off it, so there it shrinks to one control naming the problem, which opens the
/// whole message and its actions in a sheet that scrolls.
struct RestTimerIssueBanner: View {
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var isShowingDetails = false
  private let issue: RestTimerIssue
  private let retry: () -> Void
  private let reset: () -> Void

  /// `reset` is offered only for `.recoveryFailed`.
  init(issue: RestTimerIssue, retry: @escaping () -> Void, reset: @escaping () -> Void = {}) {
    self.issue = issue
    self.retry = retry
    self.reset = reset
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        compact
      } else {
        details
      }
    }
    .padding(Tokens.Spacing.regular)
    .background(Tokens.Color.background)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      banner
      actions
    }
  }

  /// One control in the inset: the problem's symbol in its hue and its name, so the kind is still
  /// carried by shape and word as well as colour. The message and the fix are one tap away.
  private var compact: some View {
    Button {
      isShowingDetails = true
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.snug) {
        Image(systemName: symbolName)
          .foregroundStyle(hue)
          .accessibilityHidden(true)
        Text(shortTitle)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.textSecondary)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(HardsetButtonStyle(.secondary))
    .accessibilityHint("Shows what happened and how to fix it")
    .sheet(isPresented: $isShowingDetails) {
      NavigationStack {
        ScrollView {
          details
            .padding(Tokens.Spacing.loose)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Tokens.Color.background)
        .hardsetNavigationTitle("Rest timer")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { isShowingDetails = false }
          }
        }
      }
      .hardsetSheet()
    }
  }

  /// The problem in a few words, for the compact control.
  private var shortTitle: String {
    switch issue {
    case .alarmsDenied: "Rest alerts are off"
    case .unavailable: "Rest timer could not be saved or scheduled"
    case .recoveryFailed: "Rest timer could not be recovered"
    }
  }

  private var symbolName: String {
    switch issue {
    case .alarmsDenied: "bell.slash"
    case .unavailable, .recoveryFailed: "exclamationmark.triangle.fill"
    }
  }

  private var hue: Color {
    switch issue {
    case .alarmsDenied: Tokens.Color.warning
    case .unavailable, .recoveryFailed: Tokens.Color.error
    }
  }

  @ViewBuilder private var banner: some View {
    switch issue {
    case .alarmsDenied:
      HardsetBanner(
        .caveat,
        title: "Rest alerts are off",
        message: "Alarms are off for Hardset, so rest ends without an alert. The countdown still "
          + "runs here. Turn on Alarms for Hardset in Settings.",
        systemImage: "bell.slash"
      )
    case .unavailable:
      HardsetBanner(
        .error,
        message: "Rest timer could not be saved or scheduled. Your workouts remain saved."
      )
    case .recoveryFailed:
      HardsetBanner(
        .error,
        message: "Rest timer could not be recovered. Your workouts remain saved. Resetting clears "
          + "only the rest that was running."
      )
    }
  }

  @ViewBuilder private var actions: some View {
    switch issue {
    case .alarmsDenied:
      if let settingsURL {
        Button("Open Settings") { openURL(settingsURL) }
          .buttonStyle(HardsetButtonStyle(.secondary))
      }
    case .unavailable:
      retryButton
    case .recoveryFailed:
      // Side by side when both labels fit, stacked at large text sizes.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Tokens.Spacing.snug) {
          retryButton
          resetButton
        }
        VStack(spacing: Tokens.Spacing.snug) {
          retryButton
          resetButton
        }
      }
    }
  }

  private var retryButton: some View {
    Button("Retry rest timer", action: retry)
      .buttonStyle(HardsetButtonStyle(.secondary))
  }

  private var resetButton: some View {
    Button("Reset rest timer", role: .destructive, action: reset)
      .buttonStyle(HardsetButtonStyle(.destructive))
      .accessibilityHint("Clears the saved rest. Your workouts are kept.")
  }

  /// This app's page in the Settings app, where its Alarms switch lives. Absent off iOS, where
  /// there is no such page and no button is drawn.
  private var settingsURL: URL? {
    #if canImport(UIKit)
      URL(string: UIApplication.openSettingsURLString)
    #else
      nil
    #endif
  }
}

#if DEBUG
  #Preview("Rest timer issues") {
    VStack(spacing: 0) {
      RestTimerIssueBanner(issue: .alarmsDenied, retry: {})
      RestTimerIssueBanner(issue: .unavailable, retry: {})
      RestTimerIssueBanner(issue: .recoveryFailed, retry: {}, reset: {})
    }
    .background(Tokens.Color.background)
  }
#endif
