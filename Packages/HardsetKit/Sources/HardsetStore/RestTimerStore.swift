import Foundation
import HardsetCore
import SQLiteData

/// A rest timer read back from disk.
public nonisolated struct PersistedRestTimer: Hashable, Sendable {
  public let state: RestTimerState
  /// The AlarmKit alarm backing it, so a timer restored after a relaunch can still be cancelled.
  public let alarmID: UUID?
  /// Which workout it belongs to. A rest left over from a workout that has since been finished is
  /// not this workout's rest.
  public let sessionID: SessionID?
  public let updatedAt: Date
}

/// Persists the rest timer so it survives leaving the app.
///
/// `deviceRestTimer` shipped in the first migration with a Swift model, a documented two-column
/// invariant, and a full storage projection on `RestTimerState` -- and no reader and no writer. The
/// Settings footer meanwhile told the lifter the timer "keeps running if you leave the app or
/// force-quit it", which was half true: AlarmKit's alarm does survive, but the app's own state did
/// not, so on relaunch the rest bar was gone and the alarm's id was lost with it -- leaving an alert
/// scheduled that nothing in the app could cancel.
///
/// Device-local by design. It is not in `syncedTableNames`, and it must not be: two phones do not
/// share one rest period, and a deadline pushed from another device would be actively wrong.
public nonisolated struct RestTimerStore {
  private let database: any DatabaseWriter

  /// The one row. A fixed id rather than "the newest row", so a failed write cannot leave two
  /// timers behind and make the reader pick.
  static let singletonID = UUID(uuidString: "5C7F9E10-0000-4000-8000-000000000001")!

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Writes the current timer, replacing whatever was there.
  ///
  /// `.idle` is written as a row with both columns nil rather than by deleting, so the table always
  /// describes the last known state and a missing row means "never used" rather than "just ended".
  public func save(
    state: RestTimerState,
    alarmID: UUID?,
    sessionID: SessionID?,
    now: Date = Date()
  ) throws {
    let projection = state.storage
    try database.write { db in
      try DeviceRestTimer.upsert {
        DeviceRestTimer.Draft(
          id: Self.singletonID,
          sessionID: sessionID?.rawValue,
          alarmID: alarmID,
          endsAt: projection.endsAt,
          pausedRemainingSeconds: projection.pausedRemainingSeconds,
          updatedAt: now
        )
      }
      .execute(db)
    }
  }

  /// Reads the timer back, or `nil` when there is nothing stored.
  ///
  /// A row that violates the one-of-two invariant is corruption. `RestTimerState.init` throws on it
  /// rather than guessing, and this returns `nil` and clears the row -- a rest timer is not worth
  /// blocking a launch over, and guessing which column to believe is how a paused timer comes back
  /// as a running one.
  public func load() throws -> PersistedRestTimer? {
    let row = try database.read { db in
      try DeviceRestTimer.where { $0.id.eq(Self.singletonID) }.fetchOne(db)
    }
    guard let row else { return nil }

    do {
      let state = try RestTimerState(
        endsAt: row.endsAt,
        pausedRemainingSeconds: row.pausedRemainingSeconds
      )
      return PersistedRestTimer(
        state: state,
        alarmID: row.alarmID,
        sessionID: row.sessionID.map(SessionID.init(rawValue:)),
        updatedAt: row.updatedAt
      )
    } catch {
      try? clear()
      return nil
    }
  }

  public func clear() throws {
    try database.write { db in
      try DeviceRestTimer.where { $0.id.eq(Self.singletonID) }.delete().execute(db)
    }
  }
}
