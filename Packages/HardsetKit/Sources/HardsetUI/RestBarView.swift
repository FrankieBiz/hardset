import HardsetCore
import SwiftUI

/// The rest countdown, and the controls for it.
///
/// The countdown is rendered by `Text(timerInterval:)`, which the system animates from an
/// absolute deadline. That is not a stylistic choice — it is the reason this view has no timer,
/// no `TimelineView`, and no `@State` that ticks. A 1 Hz publisher redrawing the screen is what
/// made the ancestor app re-run its database queries thirty times a second, and a
/// remaining-seconds counter is what makes a timer wrong after backgrounding.
///
/// The paused case cannot use `Text(timerInterval:)` at all: AlarmKit's paused presentation
/// carries only durations and no dates, so there is no deadline to hand SwiftUI. It renders as
/// static text from the frozen remainder instead, which is why `RestTimerState` models paused
/// as a `Duration` rather than as a stopped clock.
///
/// Laid out as one line when the countdown, its caption and four 56 pt controls fit, and as two
/// lines — countdown above, controls below at equal widths — when they do not. Four 56 pt
/// controls reserve over 300 pt on their own, so on most phones the second form is the one in use,
/// and the countdown keeps its full size instead of being squeezed into what is left.
public struct RestBarView: View {
  private let state: RestTimerState
  private let metadata: RestMetadata?
  private let referenceDate: Date
  private let onAdjust: (Duration) -> Void
  private let onPauseResume: () -> Void
  private let onSkip: () -> Void

  public init(
    state: RestTimerState,
    metadata: RestMetadata? = nil,
    referenceDate: Date = Date(),
    onAdjust: @escaping (Duration) -> Void,
    onPauseResume: @escaping () -> Void,
    onSkip: @escaping () -> Void
  ) {
    self.state = state
    self.metadata = metadata
    self.referenceDate = referenceDate
    self.onAdjust = onAdjust
    self.onPauseResume = onPauseResume
    self.onSkip = onSkip
  }

  public var body: some View {
    if case .idle = state {
      EmptyView()
    } else {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: Tokens.Spacing.regular) {
          status
          Spacer(minLength: Tokens.Spacing.snug)
          controls
            .fixedSize()
        }
        VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
          status
          controls
        }
      }
      .padding(Tokens.Spacing.regular)
      .background(Tokens.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
      .overlay(
        RoundedRectangle(cornerRadius: Tokens.Radius.card)
          .strokeBorder(Tokens.Color.border, lineWidth: Tokens.Stroke.hairline)
      )
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.bottom, Tokens.Spacing.snug)
      // The countdown is one element and each control is its own, so a VoiceOver user can hear
      // the time and still reach "Plus 15 seconds" directly. Combining the whole bar made the
      // controls unreachable.
      .accessibilityElement(children: .contain)
    }
  }

  /// The countdown and what it is resting after.
  private var status: some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
      countdown
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(state.isRunning ? "Resting" : "Paused")
          .font(Tokens.Text.sectionHeader)
          .foregroundStyle(state.isRunning ? Tokens.Color.accent : Tokens.Color.textSecondary)
        if let metadata {
          Text("\(metadata.exerciseName), \(metadata.setLabel.lowercased())")
            .font(Tokens.Text.caption)
            .foregroundStyle(Tokens.Color.textSecondary)
            .lineLimit(2)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel)
  }

  @ViewBuilder private var countdown: some View {
    switch state {
    case .idle:
      EmptyView()
    case .running(let endsAt):
      // System-rendered from the deadline. Costs zero updates and survives backgrounding,
      // because there is nothing of ours to keep running.
      Text(timerInterval: referenceDate...max(endsAt, referenceDate), countsDown: true)
        .font(Tokens.Text.hero)
        .foregroundStyle(Tokens.Color.textPrimary)
        .lineLimit(1)
        .fixedSize()
    case .paused(let remaining):
      Text(remaining.clockString)
        .font(Tokens.Text.hero)
        .foregroundStyle(Tokens.Color.textSecondary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  /// The ±15 labels begin with what the keys show, "−15" read as "Minus 15", so a Voice Control
  /// user can say what they see; the older "Subtract 15 seconds" still answers.
  private var controls: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      control(
        title: "−15",
        systemImage: nil,
        accessibilityLabel: "Minus 15 seconds",
        inputLabels: ["Minus 15", "Subtract 15 seconds"]
      ) { onAdjust(.seconds(-15)) }
      control(
        title: "+15",
        systemImage: nil,
        accessibilityLabel: "Plus 15 seconds",
        inputLabels: ["Plus 15", "Add 15 seconds"]
      ) { onAdjust(.seconds(15)) }
      control(
        title: nil,
        systemImage: state.isRunning ? "pause.fill" : "play.fill",
        accessibilityLabel: state.isRunning ? "Pause rest" : "Resume rest",
        action: onPauseResume
      )
      control(
        title: nil,
        systemImage: "forward.end.fill",
        accessibilityLabel: "Skip rest",
        action: onSkip
      )
    }
  }

  /// A rest control: a 56 pt key, with a figure or a symbol.
  private func control(
    title: String?,
    systemImage: String?,
    accessibilityLabel: String,
    inputLabels: [String] = [],
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Group {
        if let title {
          Text(title)
            .font(Tokens.Text.figure)
        } else if let systemImage {
          Image(systemName: systemImage)
            .font(Tokens.Text.headline)
        }
      }
      .frame(minWidth: Tokens.loggerTapTarget)
    }
    .buttonStyle(HardsetKeyStyle())
    .accessibilityLabel(accessibilityLabel)
    .accessibilityInputLabels(inputLabels.isEmpty ? [accessibilityLabel] : inputLabels)
  }

  /// What VoiceOver reads for the countdown.
  ///
  /// The running case embeds the same system-rendered timer as the visible countdown. Nothing
  /// re-renders this view while a rest runs, so a time computed here would be the time left when
  /// the bar was drawn, read back unchanged a minute later. The paused remainder is frozen, so a
  /// fixed string is already correct.
  private var spokenLabel: Text {
    let after = metadata.map { ", after \($0.exerciseName), \($0.setLabel)" } ?? ""
    switch state {
    case .idle:
      return Text(verbatim: "Not resting")
    case .running(let endsAt):
      let left = Text(timerInterval: referenceDate...max(endsAt, referenceDate), countsDown: true)
      return Text("Resting, \(left) remaining\(after)")
    case .paused(let remaining):
      return Text(verbatim: "Rest paused, \(remaining.clockString) remaining\(after)")
    }
  }

}

#if DEBUG
  #Preview("Rest bar") {
    VStack(spacing: Tokens.Spacing.loose) {
      RestBarView(
        state: .running(endsAt: Date().addingTimeInterval(96)),
        metadata: RestMetadata(
          exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4,
          machineName: "Hammer Strength"
        ),
        onAdjust: { _ in }, onPauseResume: {}, onSkip: {}
      )
      RestBarView(
        state: .paused(remaining: .seconds(75)),
        metadata: RestMetadata(exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4),
        onAdjust: { _ in }, onPauseResume: {}, onSkip: {}
      )
    }
    .padding(.vertical)
    .background(Tokens.Color.background)
  }
#endif
