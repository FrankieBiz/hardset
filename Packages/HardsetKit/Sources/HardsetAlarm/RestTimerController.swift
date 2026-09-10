#if canImport(AlarmKit)

import Foundation
import HardsetCore

/// Owns the rest timer the user sees, and keeps AlarmKit in sync with it.
///
/// ## Why adjustments are debounced
///
/// AlarmKit has **no API to change a running countdown** -- the full mutation surface is
/// `schedule`, `countdown`, `cancel`, `stop`, `pause`, `resume`. So "+15 s" is really
/// `cancel(id:)` followed by scheduling a replacement. Since `schedule` is `async throws`,
/// three fast taps would interleave three cancel/schedule pairs and the last one to land wins,
/// which is not necessarily the last one the user tapped.
///
/// The on-screen countdown therefore updates **synchronously and immediately**, and the
/// AlarmKit round-trip is coalesced behind a short debounce. The user never waits on the
/// framework, and AlarmKit is written exactly once per burst of taps.
@MainActor
@Observable
public final class RestTimerController {
  /// The truth the UI renders. A deadline or a frozen remainder -- never a countdown.
  public private(set) var state: RestTimerState = .idle
  public private(set) var lastError: (any Error)?
  /// True once AlarmKit has refused permission.
  ///
  /// Load-bearing, because the visible countdown does not need AlarmKit: `start` sets a deadline
  /// synchronously and the bar counts down from it regardless. Only the *alert* -- the part that
  /// survives backgrounding and a force-quit, which is the whole claim -- needs the framework. So an
  /// unauthorized install showed a perfectly normal running timer that would never make a sound,
  /// and `lastError` recorded why for nobody to read.
  public private(set) var isDenied = false

  private var alarmID: UUID?
  private var metadata: RestMetadata?
  private var commitTask: Task<Void, Never>?
  /// One sleep until the deadline, so a finished rest puts itself away.
  private var expiryTask: Task<Void, Never>?

  /// Where state changes are written so they survive the app being killed.
  ///
  /// A closure rather than a store, because `HardsetAlarm` depends on `HardsetCore` alone -- the
  /// same seam `RestTimerHooks` uses in the other direction. Unset in tests and previews, where
  /// persistence would be noise.
  public var persist: ((RestTimerState, UUID?) -> Void)?

  /// Long enough to absorb a burst of taps, short enough to feel immediate.
  private let debounce: Duration = .milliseconds(400)

  public init() {}

  public func start(duration: Duration, metadata: RestMetadata, now: Date = .now) {
    // Cancel what is already scheduled before losing the reference to it.
    //
    // `alarmID` was overwritten here without cancelling, so logging the next set before rest ran out
    // orphaned the previous alarm: nothing held its id any more, `commit` cancelled the *new* id,
    // and the old one fired in the middle of the following set.
    if let existing = alarmID { try? RestAlarmService.cancel(id: existing) }
    self.metadata = metadata
    state = .running(endsAt: now.addingTimeInterval(duration.seconds))
    alarmID = UUID()
    save()
    scheduleCommit()
    scheduleExpiry()
  }

  /// Asks for AlarmKit permission, once, at a moment the user will understand.
  ///
  /// Nothing called `RestAlarmService.requestAuthorization` anywhere in the app, so on a fresh
  /// install every `schedule` was refused and the rest timer silently never alerted. Called when the
  /// lifter picks a rest length, which is the point at which they have just asked for the feature.
  public func requestAuthorizationIfNeeded() async {
    guard !RestAlarmService.isAuthorized else {
      isDenied = false
      return
    }
    do {
      isDenied = try await RestAlarmService.requestAuthorization() == false
    } catch {
      lastError = error
      isDenied = true
    }
  }

  /// The +/-15 s controls. Updates the visible deadline at once; AlarmKit catches up.
  public func adjust(by delta: Duration, now: Date = .now) {
    guard state.isRunning || state.remaining(at: now) != nil else { return }
    state = state.adjusted(by: delta, at: now)
    save()
    scheduleCommit()
    scheduleExpiry()
  }

  public func pause(now: Date = .now) {
    guard state.isRunning else { return }
    state = state.paused(at: now)
    commitTask?.cancel()
    expiryTask?.cancel()
    expiryTask = nil
    save()
    if let alarmID { try? RestAlarmService.pause(id: alarmID) }
  }

  public func resume(now: Date = .now) {
    guard case .paused = state else { return }
    state = state.resumed(at: now)
    save()
    // Resuming shifts the deadline, and AlarmKit cannot be told a new one -- so the alarm is
    // replaced rather than resumed in place.
    scheduleCommit()
    scheduleExpiry()
  }

  public func cancel() {
    commitTask?.cancel()
    commitTask = nil
    expiryTask?.cancel()
    expiryTask = nil
    state = .idle
    if let alarmID { try? RestAlarmService.cancel(id: alarmID) }
    alarmID = nil
    metadata = nil
    save()
  }

