import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

/// Finding an old workout. The rules worth pinning: a search returns the finished workouts that
/// hold what was typed, newest first; a search that matches nothing is an empty answer, not a
/// failure; and the statements it runs read an index, never every set.
@Suite("History search finds old workouts by movement, machine or gym")
struct HistorySearchTests {
  let now = Date(timeIntervalSince1970: 1_700_000_000)

  private struct Fixture {
    let database: DatabaseQueue
    let logger: LoggerStore
    let gyms: GymStore
    let history: HistoryStore
    let bench: ExerciseID
    let inclineBench: ExerciseID
    let curl: ExerciseID
    let squat: ExerciseID
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let bench = ExerciseID()
    let inclineBench = ExerciseID()
    let curl = ExerciseID()
    let squat = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: bench.rawValue, name: "Barbell Bench Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: inclineBench.rawValue, name: "Incline Bench Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: curl.rawValue, name: "Barbell Curl") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: squat.rawValue, name: "Back Squat") }.execute(db)
    }
    return Fixture(
      database: database, logger: LoggerStore(database: database), gyms: GymStore(database: database),
      history: HistoryStore(database: database), bench: bench, inclineBench: inclineBench, curl: curl,
      squat: squat)
  }

  /// Logs one working set of each movement and finishes the workout `daysAgo` days back.
  @discardableResult
  private func workout(
    _ f: Fixture, _ title: String, daysAgo: Int, movements: [ExerciseID], gym: GymID? = nil,
    machine: MachineID? = nil, finish: Bool = true
  ) throws -> SessionID {
    let start = now.addingTimeInterval(Double(-daysAgo) * 86_400)
    let session = try f.logger.startSession(gymID: gym, title: title, at: start)
    for (index, movement) in movements.enumerated() {
      _ = try f.logger.logSet(
        sessionID: session, exerciseID: movement, machineID: machine,
        draft: SetEntryDraft(weightKg: 80, reps: 8), setOrdinal: index,
        at: start.addingTimeInterval(Double(index) * 120))
    }
    if finish { try f.logger.finishSession(session, at: start.addingTimeInterval(3600)) }
    return session
  }

  @Test("A movement search returns the workouts that contain it, newest first")
  func movementNewestFirst() async throws {
    let f = try fixture()
    try workout(f, "Old push", daysAgo: 400, movements: [f.bench])
    try workout(f, "Legs", daysAgo: 30, movements: [f.squat])
    try workout(f, "Recent push", daysAgo: 2, movements: [f.bench, f.curl])
    try workout(f, "Mid push", daysAgo: 90, movements: [f.inclineBench])
    try workout(f, "Arms", daysAgo: 10, movements: [f.curl])

    let page = try await f.history.searchHistory("bench", limit: 50)

    #expect(page.sessions.map(\.title) == ["Recent push", "Mid push", "Old push"])
    #expect(page.totalCount == 3)
    #expect(!page.hasMore)
    // The result is the same summary the list shows, so what was found reads the same.
    #expect(page.sessions[0].exerciseNames == ["Barbell Bench Press", "Barbell Curl"])
    #expect(page.sessions[0].volume.workingSets == 2)
  }

  @Test("A search that matches nothing returns an empty page rather than failing")
  func noMatchIsEmpty() async throws {
    let f = try fixture()
    try workout(f, "Push", daysAgo: 3, movements: [f.bench])

    let page = try await f.history.searchHistory("deadlift", limit: 50)

    #expect(page.sessions.isEmpty)
    #expect(page.totalCount == 0)
    #expect(!page.hasMore)
  }

  @Test("A search over an empty history is empty")
  func emptyHistory() async throws {
    let f = try fixture()
    #expect(try await f.history.searchHistory("bench", limit: 50).sessions.isEmpty)
  }

  @Test("A query with no word in it finds nothing instead of everything",
        arguments: ["", " ", "b", " b ", "--", "..", "- -"])
  func unsearchableQueries(query: String) async throws {
    let f = try fixture()
    try workout(f, "Push", daysAgo: 3, movements: [f.bench])

    let page = try await f.history.searchHistory(query, limit: 50)

    #expect(!HistoryStore.isSearchable(query))
    #expect(page.sessions.isEmpty)
    #expect(page.totalCount == 0)
  }

  @Test("Movement names are matched as lifters type them")
  func movementSpelling() async throws {
    let f = try fixture()
    try workout(f, "Push", daysAgo: 3, movements: [f.bench])
    try workout(f, "Legs", daysAgo: 5, movements: [f.squat])

    // Case, plurals and a word out of order, by the picker's own rules.
    #expect(try await f.history.searchHistory("BENCH", limit: 50).sessions.map(\.title) == ["Push"])
    #expect(try await f.history.searchHistory("squats", limit: 50).sessions.map(\.title) == ["Legs"])
    #expect(try await f.history.searchHistory("press bench", limit: 50).sessions.map(\.title) == ["Push"])
    // Every word has to begin a word of the name: "ben" alone is a prefix, "bench curl" is not one name.
    #expect(try await f.history.searchHistory("ben", limit: 50).sessions.map(\.title) == ["Push"])
    #expect(try await f.history.searchHistory("bench curl", limit: 50).sessions.isEmpty)
  }

  @Test("An open workout is not found")
  func openWorkoutExcluded() async throws {
    let f = try fixture()
    try workout(f, "Still going", daysAgo: 0, movements: [f.bench], finish: false)
    #expect(try await f.history.searchHistory("bench", limit: 50).sessions.isEmpty)
  }

  @Test("A workout that holds several matching sets appears once")
  func appearsOnce() async throws {
    let f = try fixture()
    try workout(f, "Bench day", daysAgo: 4, movements: [f.bench, f.inclineBench, f.bench, f.inclineBench])

    let page = try await f.history.searchHistory("bench", limit: 50)

    #expect(page.sessions.count == 1)
    #expect(page.totalCount == 1)
  }

  @Test("A movement archived later is still found in the workouts that used it")
  func archivedMovementStillFound() async throws {
    let f = try fixture()
    try workout(f, "Push", daysAgo: 3, movements: [f.bench])
    try await f.database.write { db in
      try Exercise.where { $0.id.eq(f.bench.rawValue) }.update { $0.isArchived = true }.execute(db)
    }
    #expect(try await f.history.searchHistory("bench", limit: 50).sessions.map(\.title) == ["Push"])
  }

  @Test("Searching by machine finds the workouts done on it, including a brand in the name")
  func machineSearch() async throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Downtown")
    let hammer = try f.gyms.createMachine(at: gym, name: "Chest Press", brand: "Hammer Strength")
    let pecDeck = try f.gyms.createMachine(at: gym, name: "Pec Deck", brand: "Life Fitness")
    try workout(f, "On the Hammer", daysAgo: 8, movements: [f.bench], machine: hammer)
    try workout(f, "On the deck", daysAgo: 6, movements: [f.curl], machine: pecDeck)
    try workout(f, "Free weights", daysAgo: 2, movements: [f.curl])

    #expect(try await f.history.searchHistory("hammer", limit: 50).sessions.map(\.title) == ["On the Hammer"])
    #expect(try await f.history.searchHistory("chest press", limit: 50).sessions.map(\.title) == ["On the Hammer"])
    #expect(try await f.history.searchHistory("life fitness", limit: 50).sessions.map(\.title) == ["On the deck"])
  }

  @Test("Searching by gym finds every workout done there, with or without sets on a machine")
  func gymSearch() async throws {
    let f = try fixture()
    let downtown = try f.gyms.createGym(name: "Downtown Iron")
    let garage = try f.gyms.createGym(name: "Garage")
    try workout(f, "At downtown", daysAgo: 9, movements: [f.squat], gym: downtown)
    try workout(f, "At the garage", daysAgo: 5, movements: [f.squat], gym: garage)
    try workout(f, "Nowhere in particular", daysAgo: 1, movements: [f.squat])

    #expect(try await f.history.searchHistory("downtown", limit: 50).sessions.map(\.title) == ["At downtown"])
    #expect(try await f.history.searchHistory("garage", limit: 50).sessions.map(\.title) == ["At the garage"])
  }

  @Test("A query that names a movement and a gym finds both, each workout once")
  func matchesAcrossKinds() async throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Bench Warmers Gym")
    try workout(f, "Bench at home", daysAgo: 20, movements: [f.bench])
    try workout(f, "Legs at the gym", daysAgo: 10, movements: [f.squat], gym: gym)
    try workout(f, "Bench at the gym", daysAgo: 5, movements: [f.bench], gym: gym)
    try workout(f, "Curls", daysAgo: 1, movements: [f.curl])

    let page = try await f.history.searchHistory("bench", limit: 50)

    #expect(page.sessions.map(\.title) == ["Bench at the gym", "Legs at the gym", "Bench at home"])
    #expect(page.totalCount == 3)
  }

  @Test("A page holds the newest matches and counts all of them")
  func paging() async throws {
    let f = try fixture()
    for day in 1...7 { try workout(f, "Day \(day)", daysAgo: day, movements: [f.bench]) }
    try workout(f, "Legs", daysAgo: 3, movements: [f.squat])

    let first = try await f.history.searchHistory("bench", limit: 3)
    #expect(first.sessions.map(\.title) == ["Day 1", "Day 2", "Day 3"])
    #expect(first.totalCount == 7)
    #expect(first.hasMore)

    let all = try await f.history.searchHistory("bench", limit: 53)
    #expect(all.sessions.count == 7)
    #expect(!all.hasMore)
  }

  @Test("Workouts that started together keep one stable order across pages")
  func ties() async throws {
    let f = try fixture()
    let same = now.addingTimeInterval(-86_400)
    for title in ["A", "B", "C", "D"] {
      let session = try f.logger.startSession(title: title, at: same)
      _ = try f.logger.logSet(
        sessionID: session, exerciseID: f.bench, draft: SetEntryDraft(weightKg: 80, reps: 8),
        setOrdinal: 0, at: same.addingTimeInterval(60))
      try f.logger.finishSession(session, at: same.addingTimeInterval(3600))
    }
    let wide = try await f.history.searchHistory("bench", limit: 50).sessions.map(\.id)
    let narrow = try await f.history.searchHistory("bench", limit: 2).sessions.map(\.id)
    #expect(Array(wide.prefix(2)) == narrow)
    // The list sorts a tie by id, newest start first; search has to agree with it.
    #expect(wide == (try f.history.recentSessions().map(\.id)))
  }

  @Test("A cancelled search throws cancellation, not a stale page")
  func cancelledSearch() async throws {
    let f = try fixture()
    try workout(f, "Push", daysAgo: 3, movements: [f.bench])
    let history = f.history
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await history.searchHistory("bench", limit: 50)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  /// The statements the store really emits, not a copy of them, so an index cannot quietly stop
  /// being used after a change to the query. Names are read whole from three small tables; the
  /// big ones, sets and sessions, must only ever be searched, never scanned or sorted.
  @Test("Every statement a search runs reads an index of the big tables and sorts nothing")
  func searchIsIndexed() async throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Downtown")
    let machine = try f.gyms.createMachine(at: gym, name: "Chest Press", brand: "Hammer Strength")
    try workout(f, "Push", daysAgo: 3, movements: [f.bench], gym: gym, machine: machine)

    let statements = Mutex<[String]>([])
    try await f.database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event, statement.sql.hasPrefix("SELECT") {
          statements.withLock { $0.append(statement.expandedSQL) }
        }
      }
    }
    // One query per kind of name, so every lookup runs.
    #expect(try await f.history.searchHistory("bench", limit: 50).sessions.count == 1)
    #expect(try await f.history.searchHistory("hammer", limit: 50).sessions.count == 1)
    #expect(try await f.history.searchHistory("downtown", limit: 50).sessions.count == 1)

    let emitted = statements.withLock { $0 }
    // The lookups, one per kind of name, and the two reads that resolve their sessions by id.
    let byMovement = emitted.filter { $0.contains("\"loggedSets\".\"exerciseID\") IN") }
    let byMachine = emitted.filter { $0.contains("\"loggedSets\".\"machineID\") IN") }
    let byGym = emitted.filter { $0.contains("\"sessions\".\"gymID\") IN") }
    let byID = emitted.filter { $0.contains("FROM \"sessions\"") && $0.contains("\"sessions\".\"id\") IN") }
    #expect(!byMovement.isEmpty && !byMachine.isEmpty && !byGym.isEmpty && !byID.isEmpty)

    try await f.database.read { db in
      for query in emitted {
        let plan = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query)
          .compactMap { $0["detail"] as String? }
        #expect(!plan.contains { $0.contains("SCAN loggedSets") || $0.contains("SCAN sessions") },
                "scan in: \(query)\nplan: \(plan)")
        // The one sort is the summary read the list also runs, which orders the sets of the page's
        // few workouts. Nothing that looks for a match sorts.
        let ordersPage = query.contains("ORDER BY \"loggedSets\".\"completedAt\"")
        if !ordersPage {
          #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "sort in: \(query)\nplan: \(plan)")
        }
      }
      func plan(_ query: String) throws -> [String] {
        try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + query).compactMap { $0["detail"] as String? }
      }
      let machinePlan = try plan(try #require(byMachine.first))
      #expect(machinePlan.contains { $0.contains("loggedSets_on_machineID_sessionID") }, "plan: \(machinePlan)")
      let gymPlan = try plan(try #require(byGym.first))
      #expect(gymPlan.contains { $0.contains("sessions_on_gymID") }, "plan: \(gymPlan)")
      let movementPlan = try plan(try #require(byMovement.first))
      #expect(movementPlan.contains { $0.contains("SEARCH loggedSets USING") && $0.contains("exerciseID=?") },
              "plan: \(movementPlan)")
    }
  }

  @Test("The search indexes are added by a forward migration and change no stored row",
        arguments: ["v1", "v6_openSessionLookup", "v12_finishedWorkoutLookup", "v13_preciseImportUndo"])
  func searchIndexUpgrade(from baseline: String) throws {
    let queue = try DatabaseQueue()
    let migrator = HardsetMigrations.migrator()
    try migrator.migrate(queue, upTo: baseline)
    let id = UUID().uuidString.lowercased()
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO sessions (id, title) VALUES (?, ?)", arguments: [id, "Keep this workout"])
    }
    try migrator.migrate(queue)
    // Reopening must not rerun CREATE INDEX or mutate data.
    try migrator.migrate(queue)
    try queue.read { db in
      #expect(try String.fetchOne(db, sql: "SELECT title FROM sessions WHERE id = ?", arguments: [id])
        == "Keep this workout")
      let indexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
      for name in ["loggedSets_on_machineID_sessionID", "sessions_on_gymID"] {
        #expect(indexes.contains(name), "Missing search index: \(name)")
      }
      for (table, name) in [("loggedSets", "loggedSets_on_machineID_sessionID"), ("sessions", "sessions_on_gymID")] {
        let isUnique = try Bool.fetchOne(
          db, sql: "SELECT \"unique\" FROM pragma_index_list('\(table)') WHERE name = ?", arguments: [name])
        #expect(isUnique == false)
      }
      #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
    }
  }
}
