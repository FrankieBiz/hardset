import Foundation
import HardsetCore
import SQLiteData

/// Remembers which workouts went to Apple Health, so none goes twice, and decides whether one may.
///
/// Called for one session, at the moment it is finished on this device. There is deliberately no
/// way to ask for "every session": a workout that arrives by sync was finished on another device,
/// which sent it to Health itself if its owner asked, and a backfill would send sessions nobody
/// chose to share when the setting was off.
public nonisolated struct HealthExportStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// When the lifter has not opted in, nothing is read at all.
  public func decision(
    for sessionID: SessionID, isEnabled: Bool, now: Date = Date()
  ) throws -> HealthExportDecision {
    guard isEnabled else { return .skip(.notEnabled) }
    return try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let sets = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchCount(db)
      let exported =
        try DeviceHealthExport.where { $0.sessionID.eq(sessionID.rawValue) }.fetchCount(db) > 0
      return HealthExportPolicy.decide(
        sessionID: sessionID,
        timeline: SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt),
        loggedSets: sets, isEnabled: true, alreadyExported: exported, now: now)
    }
  }

  /// Written only after HealthKit has saved the workout: persist before claiming.
  public func recordExport(of sessionID: SessionID, healthWorkoutID: UUID, at now: Date = Date())
    throws
  {
    try database.write { db in
      try DeviceHealthExport.insert {
        DeviceHealthExport.Draft(
          sessionID: sessionID.rawValue, healthWorkoutID: healthWorkoutID, exportedAt: now)
      }
      .execute(db)
    }
  }

  /// The HealthKit workout a session became, if it was sent.
  public func healthWorkoutID(for sessionID: SessionID) throws -> UUID? {
    try database.read { db in
      try DeviceHealthExport.where { $0.sessionID.eq(sessionID.rawValue) }.fetchOne(db)?
        .healthWorkoutID
    }
  }
}
