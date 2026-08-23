import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Weekly volume is read from the database and counted honestly")
struct VolumeStoreTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// Seeds the real catalogue, so these run against shipped attribution rather than a fixture.
  private func seeded() throws -> (any DatabaseWriter, LoggerStore, VolumeStore) {
    let database = try migratedDatabase()
    try CatalogSeeder(database: database).seed(now: now)
    return (database, LoggerStore(database: database), VolumeStore(database: database))
  }

  private func exerciseID(_ database: any DatabaseWriter, slug: String) throws -> ExerciseID {
    let row = try database.read { db in
      try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(db)
    }
    return ExerciseID(rawValue: try #require(row).id)
  }

  private func log(
    _ store: LoggerStore, _ session: SessionID, _ exercise: ExerciseID,
    sets: Int, at date: Date, isWarmup: Bool = false
  ) throws {
    for index in 0..<sets {
      _ = try store.logSet(
        sessionID: session, exerciseID: exercise,
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: index,
        isWarmup: isWarmup, at: date.addingTimeInterval(Double(index) * 60)
      )
    }
  }

  @Test("Fractional credit reaches the report through the database")
  func fractionalCreditEndToEnd() throws {
    let (database, logger, volume) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, bench, sets: 4, at: now.addingTimeInterval(-3600))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    let report = try volume.rollingWeek(endingAt: now)
    #expect(report.hardSets == 4)
    #expect(report.sets(for: .chest) == 4.0)
    // Pelland Table 1 has both of these as indirect on the bench press.
    #expect(report.sets(for: .frontDelts) == 2.0)
    #expect(report.sets(for: .triceps) == 2.0)
    #expect(report.coverage == 1.0)
  }

  /// Grip and bracing are stabilisers all the way through storage.
  @Test("Held grip credits nothing after a database round trip")
  func gripCreditsNothingEndToEnd() throws {
    let (database, logger, volume) = try seeded()
    let pullUp = try exerciseID(database, slug: "pull-up")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, pullUp, sets: 12, at: now.addingTimeInterval(-3600))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    let report = try volume.rollingWeek(endingAt: now)
    #expect(report.sets(for: .lats) == 12.0)
    #expect(report.sets(for: .biceps) == 6.0)
    // The defect this whole design exists to prevent: twelve sets of pulling once invented six
    // sets of forearm work.
    #expect(report.sets(for: .forearms) == 0)
  }

  @Test("Warm-ups are excluded")
  func warmupsExcluded() throws {
    let (database, logger, volume) = try seeded()
    let squat = try exerciseID(database, slug: "barbell-back-squat")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, squat, sets: 2, at: now.addingTimeInterval(-3600), isWarmup: true)
    try log(logger, session, squat, sets: 3, at: now.addingTimeInterval(-3000))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    let report = try volume.rollingWeek(endingAt: now)
    #expect(report.hardSets == 3)
    #expect(report.sets(for: .quadriceps) == 3.0)
  }

  /// A user's own exercise has no attribution, so its sets are unaccounted for rather than zero.
  @Test("A user-created exercise makes the week a lower bound")
  func userExerciseIsUnattributed() throws {
    let (database, logger, volume) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")

    let custom = ExerciseID()
    try database.write { db in
      // No attribution: primaryMuscle defaults to the reserved sentinel and the JSON to "[]".
      try Exercise.insert {
        Exercise.Draft(id: custom.rawValue, name: "Gym-specific contraption", isCurated: false)
      }
      .execute(db)
    }

    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, bench, sets: 6, at: now.addingTimeInterval(-3600))
    try log(logger, session, custom, sets: 2, at: now.addingTimeInterval(-3000))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    let report = try volume.rollingWeek(endingAt: now)
    #expect(report.hardSets == 8)
    #expect(report.unattributedHardSets == 2)
    #expect(report.isLowerBound)
    #expect(abs(report.coverage - 0.75) < 1e-9)
    // The known work still counts exactly.
    #expect(report.sets(for: .chest) == 6.0)
  }

  /// Half-open windows, so a set on a boundary is not counted in two adjacent weeks.
  @Test("The window is half-open at the upper bound")
  func windowIsHalfOpen() throws {
    let (database, logger, volume) = try seeded()
    let curl = try exerciseID(database, slug: "barbell-curl")
    let session = try logger.startSession(at: now.addingTimeInterval(-7200))
    // One set exactly at `now`, which is the exclusive upper bound.
    _ = try logger.logSet(
      sessionID: session, exerciseID: curl,
      draft: SetEntryDraft(weightKg: 30, reps: 10), setOrdinal: 0, at: now
    )
    try logger.finishSession(session, at: now)

    #expect(try volume.rollingWeek(endingAt: now).hardSets == 0)
    // And it appears in the window that does include it.
    #expect(try volume.report(from: now, to: now.addingTimeInterval(60)).hardSets == 1)
  }

  @Test("Sets outside the window are not counted")
  func outsideWindowExcluded() throws {
    let (database, logger, volume) = try seeded()
    let press = try exerciseID(database, slug: "overhead-press")
    let old = now.addingTimeInterval(-30 * 86_400)
    let session = try logger.startSession(at: old)
    try log(logger, session, press, sets: 5, at: old)
    try logger.finishSession(session, at: old.addingTimeInterval(3600))

    #expect(try volume.rollingWeek(endingAt: now).hardSets == 0)
  }

  /// An archived exercise still has logged sets. They must not silently become unattributed.
  @Test("Archiving an exercise makes its logged sets unattributed rather than wrong")
  func archivedExerciseBecomesUnattributed() throws {
    let (database, logger, volume) = try seeded()
    let fly = try exerciseID(database, slug: "cable-fly")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, fly, sets: 4, at: now.addingTimeInterval(-3600))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    #expect(try volume.rollingWeek(endingAt: now).sets(for: .chest) == 4.0)

    try database.write { db in
      try Exercise.where { $0.id.eq(fly.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }

    let after = try volume.rollingWeek(endingAt: now)
    #expect(after.hardSets == 4)
    // Reported as unaccounted for, not as zero chest volume.
    #expect(after.unattributedHardSets == 4)
    #expect(after.isLowerBound)
  }

  @Test("Group figures count sets once through the database too")
  func groupsCountOnce() throws {
    let (database, logger, volume) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, bench, sets: 4, at: now.addingTimeInterval(-3600))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    let report = try volume.rollingWeek(endingAt: now)
    #expect(report.setsTouchingGroup[.chest] == 4)
    #expect(report.setsTouchingGroup[.shoulders] == 4)
    #expect(report.setsTouchingGroup[.arms] == 4)
  }

  @Test("Coverage gaps come from the real catalogue")
  func coverageGaps() throws {
    let (database, logger, volume) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, bench, sets: 6, at: now.addingTimeInterval(-3600))
    try logger.finishSession(session, at: now.addingTimeInterval(-1800))

    let gaps = try volume.rollingWeek(endingAt: now)
      .untrainedMuscles(excluding: ExerciseCatalog.unauthoredDirectTokens)
    #expect(gaps.contains(.hamstrings))
    #expect(gaps.contains(.lats))
    #expect(!gaps.contains(.chest))

    // `neck` is a real gap in this week now that the catalogue can train it; the exclusion list is
    // empty. The rule that content debt is never presented as the user's failing is pinned on an
    // explicit set instead, so it survives the catalogue growing.
    #expect(ExerciseCatalog.unauthoredDirectTokens.isEmpty)
    #expect(gaps.contains(.neck))

    let suppressed = try volume.rollingWeek(endingAt: now).untrainedMuscles(excluding: [.neck])
    #expect(!suppressed.contains(.neck))
    #expect(suppressed.contains(.hamstrings))
  }
}
