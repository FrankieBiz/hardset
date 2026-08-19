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

  private var alarmID: UUID?
  private var metadata: RestMetadata?
  private var commitTask: Task<Void, Never>?

  /// Long enough to absorb a burst of taps, short enough to feel immediate.
  private let debounce: Duration = .milliseconds(400)

  public init() {}

  public func start(duration: Duration, metadata: RestMetadata, now: Date = .now) {
    self.metadata = metadata
    state = .running(endsAt: now.addingTimeInterval(duration.seconds))
    alarmID = UUID()
    scheduleCommit()
  }

  /// The +/-15 s controls. Updates the visible deadline at once; AlarmKit catches up.
  public func adjust(by delta: Duration, now: Date = .now) {
    guard state.isRunning || state.remaining(at: now) != nil else { return }
    state = state.adjusted(by: delta, at: now)
    scheduleCommit()
  }

  public func pause(now: Date = .now) {
    guard state.isRunning else { return }
    state = state.paused(at: now)
    commitTask?.cancel()
    if let alarmID { try? RestAlarmService.pause(id: alarmID) }
  }

  public func resume(now: Date = .now) {
    guard case .paused = state else { return }
    state = state.resumed(at: now)
    // Resuming shifts the deadline, and AlarmKit cannot be told a new one -- so the alarm is
    // replaced rather than resumed in place.
    scheduleCommit()
  }

  public func cancel() {
    commitTask?.cancel()
    commitTask = nil
    state = .idle
    if let alarmID { try? RestAlarmService.cancel(id: alarmID) }
    alarmID = nil
    metadata = nil
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
      lastError = nil
    } catch {
      lastError = error
    }
  }
}

#endif  // canImport(AlarmKit)
