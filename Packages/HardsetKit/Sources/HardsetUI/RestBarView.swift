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
  // No `accessibilityReduceMotion` here on purpose. The rule's retreat *is* the timer and runs
  // regardless (§5.4, M7), and the only things the setting would switch off in this view -- §5.4's
  // final-ten-seconds breathing and symbol pulse -- are not built yet. It comes back with them.
  /// Drives the stacked layout. The controls are four hard 56 pt targets plus spacing and padding --
  /// 284 pt that cannot yield -- and the countdown is the only flexible child, so at accessibility
  /// sizes the one thing this bar exists to show was the thing that got compressed. `SetRowView`
  /// already restacks for exactly this reason; the bar pinned to the bottom of the same screen did
  /// not.
  @Environment(\.dynamicTypeSize) private var typeSize
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
      Group {
        if typeSize.isAccessibilitySize { stackedBar } else { compactBar }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .background(Tokens.Color.surface)
      // The rule sits on the top edge and retreats right to left. An overlay rather than a row so
      // it cannot push the controls around as it shrinks.
      .overlay(alignment: .top) { progressRule }
      // `.contain`, not `.combine`: combining flattened the live countdown into a static string.
      .accessibilityElement(children: .contain)
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

  /// Countdown and controls on one row, which fits at ordinary text sizes.
  @ViewBuilder private var compactBar: some View {
    HStack(spacing: Tokens.Spacing.regular) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        countdown
        stationLabel.lineLimit(1)
      }

      Spacer(minLength: 0)

      adjustButton(label: "\u{2212}15", delta: .seconds(-15))
      adjustButton(label: "+15", delta: .seconds(15))
      pauseResumeButton
      skipButton
    }
  }

  /// Countdown above, controls below, both allowed their full size.
  ///
  /// The station line drops its `lineLimit` here: "Leg…" is worse than two lines, and the whole
  /// reason to restack is that there is room once the controls are not competing for it.
  @ViewBuilder private var stackedBar: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      countdown
      stationLabel
      HStack(spacing: Tokens.Spacing.snug) {
        adjustButton(label: "\u{2212}15", delta: .seconds(-15))
        adjustButton(label: "+15", delta: .seconds(15))
        pauseResumeButton
        skipButton
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var stationLabel: some View {
    if let metadata {
      Text("\(metadata.exerciseName) \u{00B7} \(metadata.setLabel)")
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder private var progressRule: some View {
    if total != nil {
      GeometryReader { proxy in
        // Round caps, per §5.4. A square-ended rule reads as a progress *bar*; the spec asks for a
        // rule, and at 2 pt the cap is most of what distinguishes the two.
        Capsule()
          .fill(Tokens.Color.hairline)
          .overlay(alignment: .leading) {
            Capsule()
              .fill(Tokens.Color.textPrimary)
              .frame(width: max(Tokens.restRuleHeight, proxy.size.width * fraction))
          }
      }
      .frame(height: Tokens.restRuleHeight)
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
      // Runs regardless of Reduce Motion, and that is deliberate: §5.4 says "the rule still
      // retreats -- it is the timer (M7)". This is not decoration. It is the only continuous
      // depiction of how much rest is left, and freezing it leaves a bar that shows a static
      // fraction while the clock beside it counts down. The setting asks for less *motion*, not for
      // less information -- and what it does switch off here is the escalating haptics near zero.
      //
      // A previous sweep of this file counted the `guard !reduceMotion` that used to sit here as
      // correct handling. Guarding an animation is only correct when the animation is ornament.
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
        // Left as its own accessible element, with the trait that tells VoiceOver to re-read it.
        // The container used to `.combine` its children and replace them with one authored string,
        // and that string was computed from `referenceDate` -- a `let` fixed when the view was
        // built. Since this view deliberately never re-renders while resting, a blind lifter heard
        // one figure for the entire rest period while a sighted one watched it count down.
        .accessibilityAddTraits(.updatesFrequently)
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
        .font(Tokens.Text.glyph)
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
        .font(Tokens.Text.glyph)
        .frame(width: Tokens.loggerTapTarget, height: Tokens.loggerTapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Tokens.Color.textSecondary)
    .accessibilityLabel("Skip rest")
  }

  /// Describes the rest without stating how much is left.
  ///
  /// The figure is deliberately absent while running: this view has no timer by design, so any
  /// number baked in here is the one that happened to be true when the view was last built. The
  /// live countdown is its own element and speaks for itself. A paused remainder *is* static, so
  /// there it is stated.
  private var spokenLabel: String {
    switch state {
    case .idle:
      return "Not resting"
    case .running:
      var parts = ["Resting"]
      if let metadata { parts.append("after \(metadata.exerciseName), \(metadata.setLabel)") }
      return parts.joined(separator: ", ")
    case .paused(let remaining):
      var parts = ["Rest paused, \(remaining.clockString) remaining"]
      if let metadata { parts.append("after \(metadata.exerciseName), \(metadata.setLabel)") }
      return parts.joined(separator: ", ")
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
    .padding()
    .background(Tokens.Color.ground)
  }
#endif
