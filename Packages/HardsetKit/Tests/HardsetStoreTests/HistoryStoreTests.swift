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

  @Test("Migration policy never automatically erases a database")
  func migrationsNeverErase() {
    #expect(!HardsetMigrations.migrator().eraseDatabaseOnSchemaChange)
  }

  @Test("Original and partially upgraded v1 databases preserve every existing value",
        arguments: 0..<16)
  @MainActor
  func historicalV1Upgrade(variant: Int) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hardset-upgrade-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(path: path, configuration: configuration)
    var historical = DatabaseMigrator()
    historical.registerMigration("v1") { db in try db.execute(sql: Self.historicalV1Schema) }
    try historical.migrate(database)
    let catalog = try #require(ExerciseCatalog.v1.first)
    let exercise = try #require(catalog.uuid)
    let gym = UUID()
    let machine = UUID()
    let active = UUID()
    let finished = UUID()
    let plan = UUID()
    let set = UUID()
    try database.write { db in
      // Bits 0/1 represent independently present columns; bit 2 exercises the
      // release policy explicitly, even when tests compile the app with DEBUG.
      if variant & 1 != 0 {
        try db.execute(sql: "ALTER TABLE exercises ADD COLUMN curatedName TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''")
      }
      if variant & 2 != 0 {
        try db.execute(sql: "ALTER TABLE loggedSets ADD COLUMN sessionExerciseID TEXT")
      }
      try #sql("INSERT INTO exercises (id, name, catalogSlug, isCurated, notes, isArchived) VALUES (\(exercise), 'My sled', \(bind: catalog.slug), 1, 'Keep my notes', 1)").execute(db)
      try Gym.insert { Gym.Draft(id: gym, name: "My gym") }.execute(db)
      try Machine.insert { Machine.Draft(id: machine, gymID: gym, name: "My press", stackIncrementKg: 5) }.execute(db)
      try MachineExercise.insert { MachineExercise.Draft(id: UUID(), machineID: machine, exerciseID: exercise) }.execute(db)
      // Use the historical column list, independent of today's additive Session model.
      try #sql("INSERT INTO sessions (id, gymID, title, notes, startedAt) VALUES (\(active), \(gym), 'Open workout', 'Keep this too', \(self.now))").execute(db)
      try #sql("INSERT INTO sessions (id, gymID, title, startedAt, finishedAt) VALUES (\(finished), \(gym), 'Finished workout', \(self.now.addingTimeInterval(-7200)), \(self.now.addingTimeInterval(-3600)))").execute(db)
      try SessionExercise.insert {
        SessionExercise.Draft(id: plan, sessionID: active, exerciseID: exercise, machineID: machine, position: 0, plannedSets: 3)
      }.execute(db)
      try #sql("INSERT INTO loggedSets (id, sessionID, exerciseID, machineID, weightKg, reps, completedAt) VALUES (\(set), \(active), \(exercise), \(machine), 100, 8, \(self.now))").execute(db)
      try BodyweightEntry.insert { BodyweightEntry.Draft(id: UUID(), weightKg: 80, measuredAt: self.now) }.execute(db)
      try DeviceHealthSample.insert { DeviceHealthSample.Draft(id: UUID(), kind: "fixture", value: 1) }.execute(db)
      try DeviceRestTimer.insert {
        DeviceRestTimer.Draft(id: UUID(), sessionID: active, alarmID: UUID(), pausedRemainingSeconds: 30, updatedAt: self.now)
      }.execute(db)
      if variant & 1 != 0 {
        try #sql("UPDATE exercises SET curatedName = 'Last curated name' WHERE id = \(exercise)").execute(db)
      }
      if variant & 2 != 0 {
        try #sql("UPDATE loggedSets SET sessionExerciseID = \(plan) WHERE id = \(set)").execute(db)
      }
    }
    if variant & 8 != 0 {
      var indexed = HardsetMigrations.migrator()
      indexed.eraseDatabaseOnSchemaChange = false
      try indexed.migrate(database, upTo: "v4_recordComparisons")
    }
    let tables = HardsetMigrations.syncedTableNames + HardsetMigrations.deviceLocalTableNames
      + HardsetMigrations.deferredSyncTableNames
    let before = try database.read { db in
      try tables.filter { try db.tableExists($0) }.map { table in (table, try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\" ORDER BY id")) }
    }
    var migrator = HardsetMigrations.migrator()
    if variant & 4 != 0 { migrator.eraseDatabaseOnSchemaChange = false }
    try migrator.migrate(database)
    try database.read { db in
      for (table, oldRows) in before {
        let first = try #require(oldRows.first)
        let columns = first.columnNames.map { "\"\($0)\"" }.joined(separator: ", ")
        let rows = try Row.fetchAll(db, sql: "SELECT \(columns) FROM \"\(table)\" ORDER BY id")
        #expect(rows == oldRows, "Historical data changed in \(table)")
      }
      let exerciseColumns = try db.columns(in: "exercises").map(\.name)
      let setColumns = try db.columns(in: "loggedSets").map(\.name)
      #expect(exerciseColumns.contains("curatedName"))
      #expect(setColumns.contains("sessionExerciseID"))
      let violations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      #expect(violations.isEmpty)
    }
    try database.close()
    let reopened = try DatabaseQueue(path: path, configuration: configuration)
    defer { try? reopened.close() }
    try migrator.migrate(reopened)
    let store = LoggerStore(database: reopened)
    #expect(try store.openSession()?.id.rawValue == active)
    #expect(try HistoryStore(database: reopened).recentSessions().map(\.title) == ["Finished workout"])
    let sets = try store.sets(in: SessionID(rawValue: active))
    #expect(sets.count == 1)
    let firstSet = try #require(sets.first)
    #expect(firstSet.machineID?.rawValue == machine)
    #expect(firstSet.sessionExerciseID == (variant & 2 != 0 ? plan : nil))
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    let recoveredExercise = try #require(recovered.exercises.first)
    let recoveredSet = try #require(recoveredExercise.slots.first)
    #expect(recovered.sessionID.rawValue == active)
    #expect(recovered.loggedSetCount == 1)
    #expect(recoveredExercise.slots.count == 3)
    #expect(recoveredSet.draft.weightKg == 100)
    #expect(recoveredSet.loggedMachineID?.rawValue == machine)
    #expect(recoveredExercise.machineIncrementKg == 5)
    // Upgrade cannot infer a historical plan-row identity. New writes can use
    // it immediately, while older unassigned sets keep the legacy recovery path.
    _ = try store.logSet(sessionID: SessionID(rawValue: active), exerciseID: ExerciseID(rawValue: exercise),
                         machineID: MachineID(rawValue: machine), sessionExerciseID: plan,
                         draft: SetEntryDraft(weightKg: 105, reps: 8), at: now.addingTimeInterval(60))
    let seeder = CatalogSeeder(database: reopened)
    try seeder.seed([catalog], now: now)
    try seeder.seed([catalog], now: now)
    let row = try #require(try reopened.read { db in
      try Exercise.where { $0.id.eq(exercise) }.fetchOne(db)
    })
    #expect(row.name == "My sled")
    #expect(row.notes == "Keep my notes")
    #expect(row.isArchived)
    #expect(row.curatedName == catalog.name)
  }

  @Test("Unknown catalogue-name provenance preserves the existing name")
  func unknownCuratedNamePreservesUserName() throws {
    let database = try migratedDatabase()
    let catalog = try #require(ExerciseCatalog.v1.first)
    let id = try #require(catalog.uuid)
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id, name: "My sled", isCurated: true) }.execute(db)
    }
    let seeder = CatalogSeeder(database: database)
    try seeder.seed([catalog])
    try seeder.seed([catalog])
    let name = try database.read { db in try Exercise.where { $0.id.eq(id) }.select(\.name).fetchOne(db) }
    #expect(name == "My sled")
  }

  @Test("A failed legacy repair rolls back added columns and preserves existing data")
  func failedRepairPreservesData() throws {
    let database = try DatabaseQueue()
    var original = DatabaseMigrator()
    original.registerMigration("v1") { db in try db.execute(sql: Self.historicalV1Schema) }
    try original.migrate(database)
    var indexed = HardsetMigrations.migrator()
    indexed.eraseDatabaseOnSchemaChange = false
    try indexed.migrate(database, upTo: "v4_recordComparisons")
    try database.write { db in
      try db.execute(sql: "INSERT INTO exercises (name) VALUES ('Keep my movement')")
      // This unsupported schema must fail without resetting unrelated tables.
      try db.execute(sql: "DROP TABLE loggedSets")
    }
    #expect(throws: (any Error).self) { try HardsetMigrations.migrator().migrate(database) }
    try database.read { db in
      let names = try String.fetchAll(db, sql: "SELECT name FROM exercises")
      let columns = try db.columns(in: "exercises").map(\.name)
      let migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
      #expect(names == ["Keep my movement"])
      #expect(!columns.contains("curatedName"))
      #expect(!migrations.contains("v5_legacyV1Columns"))
    }
  }

  @Test("Loading indexes upgrade existing databases without changing workout rows",
        arguments: ["v1", "v2_loadingIndexes", "v3_historyBenchmarks", "v4_recordComparisons",
                    "v5_legacyV1Columns"])
  func loadingIndexUpgrade(from baseline: String) throws {
    let queue = try DatabaseQueue()
    let migrator = HardsetMigrations.migrator()
    try migrator.migrate(queue, upTo: baseline)
    let id = UUID().uuidString.lowercased()
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO sessions (id, title) VALUES (?, ?)",
        arguments: [id, "Keep this workout"]
      )
    }
    try migrator.migrate(queue)
    // Reopening must not rerun CREATE INDEX or mutate data either.
    try migrator.migrate(queue)
    try queue.read { db in
      let title = try String.fetchOne(db, sql: "SELECT title FROM sessions WHERE id = ?", arguments: [id])
      #expect(title == "Keep this workout")
      let indexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
      for name in [
        "loggedSets_on_completedAt", "loggedSets_on_exerciseID_completedAt",
        "loggedSets_on_exerciseID_machineID_completedAt", "loggedSets_on_sessionID_setOrdinal",
        "sessionExercises_on_sessionID_position",
        "loggedSets_on_workingBenchmark",
        "loggedSets_on_workingReps",
        "sessions_on_openStartedAt",
      ] {
        #expect(indexes.contains(name), "Missing loading index: \(name)")
        let isUnique = try Bool.fetchOne(db, sql: "SELECT \"unique\" FROM pragma_index_list('loggedSets') WHERE name = ?", arguments: [name])
          ?? Bool.fetchOne(db, sql: "SELECT \"unique\" FROM pragma_index_list('sessionExercises') WHERE name = ?", arguments: [name])
          ?? Bool.fetchOne(db, sql: "SELECT \"unique\" FROM pragma_index_list('sessions') WHERE name = ?", arguments: [name])
        #expect(isUnique == false)
      }
    }
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
  // Frozen original v1 DDL from c1677fb; SQL comments/indentation removed.
  // Keep independent of current migrations so upgrade coverage cannot drift.
  private static let historicalV1Schema = """
    CREATE TABLE "exercises" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "catalogSlug" TEXT,
      "isCurated" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "modality" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
      "primaryMuscle" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
      "secondaryMusclesJSON" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '[]',
      "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
    ) STRICT;

    CREATE TABLE "gyms" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
    ) STRICT;

    CREATE TABLE "machines" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "gymID" TEXT NOT NULL REFERENCES "gyms"("id") ON DELETE CASCADE,
      "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "brand" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "loadType" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
      "stackIncrementKg" REAL,
      "isArchived" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
    ) STRICT;

    CREATE TABLE "machineExercises" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "machineID" TEXT NOT NULL REFERENCES "machines"("id") ON DELETE CASCADE,
      "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
      "createdAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
    ) STRICT;

    CREATE TABLE "sessions" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "gymID" TEXT REFERENCES "gyms"("id") ON DELETE SET NULL,
      "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "notes" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec')),
      "finishedAt" TEXT
    ) STRICT;

    CREATE TABLE "sessionExercises" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "sessionID" TEXT NOT NULL REFERENCES "sessions"("id") ON DELETE CASCADE,
      "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
      "machineID" TEXT REFERENCES "machines"("id") ON DELETE SET NULL,
      "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "plannedSets" INTEGER
    ) STRICT;

    CREATE TABLE "loggedSets" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "sessionID" TEXT NOT NULL REFERENCES "sessions"("id") ON DELETE CASCADE,
      "exerciseID" TEXT NOT NULL REFERENCES "exercises"("id") ON DELETE CASCADE,
      "machineID" TEXT REFERENCES "machines"("id") ON DELETE SET NULL,
      "setOrdinal" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "weightKg" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "reps" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "rpe" REAL,
      "isWarmup" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "completedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
    ) STRICT;

    CREATE TABLE "bodyweightEntries" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "weightKg" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "measuredAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec')),
      "enteredBy" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'manual'
    ) STRICT;

    CREATE TABLE "deviceHealthSamples" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "kind" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT 'unknown',
      "value" REAL NOT NULL ON CONFLICT REPLACE DEFAULT 0,
      "unit" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
      "startedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec')),
      "endedAt" TEXT
    ) STRICT;

    CREATE TABLE "deviceRestTimer" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "sessionID" TEXT,
      "alarmID" TEXT,
      "endsAt" TEXT,
      "pausedRemainingSeconds" REAL,
      "updatedAt" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT (datetime('now', 'subsec'))
    ) STRICT;

    CREATE INDEX "loggedSets_on_exerciseID_machineID"
      ON "loggedSets"("exerciseID", "machineID");

    CREATE INDEX "loggedSets_on_sessionID" ON "loggedSets"("sessionID");

    CREATE INDEX "sessions_on_startedAt" ON "sessions"("startedAt");
    """

}
