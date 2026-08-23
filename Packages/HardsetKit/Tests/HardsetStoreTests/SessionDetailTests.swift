import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Reading one workout back. History listed sessions and could not open them, because nothing
/// could answer "what was in this one".
@Suite("A past workout can be read back set by set")
struct SessionDetailTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func migrated() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  @MainActor
  @Test("Sets come back in logging order, with the movement and machine named")
  func setsReadBack() throws {
    let database = try migrated()
    try CatalogSeeder(database: database).seed(now: now)
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let gyms = GymStore(database: database)

    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Hammer Strength")
    let exercise = try #require(
      try database.read { db in try Exercise.where { $0.catalogSlug.eq("chest-press-machine") }.fetchOne(db) }
    )
    let exerciseID = ExerciseID(rawValue: exercise.id)

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exerciseID, machineID: machine,
      draft: SetEntryDraft(weightKg: 40, reps: 10), isWarmup: true, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: exerciseID, machineID: machine,
      draft: SetEntryDraft(weightKg: 70, reps: 8), isWarmup: false,
      at: now.addingTimeInterval(120)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    let sets = try history.sets(in: session)
    #expect(sets.count == 2)
    #expect(sets.map(\.weightKg) == [40, 70])
    #expect(sets.first?.isWarmup == true)
    #expect(sets.last?.isWarmup == false)
    // Named, because a load is only meaningful next to the equipment it was lifted on.
    #expect(sets.allSatisfy { $0.exerciseName == "Chest Press" })
    #expect(sets.allSatisfy { $0.machineName == "Hammer Strength" })
  }

  @MainActor
  @Test("A session with no sets reads back empty rather than failing")
  func emptySession() throws {
    let database = try migrated()
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let session = try logger.startSession(at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(60))
    #expect(try history.sets(in: session).isEmpty)
  }

  @MainActor
  @Test("Free-weight sets carry no machine name rather than an invented one")
  func freeWeightHasNoMachine() throws {
    let database = try migrated()
    try CatalogSeeder(database: database).seed(now: now)
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let exercise = try #require(
      try database.read { db in
        try Exercise.where { $0.catalogSlug.eq("barbell-back-squat") }.fetchOne(db)
      }
    )
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: exercise.id), machineID: nil,
      draft: SetEntryDraft(weightKg: 100, reps: 5), isWarmup: false, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(300))

    let sets = try history.sets(in: session)
    #expect(sets.count == 1)
    #expect(sets.first?.machineName == nil)
  }
}

extension SessionDetailTests {
  @MainActor
  @Test("A bodyweight set reads back as bodyweight, not as zero load")
  func bodyweightReadsBackHonestly() throws {
    let database = try migrated()
    try CatalogSeeder(database: database).seed(now: now)
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)

    let dip = try #require(
      try database.read { db in try Exercise.where { $0.catalogSlug.eq("dip") }.fetchOne(db) }
    )
    // The stored modality is what makes this readable back correctly after a relaunch.
    #expect(dip.modality == "bodyweight")

    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: dip.id),
      draft: SetEntryDraft(weightKg: 0, reps: 10), at: now
    )
    // And one with added load, which must not collapse to the same rendering.
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: dip.id),
      draft: SetEntryDraft(weightKg: 10, reps: 6), at: now.addingTimeInterval(120)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    let sets = try history.sets(in: session)
    #expect(sets.count == 2)
    #expect(sets.allSatisfy { $0.modality == .bodyweight })
    #expect(sets.first?.weightKg == 0)
    #expect(sets.last?.weightKg == 10)
  }

  @MainActor
  @Test("A loaded movement reports its modality too, so nothing guesses")
  func loadedModalityIsCarried() throws {
    let database = try migrated()
    try CatalogSeeder(database: database).seed(now: now)
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let squat = try #require(
      try database.read { db in
        try Exercise.where { $0.catalogSlug.eq("barbell-back-squat") }.fetchOne(db)
      }
    )
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: squat.id),
      draft: SetEntryDraft(weightKg: 100, reps: 5), at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(300))
    #expect(try history.sets(in: session).first?.modality == .barbell)
  }
}

