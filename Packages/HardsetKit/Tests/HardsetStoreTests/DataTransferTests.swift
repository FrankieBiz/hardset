import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Atomic imports and free complete exports")
struct DataTransferTests {
  let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n2026-11-01 10:00:00,Push,1h 2m,Press,1,100,8,8,Keep this\n2026-11-01 10:00:00,Push,1h 2m,Press,2,100,7,,\n"
  private func database() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    return database
  }

  @Test("Strong unit choice, real dates and unknown equipment survive persistence")
  func strong() async throws {
    let db = try database()
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .pounds, timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(preview.setCount == 2)
    #expect(preview.sessions[0].finishedAt.timeIntervalSince(preview.sessions[0].startedAt) == 3720)
    let transfer = DataTransferStore(database: db)
    #expect(try await transfer.importWorkouts(preview) == 2)
    let result = try await db.read { db in
      (try LoggedSet.fetchAll(db), try Exercise.fetchAll(db), try Session.fetchAll(db))
    }
    #expect(result.0.count == 2)
    #expect(result.0.allSatisfy { $0.machineID == nil && abs($0.weightKg - WeightUnit.pounds.toKilograms(100)) < 0.00001 })
    #expect(result.1[0].name.contains("Imported"))
    #expect(result.1[0].primaryMuscle == "unknown")
    #expect(result.2[0].notes.contains("Unevaluated Machine"))
    #expect(try LoggerStore(database: db).openSession() == nil)
    await #expect(throws: WorkoutImportError.alreadyImported) { try await transfer.importWorkouts(preview) }
    #expect(try await db.read { try LoggedSet.fetchAll($0).count } == 2)
  }

  @Test("Hevy English timestamps, quoted fields and canonical units")
  func hevy() throws {
    let text = "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps\nPush,\"1 Nov 2026, 10:00\",\"1 Nov 2026, 11:00\",\"Press, seated\",0,warmup,20,10\n"
    let result = try WorkoutCSVImport.preview(text, strongUnit: .pounds)
    #expect(result.source == "Hevy")
    #expect(result.sessions[0].sets[0].exercise == "Press, seated")
    #expect(result.sessions[0].sets[0].weightKg == 20)
    #expect(result.sessions[0].sets[0].isWarmup)
  }

  @Test("Invalid rows fail before persistence", arguments: ["nan", "inf", "-1", ""])
  func invalidWeight(_ weight: String) {
    #expect(throws: WorkoutImportError.self) {
      try WorkoutCSVImport.preview(csv.replacingOccurrences(of: ",100,", with: ",\(weight),"), strongUnit: .kilograms)
    }
  }

  @Test("A rejected set rolls back the whole file, and retry succeeds")
  func atomic() async throws {
    let db = try database()
    let store = DataTransferStore(database: db)
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms)
    try await db.write { db in
      try db.execute(sql: "CREATE TRIGGER failImport BEFORE INSERT ON loggedSets WHEN NEW.reps = 7 BEGIN SELECT RAISE(ABORT, 'full'); END")
    }
    await #expect(throws: (any Error).self) { try await store.importWorkouts(preview) }
    let counts = try await db.read { db in
      try ["exercises", "sessions", "loggedSets", "deviceImportBatches"].map {
        try Int.fetchOne(db, sql: "SELECT count(*) FROM \($0)")!
      }
    }
    #expect(counts == [0, 0, 0, 0])
    try await db.write { try $0.execute(sql: "DROP TRIGGER failImport") }
    #expect(try await store.importWorkouts(preview) == 2)
  }

  @Test("CSV, JSON and SQLite exports contain committed data and remain independent")
  func exports() async throws {
    let db = try database()
    let store = DataTransferStore(database: db)
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms)
    _ = try await store.importWorkouts(preview)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in DataTransferStore.Format.allCases {
      let url = try await store.export(format, directory: folder)
      #expect(FileManager.default.fileExists(atPath: url.path))
      switch format {
      case .csv:
        let rows = try CSVDocument.decode(String(contentsOf: url, encoding: .utf8))
        #expect(rows.count == 3)
        #expect(rows[0].contains("machineID"))
      case .json:
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let tables = try #require(object["tables"] as? [String: [[String: Any]]])
        #expect(tables["loggedSets"]?.count == 2)
        #expect(tables["exercises"]?.count == 1)
        #expect(tables["deviceImportBatches"]?.count == 1)
      case .sqlite:
        let copy = try DatabaseQueue(path: url.path)
        #expect(try await copy.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM loggedSets") } == 2)
        #expect(try await copy.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") } == "ok")
      }
    }
    let first = try await store.export(.json, directory: folder)
    let second = try await store.export(.json, directory: folder)
    #expect(first != second)
    #expect(try Data(contentsOf: first) == Data(contentsOf: second))
  }

  // MARK: - Overlapping exports

  /// Strong and Hevy export the whole history every time, so a later file repeats every workout
  /// an earlier one carried. Each workout already imported from the same app is skipped; only the
  /// new ones are written.
  @Test("A newer export imports only the workouts not already imported")
  func overlappingExport() async throws {
    let db = try database()
    let store = DataTransferStore(database: db)
    let utc = TimeZone(secondsFromGMT: 0)!
    _ = try await store.importWorkouts(try WorkoutCSVImport.preview(csv, strongUnit: .kilograms, timeZone: utc))
    // A native workout at the same instant and title is the lifter's own, not an import.
    try await db.write { db in
      try Session.insert {
        Session.Draft(id: UUID(), title: "Legs", startedAt: Date(timeIntervalSince1970: 1_793_728_800),
          finishedAt: Date(timeIntervalSince1970: 1_793_732_400))
      }.execute(db)
    }
    let newer = csv
      + "2026-11-03 18:00:00,Legs,1h,Squat,1,140,5,,\n2026-11-03 18:00:00,Legs,1h,Squat,2,140,5,,\n"
      + "2026-11-05 10:00:00,Push,1h,Press,1,105,8,,\n"
    let preview = try WorkoutCSVImport.preview(newer, strongUnit: .kilograms, timeZone: utc)
    #expect(try await store.alreadyImportedWorkoutCount(in: preview) == 1)

    let result = try await store.commit(preview)
    #expect(result == WorkoutImportResult(importedWorkouts: 2, importedSets: 3, skippedWorkouts: 1))
    let counts = try await db.read { db in
      (try Session.fetchCount(db), try LoggedSet.fetchCount(db),
       try Int.fetchOne(db, sql: "SELECT count(*) FROM deviceImportBatches")!,
       try Exercise.fetchAll(db).map(\.name).sorted())
    }
    #expect(counts.0 == 4)
    #expect(counts.1 == 5)
    #expect(counts.2 == 2)
    // The second file's presses join the first file's imported movement instead of starting a
    // second one with the same name, so imported history is not split in two.
    #expect(counts.3 == ["Press (Imported • Strong)", "Squat (Imported • Strong)"])
  }

  @Test("A different file holding only imported workouts writes nothing")
  func nothingNew() async throws {
    let db = try database()
    let store = DataTransferStore(database: db)
    _ = try await store.importWorkouts(try WorkoutCSVImport.preview(csv, strongUnit: .kilograms))
    // Same workout, re-exported with Windows line endings: a different file, the same history.
    let again = try WorkoutCSVImport.preview(csv.replacingOccurrences(of: "\n", with: "\r\n"), strongUnit: .kilograms)
    #expect(try await store.commit(again) == WorkoutImportResult(importedWorkouts: 0, importedSets: 0, skippedWorkouts: 1))
    let counts = try await db.read { db in
      (try LoggedSet.fetchCount(db), try Int.fetchOne(db, sql: "SELECT count(*) FROM deviceImportBatches")!)
    }
    #expect(counts.0 == 2)
    // Nothing was imported from it, so it is not retained as an import.
    #expect(counts.1 == 1)
  }

  // MARK: - Rows that are not loaded strength sets

  /// Planks, cardio and unweighted sets carry no load × reps to record. In the lenient mode the
  /// preview lists them by row and leaves them out; nothing is invented for them.
  @Test("Timed, distance and unloaded rows are listed and left out, not fatal")
  func skippedRows() throws {
    let text = """
      Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes
      2026-11-01 10:00:00,Push,1h,Press,1,100,8,0,0,
      2026-11-01 10:00:00,Push,1h,Plank,1,0,0,0,60,
      2026-11-01 10:00:00,Push,1h,Pull-up,1,,10,,,
      2026-11-01 10:00:00,Push,1h,Run,1,,,5,1200,

      """
    #expect(throws: WorkoutImportError.self) { try WorkoutCSVImport.preview(text, strongUnit: .kilograms) }
    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms, skippingUnsupportedRows: true)
    #expect(preview.setCount == 1)
    #expect(preview.sessions[0].sets.map(\.exercise) == ["Press"])
    #expect(preview.skipped == [
      .init(line: 3, reason: .noReps), .init(line: 4, reason: .noLoad), .init(line: 5, reason: .noReps),
    ])
  }

  @Test("Malformed rows still stop a lenient preview", arguments: ["nan", "-1", "inf"])
  func lenientStillRejectsMalformed(_ weight: String) {
    #expect(throws: WorkoutImportError.self) {
      try WorkoutCSVImport.preview(csv.replacingOccurrences(of: ",100,", with: ",\(weight),"),
        strongUnit: .kilograms, skippingUnsupportedRows: true)
    }
  }

  @Test("A file with no loaded strength sets says so")
  func onlyUnsupportedRows() {
    let text = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Seconds\n2026-11-01 10:00:00,Core,10m,Plank,1,0,0,60\n"
    #expect(throws: WorkoutImportError.noSupportedSets(skipped: 1)) {
      try WorkoutCSVImport.preview(text, strongUnit: .kilograms, skippingUnsupportedRows: true)
    }
  }

  /// Comma-decimal locales export with semicolons, so "82,5" is a number only in such a file.
  @Test("Comma decimals are read from semicolon files only")
  func commaDecimals() throws {
    let semicolon = "Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;RPE\n2026-11-01 10:00:00;Push;1h;Press;1;82,5;8;7,5\n"
    let set = try WorkoutCSVImport.preview(semicolon, strongUnit: .kilograms).sessions[0].sets[0]
    #expect(set.weightKg == 82.5)
    #expect(set.rpe == 7.5)
    let comma = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n2026-11-01 10:00:00,Push,1h,Press,1,\"82,5\",8\n"
    #expect(throws: WorkoutImportError.self) { try WorkoutCSVImport.preview(comma, strongUnit: .kilograms) }
  }

  // MARK: - Export naming

  @Test("Exports are named by the day they were made")
  func exportName() async throws {
    let store = DataTransferStore(database: try database())
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    // 23:30 UTC on 1 November is already 2 November in Auckland.
    let instant = Date(timeIntervalSince1970: 1_793_575_800)
    let utc = try await store.export(.csv, directory: folder, madeAt: instant, timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(utc.lastPathComponent == "Hardset-2026-11-01.csv")
    let auckland = try await store.export(.sqlite, directory: folder, madeAt: instant,
      timeZone: TimeZone(identifier: "Pacific/Auckland")!)
    #expect(auckland.lastPathComponent == "Hardset-2026-11-02.sqlite")
  }
}
