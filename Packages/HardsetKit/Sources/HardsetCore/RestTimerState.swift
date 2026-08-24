import Foundation

/// Invariant: rest is an absolute deadline or a frozen remainder -- never a ticking
/// count of seconds, and never both at once.
///
/// Expressed as an enum so "both set" is not representable rather than merely discouraged.
/// A remaining-seconds `Int` would drift across backgrounding, force-quit and clock
/// changes; a `Date` survives all three. AlarmKit's paused presentation carries only
/// durations and no dates (verified in the iOS 26.4 SDK: `AlarmPresentationState.Mode.Paused`
/// has `totalCountdownDuration` and `previouslyElapsedDuration` only), so the app must own
/// the deadline itself.
public enum RestTimerState: Hashable, Sendable, Codable {
  case idle
  /// Counting down toward an absolute instant.
  case running(endsAt: Date)
  /// Frozen with this much left. No deadline exists while paused.
  case paused(remaining: Duration)

  /// Time left at `now`, clamped at zero. `nil` when idle.
  public func remaining(at now: Date) -> Duration? {
    switch self {
    case .idle:
      return nil
    case .running(let endsAt):
      let seconds = endsAt.timeIntervalSince(now)
      return .seconds(max(0, seconds))
    case .paused(let remaining):
      return remaining
    }
  }

  public var isRunning: Bool { if case .running = self { true } else { false } }

  public func hasElapsed(at now: Date) -> Bool {
    guard case .running(let endsAt) = self else { return false }
    return now >= endsAt
  }

  /// Freeze a running timer. Idle and already-paused states are returned unchanged.
  public func paused(at now: Date) -> RestTimerState {
    guard case .running = self, let left = remaining(at: now) else { return self }
    return .paused(remaining: left)
  }

  /// Convert a frozen remainder back into a deadline measured from `now`.
  public func resumed(at now: Date) -> RestTimerState {
    guard case .paused(let remaining) = self else { return self }
    // Nothing left to resume. A paused timer can reach zero -- pause with a second on the clock and
    // adjust it down, or pause exactly at the end -- and resuming it used to produce
    // `.running(endsAt: now)`: a running timer whose deadline has already passed. Nothing would
    // schedule an alarm for it (the commit path requires a positive remainder) and nothing would end
    // it, so the bar sat at zero claiming to be running.
    guard remaining.seconds > 0 else { return .idle }
    return .running(endsAt: now.addingTimeInterval(remaining.seconds))
  }

  /// Shift the deadline by `delta` (the +/-15s controls), clamped so it never lands in
  /// the past. Adjusting a paused timer moves the remainder instead.
  public func adjusted(by delta: Duration, at now: Date) -> RestTimerState {
    switch self {
    case .idle:
      return self
    case .running(let endsAt):
      let shifted = endsAt.addingTimeInterval(delta.seconds)
      return .running(endsAt: max(shifted, now))
    case .paused(let remaining):
      return .paused(remaining: .seconds(max(0, remaining.seconds + delta.seconds)))
    }
  }
}

// MARK: - Storage projection

extension RestTimerState {
  /// Flat, two-column form for persistence. Exactly one of the two is non-nil, or both
  /// are nil when idle -- the enum guarantees the third combination cannot be written.
  public var storage: (endsAt: Date?, pausedRemainingSeconds: Double?) {
    switch self {
    case .idle: (nil, nil)
    case .running(let endsAt): (endsAt, nil)
    case .paused(let remaining): (nil, remaining.seconds)
    }
  }

  /// Rebuild from persisted columns, rejecting the impossible both-set row rather than
  /// silently preferring one. A row that violates the invariant is corruption and the
  /// caller must decide what to do about it.
  public init(endsAt: Date?, pausedRemainingSeconds: Double?) throws {
    switch (endsAt, pausedRemainingSeconds) {
    case (nil, nil):
      self = .idle
    case (let date?, nil):
      self = .running(endsAt: date)
    case (nil, let seconds?):
      guard seconds >= 0 else { throw RestTimerStateError.negativeRemaining }
      self = .paused(remaining: .seconds(seconds))
    case (.some, .some):
      throw RestTimerStateError.bothDeadlineAndRemainingSet
    }
  }
}

public enum RestTimerStateError: Error, Equatable, Sendable {
  case bothDeadlineAndRemainingSet
  case negativeRemaining
}

extension Duration {
  /// Seconds as a `Double`, including the attosecond remainder.
  public var seconds: Double {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
