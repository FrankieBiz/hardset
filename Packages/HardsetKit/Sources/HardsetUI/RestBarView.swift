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
  private let total: Duration?
  private let referenceDate: Date

  /// How much rest is left, as a fraction. Driven by **one** animation, set when the state
  /// changes and never ticked.
  ///
  /// This is the whole technique: `withAnimation(.linear(duration: remaining))` retargets the
  /// value to zero once, and SwiftUI interpolates it for the entire rest period. There is no
  /// timer, no `TimelineView` and no per-second redraw -- a 1 Hz publisher here is what made the
  /// ancestor app re-run its database queries thirty times a second.
  ///
  /// Linear, not eased. The rule represents elapsed time, and easing it would show time slowing
  /// down.
  @State private var fraction: Double = 1
  /// Bumped at T-3, T-2 and T-1 so a haptic can fire without anything polling.
  @State private var finalSecondsPulse = 0
  /// Bumped once when the rest actually runs out, as opposed to being skipped.
  @State private var completions = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let onAdjust: (Duration) -> Void
  private let onPauseResume: () -> Void
  private let onSkip: () -> Void

  /// - Parameter total: The full rest length, needed to turn "seconds remaining" into a fraction.
  ///   `nil` hides the rule rather than guessing a denominator.
  public init(
    state: RestTimerState,
    metadata: RestMetadata? = nil,
    total: Duration? = nil,
    referenceDate: Date = Date(),
    onAdjust: @escaping (Duration) -> Void,
    onPauseResume: @escaping () -> Void,
    onSkip: @escaping () -> Void
  ) {
    self.state = state
    self.metadata = metadata
    self.total = total
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
      // The rule sits on the top edge and retreats right to left. An overlay rather than a row so
      // it cannot push the controls around as it shrinks.
      .overlay(alignment: .top) { progressRule }
      .accessibilityElement(children: .combine)
      // The rule is decoration *of* the countdown, which is already spoken. Hiding it keeps the
      // bar one element instead of two.
      .accessibilityLabel(spokenLabel)
      .onAppear { retarget() }
      .onChange(of: state) { retarget() }
      // Four one-shot sleeps derived from the deadline, not a ticking clock: nothing redraws, and
      // `.task(id:)` cancels the whole thing the moment the state changes -- so skipping or
      // pausing silences the cues rather than needing to be handled.
      .task(id: state) { await scheduleCues() }
      // A tap at three, two and one second left. In the foreground only, and that is a courtesy
      // rather than the mechanism: AlarmKit owns the alert that reaches a lifter whose phone is in
      // their pocket, and it is the only thing that survives Focus and a force-quit.
      .sensoryFeedback(.impact(weight: .light), trigger: finalSecondsPulse)
      .sensoryFeedback(.success, trigger: completions)
    }
  }

  @ViewBuilder private var progressRule: some View {
    if total != nil {
      GeometryReader { proxy in
        Rectangle()
          .fill(Tokens.Color.hairline)
          .overlay(alignment: .leading) {
            Rectangle()
              .fill(Tokens.Color.textPrimary)
              .frame(width: proxy.size.width * fraction)
          }
      }
      .frame(height: 2)
      .accessibilityHidden(true)
    }
  }

  /// Waits out the last three seconds and the finish, one sleep at a time.
  ///
  /// Deliberately not a loop and not a timer. Each cue is a single suspension until an absolute
  /// instant, so the view never re-renders on its account, and cancellation is automatic.
  private func scheduleCues() async {
    guard case .running(let endsAt) = state else { return }

    for secondsRemaining in [3.0, 2.0, 1.0] {
      let wait = endsAt.addingTimeInterval(-secondsRemaining).timeIntervalSinceNow
      guard wait > 0 else { continue }
      try? await Task.sleep(for: .seconds(wait))
      guard !Task.isCancelled else { return }
      finalSecondsPulse += 1
    }

    let toEnd = endsAt.timeIntervalSinceNow
    if toEnd > 0 {
      try? await Task.sleep(for: .seconds(toEnd))
      guard !Task.isCancelled else { return }
    }
    completions += 1
  }

  /// Snaps to the true position, then runs out linearly over exactly the time remaining.
  ///
  /// Two phases because they mean different things: the jump is a correction, and only the run-out
  /// represents elapsed time. Re-derived from the deadline every time it is called, so returning
  /// from the background or adjusting by fifteen seconds lands on the truth rather than on wherever
  /// an animation happened to be.
  private func retarget() {
    guard let total, total.seconds > 0 else { return }

    switch state {
    case .running(let endsAt):
      let remaining = endsAt.timeIntervalSince(Date())
      guard remaining > 0 else { snap(to: 0); return }
      snap(to: min(1, remaining / total.seconds))
      guard !reduceMotion else { return }
      withAnimation(Tokens.Motion.decay(remaining: remaining)) { fraction = 0 }

    case .paused(let remaining):
      // Frozen at the truth, not at wherever the interpolation had reached.
      snap(to: min(1, max(0, remaining.seconds / total.seconds)))

    case .idle:
      snap(to: 1)
    }
  }

  private func snap(to value: Double) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) { fraction = value }
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
    .background(Tokens.Color.ground)
  }
#endif
