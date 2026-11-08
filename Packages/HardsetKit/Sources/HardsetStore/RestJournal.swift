import Foundation
import GRDB
import HardsetCore
import SQLiteData

/// This journal is device-local. Rest alarms are never replicated to another phone.
/// The one-row write must commit before the controller changes its visible state or the OS.
public nonisolated struct RestJournal: Sendable {
  private let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  public func load() throws -> RestCheckpoint {
    try database.read { db in
      guard let text = try String.fetchOne(db, sql: "SELECT checkpointJSON FROM deviceRestJournal WHERE id = 1") else {
        return RestCheckpoint()
      }
      return try JSONDecoder().decode(RestCheckpoint.self, from: Data(text.utf8))
    }
  }

  public func save(_ checkpoint: RestCheckpoint) throws {
    let text = String(decoding: try JSONEncoder().encode(checkpoint), as: UTF8.self)
    try database.write { db in
      try db.execute(sql: "INSERT INTO deviceRestJournal(id, checkpointJSON) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET checkpointJSON = excluded.checkpointJSON", arguments: [text])
    }
  }
}
