import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Apple Health observations stay local")
struct DeviceHealthStoreTests {
  @Test("Repeated reads upsert the same sample without creating workouts or sets")
  func replay() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let store = DeviceHealthStore(database: db)
    let sample = DeviceHealthStore.Sample(id: UUID(), kind: "apple.bodyMass", value: 80,
      unit: "kg", startedAt: Date(timeIntervalSince1970: 1000), endedAt: nil)
    try await store.save([sample])
    try await store.save([sample])
    let counts = try await db.read { db in
      (try DeviceHealthSample.fetchAll(db).count, try Session.fetchAll(db).count, try LoggedSet.fetchAll(db).count)
    }
    #expect(counts.0 == 1 && counts.1 == 0 && counts.2 == 0)
    #expect(!HardsetMigrations.syncedTableNames.contains("deviceHealthSamples"))
  }

  @Test("A malformed sample rolls back the batch")
  func invalid() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let store = DeviceHealthStore(database: db)
    let valid = DeviceHealthStore.Sample(id: UUID(), kind: "apple.bodyMass", value: 80, unit: "kg", startedAt: .now, endedAt: nil)
    let invalid = DeviceHealthStore.Sample(id: UUID(), kind: "apple.bodyMass", value: .nan, unit: "kg", startedAt: .now, endedAt: nil)
    await #expect(throws: DeviceHealthError.self) { try await store.save([valid, invalid]) }
    #expect(try await db.read { try DeviceHealthSample.fetchAll($0).isEmpty })
  }

  @Test("Only plausible completed native sessions with working sets are offered for Health export")
  func exportEligibility() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let start = Date(timeIntervalSince1970: 1000)
    let expected = UUID()
    let empty = UUID()
    let warmupOnly = UUID()
    let exercise = UUID()
    try await db.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise, name: "Press") }.execute(db)
      try Session.insert { Session.Draft(id: expected, startedAt: start, finishedAt: start.addingTimeInterval(3600)) }.execute(db)
      try Session.insert { Session.Draft(id: UUID(), notes: "Imported from Strong", startedAt: start, finishedAt: start.addingTimeInterval(3600)) }.execute(db)
      try Session.insert { Session.Draft(id: UUID(), startedAt: start) }.execute(db)
      try Session.insert { Session.Draft(id: UUID(), startedAt: start, finishedAt: start.addingTimeInterval(90000)) }.execute(db)
      // Finished, plausible and native, but nothing was trained: an accidental Start, or a
      // workout of warm-ups only. Neither is a strength workout to put in Apple Health.
      try Session.insert { Session.Draft(id: empty, startedAt: start, finishedAt: start.addingTimeInterval(600)) }.execute(db)
      try Session.insert { Session.Draft(id: warmupOnly, startedAt: start, finishedAt: start.addingTimeInterval(600)) }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(sessionID: expected, exerciseID: exercise, weightKg: 60, reps: 8, completedAt: start)
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(sessionID: warmupOnly, exerciseID: exercise, weightKg: 20, reps: 10, isWarmup: true, completedAt: start)
      }.execute(db)
    }
    #expect(try await DeviceHealthStore(database: db).workoutsToExport().map(\.id.rawValue) == [expected])
  }

  /// What was read from Apple Health is shown back, so reading it is not a silent no-op. Only a
  /// body-mass sample qualifies: a workout summary's value is a placeholder, never a weight.
  @Test("The latest body mass is the newest body-mass sample, and nothing else")
  func latestBodyMass() async throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let store = DeviceHealthStore(database: db)
    #expect(try await store.latestBodyMass() == nil)
    let older = Date(timeIntervalSince1970: 1000)
    let newer = Date(timeIntervalSince1970: 2000)
    try await store.save([
      .init(id: UUID(), kind: "apple.bodyMass", value: 82, unit: "kg", startedAt: older, endedAt: older),
      .init(id: UUID(), kind: "apple.bodyMass", value: 81.4, unit: "kg", startedAt: newer, endedAt: newer),
      .init(id: UUID(), kind: "apple.workout.50", value: 0, unit: "", startedAt: Date(timeIntervalSince1970: 3000),
        endedAt: Date(timeIntervalSince1970: 3600)),
    ])
    let latest = try #require(try await store.latestBodyMass())
    #expect(latest.kilograms == 81.4)
    #expect(latest.measuredAt == newer)
  }
}
