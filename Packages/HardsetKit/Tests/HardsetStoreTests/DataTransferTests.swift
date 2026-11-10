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

  /// Strong's dates carry no offset, so they were read in the zone the phone was in. After a move
  /// from New York to London the same wall-clock dates parse to instants five hours apart, which
  /// must not make every earlier workout look new. Each import records its zone in its notes.
  @Test("A newer export read in another time zone skips the workouts already imported")
  func reimportAfterTimeZoneChange() async throws {
    let db = try database()
    let store = DataTransferStore(database: db)
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let london = try #require(TimeZone(identifier: "Europe/London"))
    _ = try await store.importWorkouts(try WorkoutCSVImport.preview(csv, strongUnit: .kilograms, timeZone: newYork))
    let newer = csv + "2026-11-05 10:00:00,Push,1h,Press,1,105,8,,\n"
    let preview = try WorkoutCSVImport.preview(newer, strongUnit: .kilograms, timeZone: london)
    #expect(try await store.alreadyImportedWorkoutCount(in: preview) == 1)
    let result = try await store.commit(preview)
    #expect(result == WorkoutImportResult(importedWorkouts: 1, importedSets: 1, skippedWorkouts: 1))
    #expect(try await db.read { try Session.fetchCount($0) } == 2)

    // An export whose dates carry an offset is the same instant in any zone.
    let offsetCSV = csv.replacingOccurrences(of: "2026-11-01 10:00:00", with: "2026-11-01T15:00:00Z")
    let other = try database()
    let otherStore = DataTransferStore(database: other)
    _ = try await otherStore.importWorkouts(try WorkoutCSVImport.preview(offsetCSV, strongUnit: .kilograms, timeZone: newYork))
    let again = try WorkoutCSVImport.preview(offsetCSV + "\n", strongUnit: .kilograms, timeZone: london)
    #expect(try await otherStore.alreadyImportedWorkoutCount(in: again) == 1)
  }

  /// A row stamped inside the spring-forward gap names a wall time that did not exist locally. It
  /// must not fail the whole file.
  @Test("A wall time inside a daylight-saving gap is read rather than failing the file")
  func daylightSavingGap() throws {
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let text = csv.replacingOccurrences(of: "2026-11-01 10:00:00", with: "2024-03-10 02:30:00")
    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms, timeZone: newYork)
    let start = preview.sessions[0].startedAt
    // 02:30 does not exist that night; the instant lands in the hour around it, not a day away.
    let gapStart = Date(timeIntervalSince1970: 1_710_054_000)  // 2024-03-10 07:00 UTC
    #expect(abs(start.timeIntervalSince(gapStart)) <= 3600)
    // Invalid dates are still refused.
    let invalid = csv.replacingOccurrences(of: "2026-11-01 10:00:00", with: "2026-02-30 10:00:00")
    #expect(throws: WorkoutImportError.self) {
      try WorkoutCSVImport.preview(invalid, strongUnit: .kilograms, timeZone: newYork)
    }
  }

  /// Formatters are built once per preview, not once per date per format. Three years of Strong
  /// history is around fifteen thousand rows; Hevy parses two dates per row.
  @Test("A multi-year export previews quickly")
  func largePreviewIsFast() throws {
    var strong = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,RPE,Notes\n"
    var hevy = "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps\n"
    let day = 86_400.0
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let workouts = (0..<1000).map { Date(timeIntervalSince1970: 1_600_000_000 + Double($0) * day) }
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let strongDates = workouts.map(formatter.string(from:))
    formatter.dateFormat = "d MMM yyyy, HH:mm"
    let hevyStarts = workouts.map(formatter.string(from:))
    let hevyEnds = workouts.map { formatter.string(from: $0.addingTimeInterval(3600)) }
    for row in 0..<15_000 {
      let workout = row / 15
      strong += "\(strongDates[workout]),Push,1h,Press,\(row % 15 + 1),100,8,,\n"
      hevy += "Push,\"\(hevyStarts[workout])\",\"\(hevyEnds[workout])\",Press,\(row % 15),normal,100,8\n"
    }
    let utc = TimeZone(secondsFromGMT: 0)!
    let began = Date()
    let strongPreview = try WorkoutCSVImport.preview(strong, strongUnit: .kilograms, timeZone: utc)
    let hevyPreview = try WorkoutCSVImport.preview(hevy, strongUnit: .kilograms, timeZone: utc)
    let elapsed = Date().timeIntervalSince(began)
    #expect(strongPreview.sessions.count == 1000)
    #expect(hevyPreview.setCount == 15_000)
    // Building formatters per cell took about 41 s here; the bound leaves room for a loaded runner.
    #expect(elapsed < 5, "Preview took \(elapsed) s")
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

  // MARK: - Corrections and order

  /// Deleting an import's workouts in History and choosing the same file again imports it again,
  /// rather than refusing a file whose workouts are no longer anywhere in the app.
  @Test("The same file imports again after its workouts were deleted")
  func reimportAfterDeletion() async throws {
    let db = try database()
    let store = DataTransferStore(database: db)
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms)
    _ = try await store.importWorkouts(preview)
    await #expect(throws: WorkoutImportError.alreadyImported) { try await store.importWorkouts(preview) }
    try await db.write { db in
      try db.execute(sql: "DELETE FROM loggedSets; DELETE FROM sessionExercises; DELETE FROM sessions")
    }
    #expect(try await store.importWorkouts(preview) == 2)
    #expect(try await db.read { try LoggedSet.fetchAll($0).count } == 2)
    #expect(try await db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM deviceImportBatches") } == 1)
  }

  /// Sets leave in the order they were performed. Ordering by the per-movement set number first
  /// interleaved movements: a workout done Press, Press, Row exported as Press 1, Row 1, Press 2.
  @Test("CSV export lists sets in the order they were performed")
  func exportOrder() async throws {
    let db = try database()
    let session = UUID()
    let press = UUID()
    let row = UUID()
    let start = Date(timeIntervalSince1970: 1_000_000)
    try await db.write { db in
      try Exercise.insert { Exercise.Draft(id: press, name: "Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: row, name: "Row") }.execute(db)
      try Session.insert {
        Session.Draft(id: session, startedAt: start, finishedAt: start.addingTimeInterval(3600))
      }.execute(db)
      for (exercise, ordinal, minute) in [(press, 1, 1), (press, 2, 5), (row, 1, 9)] {
        try LoggedSet.insert {
          LoggedSet.Draft(sessionID: session, exerciseID: exercise, setOrdinal: ordinal, weightKg: 50,
            reps: 8, completedAt: start.addingTimeInterval(Double(minute) * 60))
        }.execute(db)
      }
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try await DataTransferStore(database: db).export(.csv, directory: folder)
    let rows = try CSVDocument.decode(String(contentsOf: url, encoding: .utf8))
    let name = try #require(rows.first?.firstIndex(of: "exerciseName"))
    let ordinal = try #require(rows.first?.firstIndex(of: "setOrdinal"))
    #expect(rows.dropFirst().map { "\($0[name]) \($0[ordinal])" } == ["Press 1", "Press 2", "Row 1"])
  }
}
