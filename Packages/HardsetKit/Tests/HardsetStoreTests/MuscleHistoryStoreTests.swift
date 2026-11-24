import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Synchronization
import Testing

@testable import HardsetStore

@Suite("Muscle history is read from the database by the rule the free screen counts with")
struct MuscleHistoryStoreTests {
  /// A Thursday, so a day either side stays inside the same seven-day window.
  let now = ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z")!

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// Seeds the real catalogue, so these run against shipped attribution rather than a fixture.
  private func seeded() throws -> (any DatabaseWriter, LoggerStore, VolumeStore, MuscleHistoryStore) {
    let database = try migratedDatabase()
    try CatalogSeeder(database: database).seed(now: now)
    return (
      database, LoggerStore(database: database), VolumeStore(database: database),
      MuscleHistoryStore(database: database)
    )
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

  // MARK: - The fixture

  @Test("The four numbers and the last buckets read end to end from disk")
  func twoWindowFixture() async throws {
    let (database, logger, _, history) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now.addingTimeInterval(-40 * 86_400))
    // Six sets five weeks ago, in the earlier four-week window, and two in the last week.
    try log(logger, session, bench, sets: 6, at: now.addingTimeInterval(-35 * 86_400))
    try log(logger, session, bench, sets: 2, at: now.addingTimeInterval(-86_400))
    try logger.finishSession(session, at: now)

    let reading = try await history.load(endingAt: now)
    let record = reading.history

    #expect(record.currentSets(for: .chest) == 2)
    #expect(record.previousSets(for: .chest) == 6)
    #expect(record.difference(for: .chest) == -4)
    #expect(record.lifetimeSets(for: .chest) == 8)
    let last = record.lastTrained[MuscleKey(.chest)]
    #expect(last?.movementName == "Barbell Bench Press")
    // The second of the two sets is a minute after the first.
    #expect(last?.date == now.addingTimeInterval(-86_400 + 60))
    // Oldest first, so the last two points are last week (none) and the current week (two).
    #expect(record.weeks.suffix(2).map { $0.report.sets(for: .chest) } == [0, 2])
    // The shape never borrows a window: it is the weeks that exist, newest last.
    #expect(record.shape(for: .chest).last == 2)
    #expect(record.shape(for: .chest).reduce(0, +) == record.lifetimeSets(for: .chest))
  }

  @Test("An empty database has no rows, no last trained and no crash")
  func emptyDatabase() async throws {
    let (_, _, _, history) = try seeded()
    let record = try await history.load(endingAt: now).history

    #expect(record.isEmpty)
    #expect(record.lifetime.hardSets == 0)
    #expect(record.lifetime.fractionalSets.isEmpty)
    #expect(record.lastTrained.isEmpty)
    #expect(record.weeks.isEmpty)
    #expect(record.emptyState(for: .chest) == .noneCredited)
  }

  // MARK: - Imports

  @Test("Imported sets count toward lifetime, then toward last trained once attributed")
  func importedHistory() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    try seeder.seed(now: now)
    let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n"
      + "2026-11-02 10:00:00,Push,1h,Bench Press (Barbell),1,100,5\n"
      + "2026-11-03 10:00:00,Push,1h,Bench Press (Barbell),1,100,5\n"
    let preview = try WorkoutCSVImport.preview(
      csv, strongUnit: .kilograms, timeZone: TimeZone(secondsFromGMT: 0)!)
    _ = try await DataTransferStore(database: database).commit(preview)
    let entry = try #require(try seeder.libraryExercises().first { $0.isImported })
    let history = MuscleHistoryStore(database: database)

    // No body part yet: the sets are working sets that credit no muscle, so lifetime counts them
    // and every figure is a floor. They cannot be a last-trained date for any muscle.
    let before = try await history.load(endingAt: now).history
    #expect(before.lifetime.hardSets == 2)
    #expect(before.lifetime.unattributedHardSets == 2)
    #expect(before.isLowerBound)
    #expect(before.lastTrained.isEmpty)
    #expect(before.includesImportedHistory)

    // Given a body part in Library, they count by the same rule and the figure moves.
    _ = try seeder.updateCustomExercise(
      entry.id, name: entry.name, attribution: try #require(CustomAttribution(primary: .chest)))
    let after = try await history.load(endingAt: now).history
    #expect(after.lifetimeSets(for: .chest) == 2)
    #expect(after.lastTrained[MuscleKey(.chest)]?.movementName == entry.name)
    #expect(after.lifetime.unattributedHardSets == 0)
  }

