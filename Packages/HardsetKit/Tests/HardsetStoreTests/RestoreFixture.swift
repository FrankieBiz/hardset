import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// One lifter's database, and the helpers the CSV and JSON restore suites share, so both prove
/// their round trip against exactly the same data.
enum RestoreFixture {
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

  static func database() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    return database
  }

  /// A fresh install: migrated, with the catalogue seeded as launch does.
  static func freshInstall() throws -> DatabaseQueue {
    let db = try database()
    try CatalogSeeder(database: db).seed(now: seedTime)
    return db
  }

  static func snapshot(_ db: DatabaseQueue, _ sql: String) async throws -> Snapshot {
    try await db.read { db in
      try Row.fetchAll(db, sql: sql).map { row in
        Dictionary(uniqueKeysWithValues: row.columnNames.map { ($0, row[$0] as DatabaseValue) })
      }
    }
  }

  static func count(_ db: DatabaseQueue, _ table: String) async throws -> Int {
    try await db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM \"\(table)\"") ?? -1 }
  }

  /// A lifter's database, built through the real stores where they exist and with explicit rows
  /// where the case needs exact control. It holds everything the CSV carries and, on purpose,
  /// several things it cannot: an open workout, an unused gym and machine, a plan row with no
  /// sets, a saved workout, body mass and a row in the retained device-sample table.
  static func populated() async throws -> (DatabaseQueue, Fixture) {
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

  static func exportCSV(_ db: DatabaseQueue) async throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try await DataTransferStore(database: db).export(.csv, directory: folder)
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func restore(_ text: String, into db: DatabaseQueue) async throws -> WorkoutImportResult {
    let preview = try WorkoutCSVImport.preview(text, strongUnit: .kilograms)
    return try await DataTransferStore(database: db).commit(preview)
  }


  static func exportJSON(_ db: DatabaseQueue) async throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try await DataTransferStore(database: db).export(.json, directory: folder)
    return try String(contentsOf: url, encoding: .utf8)
  }
}

extension Sequence {
  func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var results: [T] = []
    for element in self { results.append(try await transform(element)) }
    return results
  }
}
