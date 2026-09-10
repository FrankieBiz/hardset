import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The rotation line reads a recorded fact. These pin the recording, because a store that reported
/// "never trained" for a day trained yesterday would look exactly like a plan nobody had used.
@Suite("A plan knows when each of its days was last trained")
struct SplitRotationStoreTests {
  private let now = Date(timeIntervalSince1970: 18_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private struct Fixture {
    let database: any DatabaseWriter
    let splits: SplitStore
    let logger: LoggerStore
    let splitID: SplitID
    let push: SplitDayID
    let pull: SplitDayID
    let bench: ExerciseID
  }

  private func fixture() throws -> Fixture {
    let database = try migratedDatabase()
    let bench = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: bench.rawValue, name: "Bench Press") }.execute(db)
    }
    let splits = SplitStore(database: database)
    let splitID = try splits.createSplit(name: "Push / Pull", now: now)
    let push = try splits.addDay(to: splitID, name: "Push", now: now)
    let pull = try splits.addDay(to: splitID, name: "Pull", now: now)
    return Fixture(
      database: database,
      splits: splits,
      logger: LoggerStore(database: database),
      splitID: splitID,
      push: push,
      pull: pull,
      bench: bench
    )
  }

  /// Starts a workout attributed to `day` and finishes it, which is what the planner's
  /// "Start this day" button does end to end.
  private func trainDay(
    _ day: SplitDayID, in f: Fixture, startedAt: Date, finished: Bool = true
  ) throws -> SessionID {
    let id = try f.logger.startSession(splitDayID: day, at: startedAt)
    if finished {
      try f.logger.finishSession(id, at: startedAt.addingTimeInterval(3_600))
    }
    return id
  }

  /// The hop the whole feature rests on. Both of these used to be dropped between the planner and
  /// the session: the workout could not be attributed back to its day, and it opened nameless even
  /// though the lifter had named that day themselves.
  @MainActor
  @Test("Starting a plan day carries its name and its identity onto the session")
  func startingADayNamesAndAttributesTheSession() throws {
    let f = try fixture()
    let day = PlannedDayStart(
      dayID: f.push,
      name: "Push",
      exercises: [PlannedExercise(exerciseID: f.bench, exerciseName: "Bench Press")]
    )

    let coordinator = try SessionCoordinator.start(
      store: f.logger,
      title: day.name,
      splitDayID: day.dayID,
      plan: day.exercises,
      now: { self.now }
    )

    let row = try f.database.read { db in
      try Session.where { $0.id.eq(coordinator.sessionID.rawValue) }.fetchOne(db)
    }
    #expect(row?.splitDayID == f.push.rawValue)
    #expect(row?.title == "Push")
    // The live screen reads the coordinator, not the row. `start` used to leave this empty while
    // the row said "Push", so the workout claimed to be unnamed.
    #expect(coordinator.title == "Push")
  }

  @Test("A finished workout started from a day is what makes that day trained")
  func recordsTheDayTrained() throws {
    let f = try fixture()
    #expect(try f.splits.lastTrainedByDay(in: f.splitID).isEmpty)

    let trainedAt = now.addingTimeInterval(-6 * 86_400)
    _ = try trainDay(f.push, in: f, startedAt: trainedAt)

    let report = try f.splits.lastTrainedByDay(in: f.splitID)
    #expect(report[f.push] == trainedAt)
    // Absent, not a placeholder date. "Never" and "a long time ago" are different answers.
    #expect(report[f.pull] == nil)
  }

  @Test("The most recent of several workouts on a day is the one reported")
  func reportsTheLatest() throws {
    let f = try fixture()
    let older = now.addingTimeInterval(-20 * 86_400)
    let newer = now.addingTimeInterval(-2 * 86_400)
    // Written oldest-last, so a store that returned the first row it saw would fail here.
    _ = try trainDay(f.push, in: f, startedAt: newer)
    _ = try trainDay(f.push, in: f, startedAt: older)

    #expect(try f.splits.lastTrainedByDay(in: f.splitID)[f.push] == newer)
  }

  /// An open workout is already on screen as the live session, and a started-then-discarded one is
  /// not training that happened.
  @Test("An unfinished workout does not make a day trained")
  func ignoresOpenSessions() throws {
    let f = try fixture()
    _ = try trainDay(f.push, in: f, startedAt: now.addingTimeInterval(-86_400), finished: false)

    #expect(try f.splits.lastTrainedByDay(in: f.splitID).isEmpty)
  }

  @Test("A workout started from the Train tab belongs to no day")
  func unattributedSessionsAreIgnored() throws {
    let f = try fixture()
    let id = try f.logger.startSession(at: now.addingTimeInterval(-86_400))
    try f.logger.finishSession(id, at: now)

    #expect(try f.splits.lastTrainedByDay(in: f.splitID).isEmpty)
  }

  @Test("One plan's training never counts toward another plan's days")
  func scopedToOnePlan() throws {
    let f = try fixture()
    let otherPlan = try f.splits.createSplit(name: "Full body", now: now)
    let otherDay = try f.splits.addDay(to: otherPlan, name: "Everything", now: now)
    _ = try trainDay(otherDay, in: f, startedAt: now.addingTimeInterval(-86_400))

    #expect(try f.splits.lastTrainedByDay(in: f.splitID).isEmpty)
    #expect(try f.splits.lastTrainedByDay(in: otherPlan)[otherDay] != nil)
  }

  /// The invariant behind `ON DELETE SET NULL`. Removing a day from a plan reshapes the plan; it
  /// must not delete the training that happened on it.
  @Test("Deleting a day keeps the workout and only forgets which day it was")
  func deletingADayKeepsItsWorkouts() throws {
    let f = try fixture()
    let sessionID = try trainDay(f.push, in: f, startedAt: now.addingTimeInterval(-86_400))

    try f.splits.deleteDay(f.push)

    let survivor = try f.database.read { db in
      try Session.where { $0.id.eq(sessionID.rawValue) }.fetchOne(db)
    }
    #expect(survivor != nil)
    #expect(survivor?.splitDayID == nil)
    #expect(try f.splits.lastTrainedByDay(in: f.splitID).isEmpty)
  }
}
