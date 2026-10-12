import ActivityKit
import AlarmKit
import AppIntents
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
///
/// The extension also carries the two controls (`HardsetControls.swift`), Start workout and Rest,
/// and the two widgets that read the app's snapshot file (`HistoryWidgets.swift`), Last time and
/// Last workout.
@main
struct HardsetWidgetBundle: WidgetBundle {
  var body: some Widget {
    RestTimerLiveActivity()
    StartWorkoutControl()
    RestControl()
    LastTimeWidget()
    LastWorkoutWidget()
  }
}

extension RestActivityContent {
  /// AlarmKit's state into Core's mirror. A mode a future SDK adds is shown as finished, which
  /// offers no button that could act on a rest this build does not understand.
  static func make(_ state: AlarmPresentationState, metadata: RestMetadata?)
    -> RestActivityContent
  {
    let mode: Mode
    switch state.mode {
    case .countdown(let countdown):
      mode = .countdown(
        total: countdown.totalCountdownDuration,
        previouslyElapsed: countdown.previouslyElapsedDuration,
        startDate: countdown.startDate, fireDate: countdown.fireDate)
    case .paused(let paused):
      mode = .paused(
        total: paused.totalCountdownDuration, previouslyElapsed: paused.previouslyElapsedDuration)
    case .alert:
      mode = .alerting
    @unknown default:
      mode = .alerting
    }
    return make(mode: mode, metadata: metadata)
  }
}

struct RestTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<RestMetadata>.self) { context in
      RestLockScreenView(
        content: .make(context.state, metadata: context.attributes.metadata)
      )
      .activityBackgroundTint(nil)
    } dynamicIsland: { context in
      let content = RestActivityContent.make(context.state, metadata: context.attributes.metadata)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          RestRing(phase: content.phase).frame(width: 44, height: 44)
        }
        DynamicIslandExpandedRegion(.center) {
          RestTitle(content: content)
        }
        DynamicIslandExpandedRegion(.trailing) {
          RestClock(phase: content.phase).font(Tokens.Text.readout)
        }
        DynamicIslandExpandedRegion(.bottom) {
          RestControls(controls: content.controls)
        }
      } compactLeading: {
        RestRing(phase: content.phase).frame(width: 20, height: 20)
      } compactTrailing: {
        RestClock(phase: content.phase).monospacedDigit().frame(maxWidth: 52)
      } minimal: {
        RestRing(phase: content.phase)
      }
    }
  }
}

/// The ring. System-animated from the range, so nothing here ticks.
struct RestRing: View {
  let phase: RestActivityContent.Phase

  var body: some View {
    Group {
      switch phase {
      case .counting(let range):
        ProgressView(timerInterval: range, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
      case .paused(_, let fractionRemaining):
        ProgressView(value: fractionRemaining)
      case .finished:
        Image(systemName: "checkmark.circle.fill")
      }
    }
    .progressViewStyle(.circular)
    .tint(Tokens.Color.accent)
    .accessibilityHidden(true)
  }
}

/// The countdown. `Text(timerInterval:)` is system-rendered from the same range as the ring.
struct RestClock: View {
  let phase: RestActivityContent.Phase

  var body: some View {
    switch phase {
    case .counting(let range): Text(timerInterval: range, countsDown: true)
    case .paused(let remaining, _): Text(remaining.clockString)
    case .finished: Text("Done")
    }
  }
}

struct RestTitle: View {
  let content: RestActivityContent

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(content.title).font(.headline).lineLimit(1)
      if let detail = content.detail {
        Text(detail).font(Tokens.Text.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      if let status = content.statusText {
        Text(status).font(Tokens.Text.caption)
      }
    }
  }
}

/// Pause, Resume and Skip, each a `LiveActivityIntent` performed in the app.
struct RestControls: View {
  let controls: [RestActivityContent.Control]

  var body: some View {
    HStack(spacing: Tokens.Spacing.regular) {
      ForEach(controls, id: \.self) { control in
        button(for: control)
          .buttonStyle(.bordered)
          .tint(Tokens.Color.accent)
          .accessibilityLabel(control.spokenLabel)
      }
    }
  }

  @ViewBuilder private func button(for control: RestActivityContent.Control) -> some View {
    let label = Label(control.title, systemImage: control.symbolName)
      .frame(minWidth: Tokens.minimumTapTarget, minHeight: Tokens.minimumTapTarget)
    switch control {
    case .pause: Button(intent: PauseRestIntent()) { label }
    case .resume: Button(intent: ResumeRestIntent()) { label }
    case .stop: Button(intent: StopRestIntent()) { label }
    }
  }
}

struct RestLockScreenView: View {
  let content: RestActivityContent

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      HStack(spacing: Tokens.Spacing.regular) {
        RestRing(phase: content.phase).frame(width: 44, height: 44)
        RestTitle(content: content)
        Spacer(minLength: 0)
        RestClock(phase: content.phase).font(Tokens.Text.readout).monospacedDigit()
      }
      if !content.controls.isEmpty {
        RestControls(controls: content.controls)
      }
    }
    .padding(Tokens.Spacing.loose)
  }
}
