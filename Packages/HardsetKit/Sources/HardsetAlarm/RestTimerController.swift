#if canImport(AlarmKit)
import Foundation
import HardsetCore
import Observation

/// Persists desired absolute deadlines before changing UI or AlarmKit. One reconciler owns
/// all OS requests; a late schedule cannot overwrite a newer user action.
@MainActor
@Observable
public final class RestTimerController {
  /// What stands between the lifter and a working rest alert, in terms the interface can act on.
  ///
  /// Free of AlarmKit types, so the app can map it onto the feature layer's own enum without the
  /// feature layer importing this module.
  public enum Issue: Equatable, Sendable {
    /// Alarm permission is off. The rest still counts down in the app and ends at its deadline,
    /// but nothing alerts. Retrying cannot help; only Settings can.
    case alarmsDenied
    /// The saved rest could not be read at launch. Timer commands wait until a retry reads it or
    /// the lifter resets the rest timer.
    case recoveryFailed
    /// A journal write or an alarm request failed. Retrying can succeed.
    case failed
  }

  public private(set) var state: RestTimerState = .idle
  public private(set) var metadata: RestMetadata?
  public private(set) var lastError: (any Error)?
  private let operations: RestAlarmOperations
  private var checkpoint = RestCheckpoint()
  private var save: ((RestCheckpoint) throws -> Void)?
  private var reconciliation: Task<Void, Never>?
  /// Set when a reconcile is asked for while one is in flight, so an OS update or a deadline that
  /// arrives mid-pass gets a pass of its own instead of being dropped.
  private var reconcileAgain = false
  private var observation: Task<Void, Never>?
  /// One wake at the running deadline. See `armDeadlineWake()`.
  private var deadlineWake: Task<Void, Never>?
  private var generation = 0
  private var configured = false
  private var restore: (() throws -> RestCheckpoint)?
  private var pendingTransition: (RestTimerState, RestMetadata?)?

  public init(operations: RestAlarmOperations = .live) { self.operations = operations }

  /// `nil` while the rest timer works as intended.
  public var issue: Issue? {
    guard let lastError else { return nil }
    if !configured, restore != nil { return .recoveryFailed }
    if case .authorizationDenied? = lastError as? RestControllerError { return .alarmsDenied }
    return .failed
  }

  /// Called once after the app opens its live writer. A failed journal read blocks
  /// timer commands until retry, while the saved workouts remain accessible.
  public func configure(checkpoint: RestCheckpoint, save: @escaping (RestCheckpoint) throws -> Void) {
    guard !configured else { return }
    configured = true
    restore = nil
    // A recovery failure is resolved by the read that reached here.
    lastError = nil
    self.save = save
    self.checkpoint = checkpoint
    state = checkpoint.state
    metadata = checkpoint.metadata
    let updates = operations.updates()
    observation = Task { [weak self] in
      for await _ in updates {
        guard let self else { return }
        self.reconcile()
      }
    }
    armDeadlineWake()
    reconcile()
  }

  public func start(duration: Duration, metadata: RestMetadata, now: Date = .now) {
    guard duration.seconds.isFinite, duration > .zero else { return }
    transition(to: .running(endsAt: now.addingTimeInterval(duration.seconds)),
      metadata: metadata.withTotalRest(duration))
  }

  public func adjust(by delta: Duration, now: Date = .now) {
    guard let before = state.remaining(at: now) else { return }
    let next = state.adjusted(by: delta, at: now)
    let after = next.remaining(at: now) ?? .zero
    // Taking a rest down to nothing ends it. Keeping a deadline of "now" left a rest with no
    // alarm behind it, drawn as "Resting 0:00" until the lifter found Skip.
    guard after > .zero else { cancel(); return }
    let total = metadata?.totalRest.map { $0 + (after - before) }
    transition(to: next, metadata: metadata?.withTotalRest(total))
  }

  public func pause(now: Date = .now) {
    guard state.isRunning else { return }
    let next = state.paused(at: now)
    // A rest that has already run out has nothing left to pause.
    guard let left = next.remaining(at: now), left > .zero else { cancel(); return }
    transition(to: next, metadata: metadata)
  }

