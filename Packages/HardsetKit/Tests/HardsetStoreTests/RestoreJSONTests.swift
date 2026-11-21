import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Hardset's own JSON is read back by the app that wrote it, through the same engine and the same
/// rules as the CSV, and carries what the CSV cannot: saved workouts, body mass, and every gym,
/// machine and movement.
@Suite("Hardset's own JSON is read back, row for row")
struct RestoreJSONTests {
  typealias Snapshot = RestoreFixture.Snapshot

  private func snapshot(_ db: DatabaseQueue, _ sql: String) async throws -> Snapshot {
    try await RestoreFixture.snapshot(db, sql)
  }

  private func restore(_ text: String, into db: DatabaseQueue) async throws -> WorkoutImportResult {
    try await RestoreFixture.restore(text, into: db)
  }

  /// Every table the JSON restores, and what the source holds of it: finished workouts and their
  /// plan rows and sets, and every row of everything else.
  private static let carried: [(table: String, sql: String)] = [
    ("exercises", "SELECT * FROM exercises ORDER BY id"),
    ("gyms", "SELECT * FROM gyms ORDER BY id"),
    ("machines", "SELECT * FROM machines ORDER BY id"),
    ("machineExercises", "SELECT * FROM machineExercises ORDER BY id"),
    ("workoutTemplates", "SELECT * FROM workoutTemplates ORDER BY id"),
    ("templateExercises", "SELECT * FROM templateExercises ORDER BY id"),
    ("sessions", "SELECT * FROM sessions WHERE finishedAt IS NOT NULL ORDER BY id"),
    ("sessionExercises", "SELECT * FROM sessionExercises WHERE sessionID IN (SELECT id FROM sessions WHERE finishedAt IS NOT NULL) ORDER BY id"),
    ("loggedSets", "SELECT * FROM loggedSets WHERE sessionID IN (SELECT id FROM sessions WHERE finishedAt IS NOT NULL) ORDER BY id"),
    ("bodyweightEntries", "SELECT * FROM bodyweightEntries ORDER BY id"),
  ]

  // MARK: - The round trip

  @Test("Export, then import into a fresh install: every table matches row for row")
  func roundTripIsRowForRow() async throws {
    let (source, _) = try await RestoreFixture.populated()
    let destination = try RestoreFixture.freshInstall()
    let text = try await RestoreFixture.exportJSON(source)

    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    let restore = try #require(preview.restore)
    #expect(restore.layout == .json)
    #expect(restore.savedWorkouts == 1)
    #expect(restore.bodyweightEntries == 1)
    #expect(restore.unfinishedWorkouts == 1)
    #expect(preview.sessions.count == 3)

    let result = try await DataTransferStore(database: destination).commit(preview)
    #expect(result.importedWorkouts == 3)
    #expect(result.importedSets == 9)
    #expect(result.restoredSavedWorkouts == 1)
    #expect(result.restoredBodyweightEntries == 1)
    #expect(result.restoredGyms == 3)
    #expect(result.restoredMachines == 3)
    #expect(result.restoredMovements == 2)
    #expect(result.leftOutUnfinishedWorkouts == 1)
    #expect(result.addedAnything)

    for (table, sql) in Self.carried {
      let expected = try await snapshot(source, sql)
      let actual = try await snapshot(destination, "SELECT * FROM \(table) ORDER BY id")
      #expect(!expected.isEmpty || table == "machineExercises", "\(table): the fixture should carry rows")
      #expect(actual == expected, "\(table) differs after the round trip")
    }
  }

  @Test("What the JSON still leaves out is the open workout and the device-local tables")
  func limitsAreExactlyTheDocumentedOnes() async throws {
    let (source, fixture) = try await RestoreFixture.populated()
    let destination = try RestoreFixture.freshInstall()
    _ = try await restore(try await RestoreFixture.exportJSON(source), into: destination)
    #expect(try await RestoreFixture.count(destination, "deviceHealthSamples") == 0)
    let open = try await snapshot(destination, "SELECT id FROM sessions WHERE id = '\(fixture.openSession.uuidString.lowercased())'")
    #expect(open.isEmpty)
    #expect(try await LoggerStore(database: destination).openSession() == nil)
    // Unlike the CSV, it keeps a gym and a machine no set used, and a plan row with no sets.
    #expect(try await RestoreFixture.count(destination, "gyms") == 3)
    #expect(try await RestoreFixture.count(destination, "machines") == 3)
    #expect(try await RestoreFixture.count(destination, "sessionExercises") == 6)
  }

