import Foundation

/// What AlarmKit reports about one alarm, reduced to what reconciliation needs.
///
/// A mirror rather than AlarmKit's own type, because AlarmKit exists only in the iPhoneOS SDK and
/// this logic must be testable off-device. Optional details are optional on purpose: when the
/// framework does not expose a value, the reconciler is told so rather than handed a guess.
public struct AlarmSnapshot: Hashable, Sendable {
  public enum Mode: Hashable, Sendable {
    case countdown(fireDate: Date?)
    case paused(remaining: Duration?)
    case alerting
  }

  public let id: UUID
  public let mode: Mode

  public init(id: UUID, mode: Mode) {
    self.id = id
    self.mode = mode
  }
}

/// The rest timer as it was last written to the device.
public struct PersistedRest: Hashable, Sendable {
  public let state: RestTimerState
  public let alarmID: UUID?

  public init(state: RestTimerState, alarmID: UUID?) {
    self.state = state
    self.alarmID = alarmID
  }
}

/// The corrected rest state, and the alarms nothing on screen accounts for.
public struct RestReconciliation: Hashable, Sendable {
  public let state: RestTimerState
  public let alarmID: UUID?
  /// Alarms to cancel. Leaving them would ring for a rest the app no longer shows.
  public let staleAlarmIDs: [UUID]

  public init(state: RestTimerState, alarmID: UUID?, staleAlarmIDs: [UUID]) {
    self.state = state
    self.alarmID = alarmID
    self.staleAlarmIDs = staleAlarmIDs
  }
}

/// Decides what the rest timer really is, from what was persisted and what alarms exist.
///
/// Runs at launch and on every AlarmKit update. Without it a force-quit relaunched the app idle
/// while an alarm still counted down, and a pause from the Lock Screen left the app showing a
/// deadline that no longer existed. The rule throughout: the alarm is the truth when it can be
/// read, the persisted record fills only what the alarm cannot say, and nothing is guessed.
public enum RestReconciler {
  public static func reconcile(
    persisted: PersistedRest?,
    alarms: [AlarmSnapshot],
    now: Date
  ) -> RestReconciliation {
    let matched = persisted?.alarmID.flatMap { id in alarms.first { $0.id == id } }

    guard let alarm = matched else {
      return adoptOrDiscard(persisted: persisted, alarms: alarms)
    }
    let others = alarms.map(\.id).filter { $0 != alarm.id }

    switch alarm.mode {
    case .countdown(let fireDate?):
      return RestReconciliation(
        state: .running(endsAt: fireDate), alarmID: alarm.id, staleAlarmIDs: others)
    case .countdown(nil):
      // The alarm exists and is counting; only the persisted deadline says when it ends.
      guard case .running = persisted?.state else {
        return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: [alarm.id] + others)
      }
      return RestReconciliation(
        state: persisted!.state, alarmID: alarm.id, staleAlarmIDs: others)
    case .paused(let remaining?):
      return RestReconciliation(
        state: .paused(remaining: remaining), alarmID: alarm.id, staleAlarmIDs: others)
    case .paused(nil):
      // A remainder we cannot read is never invented from a deadline.
      if case .paused = persisted?.state {
        return RestReconciliation(
          state: persisted!.state, alarmID: alarm.id, staleAlarmIDs: others)
      }
      return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: [alarm.id] + others)
    case .alerting:
      // The rest is over and the system is presenting the alert. Cancelling it here would
      // silence the very alert the lifter is waiting for.
      return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: others)
    }
  }

  /// No persisted alarm matched. Adopt a single explicable countdown, discard the rest.
  private static func adoptOrDiscard(
    persisted: PersistedRest?, alarms: [AlarmSnapshot]
  ) -> RestReconciliation {
    let persistedIsIdle = persisted == nil || persisted?.state == .idle
    if persistedIsIdle, alarms.count == 1, case .countdown(let fireDate?) = alarms[0].mode {
      // The app died between scheduling and persisting. One countdown is explicable; it is ours.
      return RestReconciliation(
        state: .running(endsAt: fireDate), alarmID: alarms[0].id, staleAlarmIDs: [])
    }
    return RestReconciliation(state: .idle, alarmID: nil, staleAlarmIDs: alarms.map(\.id))
  }
}
