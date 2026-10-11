import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The summary is read from the database, and says only what it can stand behind")
struct WorkoutSummaryStoreTests {
  let now = Date(timeIntervalSince1970: 22_000_000)
  let posix = Locale(identifier: "en_US_POSIX")

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  /// The real catalogue, so muscle credit is the shipped attribution, not a fixture's.
  private func seeded() throws -> (any DatabaseWriter, LoggerStore, WorkoutSummaryStore) {
    let database = try migratedDatabase()
    try CatalogSeeder(database: database).seed(now: now)
    return (database, LoggerStore(database: database), WorkoutSummaryStore(database: database))
  }

  private func exercise(_ database: any DatabaseWriter, slug: String) throws -> (ExerciseID, String) {
    let row = try database.read { db in
      try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(db)
    }
    let found = try #require(row)
    return (ExerciseID(rawValue: found.id), found.name)
  }

  private func log(
    _ store: LoggerStore, _ session: SessionID, _ exercise: ExerciseID, machine: MachineID? = nil,
    _ weight: Double, _ reps: Int, warmup: Bool = false, at offset: Double
  ) throws -> SetID {
    try store.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: reps), isWarmup: warmup,
      at: now.addingTimeInterval(offset))
  }

  @Test("Length, sets, reps and volume come from what was written")
  func totals() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now)
    _ = try log(logger, session, bench, 60, 10, warmup: true, at: 60)
    for index in 1...3 { _ = try log(logger, session, bench, 100, 8, at: Double(index) * 120) }
    try logger.finishSession(session, at: now.addingTimeInterval(3_900))

    let summary = try summaries.summary(for: session)

    #expect(summary.volume.workingSets == 3)
    #expect(summary.volume.warmupSets == 1)
    #expect(summary.volume.reps == 24)
    #expect(summary.volume.volumeKg == 2_400)
    #expect(summary.lengthText == "1:05:00")
    #expect(!summary.isEmpty)
  }

  @Test("The summary and the history row cannot disagree about a session")
  func agreesWithHistory() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now)
    _ = try log(logger, session, bench, 60, 10, warmup: true, at: 30)
    _ = try log(logger, session, bench, 100, 8, at: 60)
    _ = try log(logger, session, bench, 102.5, 6, at: 120)
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let history = try HistoryStore(database: database).recentSessions()
    #expect(try summaries.summary(for: session).volume == history.first?.volume)
  }

  @Test("Every record this session is listed, with its movement and machine")
  func records() throws {
    let (database, logger, summaries) = try seeded()
    let (press, name) = try exercise(database, slug: "leg-press")
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: now)
    let hammer = try gyms.createMachine(
      at: gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let before = try logger.startSession(gymID: gym, at: now.addingTimeInterval(-7 * 86_400))
    _ = try logger.logSet(
      sessionID: before, exerciseID: press, machineID: hammer,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(-7 * 86_400))
    try logger.finishSession(before, at: now.addingTimeInterval(-7 * 86_400 + 3_600))

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try log(logger, session, press, machine: hammer, 110, 8, at: 60)
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let summary = try summaries.summary(for: session)
    #expect(summary.records.contains { $0.record.kind == .heaviestLoad })
    #expect(summary.records.allSatisfy { $0.exerciseName == name })
    #expect(summary.records.allSatisfy { $0.machineName == "Hammer Strength Leg Press" })
  }

  @Test("A corrected typo's record is gone from the summary")
  func correctedRecordGone() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let before = try logger.startSession(at: now.addingTimeInterval(-86_400))
    _ = try log(logger, before, bench, 100, 8, at: -86_400)
    try logger.finishSession(before, at: now.addingTimeInterval(-82_800))
    let session = try logger.startSession(at: now)
    let typo = try log(logger, session, bench, 1_000, 8, at: 60)
    #expect(try summaries.summary(for: session).records.isEmpty == false)

    try logger.updateSet(typo, to: SetEntryDraft(weightKg: 100, reps: 8))

    #expect(try summaries.summary(for: session).records.isEmpty)
  }

  @Test("Muscles touched follow the set-counting rules")
  func muscles() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let session = try logger.startSession(at: now)
    for index in 0..<4 { _ = try log(logger, session, bench, 100, 8, at: Double(index) * 60) }
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let summary = try summaries.summary(for: session)
    #expect(summary.muscles.first?.muscle == MuscleKey(.chest))
    #expect(summary.muscles.first?.fractionalSets == 4)
    #expect(summary.muscles.first { $0.muscle == MuscleKey(.triceps) }?.fractionalSets == 2)
    #expect(summary.muscles.allSatisfy { !$0.isLowerBound })
    #expect(summary.unattributedSets == 0)
  }

  @Test("A movement with no muscles recorded makes every muscle line a lower bound")
  func lowerBound() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let custom = ExerciseID()
    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: custom.rawValue, name: "Gym-specific contraption", isCurated: false)
      }
      .execute(db)
    }
    let session = try logger.startSession(at: now)
    for index in 0..<6 { _ = try log(logger, session, bench, 100, 8, at: Double(index) * 60) }
    for index in 0..<2 { _ = try log(logger, session, custom, 50, 10, at: 600 + Double(index) * 60) }
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let summary = try summaries.summary(for: session)
    #expect(summary.unattributedSets == 2)
    #expect(summary.muscles.allSatisfy { $0.isLowerBound })
    #expect(summary.muscles.first { $0.muscle == MuscleKey(.chest) }?.setsText(locale: posix) == "≥ 6 sets")
  }

  @Test("Machines are listed once each, in the order they were first used")
  func machinesUsed() throws {
    let (database, logger, summaries) = try seeded()
    let (press, _) = try exercise(database, slug: "leg-press")
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let gyms = GymStore(database: database)
    let gym = try gyms.createGym(name: "Home", now: now)
    let hammer = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try log(logger, session, press, machine: hammer, 100, 8, at: 60)
    _ = try log(logger, session, bench, 80, 8, at: 120)
    _ = try log(logger, session, press, machine: cybex, 90, 8, at: 180)
    _ = try log(logger, session, press, machine: hammer, 100, 8, at: 240)
    try logger.finishSession(session, at: now.addingTimeInterval(1_800))

    #expect(
      try summaries.summary(for: session).machinesUsed
        == ["Hammer Strength Leg Press", "Cybex Leg Press"])
  }

  @Test("An open or implausibly long workout has no length")
  func unknownLength() throws {
    let (database, logger, summaries) = try seeded()
    let (bench, _) = try exercise(database, slug: "barbell-bench-press")
    let open = try logger.startSession(at: now)
    _ = try log(logger, open, bench, 100, 8, at: 60)
    #expect(try summaries.summary(for: open).lengthText == "Length unknown")

    let forgotten = try logger.startSession(at: now.addingTimeInterval(-86_400))
    try logger.finishSession(forgotten, at: now.addingTimeInterval(-86_400 + 7 * 3_600))
    #expect(try summaries.summary(for: forgotten).length == nil)
  }

  @Test("An unknown workout is reported, not summarised as empty")
  func unknownSession() throws {
    let (_, _, summaries) = try seeded()
    #expect(throws: LoggerStoreError.sessionNotFound) { try summaries.summary(for: SessionID()) }
  }
}
