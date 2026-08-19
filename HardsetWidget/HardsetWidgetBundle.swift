import ActivityKit
import AlarmKit
import HardsetAlarm
import HardsetCore
import HardsetUI
import SwiftUI
import WidgetKit

/// The widget extension exists because AlarmKit requires it.
///
/// `AlarmAttributes` conforms to `ActivityKit.ActivityAttributes`, so the rest timer's
/// Lock Screen and Dynamic Island presentation is a Live Activity -- which can only be
/// rendered from a widget extension. The metadata type is therefore compiled into *both*
/// the app and this extension, which is why `RestMetadata` lives in a shared package target
/// rather than in the app.
@main
struct HardsetWidgetBundle: WidgetBundle {
  var body: some Widget {
    RestTimerLiveActivity()
  }
}

struct RestTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<RestMetadata>.self) { context in
      // Lock Screen / banner presentation.
      HStack {
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          Text(context.attributes.metadata?.exerciseName ?? "Rest")
            .font(.headline)
          if let label = context.attributes.metadata?.setLabel {
            Text(label)
              .font(Tokens.Text.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        countdown(for: context.state)
          .font(Tokens.Text.readout)
      }
      .padding(Tokens.Spacing.loose)
      .activityBackgroundTint(nil)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.metadata?.exerciseName ?? "Rest")
            .font(Tokens.Text.label)
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(for: context.state)
            .font(Tokens.Text.readout)
        }
      } compactLeading: {
        Image(systemName: "timer")
      } compactTrailing: {
        countdown(for: context.state)
          .monospacedDigit()
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }

  /// Renders the countdown from the dates AlarmKit provides.
  ///
  /// `Text(timerInterval:)` is updated by the system, so nothing here ticks and nothing
  /// recomputes from `Date()` on a timer -- which is the same invariant the app's logger
  /// follows.
  ///
  /// Note the asymmetry: `Mode.Countdown` carries `startDate`/`fireDate`, but `Mode.Paused`
  /// carries only durations and no dates at all. A paused timer therefore has no deadline to
  /// render, which is exactly why the app owns `RestTimerState` rather than deriving state
  /// from AlarmKit.
  @ViewBuilder
  private func countdown(for state: AlarmPresentationState) -> some View {
    switch state.mode {
    case .countdown(let countdown):
      Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
    case .paused(let paused):
      let left = paused.totalCountdownDuration - paused.previouslyElapsedDuration
      Text(Duration.seconds(max(0, left)), format: .time(pattern: .minuteSecond))
    case .alert:
      Text("Done")
    @unknown default:
      Text("--:--")
    }
  }
}
