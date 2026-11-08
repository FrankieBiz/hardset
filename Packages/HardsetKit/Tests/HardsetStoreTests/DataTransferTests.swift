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
}