/// Repeating a past workout. Lifters do this constantly, and the plan has to come from what
/// actually happened rather than from what was intended.
@Suite("A past workout can be turned back into a plan")
struct RepeatWorkoutTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, HistoryStore, GymStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (
      queue, LoggerStore(database: queue), HistoryStore(database: queue),
      GymStore(database: queue)
    )
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  @MainActor
  @Test("The plan carries each movement, its machine, and how many sets were done")
  func planCarriesMachineAndCount() throws {
    let (db, logger, history, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Hammer Strength")
    let press = try exercise(db, "chest-press-machine")

    let session = try logger.startSession(gymID: gym, at: now)
    for index in 0..<3 {
      _ = try logger.logSet(
        sessionID: session, exerciseID: press, machineID: machine,
        draft: SetEntryDraft(weightKg: 70, reps: 8),
        at: now.addingTimeInterval(Double(index) * 90)
      )
    }
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    let plan = try history.plan(for: session)
    #expect(plan.count == 1)
    #expect(plan.first?.workingSets == 3)
    // Returning to the same equipment is the point: it is what makes the prefilled loads mean
    // anything.
    #expect(plan.first?.machineID == machine)
    #expect(plan.first?.machineName == "Hammer Strength")
  }

  @MainActor
  @Test("Warm-ups are not planned again")
  func warmupsAreExcluded() throws {
    let (db, logger, history, _) = try fixture()
    let squat = try exercise(db, "barbell-back-squat")
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: squat,
      draft: SetEntryDraft(weightKg: 40, reps: 10), isWarmup: true, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: squat,
      draft: SetEntryDraft(weightKg: 100, reps: 5), at: now.addingTimeInterval(120)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    // One working set, so one row -- the warm-up is how you got there, not part of the plan.
    #expect(try history.plan(for: session).first?.workingSets == 1)
  }

  @MainActor
  @Test("The same movement on two machines comes back as two entries")
  func machinesDoNotMerge() throws {
    let (db, logger, history, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let hammer = try gyms.createMachine(at: gym, name: "Hammer")
    let cybex = try gyms.createMachine(at: gym, name: "Cybex")
    let press = try exercise(db, "chest-press-machine")

    let session = try logger.startSession(gymID: gym, at: now)
    for (index, machine) in [hammer, cybex].enumerated() {
      _ = try logger.logSet(
        sessionID: session, exerciseID: press, machineID: machine,
        draft: SetEntryDraft(weightKg: 70, reps: 8),
        at: now.addingTimeInterval(Double(index) * 90)
      )
    }
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    // Same rule the chart follows: two pieces of equipment are two things.
    #expect(try history.plan(for: session).count == 2)
  }

  @MainActor
  @Test("A workout with nothing logged yields an empty plan rather than a phantom one")
  func emptySessionYieldsEmptyPlan() throws {
    let (_, logger, history, _) = try fixture()
    let session = try logger.startSession(at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(60))
    #expect(try history.plan(for: session).isEmpty)
  }

  /// The ordering bug the single-movement test above could not see.
  ///
  /// Sets used to come back ordered by `setOrdinal`. A warm-up and the first working set both sit at
  /// ordinal 0, so three movements of three sets returned as "ordinal 0 of all three, then ordinal 1
  /// of all three" -- and the screen, which groups consecutive runs, showed nine headings with the
  /// same three names repeating. Logging order is the only order this screen can be read in.
  @MainActor
  @Test("Three movements come back grouped in logging order, not interleaved by ordinal")
  func multipleMovementsKeepLoggingOrder() throws {
    let (db, logger, history, _) = try fixture()
    let bench = try exercise(db, "barbell-bench-press")
    let incline = try exercise(db, "incline-dumbbell-press")
    let pushdown = try exercise(db, "cable-triceps-pushdown")

    let session = try logger.startSession(at: now)
    var minute = 0.0
    /// Logged the way a lifter actually trains: all of one movement, then all of the next.
    func block(_ exercise: ExerciseID, kg: Double, warmup: Bool) throws {
      if warmup {
        minute += 3
        _ = try logger.logSet(
          sessionID: session, exerciseID: exercise,
          draft: SetEntryDraft(weightKg: kg / 2, reps: 12), setOrdinal: 0,
          isWarmup: true, at: now.addingTimeInterval(minute * 60)
        )
      }
      for ordinal in 0..<3 {
        minute += 3
        _ = try logger.logSet(
          sessionID: session, exerciseID: exercise,
          draft: SetEntryDraft(weightKg: kg, reps: 8), setOrdinal: ordinal,
          isWarmup: false, at: now.addingTimeInterval(minute * 60)
        )
      }
    }
    try block(bench, kg: 84, warmup: true)
    try block(incline, kg: 30, warmup: false)
    try block(pushdown, kg: 25, warmup: false)
    try logger.finishSession(session, at: now.addingTimeInterval(minute * 60 + 60))

    let sets = try history.sets(in: session)
    #expect(sets.count == 10)

    // Each movement occupies one contiguous run. Collapsing consecutive equal names must leave
    // exactly three -- ordering by `setOrdinal` left nine.
    var runs: [String] = []
    for set in sets where runs.last != set.exerciseName { runs.append(set.exerciseName) }
    #expect(runs == ["Barbell Bench Press", "Incline Dumbbell Press", "Cable Triceps Pushdown"])

    // And the warm-up still leads its own movement rather than floating to the front of the session.
    #expect(sets.first?.isWarmup == true)
    #expect(sets.first?.exerciseName == "Barbell Bench Press")
  }
}
