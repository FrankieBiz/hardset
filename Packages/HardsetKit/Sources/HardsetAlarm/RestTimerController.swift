#if canImport(AlarmKit)
import Foundation
import HardsetCore
import Observation

/// Persists desired absolute deadlines before changing UI or AlarmKit. One reconciler owns
/// all OS requests; a late schedule cannot overwrite a newer user action.
@MainActor
@Observable
public final class RestTimerController {
  public private(set) var state: RestTimerState = .idle
  public private(set) var metadata: RestMetadata?
  public private(set) var lastError: (any Error)?
  private let operations: RestAlarmOperations
  private var checkpoint = RestCheckpoint()
  private var save: ((RestCheckpoint) throws -> Void)?
  private var reconciliation: Task<Void, Never>?
  private var observation: Task<Void, Never>?
  private var generation = 0
  private var configured = false
  private var restore: (() throws -> RestCheckpoint)?
  private var pendingTransition: (RestTimerState, RestMetadata?)?

  public init(operations: RestAlarmOperations = .live) { self.operations = operations }

  /// Called once after the app opens its live writer. A failed journal read blocks
  /// timer commands until retry, while the saved workouts remain accessible.
  public func configure(checkpoint: RestCheckpoint, save: @escaping (RestCheckpoint) throws -> Void) {
    guard !configured else { return }
    configured = true
    restore = nil
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
    reconcile()
  }

  public func start(duration: Duration, metadata: RestMetadata, now: Date = .now) {
    guard duration.seconds.isFinite, duration > .zero else { return }
    transition(to: .running(endsAt: now.addingTimeInterval(duration.seconds)), metadata: metadata)
  }

  public func adjust(by delta: Duration, now: Date = .now) {
    guard state.remaining(at: now) != nil else { return }
    transition(to: state.adjusted(by: delta, at: now), metadata: metadata)
  }

  public func pause(now: Date = .now) {
    guard state.isRunning else { return }
    transition(to: state.paused(at: now), metadata: metadata)
  }

  public func resume(now: Date = .now) {
    guard case .paused = state else { return }
    transition(to: state.resumed(at: now), metadata: metadata)
  }

  public func cancel() { transition(to: .idle, metadata: nil) }
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
      reconcile()
    } catch {
      if configured { pendingTransition = (state, metadata) }
      lastError = error
    }
  }

  private func reconcile() {
    // Do not cancel an in-flight schedule. Wait for its acknowledgement, then reconcile
    // the newest generation. Its ID was already journalled, so a crash can cancel it.
    guard reconciliation == nil, configured else { return }
    reconciliation = Task { [weak self] in
      guard let self else { return }
      await self.runReconciliation()
      self.reconciliation = nil
    }
  }

  private func runReconciliation() async {
    while true {
      let revision = generation
      let desired = checkpoint
      do {
        for id in desired.retiredAlarmIDs {
          // An absent alarm is already canceled; other cancellation failures remain visible.
          if try operations.contains(id) { try operations.cancel(id) }
        }
        if revision != generation { continue }
        let cleaned = RestCheckpoint(state: desired.state, metadata: desired.metadata,
          alarmID: desired.alarmID, scheduledAlarmID: desired.scheduledAlarmID, retiredAlarmIDs: [])
        try save?(cleaned)
        checkpoint = cleaned
        if case .running(let end) = desired.state, let id = desired.alarmID, let metadata = desired.metadata {
          let exists = try operations.contains(id)
          // Once an OS acknowledgement is durable, a missing alarm means it was stopped
          // or removed. Do not resurrect a rest the user dismissed on the Lock Screen.
          if desired.scheduledAlarmID == id, !exists {
            transition(to: .idle, metadata: nil)
            if revision != generation { continue }
            return
          }
          let remaining = end.timeIntervalSinceNow
          if remaining > 0 {
            if !operations.isAuthorized() {
              guard try await operations.requestAuthorization() else { throw RestControllerError.authorizationDenied }
              if revision != generation { continue }
            }
            guard end > Date.now else { if pendingTransition == nil { lastError = nil }; return }
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

  public init(contains: @escaping (UUID) throws -> Bool, cancel: @escaping (UUID) throws -> Void,
    isAuthorized: @escaping () -> Bool, requestAuthorization: @escaping () async throws -> Bool,
    schedule: @escaping (UUID, Duration, RestMetadata) async throws -> Void,
    updates: @escaping () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }) {
    self.updates = updates
    self.contains = contains; self.cancel = cancel; self.isAuthorized = isAuthorized
    self.requestAuthorization = requestAuthorization; self.schedule = schedule
  }

  public static var live: Self {
    Self(contains: { try RestAlarmService.contains(id: $0) }, cancel: { try RestAlarmService.cancel(id: $0) },
      isAuthorized: { RestAlarmService.isAuthorized }, requestAuthorization: { try await RestAlarmService.requestAuthorization() },
      schedule: { id, duration, metadata in
        try await RestAlarmService.schedule(.init(id: id, duration: duration, metadata: metadata))
      }, updates: { RestAlarmService.updates })
  }
}

private enum RestControllerError: Error { case journalUnavailable, authorizationDenied }
#endif
