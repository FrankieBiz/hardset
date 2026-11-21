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
  typealias Snapshot = RestoreFixture.Snapshot
  typealias Fixture = RestoreFixture.Fixture
  static let seedTime = RestoreFixture.seedTime

  private func database() throws -> DatabaseQueue { try RestoreFixture.database() }
  private func freshInstall() throws -> DatabaseQueue { try RestoreFixture.freshInstall() }
  private func snapshot(_ db: DatabaseQueue, _ sql: String) async throws -> Snapshot {
    try await RestoreFixture.snapshot(db, sql)
  }
  private func count(_ db: DatabaseQueue, _ table: String) async throws -> Int {
    try await RestoreFixture.count(db, table)
  }
  private func populated() async throws -> (DatabaseQueue, Fixture) { try await RestoreFixture.populated() }
  private func exportCSV(_ db: DatabaseQueue) async throws -> String { try await RestoreFixture.exportCSV(db) }
  private func restore(_ text: String, into db: DatabaseQueue) async throws -> WorkoutImportResult {
    try await RestoreFixture.restore(text, into: db)
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

  @Test("An earlier export where a block moved machine mid-way reads, with the block on its latest machine")
  func earlierExportWithAMachineChange() async throws {
    let bench = try #require(ExerciseCatalog.v1[0].uuid).uuidString.lowercased()
    let first = UUID().uuidString.lowercased(), second = UUID().uuidString.lowercased()
    let session = UUID().uuidString.lowercased(), plan = UUID().uuidString.lowercased()
    let start = "2026-10-01 09:00:00.000", end = "2026-10-01 10:00:00.000"
    func row(_ machine: String, _ name: String, _ ordinal: Int, _ minute: Int) -> String {
      "\(UUID().uuidString.lowercased()),\(session),\(bench),\(machine),\(plan),\(ordinal),50.0,10,,0,2026-10-01 09:\(10 + minute):00.000,Bench Press,Push,\(start),\(end),,\(name),,Home"
    }
    let text = [Self.earlierHeader, row(first, "Press A", 0, 0), row(second, "Press B", 1, 5)]
      .joined(separator: "\r\n") + "\r\n"
    let destination = try freshInstall()
    let result = try await restore(text, into: destination)
    #expect(result.importedSets == 2)
    #expect(try await snapshot(destination, "SELECT machineID FROM sessionExercises") == [["machineID": second.databaseValue]])
    let sets = try await snapshot(destination, "SELECT machineID FROM loggedSets ORDER BY setOrdinal")
    #expect(sets == [["machineID": first.databaseValue], ["machineID": second.databaseValue]])
  }

  @Test("A file row whose id collides with a different row aborts the restore and replaces nothing")
  func collidingIDsAreNeverReplaced() async throws {
    let (source, fixture) = try await populated()
    let text = try await exportCSV(source)
    let destination = try freshInstall()
    // A set of the destination's own, in a workout the file does not have, with an id the file uses.
    let collidingID = try #require(try await snapshot(source, "SELECT id FROM loggedSets WHERE sessionID = '\(fixture.sessions[0].uuidString.lowercased())' ORDER BY id LIMIT 1").first?["id"])
    let mine = UUID()
    let bench = try #require(ExerciseCatalog.v1[0].uuid)
    try await destination.write { db in
      try Session.insert {
        Session.Draft(id: mine, title: "Mine", startedAt: Date(timeIntervalSince1970: 1_731_000_000),
          finishedAt: Date(timeIntervalSince1970: 1_731_003_600))
      }.execute(db)
      try db.execute(sql: "INSERT INTO loggedSets(id, sessionID, exerciseID, weightKg, reps) VALUES (?, ?, ?, 77, 7)",
        arguments: [collidingID, mine.uuidString.lowercased(), bench.uuidString.lowercased()])
    }
    let before = try await snapshot(destination, "SELECT * FROM loggedSets")
    await #expect(throws: WorkoutImportError.self) { try await restore(text, into: destination) }
    // The destination's set is exactly as it was, and nothing from the file was kept.
    #expect(try await snapshot(destination, "SELECT * FROM loggedSets") == before)
    #expect(try await count(destination, "sessions") == 1)
    #expect(try await count(destination, "deviceImportBatches") == 0)
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
