import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// At most one workout may be open at a time.
///
/// Without this, a second open session made the first permanently unreachable: `openSession` reads
/// only the newest unfinished row, and history lists only finished ones -- so the older workout was
/// neither resumable nor visible, while its sets still counted toward the week. The lifter saw
/// volume from a workout they could not open.
@Suite("Only one workout can be open at a time")
struct OpenSessionInvariantTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  @Test("Starting a second workout is refused, and names the one already open")
  func secondStartIsRefused() throws {
    let (_, store) = try fixture()
    let first = try store.startSession(at: now)

    do {
      _ = try store.startSession(at: now.addingTimeInterval(3600))
      Issue.record("a second session was opened")
    } catch let error as LoggerStoreError {
      // The id comes back so the caller can offer that workout instead of dead-ending, which is
      // what makes refusing safe rather than just strict.
      #expect(error == .sessionAlreadyOpen(first))
    }

    #expect(try store.openSession()?.id == first)
  }

  /// The exact orphaning scenario, end to end.
  @Test("A workout with logged sets cannot be stranded behind a newer one")
  func loggedWorkoutCannotBeStranded() throws {
    let (db, store) = try fixture()
    let bench = try exercise(db, "barbell-bench-press")

    let first = try store.startSession(at: now)
    _ = try store.logSet(
      sessionID: first, exerciseID: bench,
      draft: SetEntryDraft(weightKg: 84, reps: 8), setOrdinal: 0, at: now
    )

    // Before the guard, this succeeded and `first` became invisible forever.
    #expect(throws: LoggerStoreError.sessionAlreadyOpen(first)) {
      _ = try store.startSession(at: now.addingTimeInterval(7200))
    }

    // The logged work is still reachable.
    #expect(try store.openSession()?.id == first)
    #expect(try store.sets(in: first).count == 1)
    // And exactly one session exists, so nothing was written before the throw.
    let count = try db.read { d in try Session.fetchCount(d) }
    #expect(count == 1)
  }

  @Test("Finishing the open workout allows the next one to start")
  func finishingReleasesTheLock() throws {
    let (_, store) = try fixture()
    let first = try store.startSession(at: now)
    try store.finishSession(first, at: now.addingTimeInterval(3600))

    let second = try store.startSession(at: now.addingTimeInterval(7200))
    #expect(second != first)
    #expect(try store.openSession()?.id == second)
  }

  /// Deleting an abandoned workout is also a way out, and must leave the lock released.
  @Test("Deleting the open workout allows the next one to start")
  func deletingReleasesTheLock() throws {
    let (_, store) = try fixture()
    let first = try store.startSession(at: now)
    try store.deleteSession(first)

    #expect(try store.openSession() == nil)
    _ = try store.startSession(at: now.addingTimeInterval(60))
  }

  /// `SessionCoordinator.start` is the path the UI actually takes.
  @MainActor
  @Test("The coordinator surfaces the refusal rather than opening a second workout")
  func coordinatorSurfacesRefusal() throws {
    let (_, store) = try fixture()
    let first = try store.startSession(at: now)

    #expect(throws: LoggerStoreError.sessionAlreadyOpen(first)) {
      _ = try SessionCoordinator.start(store: store, plan: [], now: { self.now })
    }
  }
}
