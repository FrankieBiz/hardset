import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
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

  @Test("A volume report reads its inputs in one transaction")
  func reportUsesOneRead() throws {
    let (database, _, volume) = try seeded()
    let statements = Mutex<[String]>([])
    try database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event {
          statements.withLock { $0.append(statement.sql) }
        }
      }
    }
    _ = try volume.rollingWeek(endingAt: now)
    let begins = statements.withLock { $0.filter { $0.hasPrefix("BEGIN") }.count }
    #expect(begins == 1)
  }

  @Test("A concurrent update cannot mix volume sets with later attribution")
  func reportHasConsistentSnapshot() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("hardset-volume-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("history.sqlite").path
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let reader = try DatabaseQueue(path: path, configuration: configuration)
    defer { try? reader.close() }
    try reader.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
    try HardsetMigrations.migrator().migrate(reader)
    let writer = try DatabaseQueue(path: path, configuration: configuration)
    defer { try? writer.close() }
    try CatalogSeeder(database: reader).seed(now: now)
    let logger = LoggerStore(database: reader)
    let volume = VolumeStore(database: reader)
    let bench = try exerciseID(reader, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now.addingTimeInterval(-3600))
    try log(logger, session, bench, sets: 4, at: now.addingTimeInterval(-3600))
    let before = try volume.rollingWeek(endingAt: now)
    #expect(before.hardSets == 4)
    #expect(before.sets(for: .chest) == 4)
    let fired = Mutex(false)
    let writeError = Mutex<String?>(nil)
    let later = now.addingTimeInterval(60)
    try reader.writeWithoutTransaction { db in
      db.trace(options: .profile) { event in
        guard case .profile(let statement, _) = event,
          statement.sql.contains("FROM \"loggedSets\"")
        else { return }
        let shouldWrite = fired.withLock { fired in
          if fired { return false }
          fired = true
          return true
        }
        guard shouldWrite else { return }
        do {
          // Commit on a separate WAL connection after the first input is read.
          // The complete newer version has no sets in the requested window.
          try writer.write { other in
            try #sql("UPDATE loggedSets SET completedAt = \(later)").execute(other)
            try #sql("UPDATE exercises SET isArchived = 1 WHERE id = \(bench.rawValue)").execute(other)
          }
        } catch {
          writeError.withLock { $0 = String(describing: error) }
        }
      }
    }
    let during = try volume.rollingWeek(endingAt: now)
    #expect(fired.withLock { $0 })
    #expect(writeError.withLock { $0 } == nil)
    #expect(during == before)
    let after = try volume.rollingWeek(endingAt: now)
    #expect(after.hardSets == 0)
    #expect(after.unattributedHardSets == 0)
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
    // Content debt is never presented as the user's gap.
    #expect(!gaps.contains(.neck))
  }

  // MARK: - Windows aligned to local days

  private var newYork: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  /// The labels name whole days, so the counted window must be whole days: a window that began at
  /// the current time of day moved a Sunday-evening set between two windows that both named that
  /// Sunday, depending on the hour the lifter looked.
  @Test("Volume windows start at local midnight and do not overlap")
  func windowsAreWholeDays() {
    let morning = local(2025, 11, 9, 8)
    let current = VolumeWindowRange(endingAt: morning, weeksBack: 0, calendar: newYork)
    #expect(current.start == local(2025, 11, 3))
    #expect(current.end == morning)
    #expect(current.lastDay == morning)
    let earlier = VolumeWindowRange(endingAt: morning, weeksBack: 1, calendar: newYork)
    #expect(earlier.start == local(2025, 10, 27))
    #expect(earlier.end == current.start)
    #expect(newYork.isDate(earlier.lastDay, inSameDayAs: local(2025, 11, 2)))
    // Across the 2 November clock change the window is seven local days, not 168 hours.
    #expect(earlier.end.timeIntervalSince(earlier.start) == 7 * 86_400 + 3600)
    #expect(VolumeWindowRange(endingAt: morning, weeksBack: 2, calendar: newYork).end == earlier.start)
    // The same view at a different hour of the same day names the same days.
    let evening = VolumeWindowRange(endingAt: local(2025, 11, 9, 20), weeksBack: 1, calendar: newYork)
    #expect(evening.start == earlier.start && evening.end == earlier.end)
  }

  @Test("A set late on a boundary day stays in the window that names that day")
  func boundaryDaySetStaysPut() async throws {
    let (database, store, reports) = try seeded()
    let press = try exerciseID(database, slug: "barbell-bench-press")
    let sunday = local(2025, 11, 2, 18)
    let session = try store.startSession(at: sunday)
    try log(store, session, press, sets: 3, at: sunday)
    for hour in [8, 20] {
      let viewedAt = local(2025, 11, 9, hour)
      let current = VolumeWindowRange(endingAt: viewedAt, weeksBack: 0, calendar: newYork)
      let earlier = VolumeWindowRange(endingAt: viewedAt, weeksBack: 1, calendar: newYork)
      #expect(try await reports.loadReport(in: current).hardSets == 0, "viewed at \(hour):00")
      #expect(try await reports.loadReport(in: earlier).hardSets == 3, "viewed at \(hour):00")
    }
  }
}
