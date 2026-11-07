import Dispatch
import Foundation
import GRDB
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

@Suite("App startup prepares and retains one resource set")
struct AppStartupTests {
  enum Failure: Error { case unavailable, timedOut }

  nonisolated final class Resource: Sendable {}

  @Test("Database migration leaves the main actor available")
  @MainActor
  func migrationReleasesMainActor() async throws {
    let database = try DatabaseQueue()
    let fired = Mutex(false)
    let mainActorRan = Mutex(false)
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        guard case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") else { return }
        let shouldProbe = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        guard shouldProbe else { return }
        // A test-only bounded wait exposes a synchronous caller holding MainActor.
        let signal = DispatchSemaphore(value: 0)
        Task { @MainActor in signal.signal() }
        let result = signal.wait(timeout: .now() + 2)
        mainActorRan.withLock { $0 = result == .success }
      }
    }
    let startup = AppStartup {
      try HardsetMigrations.migrator().migrate(database)
      return database
    }
    await startup.start()
    #expect(startup.resources != nil)
    #expect(startup.lastError == nil)
    #expect(fired.withLock { $0 })
    #expect(mainActorRan.withLock { $0 })
  }

  @Test("Overlapping scenes share preparation even if one caller disappears")
  @MainActor
  func sharedPreparationSurvivesCallerCancellation() async throws {
    let calls = Mutex(0)
    let entered = AsyncStream<Void>.makeStream()
    let secondEntered = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let startup = AppStartup {
      calls.withLock { $0 += 1 }
      entered.continuation.yield(())
      guard release.wait(timeout: .now() + 5) == .success else { throw Failure.timedOut }
      return 42
    }
    let first = Task { await startup.start() }
    for await _ in entered.stream { break }
    let second = Task {
      secondEntered.continuation.yield(())
      await startup.start()
    }
    for await _ in secondEntered.stream { break }
    first.cancel()
    release.signal()
    await first.value
    await second.value
    #expect(startup.resources == 42)
    #expect(startup.lastError == nil)
    await startup.start()
    await startup.retry()
    #expect(calls.withLock { $0 } == 1)
  }

  @Test("Failure exposes no resources and only explicit retry starts a new attempt")
  @MainActor
  func failureRequiresRetry() async {
    let calls = Mutex(0)
    let startup = AppStartup {
      let count = calls.withLock { calls in calls += 1; return calls }
      if count == 1 { throw Failure.unavailable }
      return 42
    }
    await startup.start()
    #expect(startup.resources == nil)
    #expect(startup.lastError is Failure)
    await startup.start()
    #expect(calls.withLock { $0 } == 1)
    await startup.retry()
    #expect(startup.resources == 42)
    #expect(startup.lastError == nil)
    await startup.retry()
    #expect(calls.withLock { $0 } == 2)
  }

  @Test("The app owner retains resources after the scene's startup task returns")
  @MainActor
  func ownsCompletedResources() async {
    var startup: AppStartup<Resource>? = AppStartup { Resource() }
    await startup?.start()
    weak var resource = startup?.resources
    #expect(resource != nil)
    await startup?.start()
    #expect(resource === startup?.resources)
    startup = nil
    #expect(resource == nil)
  }

  @Test("Startup preserves preview dependencies on its preparation queue")
  @MainActor
  func preservesDependencies() async {
    let startup = withDependencies {
      $0.context = .preview
    } operation: {
      AppStartup {
        @Dependency(\.context) var context
        return context
      }
    }
    await startup.start()
    #expect(startup.resources == .preview)
    #expect(startup.lastError == nil)
  }
}
