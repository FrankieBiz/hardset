import HardsetCore

/// Hooks the app supplies for the rest timer.
///
/// This exists so the composition root can live in a package target that builds on the host.
/// `RestTimerController` imports AlarmKit, which ships only in the iPhoneOS SDK, so depending
/// on it here would make this target — and therefore the wiring — iOS-only and unverifiable
/// outside a simulator. The app passes the controller's methods in; everything else is testable.
///
/// The default is inert rather than a fake timer: a preview or a host build shows no rest
/// running, which is honest, instead of a countdown that is not backed by an alarm.
@MainActor
public struct RestTimerHooks {
  public var metadata: () -> RestMetadata?
  public var hasError: () -> Bool
  /// What is wrong with the rest timer, so the interface can say it in the right words and offer
  /// the action that can actually help. `nil` while it works. `hasError` stays for callers that
  /// only need to know that something is wrong.
  public var issue: () -> RestTimerIssue?
  public var retry: () -> Void
  /// Replaces a saved rest that cannot be read with no rest. Offered only for
  /// `RestTimerIssue.recoveryFailed`, where a retry re-reads the same row and fails again.
  public var resetRestTimer: () -> Void
  public var state: () -> RestTimerState
  public var start: (Duration, RestMetadata) -> Void
  public var adjust: (Duration) -> Void
  public var pauseOrResume: () -> Void
  public var cancel: () -> Void

  public init(
    state: @escaping () -> RestTimerState = { .idle },
    metadata: @escaping () -> RestMetadata? = { nil },
    hasError: @escaping () -> Bool = { false },
    issue: @escaping () -> RestTimerIssue? = { nil },
    retry: @escaping () -> Void = {},
    resetRestTimer: @escaping () -> Void = {},
    start: @escaping (Duration, RestMetadata) -> Void = { _, _ in },
    adjust: @escaping (Duration) -> Void = { _ in },
    pauseOrResume: @escaping () -> Void = {},
    cancel: @escaping () -> Void = {}
  ) {
    self.metadata = metadata
    self.hasError = hasError
    self.issue = issue
    self.retry = retry
    self.resetRestTimer = resetRestTimer
    self.state = state
    self.start = start
    self.adjust = adjust
    self.pauseOrResume = pauseOrResume
    self.cancel = cancel
  }

  public static var inert: RestTimerHooks { RestTimerHooks() }
}

/// Why the rest timer cannot do its whole job, told apart so each case gets honest words and an
/// action that can work.
public enum RestTimerIssue: Equatable, Sendable {
  /// Alarm permission is off for Hardset. The countdown still runs in the app and ends at its
  /// deadline, but nothing alerts. Only Settings can change this, so there is nothing to retry.
  case alarmsDenied
  /// A rest could not be saved or its alarm could not be scheduled. Retrying can succeed.
  case unavailable
  /// The saved rest could not be read at launch, so timer commands wait. Retrying re-reads it;
  /// if it is unreadable, resetting the rest timer is the way out.
  case recoveryFailed
}