  @Test("A plan row's machine that no set used is kept, because the JSON describes every machine")
  func planMachineIsKept() async throws {
    let source = try RestoreFixture.freshInstall()
    let gyms = GymStore(database: source)
    let gym = try gyms.createGym(name: "Gym", now: RestoreFixture.seedTime)
    let used = try gyms.createMachine(at: gym, name: "Used", now: RestoreFixture.seedTime).rawValue
    let moved = try gyms.createMachine(at: gym, name: "Moved to", now: RestoreFixture.seedTime).rawValue
    let bench = try #require(ExerciseCatalog.v1[0].uuid)
    let session = UUID(), plan = UUID()
    try await source.write { db in
      try Session.insert {
        Session.Draft(id: session, gymID: gym.rawValue, startedAt: Date(timeIntervalSince1970: 1_730_000_000),
          finishedAt: Date(timeIntervalSince1970: 1_730_003_600))
      }.execute(db)
      try SessionExercise.insert {
        SessionExercise.Draft(id: plan, sessionID: session, exerciseID: bench, machineID: moved, position: 0)
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: session, exerciseID: bench, machineID: used,
          sessionExerciseID: plan, weightKg: 50, reps: 10, completedAt: Date(timeIntervalSince1970: 1_730_000_100))
      }.execute(db)
    }
    let destination = try RestoreFixture.freshInstall()
    _ = try await restore(try await RestoreFixture.exportJSON(source), into: destination)
    #expect(try await snapshot(destination, "SELECT machineID FROM sessionExercises")
      == [["machineID": moved.uuidString.lowercased().databaseValue]])
  }

  // MARK: - A second import, and a populated phone

  @Test("Importing the same file again adds nothing and says so")
  func secondRestoreAddsNothing() async throws {
    let (source, _) = try await RestoreFixture.populated()
    let destination = try RestoreFixture.freshInstall()
    let text = try await RestoreFixture.exportJSON(source)
    _ = try await restore(text, into: destination)
    let tables = Self.carried.map(\.table) + ["deviceImportBatches"]
    let before = try await tables.asyncMap { try await RestoreFixture.count(destination, $0) }
    let again = try await restore(text, into: destination)
    #expect(again.importedWorkouts == 0)
    #expect(again.skippedWorkouts == 3)
    #expect(!again.addedAnything)
    #expect(try await tables.asyncMap { try await RestoreFixture.count(destination, $0) } == before)
  }

  @Test("Restoring into the phone it came from changes nothing")
  func restoringIntoTheSourceChangesNothing() async throws {
    let (source, _) = try await RestoreFixture.populated()
    var before: [Snapshot] = []
    for (table, _) in Self.carried { before.append(try await snapshot(source, "SELECT * FROM \(table) ORDER BY id")) }
    let result = try await restore(try await RestoreFixture.exportJSON(source), into: source)
    #expect(!result.addedAnything)
    for (index, (table, _)) in Self.carried.enumerated() {
      #expect(try await snapshot(source, "SELECT * FROM \(table) ORDER BY id") == before[index], "\(table)")
    }
  }

  @Test("A saved workout already here is never changed, and neither are its movements")
  func existingSavedWorkoutIsLeftAlone() async throws {
    let (source, fixture) = try await RestoreFixture.populated()
    let destination = try RestoreFixture.freshInstall()
    let text = try await RestoreFixture.exportJSON(source)
    _ = try await restore(text, into: destination)
    let id = fixture.template.uuidString.lowercased()
    try await destination.write { db in
      try db.execute(sql: "UPDATE workoutTemplates SET name = 'Renamed' WHERE id = ?", arguments: [id])
      try db.execute(sql: "DELETE FROM templateExercises WHERE templateID = ?", arguments: [id])
    }
    let result = try await restore(text, into: destination)
    #expect(result.restoredSavedWorkouts == 0)
    #expect(try await snapshot(destination, "SELECT name FROM workoutTemplates WHERE id = '\(id)'") == [["name": "Renamed".databaseValue]])
    #expect(try await RestoreFixture.count(destination, "templateExercises") == 0)
  }

  @Test("Workouts and saved workouts missing from a phone are added beside the ones it has")
  func partialOverlap() async throws {
    let (source, fixture) = try await RestoreFixture.populated()
    let text = try await RestoreFixture.exportJSON(source)
    let destination = try RestoreFixture.freshInstall()
    _ = try await restore(text, into: destination)
    let third = fixture.sessions[2].uuidString.lowercased()
    try await destination.write { db in
      try db.execute(sql: "DELETE FROM sessions WHERE id = ?", arguments: [third])
      try db.execute(sql: "DELETE FROM bodyweightEntries")
    }
    let result = try await restore(text, into: destination)
    #expect(result.importedWorkouts == 1)
    #expect(result.importedSets == 3)
    #expect(result.restoredBodyweightEntries == 1)
    #expect(result.skippedWorkouts == 2)
    for (table, sql) in Self.carried {
      #expect(try await snapshot(destination, "SELECT * FROM \(table) ORDER BY id") == (try await snapshot(source, sql)), "\(table)")
    }
  }

  @Test("A restore is one import: undo removes only the workouts it added")
  func undoRemovesTheRestoredWorkouts() async throws {
    let (source, _) = try await RestoreFixture.populated()
    let destination = try RestoreFixture.freshInstall()
    _ = try await restore(try await RestoreFixture.exportJSON(source), into: destination)
    let store = DataTransferStore(database: destination)
    let undo = try #require(try await store.lastImportUndo())
    #expect(undo.sessionCount == 3)
    #expect(undo.setCount == 9)
    try await store.undoLastImport(undo)
    #expect(try await RestoreFixture.count(destination, "sessions") == 0)
    #expect(try await RestoreFixture.count(destination, "loggedSets") == 0)
    // What the restore created beside the workouts stays, as it does after any import.
    #expect(try await RestoreFixture.count(destination, "workoutTemplates") == 1)
    #expect(try await RestoreFixture.count(destination, "gyms") == 3)
  }

  @Test("A failure part-way rolls the whole restore back, and a retry succeeds")
  func failedRestoreWritesNothing() async throws {
    let (source, _) = try await RestoreFixture.populated()
    let destination = try RestoreFixture.freshInstall()
    let text = try await RestoreFixture.exportJSON(source)
    try await destination.write { db in
      try db.execute(sql: "CREATE TRIGGER failRestore BEFORE INSERT ON loggedSets WHEN NEW.reps = 6 BEGIN SELECT RAISE(ABORT, 'full'); END")
    }
    await #expect(throws: (any Error).self) { try await restore(text, into: destination) }
    for table in ["gyms", "machines", "workoutTemplates", "sessions", "loggedSets", "bodyweightEntries", "deviceImportBatches"] {
      #expect(try await RestoreFixture.count(destination, table) == 0, "\(table)")
    }
    try await destination.write { try $0.execute(sql: "DROP TRIGGER failRestore") }
    #expect(try await restore(text, into: destination).importedSets == 9)
  }

  @Test("Restored Strong history is still recognised when the Strong file is imported later")
  func restoredImportedHistoryStillDeduplicates() async throws {
    let strong = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n2026-11-01 10:00:00,Push,1h 2m,Press,1,100,8,8,Keep this\n2026-11-01 10:00:00,Push,1h 2m,Press,2,100,7,,\n"
    let zone = TimeZone(secondsFromGMT: 0)!
    let source = try RestoreFixture.freshInstall()
    _ = try await DataTransferStore(database: source).commit(
      WorkoutCSVImport.preview(strong, strongUnit: .kilograms, timeZone: zone))
    let destination = try RestoreFixture.freshInstall()
    #expect(try await restore(try await RestoreFixture.exportJSON(source), into: destination).importedSets == 2)
    let later = try await DataTransferStore(database: destination).commit(
      WorkoutCSVImport.preview(strong, strongUnit: .kilograms, timeZone: zone))
    #expect(later.importedWorkouts == 0)
    #expect(later.skippedWorkouts == 1)
  }

  // MARK: - Refused files

  private func edited(_ text: String, _ change: (inout [String: Any]) throws -> Void) throws -> String {
    var object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    try change(&object)
    return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
  }

  private func edit(_ object: inout [String: Any], table: String, row: Int = 0, _ change: (inout [String: Any]) -> Void) throws {
    var tables = try #require(object["tables"] as? [String: [[String: Any]]])
    var rows = try #require(tables[table])
    change(&rows[row])
    tables[table] = rows
    object["tables"] = tables
  }

  @Test("A file that is not a Hardset export, or that this version cannot read whole, is refused",
    arguments: ["notJSON", "wrongFormat", "newerVersion", "pounds", "unknownTable", "unknownColumn",
      "badID", "badDate", "badNumber", "negativeLoad", "endsBeforeStart", "nullInRequired"])
  func refusedFiles(_ kind: String) async throws {
    let (source, _) = try await RestoreFixture.populated()
    let good = try await RestoreFixture.exportJSON(source)
    let text: String
    switch kind {
    case "notJSON": text = "{ this is not json"
    case "wrongFormat": text = try edited(good) { $0["format"] = "Strong" }
    case "newerVersion": text = try edited(good) { $0["version"] = 2 }
    case "pounds": text = try edited(good) { $0["weightUnit"] = "lb" }
    case "unknownTable": text = try edited(good) { object in
      var tables = object["tables"] as! [String: Any]
      tables["trainingPlans"] = [[String: Any]]()
      object["tables"] = tables
    }
    case "unknownColumn": text = try edited(good) { try edit(&$0, table: "loggedSets") { $0["perceivedJoy"] = 5 } }
    case "badID": text = try edited(good) { try edit(&$0, table: "loggedSets") { $0["id"] = "not-a-uuid" } }
    case "badDate": text = try edited(good) { try edit(&$0, table: "loggedSets") { $0["completedAt"] = "01/11/2026" } }
    case "badNumber": text = try edited(good) { try edit(&$0, table: "loggedSets") { $0["weightKg"] = "heavy" } }
    case "negativeLoad": text = try edited(good) { try edit(&$0, table: "loggedSets") { $0["weightKg"] = -5 } }
    case "endsBeforeStart": text = try edited(good) { try edit(&$0, table: "sessions") { $0["finishedAt"] = "2000-01-01 00:00:00.000" } }
    default: text = try edited(good) { try edit(&$0, table: "loggedSets") { $0["reps"] = NSNull() } }
    }
    let destination = try RestoreFixture.freshInstall()
    let before = try await ["sessions", "loggedSets", "gyms", "workoutTemplates"].asyncMap { try await RestoreFixture.count(destination, $0) }
    #expect(throws: WorkoutImportError.self) { try WorkoutCSVImport.preview(text, strongUnit: .kilograms) }
    #expect(try await ["sessions", "loggedSets", "gyms", "workoutTemplates"].asyncMap { try await RestoreFixture.count(destination, $0) } == before)
  }

  @Test("A row that points at something the file does not hold stops the restore and writes nothing")
  func danglingReferenceWritesNothing() async throws {
    let (source, _) = try await RestoreFixture.populated()
    let text = try edited(try await RestoreFixture.exportJSON(source)) {
      try edit(&$0, table: "loggedSets") { $0["machineID"] = UUID().uuidString.lowercased() }
    }
    let destination = try RestoreFixture.freshInstall()
    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    await #expect(throws: WorkoutImportError.self) {
      try await DataTransferStore(database: destination).commit(preview)
    }
    for table in ["gyms", "machines", "workoutTemplates", "sessions", "loggedSets", "deviceImportBatches"] {
      #expect(try await RestoreFixture.count(destination, table) == 0, "\(table)")
    }
  }

  @Test("The device-local tables in the file are read past, not restored")
  func deviceTablesAreIgnored() async throws {
    let (source, _) = try await RestoreFixture.populated()
    try await source.write { db in
      try db.execute(sql: "INSERT INTO deviceRestJournal(id, checkpointJSON) VALUES (1, '{}')")
    }
    let text = try await RestoreFixture.exportJSON(source)
    #expect(text.contains("deviceRestJournal"))
    let destination = try RestoreFixture.freshInstall()
    _ = try await restore(text, into: destination)
    #expect(try await RestoreFixture.count(destination, "deviceRestJournal") == 0)
    #expect(try await RestoreFixture.count(destination, "deviceHealthSamples") == 0)
  }

  @Test("A byte-order mark and leading whitespace do not hide a JSON file")
  func tolerantOfAPreamble() async throws {
    let (source, _) = try await RestoreFixture.populated()
    let text = "\u{FEFF}\n  " + (try await RestoreFixture.exportJSON(source))
    #expect(try WorkoutCSVImport.preview(text, strongUnit: .kilograms).restore?.layout == .json)
  }
}
