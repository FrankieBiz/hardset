#if canImport(AlarmKit)

import Foundation
import HardsetCore

/// Where the rest timer is written down, so a relaunch can tell which alarm is its own.
///
/// A protocol rather than `RestTimerStore` itself, so this module keeps depending on HardsetCore
/// alone. The app conforms the store in one line where it builds the controller.
@MainActor
public protocol RestTimerPersistence {
  func load() throws -> PersistedRest?
  func save(_ rest: PersistedRest, at now: Date) throws
  func clear() throws
}

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
///
/// ## Why reconciliation waits for a pending commit
///
/// Every state change is written down at once, but its alarm arrives up to a debounce later.
/// Reconciling in that window would find the old alarm cancelled and the new one not yet
/// scheduled, and end the rest the lifter just started or adjusted. So a reconciliation that
/// arrives while a commit is pending is held back, and runs as soon as the commit finishes.
///
/// ## When alarms are off
///
/// A refusal is the lifter's choice, not a failure. The countdown stays on screen, the UI says
/// alarms are off, `lastError` stays clear, and the rest ends with a plain local notification
/// (`RestNotificationFallback`) instead. With no alert to report back, the on-screen rest ends
/// itself at its deadline (`endAtDeadlineIfNoAlarm`).
@MainActor
@Observable
public final class RestTimerController {
  /// Whether AlarmKit may sound the rest. `unknown` until the first rest asks.
  public nonisolated enum Authorization: Sendable {
    case unknown
    case authorized
    case denied
  }

  /// The truth the UI renders. A deadline or a frozen remainder -- never a countdown.
  public private(set) var state: RestTimerState = .idle
  /// The most recent failure to schedule, change, read or write down the rest, for the UI.
  public private(set) var lastError: (any Error)?
  public private(set) var authorization: Authorization = .unknown

  private var alarmID: UUID?
  private var metadata: RestMetadata?
  private var commitTask: Task<Void, Never>?
  private var reconcileAfterCommit = false
  private var expiryTask: Task<Void, Never>?
  private let persistence: (any RestTimerPersistence)?

  /// Long enough to absorb a burst of taps, short enough to feel immediate.
  private let debounce: Duration = .milliseconds(400)

  public init(persistence: (any RestTimerPersistence)? = nil) {
    self.persistence = persistence
    authorization = RestAlarmService.authorization
  }

  public func start(duration: Duration, metadata: RestMetadata, now: Date = .now) {
    self.metadata = metadata
    state = .running(endsAt: now.addingTimeInterval(duration.seconds))
    // The previous rest's alarm goes now, and this rest's alarm arrives with the commit. Until
    // then the record names no alarm, which is the truth.
    retireAlarm()
    scheduleCommit()
    persist()
  }

  /// The +/-15 s controls. Updates the visible deadline at once; AlarmKit catches up.
  public func adjust(by delta: Duration, now: Date = .now) {
    guard state.isRunning || state.remaining(at: now) != nil else { return }
    state = state.adjusted(by: delta, at: now)
    scheduleCommit()
    persist()
  }

  public func pause(now: Date = .now) {
    guard state.isRunning else { return }
    state = state.paused(at: now)
    cancelCommit()
    RestNotificationFallback.cancel()
    if let alarmID {
      do { try RestAlarmService.pause(id: alarmID) } catch { lastError = error }
    }
    persist()
  }

  public func resume(now: Date = .now) {
    guard case .paused = state else { return }
    state = state.resumed(at: now)
    // Resuming shifts the deadline, and AlarmKit cannot be told a new one -- so the alarm is
    // replaced rather than resumed in place.
    scheduleCommit()
    persist()
  }

  public func cancel() {
    cancelCommit()
    // The rest is over, and so is whatever went wrong with it.
    lastError = nil
    state = .idle
    retireAlarm()
    RestNotificationFallback.cancel()
    metadata = nil
    persist()
  }