  /// Puts back a timer read from storage at launch.
  ///
  /// A rest whose deadline has already passed is over: it goes to idle and its alarm is cancelled,
  /// rather than being restored as a running timer showing zero. Restoring a stale deadline is how a
  /// lifter opens the app the next morning to a rest bar from last night.
  ///
  /// A paused timer is restored as paused however long ago it was frozen -- that is the point of
  /// storing a remainder rather than a deadline.
  public func restore(state stored: RestTimerState, alarmID storedAlarmID: UUID?, now: Date = .now) {
    switch stored {
    case .idle:
      state = .idle
      alarmID = nil
    case .running(let endsAt) where endsAt <= now:
      if let storedAlarmID { try? RestAlarmService.cancel(id: storedAlarmID) }
      state = .idle
      alarmID = nil
      save()
    case .running, .paused:
      state = stored
      alarmID = storedAlarmID
      scheduleExpiry()
    }
  }

  /// Puts a finished rest away by itself.
  ///
  /// `restore` already refuses to bring back a deadline that has passed -- "a rest bar from last
  /// night" -- but nothing did the same thing while the app was running, so the state stayed
  /// `.running` at a deadline in the past for as long as the workout lasted. `hasElapsed` existed
  /// to answer exactly this and had no caller. The visible cost was a rest bar and a tab-bar
  /// countdown both frozen at 0:00 from the first set to the last, with skip and +15 still offered
  /// on a timer that was over.
  ///
  /// One sleep until the deadline rather than a ticking clock, the same technique the rest of the
  /// timer uses. Owned by the controller rather than by the bar, because the bar is only on screen
  /// while the Train tab is.
  private func scheduleExpiry() {
    expiryTask?.cancel()
    guard case .running(let endsAt) = state else {
      expiryTask = nil
      return
    }
    let wait = endsAt.timeIntervalSinceNow
    expiryTask = Task { [weak self] in
      if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
      guard !Task.isCancelled else { return }
      self?.expireIfElapsed()
    }
  }

  /// Moves a run-out timer to idle. Safe to call at any time; does nothing until the deadline.
  ///
  /// The alarm is deliberately *not* cancelled here. This runs at the instant AlarmKit is firing,
  /// and cancelling then would race the alert the lifter is waiting for. The id is kept so a later
  /// `start` or `cancel` can still clear it.
  public func expireIfElapsed(now: Date = .now) {
    guard state.hasElapsed(at: now) else { return }
    commitTask?.cancel()
    commitTask = nil
    expiryTask?.cancel()
    expiryTask = nil
    state = .idle
    metadata = nil
    save()
  }

  /// The metadata a restored timer no longer has.
  ///
  /// `RestMetadata` is not persisted: it is a label, it is rebuilt the next time a set is logged, and
  /// storing it would mean a schema column per field for something the lifter can already see on the
  /// row behind the bar. A restored timer therefore counts down without naming the movement.
  private func save() {
    persist?(state, alarmID)
  }

  /// Coalesces AlarmKit writes. Each call supersedes any pending one.
  private func scheduleCommit() {
    commitTask?.cancel()
    let debounce = debounce
    commitTask = Task { [weak self] in
      try? await Task.sleep(for: debounce)
      guard !Task.isCancelled else { return }
      await self?.commit()
    }
  }

  private func commit() async {
    guard case .running(let endsAt) = state, let metadata else { return }
    let remaining = endsAt.timeIntervalSince(.now)
    guard remaining > 0 else { return }

    // Replace rather than update: there is no update.
    if let existing = alarmID { try? RestAlarmService.cancel(id: existing) }
    let id = UUID()
    alarmID = id

    do {
      try await RestAlarmService.schedule(
        .init(id: id, duration: .seconds(remaining), metadata: metadata)
      )
      // `schedule` is the only suspension in here and the main actor is free across it, so a set
      // logged in that window runs `start` first. `start` cancels `alarmID` -- still `id`, because
      // this alarm does not exist yet, so the cancel lands on nothing -- and then overwrites it.
      // This `schedule` then creates `id` for a rest that is already over, and nothing holds its id
      // any more, so it fires in the middle of the following set. That is exactly the orphan the
      // comment on `start` describes, reached from the other side. Keep the alarm only while it is
      // still the current one; otherwise it is already superseded and has to go.
      guard alarmID == id else {
        try? RestAlarmService.cancel(id: id)
        return
      }
      lastError = nil
      isDenied = false
      // Written after the schedule, so the persisted id is one that really exists in AlarmKit.
      save()
    } catch {
      lastError = error
      // A schedule that fails while unauthorized is a permission problem, not a transient one, and
      // the user is the only one who can fix it -- so it has to reach them.
      isDenied = !RestAlarmService.isAuthorized
    }
  }
}

#endif  // canImport(AlarmKit)
