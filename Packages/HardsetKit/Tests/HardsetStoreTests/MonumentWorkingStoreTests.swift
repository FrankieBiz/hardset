import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The Train screen's volume monument opens a working derived from the receipt's lines, and its
/// figure comes from the history summary's rows. They are two readings of one workout, and a large
/// number with an explanation that disagrees with it is worse than one with none, so this holds them
/// equal on a real database, warm-ups and a no-load set included.
@Suite("Worked from: the last workout's volume matches its summary")
struct MonumentWorkingStoreTests {
  @Test("The working's volume is the summary's, set for set")
  func workingMatchesSummary() async throws {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let db = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(db)
    let press = ExerciseID(), pullUp = ExerciseID(), session = SessionID()
    let start = Date(timeIntervalSince1970: 15_000_000)
    try await db.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: pullUp.rawValue, name: "Pull-up") }.execute(db)
      try Session.insert {
        Session.Draft(
          id: session.rawValue, startedAt: start, finishedAt: start.addingTimeInterval(3600))
      }.execute(db)
      let rows: [(UUID, Double, Int, Bool, Double)] = [
        (press.rawValue, 40, 12, true, 60),
        (press.rawValue, 100, 10, false, 120),
        (press.rawValue, 102.5, 8, false, 240),
        (pullUp.rawValue, 0, 12, false, 360),
      ]
      for (index, row) in rows.enumerated() {
        try LoggedSet.insert {
          LoggedSet.Draft(
            id: UUID(), sessionID: session.rawValue, exerciseID: row.0, setOrdinal: index,
            weightKg: row.1, reps: row.2, isWarmup: row.3,
            completedAt: start.addingTimeInterval(row.4))
        }.execute(db)
      }
    }

    let receipt = try await ReceiptStore(database: db).load(session)
    let summary = try #require(try await HistoryStore(database: db).loadRecentSessions(limit: 1).first)
    let working = SessionVolumeWorking.derive(lines: receipt.lines)

    #expect(working.volume == summary.volume)
    #expect(working.volume.workingSets == 3)
    #expect(working.volume.warmupSets == 1)
    #expect(working.volume.volumeKg == 1_820)

    // And the figure it states is the one the Train screen rounds to.
    let format = WorkedFromFormat(unit: .kilograms, locale: Locale(identifier: "en_US"))
    let account = working.account(title: "Press day", format: format)
    #expect(account.figure == "1,820 kg")
  }
}
