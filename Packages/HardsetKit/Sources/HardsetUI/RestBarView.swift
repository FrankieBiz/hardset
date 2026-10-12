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
/// This is the one rest cluster. It is built to live in the tab bar's bottom accessory, which is
/// already Liquid Glass, so inside it the view draws no background of its own and adapts to the
/// accessory's `.inline` (collapsed tab bar) and `.expanded` placements.
public struct RestBarView: View {
  private let state: RestTimerState
  private let metadata: RestMetadata?
  private let referenceDate: Date
  private let onAdjust: (Duration) -> Void
  private let onPauseResume: () -> Void
  private let onSkip: () -> Void
  private let onOpen: (() -> Void)?

  #if os(iOS)
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  #endif
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var adjustCount = 0
  // In the logger the buttons grow with the type, between the 56 pt floor and the 88 pt cap.
  // `@ScaledMetric` also scales down below Large, so the floor is applied, not assumed
  // (`Tokens.tapTarget`). The accessory's are a fixed 44 pt: see `tapTarget`.
  @ScaledMetric(relativeTo: .body) private var scaledLoggerTarget: CGFloat = Tokens.loggerTapTarget

  public init(
    state: RestTimerState,
    metadata: RestMetadata? = nil,
    referenceDate: Date = Date(),
    onAdjust: @escaping (Duration) -> Void,
    onPauseResume: @escaping () -> Void,
    onSkip: @escaping () -> Void,
    onOpen: (() -> Void)? = nil
  ) {
    self.state = state
    self.metadata = metadata
    self.referenceDate = referenceDate
    self.onAdjust = onAdjust
    self.onPauseResume = onPauseResume
    self.onSkip = onSkip
    self.onOpen = onOpen
  }

  /// True when hosted in the tab accessory, which supplies its own glass and is short.
  private var inAccessory: Bool {
    #if os(iOS)
      placement != nil
    #else
      false
    #endif
  }

  /// True when the tab bar is collapsed and the accessory shows only the countdown and pause.
  private var isInline: Bool {
    #if os(iOS)
      placement == .inline
    #else
      false
    #endif
  }

  /// The accessory is a fixed-height system slot, so its buttons do not grow with the type: at the
  /// largest size a scaled 44 pt reached about 137, and four of them pushed the countdown out of
  /// the slot. They stay at the 44 pt floor. Collapsed, the controls the slot has no room for are
  /// the countdown's VoiceOver actions (see `body`).
  private var tapTarget: CGFloat {
    inAccessory
      ? Tokens.minimumTapTarget
      : Tokens.tapTarget(scaledLoggerTarget, floor: Tokens.loggerTapTarget)
  }

  /// Only a running rest is adjusted. AlarmKit cannot change a paused alarm's remainder, so ±15
  /// while paused would leave this bar and the Lock Screen disagreeing about the rest. Resume
  /// first, then adjust.
  private var canAdjust: Bool { state.isRunning }

  public var body: some View {
    if case .idle = state {
      EmptyView()
    } else {
      HStack(spacing: Tokens.Spacing.regular) {
        readout
          // Collapsed, the accessory draws only the countdown and pause, so -15, +15 and skip
          // would be unreachable by VoiceOver. They are offered as actions on the countdown.
          .accessibilityActions {
            if isInline {
              if canAdjust {
                Button("Subtract 15 seconds") {
                  adjustCount += 1
                  onAdjust(.seconds(-15))
                }
                Button("Add 15 seconds") {
                  adjustCount += 1
                  onAdjust(.seconds(15))
                }
              }
              Button("Skip rest", action: onSkip)
            }
          }

        Spacer(minLength: 0)

        if !isInline && canAdjust {
          adjustButton(label: "−15", delta: .seconds(-15))
          adjustButton(label: "+15", delta: .seconds(15))
        }
        pauseResumeButton
        if !isInline {
          skipButton
        }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, inAccessory ? 0 : Tokens.Spacing.snug)
      // The accessory is already glass; glass on an opaque fill (or on glass) is wrong.
      .background {
        if !inAccessory { Tokens.Color.surface }
      }
      .sensoryFeedback(Tokens.Haptic.feedback(for: .restAdjust), trigger: adjustCount)
    }
  }

  /// The countdown and, when there is room, the caption. It opens the workout when tapped.
  /// Without an `onOpen` it is plain content rather than a disabled button, which the system
  /// would dim. Only this element carries the spoken status; the controls beside it keep their
  /// own labels so VoiceOver can reach each of them.
  @ViewBuilder private var readout: some View {
    if let onOpen {
      Button(action: onOpen) { readoutContent }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Opens the workout")
    } else {
      readoutContent
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
  }

  private var readoutContent: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
      countdown
      if let metadata, !isInline {
        Text("\(metadata.exerciseName) · \(metadata.setLabel)")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
          .lineLimit(1)
      }
    }
    .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
    .contentShape(Rectangle())
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
          .contentTransition(.numericText(countsDown: true))
          .animation(Tokens.Motion.quick(reduceMotion), value: remaining)
        Image(systemName: "pause.fill")
          .font(Tokens.Text.caption)
      }
      .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  private func adjustButton(label: String, delta: Duration) -> some View {
    Button {
      adjustCount += 1
      onAdjust(delta)
    } label: {
      Text(label)
        .font(Tokens.Text.label.weight(.semibold))
        .monospacedDigit()
        .frame(minWidth: tapTarget, minHeight: tapTarget)
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
        .frame(width: tapTarget, height: tapTarget)
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
        .frame(width: tapTarget, height: tapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(Tokens.Color.textSecondary)
    .accessibilityLabel("Skip rest")
  }

  /// A running rest is spoken by its end time, not its remaining time: this label is built with the
  /// view, and the accessory rebuilds it only when the timer's state changes, so a remaining time
  /// would still say "2:00" a minute later. The end time stays true whenever it is read.
  private var spokenLabel: String {
    var parts: [String]
    switch state {
    case .idle:
      return "Not resting"
    case .running(let endsAt):
      parts = ["Resting until \(endsAt.formatted(date: .omitted, time: .shortened))"]
    case .paused(let remaining):
      parts = ["Rest paused, \(remaining.clockString) remaining"]
    }
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