  public func resume(now: Date = .now) {
    guard case .paused(let remaining) = state else { return }
    // Resuming nothing would set a deadline that has already passed.
    guard remaining > .zero else { cancel(); return }
    transition(to: state.resumed(at: now), metadata: metadata)
  }

  public func cancel() { transition(to: .idle, metadata: nil) }

  /// Re-checks the rest against the clock and the OS. The app calls it on returning to the
  /// foreground, so a rest that ended, or was stopped on the Lock Screen, clears straight away.
  public func refresh() { reconcile() }

  public func configureRecoveryFailure(_ error: any Error,
    restore: @escaping () throws -> RestCheckpoint, save: @escaping (RestCheckpoint) throws -> Void) {
    guard !configured else { return }
    self.restore = restore
    self.save = save
    lastError = error
  }

  public func retry() {
    if let restore {
      do {
        let recovered = try restore()
        guard let save else { return }
        configure(checkpoint: recovered, save: save)
      } catch { lastError = error }
    } else if let pendingTransition {
      transition(to: pendingTransition.0, metadata: pendingTransition.1)
    } else { reconcile() }
  }

  /// The way out of a saved rest that cannot be read at all, chosen by the lifter. A retry that
  /// re-reads the same unreadable row fails the same way for ever.
  ///
  /// Only the current rest is lost: the journal is replaced with no rest, and every alarm this
  /// app still holds is recorded for cancellation, because the unreadable row was the only record
  /// of which alarm was current. Every alarm this app schedules is a rest alarm. Workouts are not
  /// touched. If the alarms cannot be listed, none are recorded, and a stale one can still ring
  /// once; Stop ends it.
  public func resetAfterRecoveryFailure() {
    guard !configured, restore != nil, let save else { return }
    let fresh = RestCheckpoint(retiredAlarmIDs: (try? operations.alarmIDs()) ?? [])
    do {
      try save(fresh)
      configure(checkpoint: fresh, save: save)
    } catch { lastError = error }
  }

  public func waitForReconciliation() async { await reconciliation?.value }

  private func transition(to state: RestTimerState, metadata: RestMetadata?) {
    var retired = checkpoint.retiredAlarmIDs
    if let old = checkpoint.alarmID { retired.append(old) }
    let updated = RestCheckpoint(state: state, metadata: metadata,
      alarmID: state.isRunning ? UUID() : nil, retiredAlarmIDs: Array(Set(retired)))
    do {
      guard configured, let save else { throw RestControllerError.journalUnavailable }
      try save(updated)
      pendingTransition = nil
      checkpoint = updated
      self.state = state
      self.metadata = metadata
      generation += 1
      lastError = nil
      armDeadlineWake()
      reconcile()
    } catch {
      if configured { pendingTransition = (state, metadata) }
      lastError = error
    }
  }

  /// One wake at the running deadline, not a ticking loop. A live alarm's own updates drive
  /// reconciliation, but when there is none (alarms are off, or scheduling failed) nothing else
  /// would notice that the rest is over, and the bar would sit at "Resting 0:00".
  private func armDeadlineWake() {
    deadlineWake?.cancel()
    deadlineWake = nil
    guard case .running(let end) = state else { return }
    deadlineWake = Task { [weak self] in
      try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
      guard !Task.isCancelled else { return }
      self?.reconcile()
    }
  }

  private func reconcile() {
    // Do not cancel an in-flight schedule. Wait for its acknowledgement, then reconcile
    // the newest generation. Its ID was already journalled, so a crash can cancel it.
    guard configured else { return }
    guard reconciliation == nil else { reconcileAgain = true; return }
    reconciliation = Task { [weak self] in
      guard let self else { return }
      repeat {
        self.reconcileAgain = false
        await self.runReconciliation()
      } while self.reconcileAgain
      self.reconciliation = nil
    }
  }

