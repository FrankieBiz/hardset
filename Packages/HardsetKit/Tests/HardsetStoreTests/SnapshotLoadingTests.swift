import Dispatch
import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

@Suite("Screen snapshot loading releases the main actor")
struct SnapshotLoadingTests {
  enum Screen: CaseIterable, Sendable { case volume, progression, history }

  @Test("A database wait leaves the main actor available", arguments: Screen.allCases)
  @MainActor
  func loadingReleasesMainActor(screen: Screen) async throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    try await database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute(db)
    }
    let now = Date(timeIntervalSince1970: 15_000_000)
    let logger = LoggerStore(database: database)
    let session = try logger.startSession(at: now.addingTimeInterval(-100))
    _ = try logger.logSet(sessionID: session, exerciseID: exercise,
                         draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(-60))
    try logger.finishSession(session, at: now)
    let fired = Mutex(false)
    let mainActorRan = Mutex(false)
    let begins = Mutex(0)
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        guard case .statement(let statement) = event else { return }
        if statement.sql.hasPrefix("BEGIN") { begins.withLock { $0 += 1 } }
        guard statement.sql.contains("FROM \"loggedSets\"") else { return }
        let shouldProbe = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        guard shouldProbe else { return }
        // Test-only bounded wait. A synchronous caller occupies MainActor until
        // this callback returns; an asynchronous database read lets the job run.
        let signal = DispatchSemaphore(value: 0)
        Task { @MainActor in signal.signal() }
        let result = signal.wait(timeout: .now() + 2)
        mainActorRan.withLock { $0 = result == .success }
      }
    }
    switch screen {
    case .volume:
      let store = VolumeStore(database: database)
      let loaded = try await store.loadRollingWeek(endingAt: now)
      #expect(loaded == (try store.rollingWeek(endingAt: now)))
    case .progression:
      let store = ProgressionStore(database: database)
      let loaded = try await store.loadHistory(for: exercise)
      #expect(loaded == (try store.history(for: exercise)))
    case .history:
      let store = HistoryStore(database: database)
      let loaded = try await store.loadRecentSessions()
      #expect(loaded == (try store.recentSessions()))
    }
    #expect(fired.withLock { $0 })
    #expect(mainActorRan.withLock { $0 })
    // One async load and one synchronous reference load, each in one snapshot.
    #expect(begins.withLock { $0 } == 2)
  }

  @Test("Already canceled screen reads do not access the database", arguments: Screen.allCases)
  @MainActor
  func canceledReadDoesNotQuery(screen: Screen) async throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let selects = Mutex(0)
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") {
          selects.withLock { $0 += 1 }
        }
      }
    }
    let caller = Task { @MainActor in
      do {
        switch screen {
        case .volume:
          _ = try await VolumeStore(database: database).loadRollingWeek(endingAt: .now)
        case .progression:
          _ = try await ProgressionStore(database: database).loadHistory(for: ExerciseID())
        case .history:
          _ = try await HistoryStore(database: database).loadRecentSessions()
        }
        Issue.record("A canceled read returned a snapshot")
      } catch {
        #expect(error is CancellationError)
      }
    }
    // Both tasks are MainActor-isolated, so cancellation precedes the child's
    // first instruction, without a scheduling race or artificial sleep.
    caller.cancel()
    await caller.value
    #expect(selects.withLock { $0 } == 0)
  }

  @Test("Canceling an active database read leaves the connection usable", arguments: Screen.allCases)
  @MainActor
  func canceledActiveRead(screen: Screen) async throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let callerHandle = Mutex<Task<Bool, Never>?>(nil)
    let fired = Mutex(false)
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        guard case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") else { return }
        let shouldCancel = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        if shouldCancel { callerHandle.withLock { $0?.cancel() } }
      }
    }
    let caller = Task { @MainActor in
      do {
        switch screen {
        case .volume:
          _ = try await VolumeStore(database: database).loadRollingWeek(endingAt: .now)
        case .progression:
          _ = try await ProgressionStore(database: database).loadHistory(for: ExerciseID())
        case .history:
          _ = try await HistoryStore(database: database).loadRecentSessions()
        }
        return false
      } catch {
        // GRDB may surface interruption as DatabaseError or CancellationError;
        // the UI must treat either as cancellation when its task is canceled.
        return Task.isCancelled
      }
    }
    callerHandle.withLock { $0 = caller }
    let wasCanceled = await caller.value
    callerHandle.withLock { $0 = nil }
    #expect(fired.withLock { $0 })
    #expect(wasCanceled)
    let health = try await database.read { db in try Int.fetchOne(db, sql: "SELECT 42") }
    #expect(health == 42)
  }

  @Test("Superseded reads are canceled and cannot overwrite newer content", arguments: [false, true])
  @MainActor
  func latestRequestWins(lateFailure: Bool) async throws {
    enum Failure: Error { case unreadable }
    let loader = SnapshotLoader<Int>()
    let started = AsyncStream<Void>.makeStream()
    let pending = Mutex<CheckedContinuation<Int, Never>?>(nil)
    let sawCancellation = Mutex(false)
    let old = Task {
      await loader.load {
        let result = await withCheckedContinuation { continuation in
          pending.withLock { $0 = continuation }
          started.continuation.yield(())
        }
        sawCancellation.withLock { $0 = Task.isCancelled }
        if lateFailure { throw Failure.unreadable }
        return result
      }
    }
    for await _ in started.stream { break }
    await loader.load { 2 }
    let continuation = try #require(pending.withLock { $0 })
    continuation.resume(returning: 1)
    await old.value
    #expect(sawCancellation.withLock { $0 })
    #expect(loader.value == 2)
    #expect(!loader.loadFailed)
  }

  @Test("Caller cancellation reaches the read and preserves visible content")
  @MainActor
  func canceledCallerPreservesContent() async throws {
    let loader = SnapshotLoader<Int>()
    await loader.load { 7 }
    let started = AsyncStream<Void>.makeStream()
    let pending = Mutex<CheckedContinuation<Int, Never>?>(nil)
    let sawCancellation = Mutex(false)
    let caller = Task {
      await loader.load {
        let result = await withCheckedContinuation { continuation in
          pending.withLock { $0 = continuation }
          started.continuation.yield(())
        }
        sawCancellation.withLock { $0 = Task.isCancelled }
        return result
      }
    }
    for await _ in started.stream { break }
    caller.cancel()
    let continuation = try #require(pending.withLock { $0 })
    continuation.resume(returning: 9)
    await caller.value
    #expect(sawCancellation.withLock { $0 })
    #expect(loader.value == 7)
    #expect(!loader.loadFailed)
  }

  @Test("A failed read is visible and a later successful read recovers")
  @MainActor
  func failureAndRetry() async {
    enum Failure: Error { case unreadable }
    let loader = SnapshotLoader<Int>()
    await loader.load { 1 }
    await loader.load { throw Failure.unreadable }
    #expect(loader.loadFailed)
    #expect(loader.value == nil)
    await loader.load { 3 }
    #expect(!loader.loadFailed)
    #expect(loader.value == 3)
    await loader.load { throw CancellationError() }
    #expect(!loader.loadFailed)
    #expect(loader.value == 3)
  }
}
