import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The rest timer survives the process that started it")
struct RestTimerStoreTests {
  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  let now = Date(timeIntervalSince1970: 2_000_000)

  @Test("Nothing saved loads as nil")
  func emptyIsNil() throws {
    #expect(try RestTimerStore(database: migratedDatabase()).load() == nil)
  }

  @Test("A running rest round-trips with its alarm")
  func runningRoundTrip() throws {
    let store = RestTimerStore(database: try migratedDatabase())
    let alarm = UUID()
    let rest = PersistedRest(state: .running(endsAt: now.addingTimeInterval(90)), alarmID: alarm)
    try store.save(rest, at: now)
    #expect(try store.load() == rest)
  }

  @Test("A paused rest round-trips")
  func pausedRoundTrip() throws {
    let store = RestTimerStore(database: try migratedDatabase())
    let rest = PersistedRest(state: .paused(remaining: .seconds(42)), alarmID: nil)
    try store.save(rest, at: now)
    #expect(try store.load() == rest)
  }

  @Test("Saving again replaces, so there is only ever one row")
  func singleRow() throws {
    let database = try migratedDatabase()
    let store = RestTimerStore(database: database)
    try store.save(PersistedRest(state: .paused(remaining: .seconds(5)), alarmID: nil), at: now)
    let later = PersistedRest(state: .running(endsAt: now.addingTimeInterval(30)), alarmID: UUID())
    try store.save(later, at: now)
    #expect(try store.load() == later)
    let count = try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deviceRestTimer") }
    #expect(count == 1)
  }

  @Test("Saving idle, or clearing, leaves nothing to load")
  func idleClears() throws {
    let store = RestTimerStore(database: try migratedDatabase())
    try store.save(PersistedRest(state: .paused(remaining: .seconds(5)), alarmID: nil), at: now)
    try store.save(PersistedRest(state: .idle, alarmID: nil), at: now)
    #expect(try store.load() == nil)
    try store.save(PersistedRest(state: .paused(remaining: .seconds(5)), alarmID: nil), at: now)
    try store.clear()
    #expect(try store.load() == nil)
  }

  @Test("A corrupt row with both a deadline and a remainder throws rather than picking one")
  func corruptRowThrows() throws {
    let database = try migratedDatabase()
    try database.write { db in
      try db.execute(
        sql: """
          INSERT INTO deviceRestTimer (id, endsAt, pausedRemainingSeconds)
          VALUES (?, '2026-01-01 00:00:00.000', 10)
          """,
        arguments: [RestTimerStore.rowID.uuidString.lowercased()])
    }
    #expect(throws: RestTimerStateError.bothDeadlineAndRemainingSet) {
      try RestTimerStore(database: database).load()
    }
  }
}
