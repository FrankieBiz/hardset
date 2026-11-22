import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

/// Jumping to a month. The properties worth pinning: only months that hold workouts are offered,
/// a month is cut where the lifter's own calendar cuts it, and landing on a month starts the list
/// at that month's last workout and shows nothing newer.
@Suite("History can jump to a month that has workouts in it")
struct HistoryMonthsTests {
  private func calendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
  }

  private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
    in calendar: Calendar
  ) -> Date {
    calendar.date(from: DateComponents(
      year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
  }

  // MARK: - Grouping

  @Test("Workouts group into the months they started in, newest month first, with counts")
  func grouping() {
    let utc = calendar()
    let starts = [
      date(2024, 1, 2, in: utc), date(2023, 4, 30, in: utc), date(2023, 4, 15, in: utc),
      date(2023, 3, 9, in: utc), date(2020, 2, 29, in: utc),
    ]

    let months = HistoryStore.months(of: starts, calendar: utc)

    #expect(months.map(\.workoutCount) == [1, 2, 1, 1])
    #expect(months.map(\.start) == [
      date(2024, 1, 1, 0, in: utc), date(2023, 4, 1, 0, in: utc), date(2023, 3, 1, 0, in: utc),
      date(2020, 2, 1, 0, in: utc),
    ])
    // Each month ends where the next calendar month begins, so the page that lands on it is cut on a
    // real boundary.
    for month in months {
      #expect(month.end == utc.date(byAdding: .month, value: 1, to: month.start))
    }
  }

  @Test("The last second of a month and the first of the next fall in different months")
  func boundaries() {
    let utc = calendar()
    let lastSecond = date(2023, 3, 31, 23, 59, 59, in: utc)
    let firstSecond = date(2023, 4, 1, 0, 0, 0, in: utc)

    let months = HistoryStore.months(of: [firstSecond, lastSecond], calendar: utc)

    #expect(months.map(\.workoutCount) == [1, 1])
    #expect(months[0].start == firstSecond)
    #expect(months[1].end == firstSecond)
  }

  @Test("A month is cut by the lifter's calendar, not by UTC")
  func timeZone() {
    let utc = calendar()
    let losAngeles = calendar("America/Los_Angeles")
    // 03:00 UTC on 1 April is 8 pm on 31 March in Los Angeles, so it was a March workout there.
    let instant = date(2023, 4, 1, 3, in: utc)

    let inUTC = HistoryStore.months(of: [instant], calendar: utc)
    let inLosAngeles = HistoryStore.months(of: [instant], calendar: losAngeles)

    #expect(inUTC[0].start == date(2023, 4, 1, 0, in: utc))
    #expect(inLosAngeles[0].start == date(2023, 3, 1, 0, in: losAngeles))
    #expect(inLosAngeles[0].end == date(2023, 4, 1, 0, in: losAngeles))
  }

  @Test("No workouts means no months")
  func none() {
    #expect(HistoryStore.months(of: [], calendar: calendar()).isEmpty)
  }

  // MARK: - Against the store

  private struct Fixture {
    let database: DatabaseQueue
    let logger: LoggerStore
    let history: HistoryStore
    let exercise: ExerciseID
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Bench Press") }.execute(db)
    }
    return Fixture(
      database: database, logger: LoggerStore(database: database),
      history: HistoryStore(database: database), exercise: exercise)
  }

  @discardableResult
  private func workout(_ f: Fixture, _ title: String, at start: Date, finish: Bool = true) throws -> SessionID {
    let session = try f.logger.startSession(title: title, at: start)
    _ = try f.logger.logSet(
      sessionID: session, exerciseID: f.exercise, draft: SetEntryDraft(weightKg: 80, reps: 8),
      setOrdinal: 0, at: start.addingTimeInterval(60))
    if finish { try f.logger.finishSession(session, at: start.addingTimeInterval(3600)) }
    return session
  }

  /// Three years with gaps: the months a lifter did not train are simply absent.
  private func threeYears(_ f: Fixture, _ utc: Calendar) throws {
    try workout(f, "2021-02", at: date(2021, 2, 10, in: utc))
    try workout(f, "2022-07 a", at: date(2022, 7, 4, in: utc))
    try workout(f, "2022-07 b", at: date(2022, 7, 28, in: utc))
    try workout(f, "2022-07 c", at: date(2022, 7, 31, 23, 30, in: utc))
    try workout(f, "2022-08", at: date(2022, 8, 1, 0, 0, 0, in: utc))
    try workout(f, "2024-01", at: date(2024, 1, 15, in: utc))
  }

  @Test("Only months that hold finished workouts are offered")
  func storeMonths() async throws {
    let f = try fixture()
    let utc = calendar()
    try threeYears(f, utc)
    try workout(f, "Still going", at: date(2024, 5, 3, in: utc), finish: false)

    let months = try await f.history.loadMonths(calendar: utc)

    #expect(months.map(\.start) == [
      date(2024, 1, 1, 0, in: utc), date(2022, 8, 1, 0, in: utc), date(2022, 7, 1, 0, in: utc),
      date(2021, 2, 1, 0, in: utc),
    ])
    #expect(months.map(\.workoutCount) == [1, 1, 3, 1])
    // The open workout's month is not offered: it is not history yet.
    #expect(!months.contains { $0.start == date(2024, 5, 1, 0, in: utc) })
  }

  @Test("An empty history has no months")
  func emptyStore() async throws {
    let f = try fixture()
    #expect(try await f.history.loadMonths(calendar: calendar()).isEmpty)
  }

  @Test("Landing on a month starts at its last workout and shows nothing newer")
  func landing() async throws {
    let f = try fixture()
    let utc = calendar()
    try threeYears(f, utc)
    let july = try #require(try await f.history.loadMonths(calendar: utc).first {
      $0.start == date(2022, 7, 1, 0, in: utc)
    })

    let page = try await f.history.loadHistory(limit: 50, startedBefore: july.end)

    // 31 July at 11:30 pm leads, and 1 August at midnight is the next month, so it is not here.
    #expect(page.sessions.map(\.title) == ["2022-07 c", "2022-07 b", "2022-07 a", "2021-02"])
    #expect(page.totalCount == 4)
    #expect(!page.hasMore)
  }

  @Test("Landing on a month is a page like any other: paged, counted, newest first")
  func landingPages() async throws {
    let f = try fixture()
    let utc = calendar()
    try threeYears(f, utc)
    let july = try #require(try await f.history.loadMonths(calendar: utc).first {
      $0.start == date(2022, 7, 1, 0, in: utc)
    })

    let page = try await f.history.loadHistory(limit: 2, startedBefore: july.end)

    #expect(page.sessions.map(\.title) == ["2022-07 c", "2022-07 b"])
    #expect(page.totalCount == 4)
    #expect(page.hasMore)
  }

  @Test("Without a month the list is unchanged: everything, newest first")
  func noBound() async throws {
    let f = try fixture()
    let utc = calendar()
    try threeYears(f, utc)

    let all = try await f.history.loadHistory(limit: 50)
    let unbounded = try await f.history.loadHistory(limit: 50, startedBefore: nil)

    #expect(all == unbounded)
    #expect(all.totalCount == 6)
    #expect(all.sessions.first?.title == "2024-01")
  }

  /// The promise of the picker: whichever month is chosen, the list opens on a workout from it.
  @Test("Every month offered lands on a workout from that month")
  func everyMonthLandsOnData() async throws {
    let f = try fixture()
    let losAngeles = calendar("America/Los_Angeles")
    try threeYears(f, losAngeles)
    // Right on a boundary in the lifter's calendar, and in the one before it.
    try workout(f, "edge", at: date(2023, 9, 1, 0, 0, 0, in: losAngeles))
    try workout(f, "edge before", at: date(2023, 8, 31, 23, 59, 59, in: losAngeles))

    let months = try await f.history.loadMonths(calendar: losAngeles)
    #expect(months.count >= 6)
    for month in months {
      let page = try await f.history.loadHistory(limit: 1, startedBefore: month.end)
      let first = try #require(page.sessions.first, "no workout for \(month.start)")
      #expect(first.timeline.startedAt >= month.start && first.timeline.startedAt < month.end,
              "\(month.start) landed on \(first.timeline.startedAt)")
    }
  }

  /// The statements the store really emits, as the search tests do: the pages and the month list
  /// read the index built for them, in its own order, and sort nothing.
  @Test("The page, its count and the month list read the history index and sort nothing")
  func historyOrderIsIndexed() async throws {
    let f = try fixture()
    let utc = calendar()
    try threeYears(f, utc)
    let statements = Mutex<[String]>([])
    try await f.database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") {
          statements.withLock { $0.append(statement.expandedSQL) }
        }
      }
    }
    let july = try #require(try await f.history.loadMonths(calendar: utc).first {
      $0.start == date(2022, 7, 1, 0, in: utc)
    })
    _ = try await f.history.loadHistory(limit: 50, startedBefore: july.end)
    _ = try await f.history.loadHistory(limit: 50)

    let emitted = statements.withLock { $0 }
    let sessionReads = emitted.filter { $0.contains("FROM \"sessions\"") && !$0.contains("\"loggedSets\"") }
    // The month list, the bounded page and its count, the unbounded page and its count.
    #expect(sessionReads.count == 5, "reads: \(sessionReads)")

    try await f.database.read { db in
      for query in sessionReads {
        let plan = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query)
          .compactMap { $0["detail"] as String? }
        #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "sort in: \(query)\nplan: \(plan)")
        if query.contains("\"startedAt\" <") {
          #expect(plan.contains { $0.contains("SEARCH sessions") && $0.contains("sessions_on_historyOrder") },
                  "plan: \(plan)\nfor: \(query)")
        }
        if query.contains("ORDER BY") {
          #expect(plan.contains { $0.contains("sessions_on_historyOrder") }, "plan: \(plan)\nfor: \(query)")
        }
      }
    }
  }

  @Test("The history index is added by a forward migration and changes no stored row",
        arguments: ["v1", "v12_finishedWorkoutLookup", "v13_preciseImportUndo", "v14_historySearch"])
  func historyIndexUpgrade(from baseline: String) throws {
    let queue = try DatabaseQueue()
    let migrator = HardsetMigrations.migrator()
    try migrator.migrate(queue, upTo: baseline)
    let id = UUID().uuidString.lowercased()
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO sessions (id, title, finishedAt) VALUES (?, ?, ?)",
        arguments: [id, "Keep this workout", "2023-03-01 10:00:00.000"])
    }
    try migrator.migrate(queue)
    // Reopening must not rerun CREATE INDEX or mutate data.
    try migrator.migrate(queue)
    try queue.read { db in
      #expect(try String.fetchOne(db, sql: "SELECT title FROM sessions WHERE id = ?", arguments: [id])
        == "Keep this workout")
      let indexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
      #expect(indexes.contains("sessions_on_historyOrder"))
      let isUnique = try Bool.fetchOne(
        db, sql: "SELECT \"unique\" FROM pragma_index_list('sessions') WHERE name = 'sessions_on_historyOrder'")
      #expect(isUnique == false)
      #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
    }
  }
}