  // MARK: - Honest degradation

  @Test("Archiving a movement makes the lifetime figure a lower bound, not a smaller total")
  func archivedMovement() async throws {
    let (database, logger, _, history) = try seeded()
    let fly = try exerciseID(database, slug: "cable-fly")
    let session = try logger.startSession(at: now.addingTimeInterval(-86_400))
    try log(logger, session, fly, sets: 4, at: now.addingTimeInterval(-86_400))
    try logger.finishSession(session, at: now)

    #expect(try await history.load(endingAt: now).history.lifetimeSets(for: .chest) == 4)

    try await database.write { db in
      try Exercise.where { $0.id.eq(fly.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }

    let after = try await history.load(endingAt: now).history
    #expect(after.lifetime.hardSets == 4)
    #expect(after.lifetime.unattributedHardSets == 4)
    #expect(after.isLowerBound)
    // The figure falls, and the reason travels with it rather than shrinking silently.
    #expect(after.lifetimeSets(for: .chest) == 0)
    #expect(after.lastTrained[MuscleKey(.chest)] == nil)
  }

  // MARK: - One read, one rule

  @Test("The history is one transaction, not thirteen")
  func oneRead() async throws {
    let (database, _, _, history) = try seeded()
    let statements = Mutex<[String]>([])
    try await database.writeWithoutTransaction { db in
      db.trace { event in
        if case .statement(let statement) = event {
          statements.withLock { $0.append(statement.sql) }
        }
      }
    }
    _ = try await history.load(endingAt: now)
    let begins = statements.withLock { $0.filter { $0.hasPrefix("BEGIN") }.count }
    #expect(begins == 1)
  }

  @Test("The four-week total equals the free screen's four windows, summed")
  func agreesWithTheFreeScreen() async throws {
    let (database, logger, volume, history) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now.addingTimeInterval(-20 * 86_400))
    try log(logger, session, bench, sets: 3, at: now.addingTimeInterval(-19 * 86_400))
    try log(logger, session, bench, sets: 2, at: now.addingTimeInterval(-3 * 86_400))
    try logger.finishSession(session, at: now)

    var summed = 0.0
    for weeksBack in 0...3 {
      let range = VolumeWindowRange(endingAt: now, weeksBack: weeksBack)
      summed += try await volume.loadReport(in: range).sets(for: .chest)
    }
    let record = try await history.load(endingAt: now).history
    #expect(record.currentSets(for: .chest) == summed)
  }

  // MARK: - D31 and boundaries

  @Test("A future-dated session is in lifetime and not in last trained or the shape")
  func futureDatedSession() async throws {
    let (database, logger, _, history) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let past = try logger.startSession(at: now.addingTimeInterval(-2 * 86_400))
    try log(logger, past, bench, sets: 1, at: now.addingTimeInterval(-2 * 86_400))
    try logger.finishSession(past, at: now)
    // A mistyped export, or a clock set wrong, can put a set in the future. It stays in the total.
    let future = try logger.startSession(at: now.addingTimeInterval(30 * 86_400))
    try log(logger, future, bench, sets: 1, at: now.addingTimeInterval(30 * 86_400))
    try logger.finishSession(future, at: now.addingTimeInterval(30 * 86_400))

    let record = try await history.load(endingAt: now).history
    #expect(record.futureDatedSets == 1)
    #expect(record.lifetimeSets(for: .chest) == 2)
    #expect(record.lastTrained[MuscleKey(.chest)]?.date == now.addingTimeInterval(-2 * 86_400))
    #expect(record.shape(for: .chest).reduce(0, +) == 1)
    #expect(record.lastTrained[MuscleKey(.chest)]!.date < now)
  }

  @Test("A set exactly on a window boundary counts once, in the window that owns the day")
  func boundarySetCountsOnce() async throws {
    let (database, logger, _, history) = try seeded()
    let bench = try exerciseID(database, slug: "barbell-bench-press")
    let boundary = VolumeWindowRange(endingAt: now, weeksBack: 0).start
    let session = try logger.startSession(at: boundary)
    try log(logger, session, bench, sets: 1, at: boundary)
    try logger.finishSession(session, at: boundary.addingTimeInterval(3_600))

    let record = try await history.load(endingAt: now).history
    #expect(record.currentSets(for: .chest) == 1)
    #expect(record.previousSets(for: .chest) == 0)
    #expect(record.lifetimeSets(for: .chest) == 1)
    #expect(record.shape(for: .chest).reduce(0, +) == 1)
  }
}
