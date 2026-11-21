import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Hardset's own CSV is read back by the app that wrote it.
///
/// The deliverable is `roundTripIsRowForRow`: a populated database is exported, the file is
/// imported into a fresh one, and every table the CSV carries is compared row for row. The tests
/// around it pin what a second import does, what it never touches, and the exact limits.
@Suite("Hardset's own CSV is read back, row for row")
struct RestoreCSVTests {
  typealias Snapshot = [[String: DatabaseValue]]

  static let seedTime = Date(timeIntervalSince1970: 1_700_000_000)

  struct Fixture {
    let bench: UUID
    let press: UUID
    let fly: UUID
    let landmine: UUID
    let gymA: UUID
    let gymB: UUID
    let gymUnused: UUID
    let machineA: UUID
    let machineB: UUID
    let machineUnused: UUID
    let template: UUID
    let sessions: [UUID]
    let openSession: UUID
  }

  private func database() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    return database
  }

  /// A fresh install: migrated, with the catalogue seeded as launch does.
  private func freshInstall() throws -> DatabaseQueue {
    let db = try database()
    try CatalogSeeder(database: db).seed(now: Self.seedTime)
    return db
  }

  private func snapshot(_ db: DatabaseQueue, _ sql: String) async throws -> Snapshot {
    try await db.read { db in
      try Row.fetchAll(db, sql: sql).map { row in
        Dictionary(uniqueKeysWithValues: row.columnNames.map { ($0, row[$0] as DatabaseValue) })
      }
    }
  }

  private func count(_ db: DatabaseQueue, _ table: String) async throws -> Int {
    try await db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM \"\(table)\"") ?? -1 }
  }

  /// A lifter's database, built through the real stores where they exist and with explicit rows
  /// where the case needs exact control. It holds everything the CSV carries and, on purpose,
  /// several things it cannot: an open workout, an unused gym and machine, a plan row with no
  /// sets, a saved workout, body mass and a Health copy.
  private func populated() async throws -> (DatabaseQueue, Fixture) {
    let db = try freshInstall()
    let seeder = CatalogSeeder(database: db)
    let gyms = GymStore(database: db)
    let bench = try #require(ExerciseCatalog.v1[0].uuid)
    let press = try #require(ExerciseCatalog.v1[1].uuid)
    let fly = try seeder.createCustomExercise(
      named: "Cable Fly; \"chest\", finisher",
      attribution: try #require(CustomAttribution(
        primary: .chest, secondary: [.frontDelts, .triceps], modality: .cable)),
      now: Date(timeIntervalSince1970: 1_700_000_100.456)).id.rawValue
    let landmine = try seeder.createCustomExercise(
      named: "Old Landmine Press", now: Date(timeIntervalSince1970: 1_700_000_200)).id.rawValue
    let gymA = try gyms.createGym(name: "Iron, \"Works\"", now: Date(timeIntervalSince1970: 1_700_000_300.5)).rawValue
    let gymB = try gyms.createGym(name: "Garage", now: Date(timeIntervalSince1970: 1_700_000_400)).rawValue
    let gymUnused = try gyms.createGym(name: "Hotel", now: Date(timeIntervalSince1970: 1_700_000_500)).rawValue
    let machineA = try gyms.createMachine(
      at: GymID(rawValue: gymA), name: "Pec deck", brand: "Hammer, Strength", stackIncrementKg: 2.5,
      now: Date(timeIntervalSince1970: 1_700_000_600)).rawValue
    let machineB = try gyms.createMachine(
      at: GymID(rawValue: gymB), name: "Sled", now: Date(timeIntervalSince1970: 1_700_000_700)).rawValue
    let machineUnused = try gyms.createMachine(
      at: GymID(rawValue: gymA), name: "Unused rack", now: Date(timeIntervalSince1970: 1_700_000_800)).rawValue
    let template = UUID(), session1 = UUID(), session2 = UUID(), session3 = UUID(), open = UUID()
    let plan1 = UUID(), plan2 = UUID(), plan3 = UUID(), plan4 = UUID(), plan5 = UUID(), planEmpty = UUID()
    let t1 = 1_730_000_000.25, t2 = 1_730_100_000.0, t3 = 1_730_200_000.75, t4 = 1_730_300_000.0
    try await db.write { db in
      try db.execute(sql: "UPDATE exercises SET isArchived = 1, notes = ? WHERE id = ?",
        arguments: ["Retired: shoulder, \"ouch\"", landmine.uuidString.lowercased()])
      try db.execute(sql: "UPDATE gyms SET isArchived = 1 WHERE id = ?", arguments: [gymB.uuidString.lowercased()])
      try db.execute(sql: "UPDATE machines SET isArchived = 1, loadType = 'plateLoaded' WHERE id = ?",
        arguments: [machineB.uuidString.lowercased()])

      try Session.insert {
        Session.Draft(id: session1, gymID: gymA, title: "Push, heavy",
          notes: "Felt fine\nsecond line; \"quoted\" é ✓", startedAt: Date(timeIntervalSince1970: t1),
          finishedAt: Date(timeIntervalSince1970: t1 + 3722.5), templateID: template)
      }.execute(db)
      try Session.insert {
        Session.Draft(id: session2, title: "", startedAt: Date(timeIntervalSince1970: t2),
          finishedAt: Date(timeIntervalSince1970: t2 + 1800))
      }.execute(db)
      try Session.insert {
        Session.Draft(id: session3, gymID: gymB, title: "Garage", startedAt: Date(timeIntervalSince1970: t3),
          finishedAt: Date(timeIntervalSince1970: t3 + 2400))
      }.execute(db)
      try Session.insert {
        Session.Draft(id: open, gymID: gymA, title: "Still going", startedAt: Date(timeIntervalSince1970: t4))
      }.execute(db)

      func plan(_ id: UUID, _ session: UUID, _ exercise: UUID, _ machine: UUID?, _ position: Int,
        planned: Int? = nil, range: ClosedRange<Int>? = nil) throws {
        try SessionExercise.insert {
          SessionExercise.Draft(id: id, sessionID: session, exerciseID: exercise, machineID: machine,
            position: position, plannedSets: planned, repRangeLower: range?.lowerBound,
            repRangeUpper: range?.upperBound)
        }.execute(db)
      }
      try plan(plan1, session1, bench, nil, 0, planned: 3, range: 6...10)
      try plan(plan2, session1, fly, machineA, 1, planned: 2)
      try plan(planEmpty, session1, press, nil, 2, planned: 3)
      try plan(plan3, session2, press, nil, 0)
      try plan(plan4, session3, fly, machineA, 0)
      try plan(plan5, session3, press, machineB, 1)

      func set(_ session: UUID, _ exercise: UUID, _ machine: UUID?, _ plan: UUID?, ordinal: Int,
        kg: Double, reps: Int, rpe: Double? = nil, warmup: Bool = false, at seconds: Double) throws {
        try LoggedSet.insert {
          LoggedSet.Draft(id: UUID(), sessionID: session, exerciseID: exercise, machineID: machine,
            sessionExerciseID: plan, setOrdinal: ordinal, weightKg: kg, reps: reps, rpe: rpe,
            isWarmup: warmup, completedAt: Date(timeIntervalSince1970: seconds))
        }.execute(db)
      }
      // A load that does not print cleanly, to prove nothing is rounded on the way out and back.
      try set(session1, bench, nil, plan1, ordinal: 0, kg: 0.1 + 0.2, reps: 12, warmup: true, at: t1 + 60.125)
      try set(session1, bench, nil, plan1, ordinal: 1, kg: 100, reps: 8, rpe: 8.5, at: t1 + 300)
      try set(session1, bench, nil, plan1, ordinal: 2, kg: 102.5, reps: 6, rpe: 9, at: t1 + 600.5)
      try set(session1, fly, machineA, plan2, ordinal: 0, kg: 32.5, reps: 15, at: t1 + 900)
      // Logged with no plan row and no machine.
      try set(session2, press, nil, nil, ordinal: 0, kg: 60, reps: 10, at: t2 + 120)
      try set(session2, press, nil, plan3, ordinal: 1, kg: 62.5, reps: 9, at: t2 + 240)
      // A machine from another gym than the workout's, and a machine of the workout's own gym.
      try set(session3, fly, machineA, plan4, ordinal: 0, kg: 27.5, reps: 12, at: t3 + 100)
      try set(session3, press, machineB, plan5, ordinal: 0, kg: 45, reps: 10, at: t3 + 400)
      try set(session3, landmine, nil, nil, ordinal: 0, kg: 20, reps: 10, at: t3 + 900)
      try set(open, bench, nil, nil, ordinal: 0, kg: 90, reps: 5, at: t4 + 60)

      // Things the CSV does not carry.
      try StoredTemplate.insert {
        StoredTemplate.Draft(id: template, name: "Push", position: 0, createdAt: Date(timeIntervalSince1970: t1 - 100))
      }.execute(db)
      try StoredTemplateExercise.insert {
        StoredTemplateExercise.Draft(id: UUID(), templateID: template, exerciseID: bench, position: 0,
          plannedSets: 3, repRangeLower: 6, repRangeUpper: 10, restSeconds: 120,
          createdAt: Date(timeIntervalSince1970: t1 - 100))
      }.execute(db)
      try BodyweightEntry.insert {
        BodyweightEntry.Draft(id: UUID(), weightKg: 82.4, measuredAt: Date(timeIntervalSince1970: t1))
      }.execute(db)
      try DeviceHealthSample.insert {
        DeviceHealthSample.Draft(id: UUID(), kind: "bodyMass", value: 82.4, unit: "kg",
          startedAt: Date(timeIntervalSince1970: t1))
      }.execute(db)
    }
    return (db, Fixture(
      bench: bench, press: press, fly: fly, landmine: landmine, gymA: gymA, gymB: gymB,
      gymUnused: gymUnused, machineA: machineA, machineB: machineB, machineUnused: machineUnused,
      template: template, sessions: [session1, session2, session3], openSession: open))
  }

  private func exportCSV(_ db: DatabaseQueue) async throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try await DataTransferStore(database: db).export(.csv, directory: folder)
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func restore(_ text: String, into db: DatabaseQueue) async throws -> WorkoutImportResult {
    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    return try await DataTransferStore(database: db).commit(preview)
  }

  /// What the CSV carries of each table, as a query over the source database: only finished
  /// workouts that have sets, and only the movements, machines, gyms and plan rows those sets name.
  private static let finishedWithSets = """
    (SELECT DISTINCT s.id FROM sessions s JOIN loggedSets l ON l.sessionID = s.id WHERE s.finishedAt IS NOT NULL)
    """
  private static let carried: [(table: String, sql: String)] = [
    ("exercises", "SELECT * FROM exercises ORDER BY id"),
    ("gyms", """
      SELECT * FROM gyms WHERE id IN (
        SELECT gymID FROM sessions WHERE id IN \(finishedWithSets)
        UNION SELECT gymID FROM machines WHERE id IN
          (SELECT machineID FROM loggedSets WHERE sessionID IN \(finishedWithSets))) ORDER BY id
      """),
    ("machines", """
      SELECT * FROM machines WHERE id IN
        (SELECT machineID FROM loggedSets WHERE sessionID IN \(finishedWithSets)) ORDER BY id
      """),
    ("sessions", "SELECT * FROM sessions WHERE id IN \(finishedWithSets) ORDER BY id"),
    ("sessionExercises", """
      SELECT * FROM sessionExercises WHERE id IN
        (SELECT sessionExerciseID FROM loggedSets WHERE sessionID IN \(finishedWithSets)) ORDER BY id
      """),
    ("loggedSets", "SELECT * FROM loggedSets WHERE sessionID IN \(finishedWithSets) ORDER BY id"),
  ]

  // MARK: - The round trip

  @Test("Export, then import into a fresh install: every carried table matches row for row")
  func roundTripIsRowForRow() async throws {
    let (source, fixture) = try await populated()
    let destination = try freshInstall()
    let text = try await exportCSV(source)

    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    let restore = try #require(preview.restore)
    #expect(restore.layout == .csv)
    #expect(restore.unfinishedWorkouts == 1)
    #expect(preview.sessions.count == 3)
    #expect(preview.setCount == 9)

    let result = try await DataTransferStore(database: destination).commit(preview)
    #expect(result.importedWorkouts == 3)
    #expect(result.importedSets == 9)
    #expect(result.skippedWorkouts == 0)
    #expect(result.leftOutUnfinishedWorkouts == 1)

    for (table, sql) in Self.carried {
      let expected = try await snapshot(source, sql)
      // The whole destination table, so a row restored that should not have been fails too.
      let actual = try await snapshot(destination, "SELECT * FROM \(table) ORDER BY id")
      #expect(!expected.isEmpty, "\(table): the fixture should carry rows")
      #expect(actual == expected, "\(table) differs after the round trip")
    }

    // Each of those rows is the same row, not merely a similar one.
    let loads = try await snapshot(destination, "SELECT weightKg, reps, isWarmup, rpe FROM loggedSets ORDER BY completedAt")
    #expect(loads.first?["weightKg"] == (0.1 + 0.2).databaseValue)
    #expect(loads.first?["isWarmup"] == Int64(1).databaseValue)
    #expect(loads.dropFirst().first?["rpe"] == (8.5).databaseValue)
    let ids = try await snapshot(destination, "SELECT id FROM sessions ORDER BY id")
    #expect(ids == fixture.sessions.sorted { $0.uuidString < $1.uuidString }
      .map { ["id": $0.uuidString.lowercased().databaseValue] })
  }

  @Test("What the CSV cannot carry stays out, and is exactly this list")
  func limitsAreExactlyTheDocumentedOnes() async throws {
    let (source, fixture) = try await populated()
    let destination = try freshInstall()
    _ = try await restore(try await exportCSV(source), into: destination)

    // Never carried: saved workouts, body mass, Health copies.
    for table in ["workoutTemplates", "templateExercises", "bodyweightEntries", "deviceHealthSamples"] {
      #expect(try await count(destination, table) == 0, "\(table)")
    }
    // The workout still remembers which saved workout started it, as plain text.
    let remembered = try await snapshot(destination, "SELECT templateID FROM sessions WHERE templateID IS NOT NULL")
    #expect(remembered == [["templateID": fixture.template.uuidString.lowercased().databaseValue]])
    // Not carried: a workout that was still open, a gym and a machine no set used, a plan row with no sets.
    #expect(try await count(destination, "sessions") == 3)
    let absent = try await snapshot(destination, """
      SELECT id FROM gyms WHERE id = '\(fixture.gymUnused.uuidString.lowercased())'
      UNION ALL SELECT id FROM machines WHERE id = '\(fixture.machineUnused.uuidString.lowercased())'
      UNION ALL SELECT id FROM sessions WHERE id = '\(fixture.openSession.uuidString.lowercased())'
      """)
    #expect(absent.isEmpty)
    #expect(try await count(destination, "sessionExercises") == 5)
    #expect(try await LoggerStore(database: destination).openSession() == nil)
  }

  // MARK: - A second import, and a populated phone

  @Test("Importing the same file again adds nothing and says so")
  func secondImportAddsNothing() async throws {
    let (source, _) = try await populated()
    let destination = try freshInstall()
    let text = try await exportCSV(source)
    _ = try await restore(text, into: destination)
    let before = try await ["sessions", "loggedSets", "sessionExercises", "exercises", "gyms", "machines", "deviceImportBatches"]
      .asyncMap { try await count(destination, $0) }

    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    let store = DataTransferStore(database: destination)
    #expect(try await store.alreadyImportedWorkoutCount(in: preview) == 3)
    let again = try await store.commit(preview)
    #expect(again.importedWorkouts == 0)
    #expect(again.importedSets == 0)
    #expect(again.skippedWorkouts == 3)

    let after = try await ["sessions", "loggedSets", "sessionExercises", "exercises", "gyms", "machines", "deviceImportBatches"]
      .asyncMap { try await count(destination, $0) }
    #expect(after == before)
  }

  @Test("Restoring into the phone it came from changes nothing")
  func restoringIntoTheSourceChangesNothing() async throws {
    let (source, _) = try await populated()
    let tables = ["exercises", "gyms", "machines", "sessions", "sessionExercises", "loggedSets",
      "workoutTemplates", "templateExercises", "bodyweightEntries", "machineExercises"]
    var before: [Snapshot] = []
    for table in tables { before.append(try await snapshot(source, "SELECT * FROM \(table) ORDER BY id")) }
    let result = try await restore(try await exportCSV(source), into: source)
    #expect(result.importedSets == 0)
    #expect(result.skippedWorkouts == 3)
    for (index, table) in tables.enumerated() {
      #expect(try await snapshot(source, "SELECT * FROM \(table) ORDER BY id") == before[index], "\(table)")
    }
  }

  @Test("A workout already here is never changed, and a set deleted since is not brought back")
  func existingWorkoutIsLeftAlone() async throws {
    let (source, fixture) = try await populated()
    let text = try await exportCSV(source)
    let destination = try freshInstall()
    _ = try await restore(text, into: destination)
    let first = fixture.sessions[0].uuidString.lowercased()
    // The lifter corrects a workout after the export: renames it and deletes a mistyped set.
    try await destination.write { db in
      try db.execute(sql: "UPDATE sessions SET title = 'Corrected' WHERE id = ?", arguments: [first])
      try db.execute(sql: "DELETE FROM loggedSets WHERE id = (SELECT id FROM loggedSets WHERE sessionID = ? ORDER BY completedAt LIMIT 1)",
        arguments: [first])
    }
    let sets = try await count(destination, "loggedSets")
    let result = try await restore(text, into: destination)
    #expect(result.importedSets == 0)
    #expect(try await count(destination, "loggedSets") == sets)
    #expect(try await snapshot(destination, "SELECT title FROM sessions WHERE id = '\(first)'") == [["title": "Corrected".databaseValue]])
  }

  @Test("Workouts missing from a phone are added beside the ones it has")
  func partialOverlapAddsOnlyTheMissing() async throws {
    let (source, fixture) = try await populated()
    let text = try await exportCSV(source)
    let destination = try freshInstall()
    _ = try await restore(text, into: destination)
    // The phone lost its third workout (deleted in History), and has a new one of its own.
    let third = fixture.sessions[2].uuidString.lowercased()
    try await destination.write { db in
      try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [third])
      try Session.insert {
        Session.Draft(id: UUID(), title: "Mine", startedAt: Date(timeIntervalSince1970: 1_731_000_000),
          finishedAt: Date(timeIntervalSince1970: 1_731_003_600))
      }.execute(db)
    }
    let result = try await restore(text, into: destination)
    #expect(result.importedWorkouts == 1)
    #expect(result.importedSets == 3)
    #expect(result.skippedWorkouts == 2)
    #expect(try await count(destination, "sessions") == 4)
    #expect(try await snapshot(destination, "SELECT * FROM sessions WHERE id = '\(third)'")
      == (try await snapshot(source, "SELECT * FROM sessions WHERE id = '\(third)'")))
  }

  @Test("A restore is one import: it can be undone, and undo removes only the workouts it added")
  func undoRemovesTheRestoredWorkouts() async throws {
    let (source, _) = try await populated()
    let destination = try freshInstall()
    try await destination.write { db in
      try Session.insert {
        Session.Draft(id: UUID(), title: "Mine", startedAt: Date(timeIntervalSince1970: 1_731_000_000),
          finishedAt: Date(timeIntervalSince1970: 1_731_003_600))
      }.execute(db)
    }
    _ = try await restore(try await exportCSV(source), into: destination)
    let store = DataTransferStore(database: destination)
    let undo = try #require(try await store.lastImportUndo())
    #expect(undo.sessionCount == 3)
    #expect(undo.setCount == 9)
    try await store.undoLastImport(undo)
    #expect(try await count(destination, "sessions") == 1)
    #expect(try await count(destination, "loggedSets") == 0)
    #expect(try await store.lastImportUndo() == nil)
  }

  @Test("A failure part-way rolls the whole restore back, and a retry succeeds")
  func failedRestoreWritesNothing() async throws {
    let (source, _) = try await populated()
    let destination = try freshInstall()
    let text = try await exportCSV(source)
    let seeded = try await ["exercises", "gyms", "machines"].asyncMap { try await count(destination, $0) }
    try await destination.write { db in
      try db.execute(sql: "CREATE TRIGGER failRestore BEFORE INSERT ON loggedSets WHEN NEW.reps = 6 BEGIN SELECT RAISE(ABORT, 'full'); END")
    }
    await #expect(throws: (any Error).self) { try await restore(text, into: destination) }
    let after = try await ["sessions", "loggedSets", "sessionExercises", "deviceImportBatches"]
      .asyncMap { try await count(destination, $0) }
    #expect(after == [0, 0, 0, 0])
    #expect(try await ["exercises", "gyms", "machines"].asyncMap { try await count(destination, $0) } == seeded)
    try await destination.write { try $0.execute(sql: "DROP TRIGGER failRestore") }
    #expect(try await restore(text, into: destination).importedSets == 9)
  }

  @Test("Restored Strong history is still recognised when the Strong file is imported later")
  func restoredImportedHistoryStillDeduplicates() async throws {
    let strong = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n2026-11-01 10:00:00,Push,1h 2m,Press,1,100,8,8,Keep this\n2026-11-01 10:00:00,Push,1h 2m,Press,2,100,7,,\n"
    let source = try freshInstall()
    _ = try await DataTransferStore(database: source).commit(
      WorkoutCSVImport.preview(strong, strongUnit: .kilograms, timeZone: TimeZone(secondsFromGMT: 0)!))
    let destination = try freshInstall()
    let restored = try await restore(try await exportCSV(source), into: destination)
    #expect(restored.importedSets == 2)

    let later = try await DataTransferStore(database: destination).commit(
      WorkoutCSVImport.preview(strong, strongUnit: .kilograms, timeZone: TimeZone(secondsFromGMT: 0)!))
    #expect(later.importedWorkouts == 0)
    #expect(later.skippedWorkouts == 1)
    #expect(try await count(destination, "loggedSets") == 2)
    #expect(try await count(destination, "exercises") == (try await count(source, "exercises")))
  }

  @Test("A plan row's machine that no set used is dropped rather than failing the restore")
  func planMachineNoSetUsedIsDropped() async throws {
    let source = try freshInstall()
    let gyms = GymStore(database: source)
    let gym = try gyms.createGym(name: "Gym", now: Self.seedTime)
    let used = try gyms.createMachine(at: gym, name: "Used", now: Self.seedTime).rawValue
    let moved = try gyms.createMachine(at: gym, name: "Moved to", now: Self.seedTime).rawValue
    let bench = try #require(ExerciseCatalog.v1[0].uuid)
    let session = UUID(), plan = UUID()
    try await source.write { db in
      try Session.insert {
        Session.Draft(id: session, gymID: gym.rawValue, startedAt: Date(timeIntervalSince1970: 1_730_000_000),
          finishedAt: Date(timeIntervalSince1970: 1_730_003_600))
      }.execute(db)
      // The block moved to another machine after its first set, and no set was logged on it.
      try SessionExercise.insert {
        SessionExercise.Draft(id: plan, sessionID: session, exerciseID: bench, machineID: moved, position: 0)
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: session, exerciseID: bench, machineID: used,
          sessionExerciseID: plan, weightKg: 50, reps: 10, completedAt: Date(timeIntervalSince1970: 1_730_000_100))
      }.execute(db)
    }
    let destination = try freshInstall()
    let result = try await restore(try await exportCSV(source), into: destination)
    #expect(result.importedSets == 1)
    let stored = try await snapshot(destination, "SELECT machineID FROM sessionExercises")
    #expect(stored == [["machineID": DatabaseValue.null]])
    #expect(try await snapshot(destination, "SELECT machineID FROM loggedSets") == [["machineID": used.uuidString.lowercased().databaseValue]])
  }

  // MARK: - An earlier build's export

  /// The header and the shape of a row exactly as the first export wrote them: 19 columns, no gym
  /// or machine identity beyond names, a plan row id with no plan row described.
  private static let earlierHeader = "id,sessionID,exerciseID,machineID,sessionExerciseID,setOrdinal,weightKg,reps,rpe,isWarmup,completedAt,exerciseName,workoutTitle,workoutStart,workoutEnd,workoutNotes,machineName,machineBrand,gymName"

  @Test("An export from before this change still restores, as far as it can")
  func earlierExportStillRestores() async throws {
    let bench = try #require(ExerciseCatalog.v1[0].uuid).uuidString.lowercased()
    let custom = UUID().uuidString.lowercased(), machine = UUID().uuidString.lowercased()
    let session = UUID().uuidString.lowercased(), plan = UUID().uuidString.lowercased()
    let set1 = UUID().uuidString.lowercased(), set2 = UUID().uuidString.lowercased(), set3 = UUID().uuidString.lowercased()
    let start = "2026-10-01 09:00:00.000", end = "2026-10-01 10:00:00.000"
    let text = [
      Self.earlierHeader,
      "\(set1),\(session),\(bench),,\(plan),0,100.0,8,,0,2026-10-01 09:05:00.000,Bench Press,Push,\(start),\(end),,,,Home",
      "\(set2),\(session),\(custom),\(machine),,0,32.5,12,8.5,0,2026-10-01 09:20:00.000,\"Cable fly, low\",Push,\(start),\(end),,Pec deck,Hammer,Home",
      "\(set3),\(session),\(custom),\(machine),,1,32.5,10,,1,2026-10-01 09:25:00.000,\"Cable fly, low\",Push,\(start),\(end),,Pec deck,Hammer,Home",
    ].joined(separator: "\r\n") + "\r\n"

    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    #expect(try #require(preview.restore).layout == .earlierCSV)

    // A phone that already has a gym called Home must not get a second one.
    let destination = try freshInstall()
    let home = try GymStore(database: destination).createGym(name: "Home", now: Self.seedTime).rawValue
    let curatedBefore = try await snapshot(destination, "SELECT * FROM exercises WHERE id = '\(bench)'")
    let result = try await DataTransferStore(database: destination).commit(preview)
    #expect(result.importedWorkouts == 1)
    #expect(result.importedSets == 3)

    #expect(try await count(destination, "gyms") == 1)
    let sets = try await snapshot(destination, "SELECT id, weightKg, reps, rpe, isWarmup, machineID, sessionExerciseID FROM loggedSets ORDER BY setOrdinal, id")
    #expect(sets.count == 3)
    #expect(Set(sets.compactMap { $0["id"] }) == Set([set1, set2, set3].map { $0.databaseValue }))
    let fly = try await snapshot(destination, "SELECT name, primaryMuscle, modality, isCurated, createdAt FROM exercises WHERE id = '\(custom)'")
    #expect(fly == [[
      "name": "Cable fly, low".databaseValue, "primaryMuscle": "unknown".databaseValue,
      "modality": "unknown".databaseValue, "isCurated": Int64(0).databaseValue, "createdAt": start.databaseValue,
    ]])
    let placed = try await snapshot(destination, "SELECT m.name AS name, m.gymID AS gymID FROM machines m WHERE id = '\(machine)'")
    #expect(placed == [["name": "Pec deck".databaseValue, "gymID": home.uuidString.lowercased().databaseValue]])
    let blocks = try await snapshot(destination, "SELECT id, position FROM sessionExercises")
    #expect(blocks == [["id": plan.databaseValue, "position": Int64(0).databaseValue]])
    // The curated movement was already here and is untouched.
    #expect(try await snapshot(destination, "SELECT * FROM exercises WHERE id = '\(bench)'") == curatedBefore)
    // And a second import of the same earlier file adds nothing, with no second gym.
    #expect(try await DataTransferStore(database: destination).commit(preview).importedSets == 0)
    #expect(try await count(destination, "gyms") == 1)
  }

  @Test("An earlier export that uses one movement and machine across workouts reads, dated by the first")
  func earlierExportAcrossWorkouts() async throws {
    let custom = UUID().uuidString.lowercased(), machine = UUID().uuidString.lowercased()
    func row(_ day: Int) -> String {
      "\(UUID().uuidString.lowercased()),\(UUID().uuidString.lowercased()),\(custom),\(machine),,0,32.5,12,,0,2026-10-0\(day) 09:20:00.000,Cable fly,Push,2026-10-0\(day) 09:00:00.000,2026-10-0\(day) 10:00:00.000,,Pec deck,Hammer,Home"
    }
    let text = [Self.earlierHeader, row(3), row(1), row(2)].joined(separator: "\r\n") + "\r\n"
    let destination = try freshInstall()
    let result = try await restore(text, into: destination)
    #expect(result.importedWorkouts == 3)
    let made = try await snapshot(destination, "SELECT createdAt FROM exercises WHERE id = '\(custom)' UNION ALL SELECT createdAt FROM machines WHERE id = '\(machine)'")
    // File order, not calendar order: the first row names the third of October.
    #expect(made == [["createdAt": "2026-10-03 09:00:00.000".databaseValue], ["createdAt": "2026-10-03 09:00:00.000".databaseValue]])
    #expect(try await count(destination, "gyms") == 1)
  }

  @Test("An earlier export names a gym the phone does not have: it is created once")
  func earlierExportCreatesAMissingGymOnce() async throws {
    let bench = try #require(ExerciseCatalog.v1[0].uuid).uuidString.lowercased()
    func row(_ session: UUID, _ gym: String, _ day: Int) -> String {
      "\(UUID().uuidString.lowercased()),\(session.uuidString.lowercased()),\(bench),,,0,100.0,8,,0,2026-10-0\(day) 09:05:00.000,Bench Press,Push,2026-10-0\(day) 09:00:00.000,2026-10-0\(day) 10:00:00.000,,,,\(gym)"
    }
    let text = ([Self.earlierHeader, row(UUID(), "Garage", 1), row(UUID(), "Garage", 2), row(UUID(), "", 3)]
      .joined(separator: "\r\n")) + "\r\n"
    let destination = try freshInstall()
    let result = try await restore(text, into: destination)
    #expect(result.importedWorkouts == 3)
    let gyms = try await snapshot(destination, "SELECT name FROM gyms")
    #expect(gyms == [["name": "Garage".databaseValue]])
    let placed = try await snapshot(destination, "SELECT count(*) AS n FROM sessions WHERE gymID IS NULL")
    #expect(placed == [["n": Int64(1).databaseValue]])
  }

  // MARK: - Damaged and foreign files

  private func mutate(_ text: String, column: String, row: Int = 1, to value: String) throws -> String {
    var rows = try CSVDocument.decode(text)
    let index = try #require(rows[0].firstIndex(of: column))
    rows[row][index] = value
    return CSVDocument.encode(rows)
  }

  @Test("A file that has been damaged is refused before anything is written",
    arguments: [
      ("id", "not-a-uuid"), ("completedAt", "01/11/2026"), ("completedAt", "2026-02-30 10:00:00.000"),
      ("weightKg", "-5"), ("weightKg", "heavy"), ("reps", "-1"), ("rpe", "11"), ("isWarmup", "maybe"),
      ("workoutEnd", "2000-01-01 00:00:00.000"), ("exerciseSecondaryMuscles", "{not json"),
      ("machineStackIncrementKg", "0"),
    ])
  func damagedFilesAreRefused(column: String, value: String) async throws {
    let (source, _) = try await populated()
    let text = try await exportCSV(source)
    // Row 1 is a set on the plain bench; use a machine row for the machine column.
    let row = column.hasPrefix("machine") ? 4 : 1
    #expect(throws: WorkoutImportError.self) {
      try WorkoutCSVImport.preview(try mutate(text, column: column, row: row, to: value), strongUnit: .kilograms)
    }
  }

  @Test("A movement described two ways, or a short row, is refused with its line")
  func inconsistentFilesAreRefused() async throws {
    let (source, _) = try await populated()
    let text = try await exportCSV(source)
    let renamed = try mutate(text, column: "exerciseName", row: 2, to: "Not the bench")
    #expect(throws: WorkoutImportError.self) { try WorkoutCSVImport.preview(renamed, strongUnit: .kilograms) }
    var rows = try CSVDocument.decode(text)
    rows[3].removeLast()
    #expect(throws: WorkoutImportError.row(4, "Column count differs from the header")) {
      try WorkoutCSVImport.preview(CSVDocument.encode(rows), strongUnit: .kilograms)
    }
  }

  @Test("A Strong or Hevy file never takes the restore path")
  func foreignFilesStillConvert() throws {
    let strong = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n2026-11-01 10:00:00,Push,1h 2m,Press,1,100,8,8,Keep this\n"
    #expect(try WorkoutCSVImport.preview(strong, strongUnit: .kilograms).restore == nil)
    let hevy = "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps\nPush,\"1 Nov 2026, 10:00\",\"1 Nov 2026, 11:00\",Press,0,normal,20,10\n"
    #expect(try WorkoutCSVImport.preview(hevy, strongUnit: .kilograms).restore == nil)
  }

  // MARK: - The format itself

  @Test("The first 19 columns are the original export, unchanged and in order")
  func originalColumnsAreUnchanged() {
    #expect(RestoreCSV.columns.prefix(RestoreCSV.originalColumnCount).map(\.name) == Self.earlierHeader.split(separator: ",").map(String.init))
  }

  @Test("Every column of every table the CSV restores is carried, and nothing in the header is unused")
  func nothingIsSilentlyLeftOut() async throws {
    let db = try database()
    let tableColumns = try await db.read { db in
      Dictionary(uniqueKeysWithValues: try Set(RestoreCSV.entities.map(\.table)).map { table in
        (table, Set(try db.columns(in: table).map(\.name)))
      })
    }
    for table in Set(RestoreCSV.entities.map(\.table)) {
      let carried = Set(RestoreCSV.entities.filter { $0.table == table }.flatMap { $0.fields.map(\.column) })
      #expect(carried == tableColumns[table], "\(table): the CSV must carry exactly the table's columns")
    }
    let named = Set(RestoreCSV.columns.map(\.name))
    let referenced = Set(RestoreCSV.entities.flatMap { $0.fields.map(\.header) })
    #expect(referenced == named, "every header is read, and every header read is written")
    #expect(named.count == RestoreCSV.columns.count)
  }

  @Test("The restore schema lists every column of every table it restores, and every non-device table")
  func restoreSchemaMatchesTheDatabase() async throws {
    let db = try database()
    for table in RestoreSchema.tables {
      let actual = try await db.read { try $0.columns(in: table.name).map(\.name) }
      #expect(Set(table.columns.map(\.name)) == Set(actual), "\(table.name)")
    }
    let restorable = Set(RestoreSchema.tables.map(\.name))
    let notDevice = Set(HardsetMigrations.syncedTableNames + HardsetMigrations.deferredSyncTableNames)
    #expect(restorable == notDevice, "a table added to the database must be restored or deliberately left out")
  }
}

extension Sequence {
  fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var results: [T] = []
    for element in self { results.append(try await transform(element)) }
    return results
  }
}
