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

/// The rest timer away from the app, drawn in the app's own type and palette.
///
/// The Lock Screen shows what the lifter is resting after, the countdown at the app's largest
/// figure size, and a bar that the system advances from AlarmKit's own dates. The Dynamic Island
/// keeps to the countdown and the movement, because that is all there is room to read at a glance.
struct RestTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<RestMetadata>.self) { context in
      // Lock Screen / banner presentation.
      VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        HStack(alignment: .center, spacing: Tokens.Spacing.loose) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(statusLabel(for: context.state))
              .font(Tokens.Text.sectionHeader)
              .foregroundStyle(Tokens.Color.accent)
            Text(context.attributes.metadata?.exerciseName ?? "Rest")
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.textPrimary)
              .lineLimit(1)
            if let detail = detail(for: context.attributes.metadata) {
              Text(detail)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
                .lineLimit(1)
            }
          }
          Spacer(minLength: Tokens.Spacing.snug)
          countdown(for: context.state)
            .font(Tokens.Text.hero)
            .foregroundStyle(Tokens.Color.textPrimary)
            .multilineTextAlignment(.trailing)
        }
        progress(for: context.state, metadata: context.attributes.metadata)
      }
      .padding(Tokens.Spacing.loose)
      .activityBackgroundTint(Tokens.Color.background)
      .activitySystemActionForegroundColor(Tokens.Color.accent)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(statusLabel(for: context.state))
              .font(Tokens.Text.caption.weight(.semibold))
              .foregroundStyle(Tokens.Color.accent)
            Text(context.attributes.metadata?.exerciseName ?? "Rest")
              .font(Tokens.Text.headline)
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(for: context.state)
            .font(Tokens.Text.readout)
            .foregroundStyle(Tokens.Color.accent)
            .multilineTextAlignment(.trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
            if let detail = detail(for: context.attributes.metadata) {
              Text(detail)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
                .lineLimit(1)
            }
            progress(for: context.state, metadata: context.attributes.metadata)
          }
        }
      } compactLeading: {
        Image(systemName: "timer")
          .foregroundStyle(Tokens.Color.accent)
      } compactTrailing: {
        countdown(for: context.state)
          .font(Tokens.Text.figure)
          .foregroundStyle(Tokens.Color.accent)
          // A timer text otherwise claims all the width it is offered and pushes the island wide.
          .frame(width: 44)
      } minimal: {
        Image(systemName: "timer")
          .foregroundStyle(Tokens.Color.accent)
      }
      .keylineTint(Tokens.Color.accent)
    }
  }

  private func statusLabel(for state: AlarmPresentationState) -> String {
    switch state.mode {
    case .countdown: "Resting"
    case .paused: "Rest paused"
    case .alert: "Rest over"
    @unknown default: "Rest"
    }
  }

  /// "Set 2 of 4, Hammer Strength" — the set and, when it was recorded, the machine.
  private func detail(for metadata: RestMetadata?) -> String? {
    guard let metadata else { return nil }
    return [metadata.setLabel, metadata.machineName].compactMap { $0 }.joined(separator: ", ")
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
      // Clamped like the app's rest bar: a deadline already past would make an inverted range,
      // which traps, in the moment before the presentation switches to the alert.
      Text(timerInterval: Date.now...max(Date.now, countdown.fireDate), countsDown: true)
        .monospacedDigit()
    case .paused(let paused):
      let left = paused.totalCountdownDuration - paused.previouslyElapsedDuration
      Text(Duration.seconds(max(0, left)), format: .time(pattern: .minuteSecond))
        .monospacedDigit()
    case .alert:
      Text("Done")
    @unknown default:
      Text("--:--")
    }
  }

  /// How much of the rest has gone, as a bar the system advances.
  ///
  /// Built from AlarmKit's own deadline and a total length, so it costs no updates, exactly like
  /// the countdown beside it. Paused and finished timers have no running interval, so they draw
  /// no bar rather than a frozen or invented one.
  ///
  /// The total is the whole rest the app recorded in the metadata. Each ±15 s or resume is a
  /// fresh alarm whose own countdown is only what remained, so measuring from that restarted the
  /// bar at full after every tap. A rest saved before the total was recorded falls back to the
  /// alarm's own length, and the bar never claims a rest shorter than what is left.
  @ViewBuilder
  private func progress(for state: AlarmPresentationState, metadata: RestMetadata?) -> some View {
    if case .countdown(let countdown) = state.mode {
      let total = max(metadata?.totalRest?.seconds ?? 0, countdown.totalCountdownDuration)
      let start = countdown.fireDate.addingTimeInterval(-total)
      ProgressView(timerInterval: start...max(start, countdown.fireDate), countsDown: true) {
        EmptyView()
      } currentValueLabel: {
        EmptyView()
      }
      .progressViewStyle(.linear)
      .tint(Tokens.Color.accent)
      .accessibilityHidden(true)
    }
  }
}
