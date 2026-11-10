import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Rest survives process and database reopening")
struct RestJournalTests {
  @Test("Deadline, pause, metadata and pending cancellations round trip")
  func relaunch() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let database = try DatabaseQueue(path: path)
    try HardsetMigrations.migrator().migrate(database)
    let journal = RestJournal(database: database)
    #expect(try journal.load().state == .idle)
    let end = Date(timeIntervalSince1970: 5000)
    let metadata = RestMetadata(exerciseName: "Press", setOrdinal: 2, machineName: "Cybex")
    let saved = RestCheckpoint(state: .running(endsAt: end), metadata: metadata,
      alarmID: UUID(), retiredAlarmIDs: [UUID(), UUID()])
    try journal.save(saved)
    try database.close()
    let reopened = try DatabaseQueue(path: path)
    try HardsetMigrations.migrator().migrate(reopened)
    let restored = RestJournal(database: reopened)
    #expect(try restored.load() == saved)
    let paused = RestCheckpoint(state: .paused(remaining: .seconds(45)), metadata: metadata)
    try restored.save(paused)
    #expect(try restored.load() == paused)
    try restored.save(.init())
    #expect(try restored.load().state == .idle)
  }

  @Test("An unsuccessful write preserves the previous deadline")
  func failure() throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let journal = RestJournal(database: database)
    let previous = RestCheckpoint(state: .running(endsAt: Date(timeIntervalSince1970: 5000)))
    try journal.save(previous)
    try database.write { db in
      try db.execute(sql: "CREATE TRIGGER refuseRest BEFORE UPDATE ON deviceRestJournal BEGIN SELECT RAISE(ABORT, 'full'); END")
    }
    #expect(throws: (any Error).self) { try journal.save(.init()) }
    #expect(try journal.load() == previous)
  }

  /// The journal outlives app updates on a phone, so a rest written by an older build must still
  /// load after the payload gains a field. An unreadable row blocks the rest timer until reset.
  @Test("A rest journalled before the total was recorded still loads")
  func olderRow() throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let id = UUID()
    let json = #"{"state":{"running":{"endsAt":800000000}},"metadata":{"exerciseName":"Press","setOrdinal":2},"alarmID":"\#(id.uuidString)","retiredAlarmIDs":[]}"#
    try database.write { try $0.execute(sql: "INSERT INTO deviceRestJournal VALUES (1, ?)", arguments: [json]) }
    let loaded = try RestJournal(database: database).load()
    #expect(loaded.state == .running(endsAt: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    #expect(loaded.metadata == RestMetadata(exerciseName: "Press", setOrdinal: 2))
    #expect(loaded.metadata?.totalRest == nil)
    #expect(loaded.alarmID == id)
  }

  @Test("Corrupt durable state is surfaced rather than treated as idle")
  func corrupt() throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    try database.write { try $0.execute(sql: "INSERT INTO deviceRestJournal VALUES (1, 'invalid')") }
    #expect(throws: (any Error).self) { try RestJournal(database: database).load() }
  }
}
