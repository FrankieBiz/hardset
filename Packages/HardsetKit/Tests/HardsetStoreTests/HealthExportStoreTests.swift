import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A workout goes to Apple Health once, from this device, with the times it really had")
struct HealthExportStoreTests {
  let now = Date(timeIntervalSince1970: 80_000_000)

  private func database(migrated: Bool = true) throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    if migrated { try HardsetMigrations.migrator().migrate(queue) }
    return queue
  }

  /// A seeded catalogue, one finished session of `length` seconds with `sets` working sets.
  private func workout(
    _ db: any DatabaseWriter, length: Double? = 3_000, sets: Int = 2
  ) throws -> SessionID {
    try CatalogSeeder(database: db).seed(now: now)
    let exercise = try #require(try db.read { try Exercise.fetchOne($0) })
    let logger = LoggerStore(database: db)
    let session = try logger.startSession(at: now)
    for index in 0..<sets {
      try logger.logSet(
        sessionID: session, exerciseID: ExerciseID(rawValue: exercise.id),
        draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(Double(index + 1) * 60))
    }
    if let length { try logger.finishSession(session, at: now.addingTimeInterval(length)) }
    return session
  }

  @Test("When off, nothing is read, not even a database that cannot be")
  func offReadsNothing() throws {
    let store = HealthExportStore(database: try database(migrated: false))
    #expect(try store.decision(for: SessionID(), isEnabled: false) == .skip(.notEnabled))
  }

  @Test("A finished workout is offered with its session's own start and finish")
  func finishedWorkoutIsExported() throws {
    let db = try database()
    let session = try workout(db)
    let decision = try HealthExportStore(database: db)
      .decision(for: session, isEnabled: true, now: now.addingTimeInterval(4_000))
    #expect(
      decision
        == .export(
          HealthWorkoutPlan(
            sessionID: session, activity: .traditionalStrengthTraining, start: now,
            end: now.addingTimeInterval(3_000))))
  }

  @Test("Once recorded, the same workout is never offered again")
  func secondExportIsSkipped() throws {
    let db = try database()
    let session = try workout(db)
    let store = HealthExportStore(database: db)
    let healthID = UUID()
    try store.recordExport(of: session, healthWorkoutID: healthID, at: now.addingTimeInterval(3_001))
    #expect(try store.healthWorkoutID(for: session) == healthID)
    #expect(
      try store.decision(for: session, isEnabled: true, now: now.addingTimeInterval(4_000))
        == .skip(.alreadyExported))
  }

  @Test("Recording the same session twice leaves one row, and the first workout id")
  func recordingTwiceIsOneRow() throws {
    let db = try database()
    let session = try workout(db)
    let store = HealthExportStore(database: db)
    let first = UUID()
    try store.recordExport(of: session, healthWorkoutID: first, at: now.addingTimeInterval(3_001))
    try store.recordExport(of: session, healthWorkoutID: UUID(), at: now.addingTimeInterval(3_002))
    #expect(try db.read { try DeviceHealthExport.fetchCount($0) } == 1)
    #expect(try store.healthWorkoutID(for: session) == first)
  }

  @Test("A database migrated only to v1, with a finished session, upgrades to v2 and keeps it")
  func upgradeFromV1KeepsSessions() throws {
    let db = try database(migrated: false)
    try HardsetMigrations.migrator().migrate(db, upTo: "v1")
    #expect(try db.read { try $0.tableExists("deviceHealthExports") } == false)
    let session = try workout(db)
    try HardsetMigrations.migrator().migrate(db)
    #expect(try db.read { try $0.tableExists("deviceHealthExports") })
    #expect(try db.read { try Session.where { $0.id.eq(session.rawValue) }.fetchCount($0) } == 1)
  }

  /// Review Focus: signing out of iCloud wipes the synced session rows; signing back in downloads
  /// the same session again, under the same id. It must not reach Health a second time.
  @Test("The record survives the session row, so a re-downloaded workout is not sent twice")
  func exportSurvivesSessionDeletion() throws {
    let db = try database()
    let session = try workout(db)
    let store = HealthExportStore(database: db)
    try store.recordExport(of: session, healthWorkoutID: UUID(), at: now.addingTimeInterval(3_001))

    let row = try #require(try db.read { db in
      try Session.where { $0.id.eq(session.rawValue) }.fetchOne(db)
    })
    try db.write { db in try Session.where { $0.id.eq(session.rawValue) }.delete().execute(db) }
    #expect(try store.healthWorkoutID(for: session) != nil)

    try db.write { db in
      try Session.insert {
        Session.Draft(
          id: row.id, gymID: nil, title: row.title, notes: row.notes, startedAt: row.startedAt,
          finishedAt: row.finishedAt)
      }
      .execute(db)
    }
    #expect(
      try store.decision(for: session, isEnabled: true, now: now.addingTimeInterval(4_000))
        == .skip(.alreadyExported))
  }

  @Test("An open workout, an empty one, and one left open overnight are not sent")
  func notWorkoutsToRecord() throws {
    let db = try database()
    let open = try workout(db, length: nil)
    let store = HealthExportStore(database: db)
    let later = now.addingTimeInterval(86_400)
    #expect(try store.decision(for: open, isEnabled: true, now: later) == .skip(.stillOpen))

    let logger = LoggerStore(database: db)
    let empty = try logger.startSession(at: now)
    try logger.finishSession(empty, at: now.addingTimeInterval(600))
    #expect(try store.decision(for: empty, isEnabled: true, now: later) == .skip(.nothingLogged))

    let overnight = try logger.startSession(at: now)
    try logger.logSet(
      sessionID: overnight,
      exerciseID: ExerciseID(rawValue: try #require(try db.read { try Exercise.fetchOne($0) }).id),
      draft: SetEntryDraft(weightKg: 60, reps: 10), at: now.addingTimeInterval(60))
    try logger.finishSession(overnight, at: now.addingTimeInterval(9 * 3_600))
    #expect(try store.decision(for: overnight, isEnabled: true, now: later) == .skip(.implausiblyLong))
  }

  @Test("An unknown session is an error, not a skip")
  func unknownSessionThrows() throws {
    let store = HealthExportStore(database: try database())
    #expect(throws: LoggerStoreError.sessionNotFound) {
      try store.decision(for: SessionID(), isEnabled: true)
    }
  }

  @Test("The table is device-local: named so, and never synchronized")
  func tableIsDeviceLocal() {
    #expect(HardsetMigrations.deviceLocalTableNames.contains("deviceHealthExports"))
    #expect(!HardsetMigrations.syncedTableNames.contains("deviceHealthExports"))
  }
}