  /// Brings the on-screen timer back in line with AlarmKit. Run at launch and on every update:
  /// a force-quit relaunched the app idle while its alarm still counted down.
  public func reconcile(now: Date = .now) async {
    // Held while a commit is pending (see "Why reconciliation waits"). The record already says
    // what the lifter did; the alarms do not yet, and reading them now would end the rest.
    guard commitTask == nil else {
      reconcileAfterCommit = true
      return
    }
    reconcileAfterCommit = false
    authorization = RestAlarmService.authorization
    let persisted = lastWrittenRest()

    let alarms: [AlarmSnapshot]
    switch authorization {
    case .unknown, .denied:
      // Not authorized, so no alarm of ours is there to read. Not read either, since reading
      // before the lifter has been asked may fail and would surface an error nobody caused.
      // An empty list is a fact here, not a guess.
      alarms = []
    case .authorized:
      do {
        alarms = try RestAlarmService.currentAlarms().map(RestAlarmService.snapshot(of:))
      } catch {
        // Alarms that cannot be read are no evidence. Change nothing, and leave the record for
        // the next pass, rather than reconcile against an empty list (a guess that there are
        // none) and end a live rest. The failure is kept, not swallowed.
        lastError = error
        return
      }
    }

    let result = RestReconciler.reconcile(persisted: persisted, alarms: alarms, now: now)
    for stale in result.staleAlarmIDs {
      // A stale alarm that will not cancel would ring for a rest nobody sees: kept in lastError.
      do { try RestAlarmService.cancel(id: stale) } catch { lastError = error }
    }

    // Some rests have no alarm to be reconciled against, and the reconciler would end them:
    // alarms are off and a notification stands in, or, this session, the rest's alarm failed to
    // schedule (the UI says so) or it was paused before its first commit. Such a rest stands
    // until its deadline passes; any alarm left over is not its own and went as stale above.
    // Nothing is guessed: the deadline or remainder shown is the one the lifter set and the
    // record holds. After a relaunch only the first case applies: an alarm that was never
    // scheduled before the app died leaves nothing behind to show.
    let hasNoAlarm = authorization == .denied || (state != .idle && alarmID == nil)
    if hasNoAlarm, let persisted {
      adopt(persisted.state.hasElapsed(at: now) ? .idle : persisted.state, alarmID: nil)
      endAtDeadlineIfNoAlarm()
    } else {
      adopt(result.state, alarmID: result.alarmID)
    }
  }

  /// Follows AlarmKit for the life of the app.
  public func observeAlarms() async {
    for await _ in RestAlarmService.alarmUpdates() { await reconcile() }
  }

  /// What the reconciler is told was last written down.
  ///
  /// Memory is never staler than the store, since every change is written from it, and it is
  /// empty only after a relaunch, which is exactly when the store is needed. Reading memory first
  /// also means a controller with no store reconciles against its own rest rather than none, and
  /// a failed write cannot make the controller cancel the alarm it just scheduled.
  private func lastWrittenRest() -> PersistedRest? {
    if state != .idle { return PersistedRest(state: state, alarmID: alarmID) }
    guard let persistence else { return nil }
    do {
      return try persistence.load()
    } catch {
      // A corrupt record is discarded, not half-read. The alarms are still the truth.
      do { try persistence.clear() } catch { lastError = error }
      return nil
    }
  }

  /// Takes on the reconciled rest, and writes it down.
  private func adopt(_ rest: RestTimerState, alarmID id: UUID?) {
    state = rest
    alarmID = id
    if rest == .idle { metadata = nil }
    persist()
  }

  /// Writes the rest down, so a relaunch can find its alarm. A failed write is surfaced: the
  /// countdown still runs, but a force-quit would lose track of it.
  private func persist() {
    guard let persistence else { return }
    do {
      try persistence.save(PersistedRest(state: state, alarmID: alarmID), at: .now)
    } catch {
      lastError = error
    }
  }

  /// Cancels the alarm behind the rest, if there is one, and forgets it. An alerting alarm is
  /// left to the system: it is the alert the lifter is waiting for.
  private func retireAlarm() {
    guard let id = alarmID else { return }
    alarmID = nil
    do { try RestAlarmService.cancelUnlessAlerting(id: id) } catch { lastError = error }
  }

  /// Coalesces AlarmKit writes. Each call supersedes any pending one.
  private func scheduleCommit() {
    commitTask?.cancel()
    let debounce = debounce
    commitTask = Task { [weak self] in
      try? await Task.sleep(for: debounce)
      guard !Task.isCancelled else { return }
      await self?.commit()
      // Still current unless cancelled: everything that replaces or drops this task cancels it.
      guard !Task.isCancelled else { return }
      await self?.commitFinished()
    }
  }

