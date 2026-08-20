import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("History shows finished sessions, and quarantines impossible ones")
struct HistoryStoreTests {
  let now = Date(timeIntervalSince1970: 15_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, HistoryStore, ExerciseID, ExerciseID) {
    let database = try migratedDatabase()
    let press = ExerciseID()
    let curl = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Bench Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: curl.rawValue, name: "Barbell Curl") }.execute(db)
    }
    return (database, LoggerStore(database: database), HistoryStore(database: database), press, curl)
  }

  @Test("A finished session appears with its volume and duration")
  func finishedSessionAppears() throws {
    let (_, logger, history, press, _) = try fixture()
    let start = now.addingTimeInterval(-86_400)
    let session = try logger.startSession(title: "Push", at: start)
    for index in 0..<3 {
      _ = try logger.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: index,
        at: start.addingTimeInterval(Double(index) * 120)
      )
    }
    try logger.finishSession(session, at: start.addingTimeInterval(3600))

    let rows = try history.recentSessions()
    #expect(rows.count == 1)
    let row = rows[0]
    #expect(row.title == "Push")
    #expect(row.exerciseNames == ["Bench Press"])
    #expect(row.volume.workingSets == 3)
    #expect(row.volume.volumeKg == 2400)
    #expect(row.timeline.duration == .seconds(3600))
    #expect(!row.hasImplausibleDuration)
  }

  /// An unfinished workout belongs in the recovery path. Listing it with no duration invites the
  /// reader to think it lasted no time at all.
  @Test("An open session is not in history")
  func openSessionExcluded() throws {
    let (_, logger, history, press, _) = try fixture()
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    _ = try logger.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: now.addingTimeInterval(-3600)
    )
    #expect(try history.recentSessions().isEmpty)

    try logger.finishSession(session, at: now)
    #expect(try history.recentSessions().count == 1)
  }

  @Test("Sessions are newest first")
  func newestFirst() throws {
    let (_, logger, history, press, _) = try fixture()
    for daysAgo in [5, 1, 3] {
      let start = now.addingTimeInterval(Double(-daysAgo) * 86_400)
      let session = try logger.startSession(title: "Day \(daysAgo)", at: start)
      _ = try logger.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: start
      )
      try logger.finishSession(session, at: start.addingTimeInterval(3600))
    }
    #expect(try history.recentSessions().map(\.title) == ["Day 1", "Day 3", "Day 5"])
  }

  @Test("Movements are listed once, in the order first logged")
  func exerciseOrder() throws {
    let (_, logger, history, press, curl) = try fixture()
    let start = now.addingTimeInterval(-86_400)
    let session = try logger.startSession(at: start)
    for (index, exercise) in [press, curl, press].enumerated() {
      _ = try logger.logSet(
        sessionID: session, exerciseID: exercise,
        draft: SetEntryDraft(weightKg: 60, reps: 10), setOrdinal: index,
        at: start.addingTimeInterval(Double(index) * 60)
      )
    }
    try logger.finishSession(session, at: start.addingTimeInterval(3600))

    #expect(try history.recentSessions()[0].exerciseNames == ["Bench Press", "Barbell Curl"])
  }

  /// Warm-ups are separate from working volume here exactly as they are on the live screen.
  @Test("Warm-ups are counted separately, not folded into volume")
  func warmupsSeparate() throws {
    let (_, logger, history, press, _) = try fixture()
    let start = now.addingTimeInterval(-86_400)
    let session = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 40, reps: 15), setOrdinal: 0, isWarmup: true, at: start
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 1,
      at: start.addingTimeInterval(120)
    )
    try logger.finishSession(session, at: start.addingTimeInterval(3600))

    let row = try history.recentSessions()[0]
    #expect(row.volume.warmupSets == 1)
    #expect(row.volume.workingSets == 1)
    #expect(row.volume.volumeKg == 800)
  }

  /// The ancestor shipped 9,749-minute workouts to its history screen. This flags them rather than
  /// rendering them as achievements.
  @Test("An implausibly long session is flagged")
  func implausibleSessionFlagged() throws {
    let (_, logger, history, press, _) = try fixture()
    let start = now.addingTimeInterval(-10 * 86_400)
    let session = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: session, exerciseID: press,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: start
    )
    // Left running overnight and finished the next day.
    try logger.finishSession(session, at: start.addingTimeInterval(20 * 3600))

    let row = try history.recentSessions()[0]
    #expect(row.hasImplausibleDuration)
    // The duration is still reported truthfully; it is the presentation that changes.
    #expect(row.timeline.duration == .seconds(20 * 3600))
  }

  @Test("A session with no sets still appears, with nothing in it")
  func emptySession() throws {
    let (_, logger, history, _, _) = try fixture()
    let start = now.addingTimeInterval(-86_400)
    let session = try logger.startSession(at: start)
    try logger.finishSession(session, at: start.addingTimeInterval(600))

    let row = try history.recentSessions()[0]
    #expect(row.exerciseNames.isEmpty)
    #expect(row.volume.isEmpty)
  }

  @Test("The limit is respected")
  func limitRespected() throws {
    let (_, logger, history, press, _) = try fixture()
    for daysAgo in 1...5 {
      let start = now.addingTimeInterval(Double(-daysAgo) * 86_400)
      let session = try logger.startSession(at: start)
      _ = try logger.logSet(
        sessionID: session, exerciseID: press,
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: start
      )
      try logger.finishSession(session, at: start.addingTimeInterval(3600))
    }
    #expect(try history.recentSessions(limit: 2).count == 2)
  }
}
