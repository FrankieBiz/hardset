import Foundation
import HardsetCore
import SQLiteData

/// Where the rest timer is written down, so a relaunch can tell which AlarmKit alarm is its own.
///
/// One row, with a fixed id: a device runs one rest timer at a time, so there is nothing to
/// key it by. It is device-local and never synced, because an alarm scheduled on this phone means
/// nothing on another device. The table is deliberately absent from the sync list, which also
/// keeps it out of SQLiteData's account-change wipe.
public nonisolated struct RestTimerStore {
  /// The only id the table ever holds a row under.
  static let rowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// The persisted rest, or nil when there is no row or the row is idle.
  ///
  /// Throws `RestTimerStateError.bothDeadlineAndRemainingSet` for a row carrying both a deadline
  /// and a remainder. That is corruption, and picking either column would invent a rest the
  /// lifter never took.
  public func load() throws -> PersistedRest? {
    try database.read { db in
      guard let row = try DeviceRestTimer.where({ $0.id.eq(Self.rowID) }).fetchOne(db) else {
        return nil
      }
      let state = try RestTimerState(
        endsAt: row.endsAt, pausedRemainingSeconds: row.pausedRemainingSeconds)
      guard state != .idle else { return nil }
      return PersistedRest(state: state, alarmID: row.alarmID)
    }
  }

  /// Writes the rest, replacing whatever was there. An idle state deletes the row instead, so
  /// "no rest" has exactly one representation.
  public func save(_ rest: PersistedRest, at now: Date) throws {
    guard rest.state != .idle else { return try clear() }
    let columns = rest.state.storage
    try database.write { db in
      // A real upsert. The schema's `ON CONFLICT REPLACE` clauses attach to the NOT NULL
      // constraints, not to the primary key, so a plain insert under the fixed id would fail
      // with a UNIQUE violation the second time.
      try DeviceRestTimer.upsert {
        DeviceRestTimer(
          id: Self.rowID,
          sessionID: nil,
          alarmID: rest.alarmID,
          endsAt: columns.endsAt,
          pausedRemainingSeconds: columns.pausedRemainingSeconds,
          updatedAt: now)
      }
      .execute(db)
    }
  }

  public func clear() throws {
    try database.write { db in
      try DeviceRestTimer.where { $0.id.eq(Self.rowID) }.delete().execute(db)
    }
  }
}
