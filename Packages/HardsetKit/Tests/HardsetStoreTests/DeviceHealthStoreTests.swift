import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Apple Health observations stay local")
struct DeviceHealthStoreTests {
  @Test("Repeated reads upsert the same sample without creating workouts or sets")
  func replay() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let store = DeviceHealthStore(database: db)
    let sample = DeviceHealthStore.Sample(id: UUID(), kind: "apple.bodyMass", value: 80,
      unit: "kg", startedAt: Date(timeIntervalSince1970: 1000), endedAt: nil)
    try await store.save([sample])
    try await store.save([sample])
    let counts = try await db.read { db in
      (try DeviceHealthSample.fetchAll(db).count, try Session.fetchAll(db).count, try LoggedSet.fetchAll(db).count)
    }
    #expect(counts.0 == 1 && counts.1 == 0 && counts.2 == 0)
    #expect(!HardsetMigrations.syncedTableNames.contains("deviceHealthSamples"))
  }

  @Test("A malformed sample rolls back the batch")
  func invalid() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let store = DeviceHealthStore(database: db)
    let valid = DeviceHealthStore.Sample(id: UUID(), kind: "apple.bodyMass", value: 80, unit: "kg", startedAt: .now, endedAt: nil)
    let invalid = DeviceHealthStore.Sample(id: UUID(), kind: "apple.bodyMass", value: .nan, unit: "kg", startedAt: .now, endedAt: nil)
    await #expect(throws: DeviceHealthError.self) { try await store.save([valid, invalid]) }
    #expect(try await db.read { try DeviceHealthSample.fetchAll($0).isEmpty })
  }

  @Test("Only plausible completed native sessions are offered for Health export")
  func exportEligibility() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let start = Date(timeIntervalSince1970: 1000)
    let expected = UUID()
    try await db.write { db in
      try Session.insert { Session.Draft(id: expected, startedAt: start, finishedAt: start.addingTimeInterval(3600)) }.execute(db)
      try Session.insert { Session.Draft(id: UUID(), notes: "Imported from Strong", startedAt: start, finishedAt: start.addingTimeInterval(3600)) }.execute(db)
      try Session.insert { Session.Draft(id: UUID(), startedAt: start) }.execute(db)
      try Session.insert { Session.Draft(id: UUID(), startedAt: start, finishedAt: start.addingTimeInterval(90000)) }.execute(db)
    }
    #expect(try await DeviceHealthStore(database: db).workoutsToExport().map(\.id.rawValue) == [expected])
  }
}