  private func cancelCommit() {
    commitTask?.cancel()
    commitTask = nil
  }

  /// AlarmKit has caught up, so the reconciliation held back meanwhile can run.
  private func commitFinished() async {
    commitTask = nil
    if reconcileAfterCommit { await reconcile() }
  }

  private func commit() async {
    guard state.isRunning else { return }
    // A fresh attempt. Whatever failed before describes a write that this one replaces.
    lastError = nil
    await authorize()
    // Read again: the first rest waits on a permission prompt, and the deadline kept moving.
    guard case .running(let endsAt) = state else { return }
    let remaining = Duration.seconds(endsAt.timeIntervalSince(.now))
    guard remaining > .zero else {
      // Adjusted down to nothing: no alarm to schedule, so a rest without one ends now.
      endAtDeadlineIfNoAlarm()
      return
    }

    // Replace rather than update: there is no update.
    retireAlarm()

    guard authorization == .authorized else {
      // Denied: not an error, so `lastError` stays clear and the UI shows the refusal instead.
      // (`unknown` here means asking failed, and `lastError` already says why.)
      persist()
      endAtDeadlineIfNoAlarm()
      await scheduleFallback()
      return
    }

    // A notification left from a rest that began while alarms were off gives way to the alarm.
    RestNotificationFallback.cancel()
    let id = UUID()
    alarmID = id
    persist()

    do {
      try await RestAlarmService.schedule(
        .init(id: id, duration: remaining, metadata: metadata)
      )
    } catch {
      // Nothing was scheduled, so the record must not name an alarm; the countdown stays. Unless
      // the lifter has moved on meanwhile, in which case the record is already theirs.
      if alarmID == id {
        alarmID = nil
        persist()
        endAtDeadlineIfNoAlarm()
      }
      lastError = error
    }
  }

  /// Ends a rest that has no alarm behind it when its deadline passes, as the alert would have.
  ///
  /// With an alarm, the alert's update ends the rest. Without one nothing arrives, and the bar
  /// would sit at 0:00 until Skip. One sleep to the deadline, not a ticking timer, and it does
  /// nothing if the rest has changed meanwhile (an adjust or resume arms a new one).
  private func endAtDeadlineIfNoAlarm() {
    expiryTask?.cancel()
    expiryTask = nil
    guard alarmID == nil, case .running(let endsAt) = state else { return }
    expiryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
      guard !Task.isCancelled else { return }
      self?.expire(endsAt)
    }
  }

  private func expire(_ endsAt: Date) {
    // A commit still pending for this same rest finds it idle and does nothing.
    guard state == .running(endsAt: endsAt), alarmID == nil else { return }
    // The notification is left alone. It fires at this same moment, and removing a request a
    // hair from firing would silence the only alert the lifter gets. Once delivered, a one-shot
    // request is no longer pending, so there is nothing to clean up.
    // As with `cancel()`, the rest is over, and so is whatever went wrong with it.
    lastError = nil
    adopt(.idle, alarmID: nil)
  }

  /// Asks for alarm permission the first time a rest needs it, which is the moment the lifter
  /// can see why. Read fresh every time, since the answer can change in Settings.
  private func authorize() async {
    authorization = RestAlarmService.authorization
    guard authorization == .unknown else { return }
    do {
      authorization = try await RestAlarmService.requestAuthorization()
    } catch {
      lastError = error
    }
  }

  /// Schedules the plain notification that stands in for the alarm when alarms are off.
  private func scheduleFallback() async {
    do {
      guard try await RestNotificationFallback.requestAuthorization() else { return }
      // Read again: the first ask shows a prompt, and the rest may have changed meanwhile.
      guard case .running(let endsAt) = state else { return }
      try await RestNotificationFallback.schedule(
        after: .seconds(endsAt.timeIntervalSince(.now)),
        title: "Rest complete",
        body: metadata.map { "\($0.exerciseName) · \($0.setLabel)" } ?? ""
      )
    } catch {
      lastError = error
    }
  }
}

#endif  // canImport(AlarmKit)
