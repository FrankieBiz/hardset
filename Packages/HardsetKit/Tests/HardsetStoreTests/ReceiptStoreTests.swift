import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Receipts preserve machine identity and record honesty")
struct ReceiptStoreTests {
  @Test("A PR compares only the same machine, with no history row cap")
  func records() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let exercise = ExerciseID(), gym = UUID(), a = MachineID(), b = MachineID()
    let now = Date(timeIntervalSince1970: 10000)
    let old = SessionID(), current = SessionID()
    try await db.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute(db)
      try Gym.insert { Gym.Draft(id: gym, name: "Gym") }.execute(db)
      try Machine.insert { Machine.Draft(id: a.rawValue, gymID: gym, name: "Sled A", stackIncrementKg: 5) }.execute(db)
      try Machine.insert { Machine.Draft(id: b.rawValue, gymID: gym, name: "Sled B", stackIncrementKg: 5) }.execute(db)
      try Session.insert { Session.Draft(id: old.rawValue, startedAt: now.addingTimeInterval(-5000), finishedAt: now.addingTimeInterval(-1000)) }.execute(db)
      try Session.insert { Session.Draft(id: current.rawValue, startedAt: now, finishedAt: now.addingTimeInterval(600)) }.execute(db)
      for index in 0..<1005 {
        try LoggedSet.insert {
          LoggedSet.Draft(id: UUID(), sessionID: old.rawValue, exerciseID: exercise.rawValue, machineID: a.rawValue,
            setOrdinal: index, weightKg: index == 0 ? 120 : 60, reps: 8, completedAt: now.addingTimeInterval(Double(index - 4000)))
        }.execute(db)
      }
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: old.rawValue, exerciseID: exercise.rawValue, machineID: b.rawValue,
          weightKg: 200, reps: 8, completedAt: now.addingTimeInterval(-1000))
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: current.rawValue, exerciseID: exercise.rawValue, machineID: a.rawValue,
          weightKg: 100, reps: 8, completedAt: now.addingTimeInterval(60))
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(id: UUID(), sessionID: current.rawValue, exerciseID: exercise.rawValue, machineID: a.rawValue,
          setOrdinal: 1, weightKg: 130, reps: 8, completedAt: now.addingTimeInterval(120))
      }.execute(db)
    }
    let receipt = try await ReceiptStore(database: db).load(current)
    #expect(receipt.lines.count == 2)
    #expect(receipt.lines[0].records.allSatisfy { $0.kind != .heaviestLoad })
    #expect(receipt.lines[1].records.contains { $0.kind == .heaviestLoad })
    #expect(receipt.lines.allSatisfy { $0.machineName == "Sled A" })
    #expect(receipt.text(unit: .kilograms).contains("not independently verified"))
  }

  @Test("Imported equipment remains unevaluated in a shareable receipt")
  func imported() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let csv = "Date,Workout Name,Duration,Exercise Name,Weight,Reps\n2026-11-01 10:00:00,Push,3600,Press,100,8\n"
    let transfer = DataTransferStore(database: db)
    _ = try await transfer.importWorkouts(WorkoutCSVImport.preview(csv, strongUnit: .kilograms))
    let id = try #require(try await db.read { try Session.fetchOne($0)?.id })
    let receipt = try await ReceiptStore(database: db).load(SessionID(rawValue: id))
    #expect(receipt.lines.allSatisfy { $0.isImported && $0.machineName == nil && $0.records.isEmpty })
    #expect(receipt.text(unit: .kilograms).contains("Unevaluated Machine"))
  }

  @Test("An unfinished workout cannot be shared as a finished receipt")
  func openWorkout() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let session = try LoggerStore(database: db).startSession(at: .now)
    await #expect(throws: ReceiptError.self) { try await ReceiptStore(database: db).load(session) }
  }
}
