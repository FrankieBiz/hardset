import Foundation
import GRDB
import Testing

@testable import HardsetStore

/// The Apple Health feature is gone from 1.0, but `deviceHealthSamples` is part of the permanent
/// schema and real devices already carry rows in it. Removing the feature's store must not remove
/// the table, so this opens it through the real migration and round-trips a row.
@Suite("The retained device table survives the feature's removal")
struct RetainedDeviceTableTests {
  private func migratedDatabase() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  @Test("deviceHealthSamples still opens and round-trips a row")
  func retainedDeviceHealthSamplesRoundTrips() throws {
    let database = try migratedDatabase()
    let id = UUID()
    try database.write { db in
      try db.execute(
        sql: """
          INSERT INTO deviceHealthSamples (id, kind, value, unit, startedAt, endedAt)
          VALUES (?, ?, ?, ?, ?, NULL)
          """,
        arguments: [id.uuidString, "apple.bodyMass", 80.0, "kg", "2026-01-01T00:00:00Z"])
    }
    let row = try database.read { db in
      try Row.fetchOne(
        db, sql: "SELECT kind, value, unit FROM deviceHealthSamples WHERE id = ?",
        arguments: [id.uuidString])
    }
    #expect(row?["kind"] as String? == "apple.bodyMass")
    #expect(row?["value"] as Double? == 80)
    #expect(row?["unit"] as String? == "kg")
  }
}
