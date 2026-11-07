import Foundation
import Observation

/// Owns one screen's snapshot. New requests cancel older reads; canceled or stale
/// completions never replace visible content or publish an error.
@MainActor
@Observable
public final class SnapshotLoader<Value: Sendable> {
  public private(set) var value: Value?
  public private(set) var loadFailed = false

  @ObservationIgnored private var latestRequest: UUID?
  @ObservationIgnored private var activeRead: Task<Value, any Error>?

  public init() {}

  public func load(_ read: @escaping @Sendable () async throws -> Value) async {
    guard !Task.isCancelled else { return }
    activeRead?.cancel()
    let id = UUID()
    latestRequest = id
    let request = Task { try await read() }
    activeRead = request
    do {
      let result = try await withTaskCancellationHandler {
        try await request.value
      } onCancel: {
        request.cancel()
      }
      guard latestRequest == id else { return }
      activeRead = nil
      guard !Task.isCancelled else { return }
      value = result
      loadFailed = false
    } catch {
      guard latestRequest == id else { return }
      activeRead = nil
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      value = nil
      loadFailed = true
    }
  }
}