  private func runReconciliation() async {
    while true {
      let revision = generation
      let desired = checkpoint
      do {
        // Permission comes before any alarm query, so a query that fails before the lifter has
        // answered the prompt cannot be what keeps the prompt from ever appearing. Only a rest
        // that still needs an alarm asks.
        var authorized = operations.isAuthorized()
        if !authorized, case .running(let end) = desired.state, end > .now {
          authorized = try await operations.requestAuthorization()
          if revision != generation { continue }
        }
        var retained: [UUID] = []
        for id in desired.retiredAlarmIDs {
          // An absent alarm is already canceled; other cancellation failures remain visible.
          // Without permission a failure is not fatal: the ID stays recorded and is canceled
          // once alarms are allowed again.
          do {
            if try operations.contains(id) { try operations.cancel(id) }
          } catch {
            if authorized { throw error }
            retained.append(id)
          }
        }
        if revision != generation { continue }
        let cleaned = RestCheckpoint(state: desired.state, metadata: desired.metadata,
          alarmID: desired.alarmID, scheduledAlarmID: desired.scheduledAlarmID, retiredAlarmIDs: retained)
        try save?(cleaned)
        checkpoint = cleaned
        if case .running(let end) = desired.state {
          if authorized, let id = desired.alarmID {
            let exists = try operations.contains(id)
            // Once an OS acknowledgement is durable, a missing alarm means it was stopped
            // or removed. Do not resurrect a rest the user dismissed on the Lock Screen.
            // A deadline that has passed with no alarm left to finish it is over as well:
            // nothing else would end it, and it would come back after every relaunch.
            if !exists, desired.scheduledAlarmID == id || end <= .now {
              transition(to: .idle, metadata: nil)
              if revision != generation { continue }
              return
            }
            // A ringing alarm (`exists` past the deadline) is left alone; its Stop ends the rest.
            if end > .now, let metadata = desired.metadata {
              // Relaunch keeps an existing alarm. A fresh request uses its already-journalled ID.
              if !exists {
                try await operations.schedule(id, .seconds(max(0, end.timeIntervalSinceNow)), metadata)
              }
              if revision != generation { continue }
              let acknowledged = RestCheckpoint(state: desired.state, metadata: desired.metadata,
                alarmID: id, scheduledAlarmID: id, retiredAlarmIDs: [])
              try save?(acknowledged)
              checkpoint = acknowledged
            }
          } else if end <= .now {
            // No alarm can end this rest, so the app ends it at its deadline.
            transition(to: .idle, metadata: nil)
            if revision != generation { continue }
            return
          } else if !authorized {
            // The durable deadline stays: the countdown still runs in the app, it just cannot
            // alert. The deadline wake ends it, and an authorization update schedules it.
            throw RestControllerError.authorizationDenied
          }
        }
        if revision != generation { continue }
        if pendingTransition == nil { lastError = nil }
        return
      } catch {
        if revision != generation { continue }
        lastError = error
        return
      }
    }
  }
}

/// Injectable OS boundary for deterministic scheduling, cancellation and relaunch tests.
@MainActor
public struct RestAlarmOperations {
  public let updates: () -> AsyncStream<Void>
  public let contains: (UUID) throws -> Bool
  public let cancel: (UUID) throws -> Void
  public let isAuthorized: () -> Bool
  public let requestAuthorization: () async throws -> Bool
  public let schedule: (UUID, Duration, RestMetadata) async throws -> Void
  /// Every alarm this app holds. Used only to reset after an unreadable journal.
  public let alarmIDs: () throws -> [UUID]

  public init(contains: @escaping (UUID) throws -> Bool, cancel: @escaping (UUID) throws -> Void,
    isAuthorized: @escaping () -> Bool, requestAuthorization: @escaping () async throws -> Bool,
    schedule: @escaping (UUID, Duration, RestMetadata) async throws -> Void,
    updates: @escaping () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
    alarmIDs: @escaping () throws -> [UUID] = { [] }) {
    self.updates = updates
    self.contains = contains; self.cancel = cancel; self.isAuthorized = isAuthorized
    self.requestAuthorization = requestAuthorization; self.schedule = schedule
    self.alarmIDs = alarmIDs
  }

  public static var live: Self {
    Self(contains: { try RestAlarmService.contains(id: $0) }, cancel: { try RestAlarmService.cancel(id: $0) },
      isAuthorized: { RestAlarmService.isAuthorized }, requestAuthorization: { try await RestAlarmService.requestAuthorization() },
      schedule: { id, duration, metadata in
        try await RestAlarmService.schedule(.init(id: id, duration: duration, metadata: metadata))
      }, updates: { RestAlarmService.updates }, alarmIDs: { try RestAlarmService.alarmIDs() })
  }
}

private enum RestControllerError: Error { case journalUnavailable, authorizationDenied }
#endif
