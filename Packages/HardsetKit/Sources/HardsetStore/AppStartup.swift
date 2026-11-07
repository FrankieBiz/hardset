import Dispatch
import Foundation
import Observation
import SQLiteData

/// App-owned, single-flight preparation of process-lifetime resources.
///
/// Blocking open/migration work runs on a dedicated queue. View disappearance
/// does not cancel preparation or release a live resource set. A failed attempt
/// exposes no resources and requires an explicit retry, rather than a fallback.
@MainActor
@Observable
public final class AppStartup<Resources: Sendable> {
  public private(set) var resources: Resources?
  public private(set) var lastError: (any Error)?

  @ObservationIgnored private let prepare: @Sendable () throws -> Resources
  @ObservationIgnored private let queue = DispatchQueue(label: "Hardset.startup", qos: .userInitiated)
  @ObservationIgnored private var attempt: Attempt?

  private struct Attempt {
    let id: UUID
    let task: Task<Resources, any Error>
  }

  public init(prepare: @escaping @Sendable () throws -> Resources) {
    // Queue closures do not inherit task-local dependencies. Preserve the app,
    // preview or test context instead of opening a different database there.
    let dependencies = withEscapedDependencies { $0 }
    self.prepare = { try dependencies.yield { try prepare() } }
  }

  public func start() async {
    guard resources == nil, lastError == nil else { return }
    let current: Attempt
    if let attempt {
      current = attempt
    } else {
      let queue = queue
      let prepare = prepare
      current = Attempt(id: UUID(), task: Task {
        try await withCheckedThrowingContinuation { continuation in
          queue.async {
            continuation.resume(with: Result { try prepare() })
          }
        }
      })
      attempt = current
    }
    // This operation belongs to the app, not to an individual scene's task.
    let result = await current.task.result
    guard attempt?.id == current.id else { return }
    attempt = nil
    switch result {
    case .success(let resources):
      self.resources = resources
    case .failure(let error):
      lastError = error
    }
  }

  public func retry() async {
    guard resources == nil, attempt == nil else { return }
    lastError = nil
    await start()
  }
}
