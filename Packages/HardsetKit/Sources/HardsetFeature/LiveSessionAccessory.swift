import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The content of the tab bar's bottom accessory while a workout is open.
///
/// While a rest runs, the one rest cluster: `SessionView` no longer draws a rest bar on iOS, so
/// the countdown and its controls are drawn here, once. Otherwise, the workout's status. Either
/// way a tap brings the lifter back to Train, where the workout is.
struct LiveSessionAccessory: View {
  let coordinator: SessionCoordinator
  let hooks: RestTimerHooks
  /// Brings the lifter back to Train.
  let onOpen: () -> Void

  var body: some View {
    let restState = hooks.state()
    if restState != .idle {
      RestBarView(
        state: restState,
        // The coordinator's record of what was asked of the timer, so the bar names the set that
        // actually started this rest.
        metadata: coordinator.activeRest,
        onAdjust: hooks.adjust,
        onPauseResume: hooks.pauseOrResume,
        onSkip: {
          hooks.cancel()
          coordinator.endRest()
        },
        onOpen: onOpen
      )
    } else {
      Button {
        onOpen()
      } label: {
        HStack(spacing: Tokens.Spacing.snug) {
          Image(systemName: "figure.strengthtraining.traditional")
          // Inflected rather than concatenated, so one set does not read "1 sets".
          Text("^[\(coordinator.loggedSetCount) set](inflect: true) logged")
            .font(Tokens.Text.caption)
            .monospacedDigit()
          Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Spacing.regular)
        .frame(minHeight: Tokens.minimumTapTarget)
        // The whole pill opens the workout, not only the glyph and the words.
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        Text("Workout in progress, ^[\(coordinator.loggedSetCount) set](inflect: true) logged")
      )
      .accessibilityHint("Opens the workout")
    }
  }
}
