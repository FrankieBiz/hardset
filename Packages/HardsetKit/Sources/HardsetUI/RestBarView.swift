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
      HStack(spacing: Tokens.Spacing.regular) {
        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          countdown
          if let metadata {
            Text("\(metadata.exerciseName) · \(metadata.setLabel)")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)

        adjustButton(label: "−15", delta: .seconds(-15))
        adjustButton(label: "+15", delta: .seconds(15))
        pauseResumeButton
        skipButton
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .background(Tokens.Color.surface)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(spokenLabel)
    }
  }

  @ViewBuilder private var countdown: some View {
    switch state {
    case .idle:
      EmptyView()
    case .running(let endsAt):
      // System-rendered from the deadline. Costs zero updates and survives backgrounding,
      // because there is nothing of ours to keep running.
      Text(timerInterval: referenceDate...max(endsAt, referenceDate), countsDown: true)
        .font(Tokens.Text.readout)
        .foregroundStyle(Tokens.Color.textPrimary)
    case .paused(let remaining):
      HStack(spacing: Tokens.Spacing.tight) {
        Text(remaining.clockString)
          .font(Tokens.Text.readout)
        Image(systemName: "pause.fill")
          .font(Tokens.Text.caption)
      }
      .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  private func adjustButton(label: String, delta: Duration) -> some View {
    Button { onAdjust(delta) } label: {
      Text(label)
        .font(Tokens.Text.label.weight(.semibold))
        .monospacedDigit()
        .frame(minWidth: Tokens.loggerTapTarget, minHeight: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Tokens.Color.accent)
    .accessibilityLabel(delta.seconds < 0 ? "Subtract 15 seconds" : "Add 15 seconds")
  }

  private var pauseResumeButton: some View {
    Button(action: onPauseResume) {
      Image(systemName: state.isRunning ? "pause.circle" : "play.circle")
        .font(.title2)
        .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Tokens.Color.accent)
    .accessibilityLabel(state.isRunning ? "Pause rest" : "Resume rest")
  }

  private var skipButton: some View {
    Button(action: onSkip) {
      Image(systemName: "forward.end")
        .font(.body)
        .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Tokens.Color.textSecondary)
    .accessibilityLabel("Skip rest")
  }

  private var spokenLabel: String {
    guard let remaining = state.remaining(at: referenceDate) else { return "Not resting" }
    let status = state.isRunning ? "Resting" : "Rest paused"
    var parts = ["\(status), \(remaining.clockString) remaining"]
    if let metadata { parts.append("after \(metadata.exerciseName), \(metadata.setLabel)") }
    return parts.joined(separator: ", ")
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
    .padding()
    .background(Tokens.Color.background)
  }
#endif
