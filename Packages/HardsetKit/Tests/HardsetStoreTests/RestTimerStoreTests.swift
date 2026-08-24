import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Persisting rest. `deviceRestTimer` shipped with a model, a documented invariant, and a full
/// storage projection -- and no reader and no writer, while Settings told the lifter the timer
/// survives a force-quit.
@Suite("A rest timer survives leaving the app")
struct RestTimerStoreTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, RestTimerStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return (queue, RestTimerStore(database: queue))
  }

  @Test("Nothing stored reads back as nothing")
  func emptyReadsAsNil() throws {
    let (_, store) = try fixture()
    #expect(try store.load() == nil)
  }

  @Test("A running timer round-trips as a deadline, not a countdown")
  func runningRoundTrips() throws {
    let (_, store) = try fixture()
    let endsAt = now.addingTimeInterval(90)
    let alarm = UUID()
    let session = SessionID()

    try store.save(state: .running(endsAt: endsAt), alarmID: alarm, sessionID: session, now: now)
    let loaded = try #require(try store.load())

    #expect(loaded.state == .running(endsAt: endsAt))
    // The alarm id is the point: without it a restored timer cannot cancel the alert it left behind.
    #expect(loaded.alarmID == alarm)
    #expect(loaded.sessionID == session)
  }

  @Test("A paused timer round-trips as a frozen remainder")
  func pausedRoundTrips() throws {
    let (_, store) = try fixture()
    try store.save(state: .paused(remaining: .seconds(42)), alarmID: nil, sessionID: nil, now: now)
    let loaded = try #require(try store.load())
    #expect(loaded.state == .paused(remaining: .seconds(42)))
    #expect(loaded.alarmID == nil)
  }

  @Test("Idle is stored as a state, not as an absence")
  func idleIsStored() throws {
    let (_, store) = try fixture()
    try store.save(state: .idle, alarmID: nil, sessionID: nil, now: now)
    let loaded = try #require(try store.load())
    #expect(loaded.state == .idle)
  }

  /// One row, always. A second save must replace rather than accumulate, or the reader has to pick.
  @Test("Saving twice leaves exactly one timer")
  func saveReplaces() throws {
    let (db, store) = try fixture()
    try store.save(state: .running(endsAt: now.addingTimeInterval(60)), alarmID: nil, sessionID: nil, now: now)
    try store.save(state: .paused(remaining: .seconds(10)), alarmID: nil, sessionID: nil, now: now)

    let count = try db.read { d in try DeviceRestTimer.fetchCount(d) }
    #expect(count == 1)
    #expect(try store.load()?.state == .paused(remaining: .seconds(10)))
  }

  @Test("Clearing removes the timer")
  func clearRemoves() throws {
    let (_, store) = try fixture()
    try store.save(state: .running(endsAt: now), alarmID: UUID(), sessionID: nil, now: now)
    try store.clear()
    #expect(try store.load() == nil)
  }

  /// A row with both columns set violates the invariant the enum exists to enforce. Guessing which
  /// one to believe is how a paused timer comes back running.
  @Test("A corrupt row is discarded rather than guessed at")
  func corruptRowIsDiscarded() throws {
    let (db, store) = try fixture()
    try db.write { d in
      try DeviceRestTimer.upsert {
        DeviceRestTimer.Draft(
          id: RestTimerStore.singletonID,
          sessionID: nil,
          alarmID: nil,
          endsAt: now,
          pausedRemainingSeconds: 30,
          updatedAt: now
        )
      }
      .execute(d)
    }

    #expect(try store.load() == nil)
    // And the bad row is gone, so it cannot be re-read on every launch.
    let count = try db.read { d in try DeviceRestTimer.fetchCount(d) }
    #expect(count == 0)
  }

  /// The table must never join the synced set: two phones do not share one rest period, and a
  /// deadline arriving from another device would be actively wrong.
  @Test("The rest timer is device-local")
  func restTimerIsNotSynced() {
    #expect(!HardsetMigrations.syncedTableNames.contains("deviceRestTimer"))
  }
}
