import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The rest the daily app actually runs.
///
/// `HardsetApp` passes no fixed rest length, so the coordinator's `restAfterSet` is nil in
/// production and the only rest that starts after a set is the one the lifter last chose for that
/// movement. That decision, and ending the rest when the workout closes, used to live in the
/// SwiftUI screen, where no test could reach it; the tests that did exist covered a fixed-length
/// path nothing in the app uses. These go through the coordinator, and through the root model that
/// builds every coordinator the app has, the way the app builds them.
@Suite("A rest starts when the lifter's own choice says it should, and ends when the workout does")
@MainActor
struct SessionRestTests {
  let start = Date(timeIntervalSince1970: 7_000_000)

  private func migratedDatabase() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(_ database: DatabaseQueue, name: String = "Chest Press") throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  /// A preferences store of its own, so a test never reads or writes the developer's defaults.
  private func scratchRest() -> RestPreferences {
    RestPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  }

  /// What the rest timer was asked to do, as the app's own wiring would see it.
  private final class TimerSpy {
    var starts: [(duration: Duration, metadata: RestMetadata)] = []
    var cancels = 0
  }

  /// A live workout built the way the app builds one: no fixed rest length, the lifter's
  /// preferences, and the timer hooks.
  private func liveWorkout(
    plannedSets: Int = 2, restPreferences: RestPreferences? = nil, restAfterSet: Duration? = nil,
    spy: TimerSpy, database: DatabaseQueue, exercise: ExerciseID,
    now: (@Sendable () -> Date)? = nil
  ) throws -> SessionCoordinator {
    let fixedStart = start
    return try SessionCoordinator.start(
      store: LoggerStore(database: database),
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Chest Press", plannedSets: plannedSets)],
      now: now ?? { fixedStart }, restAfterSet: restAfterSet,
      onStartRest: { spy.starts.append(($0, $1)) },
      restPreferences: restPreferences, onCancelRest: { spy.cancels += 1 }
    )
  }

  private func log(_ live: SessionCoordinator, slot: Int = 0, exercise: Int = 0, kg: Double = 40, reps: Int = 10)
    -> Bool
  {
    let state = live.exercises[exercise]
    live.exercises[exercise].slots[slot].draft = SetEntryDraft(weightKg: kg, reps: reps)
    return live.logSet(slotID: state.slots[slot].id, inExercise: state.id)
  }

  // MARK: - After a set

  @Test("A working set starts the rest remembered for its movement, with nothing fixed in the app")
  func rememberedRestStartsAfterAWorkingSet() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)

    #expect(log(live))

    #expect(spy.starts.map(\.duration) == [.seconds(75)])
    #expect(spy.starts.first?.metadata.exerciseName == "Chest Press")
    #expect(spy.starts.first?.metadata.setOrdinal == 1)
    #expect(spy.starts.first?.metadata.plannedSets == 2)
    #expect(live.restExerciseID == live.exercises[0].id)
    #expect(live.restMetadata == spy.starts.first?.metadata)
  }

  @Test("A movement with no remembered rest starts none: the app never invents a length")
  func noRememberedRestStartsNone() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: scratchRest(), spy: spy, database: database, exercise: press)

    #expect(log(live))

    #expect(spy.starts.isEmpty)
    #expect(live.restExerciseID == nil)
    #expect(live.restMetadata == nil)
  }

  @Test("A warm-up starts no rest, and the working set after it starts one for set one")
  func warmUpStartsNoRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(60), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)
    live.addSet(inExercise: live.exercises[0].id, isWarmup: true)
    let warmUp = try #require(live.exercises[0].slots.firstIndex { $0.isWarmup })
    let working = try #require(live.exercises[0].slots.firstIndex { !$0.isWarmup })

    #expect(log(live, slot: warmUp, kg: 20, reps: 10))
    #expect(spy.starts.isEmpty)
    #expect(log(live, slot: working))
    #expect(spy.starts.count == 1)
    #expect(spy.starts.first?.metadata.setOrdinal == 1)
  }

  @Test("A set that is not saved starts no rest")
  func failedSaveStartsNoRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)
    try database.write { db in
      try db.execute(sql: """
        CREATE TEMP TRIGGER refuse_set BEFORE INSERT ON loggedSets BEGIN
          SELECT RAISE(ABORT, 'injected set save failure');
        END
        """)
    }

    #expect(!log(live))

    #expect(spy.starts.isEmpty)
    #expect(live.restExerciseID == nil)
  }

  @Test("The lifter's remembered length wins over a fixed one, and a fixed one covers a movement with none")
  func rememberedRestWinsOverTheFixedLength() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    let spy = TimerSpy()
    let live = try liveWorkout(
      restPreferences: rest, restAfterSet: .seconds(90), spy: spy, database: database, exercise: press)

    #expect(log(live, slot: 0))
    rest.remember(.seconds(45), for: press)
    #expect(log(live, slot: 1))

    #expect(spy.starts.map(\.duration) == [.seconds(90), .seconds(45)])
  }

  // MARK: - Choosing a rest

  @Test("Starting a rest from the card remembers the choice for the movement and follows it")
  func choosingARestRemembersIt() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)
    #expect(log(live))
    #expect(live.lastRestByCard.isEmpty)

    live.startRest(.seconds(120), afterExercise: live.exercises[0].id)

    #expect(spy.starts.map(\.duration) == [.seconds(120)])
    #expect(spy.starts.first?.metadata.setOrdinal == 1)
    #expect(rest.lastRest(for: press) == .seconds(120))
    #expect(live.lastRestByCard[live.exercises[0].id] == .seconds(120))
    #expect(live.restExerciseID == live.exercises[0].id)

    // And that choice is what the next working set starts.
    #expect(log(live, slot: 1))
    #expect(spy.starts.map(\.duration) == [.seconds(120), .seconds(120)])
    #expect(spy.starts.last?.metadata.setOrdinal == 2)
  }

  @Test("Choosing the next rest on the rest bar remembers it without starting one")
  func choosingTheNextRestStartsNothing() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)

    live.rememberRest(.seconds(150), forExercise: live.exercises[0].id)

    #expect(spy.starts.isEmpty)
    #expect(rest.lastRest(for: press) == .seconds(150))
    #expect(live.lastRestByCard[live.exercises[0].id] == .seconds(150))
    #expect(log(live))
    #expect(spy.starts.map(\.duration) == [.seconds(150)])
  }

  @Test("Skipping the rest cancels the timer and forgets which movement it followed")
  func skippingEndsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)
    #expect(log(live))

    live.endRest()

    #expect(spy.cancels == 1)
    #expect(live.restExerciseID == nil)
    #expect(live.restMetadata == nil)
  }

  // MARK: - Re-logging

  @Test("Logging a row that is already saved changes nothing: no new rest, the record card stays")
  func reLoggingASavedSetChangesNothing() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let store = LoggerStore(database: database)
    let previous = try store.startSession(at: start.addingTimeInterval(-1000))
    _ = try store.logSet(
      sessionID: previous, exerciseID: press, draft: SetEntryDraft(weightKg: 30, reps: 8),
      at: start.addingTimeInterval(-900))
    try store.finishSession(previous, at: start.addingTimeInterval(-500))
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)
    let state = live.exercises[0]
    #expect(log(live, kg: 40, reps: 10))
    let earned = live.lastRecords
    #expect(!earned.isEmpty)
    #expect(live.lastRecordsExerciseName == "Chest Press")
    #expect(spy.starts.count == 1)

    // The same row again, as a stale tap or an accessibility action would send it.
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))

    #expect(live.lastRecords == earned)
    #expect(live.lastRecordsExerciseName == "Chest Press")
    #expect(spy.starts.count == 1)
    #expect(try store.sets(in: live.sessionID).count == 1)
  }

  // MARK: - Ending the workout

  @Test("Finishing cancels the rest, once the workout is really closed")
  func finishCancelsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(
      restPreferences: rest, spy: spy, database: database, exercise: press,
      now: { Date(timeIntervalSince1970: 7_000_600) })
    #expect(log(live))
    #expect(spy.cancels == 0)

    try live.finish()

    #expect(live.isFinished)
    #expect(spy.cancels == 1)
    #expect(live.restExerciseID == nil)
  }

  @Test("Finishing at the last set cancels the rest too")
  func finishAtLastSetCancelsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let spy = TimerSpy()
    let live = try liveWorkout(
      restPreferences: scratchRest(), spy: spy, database: database, exercise: press,
      now: { Date(timeIntervalSince1970: 7_000_600) })
    #expect(log(live))

    try live.finish(at: try #require(live.lastLoggedAt))

    #expect(spy.cancels == 1)
  }

  @Test("A finish the store refuses leaves the rest running")
  func refusedFinishKeepsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let clock = ClockBox(Date(timeIntervalSince1970: 7_000_600))
    let live = try liveWorkout(
      restPreferences: rest, spy: spy, database: database, exercise: press, now: { clock.value })
    #expect(log(live))
    // The device clock now reads earlier than the workout's start, which the store refuses.
    clock.value = Date(timeIntervalSince1970: 6_000_000)

    #expect(throws: SessionTimelineError.finishedBeforeStart) { try live.finish() }

    #expect(!live.isFinished)
    #expect(spy.cancels == 0)
    #expect(live.restExerciseID == live.exercises[0].id)
  }

  @Test("A finish refused before it reaches the store leaves the rest running")
  func failedFinishKeepsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let spy = TimerSpy()
    let live = try liveWorkout(
      restPreferences: scratchRest(), spy: spy, database: database, exercise: press,
      now: { Date(timeIntervalSince1970: 7_000_600) })
    #expect(log(live))
    // An end before the work it contains is refused, so nothing closes.
    #expect(throws: SessionCoordinatorError.invalidFinishTime) {
      try live.finish(at: Date(timeIntervalSince1970: 6_000_000))
    }

    #expect(!live.isFinished)
    #expect(spy.cancels == 0)
  }

  @Test("A workout already closed elsewhere still ends the rest")
  func alreadyFinishedEndsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let spy = TimerSpy()
    let live = try liveWorkout(
      restPreferences: scratchRest(), spy: spy, database: database, exercise: press,
      now: { Date(timeIntervalSince1970: 7_000_600) })
    #expect(log(live))
    try LoggerStore(database: database).finishSession(
      live.sessionID, at: Date(timeIntervalSince1970: 7_000_650))

    try live.finish()

    #expect(live.isFinished)
    #expect(spy.cancels == 1)
  }

  @Test("Discarding cancels the rest")
  func discardCancelsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let rest = scratchRest()
    rest.remember(.seconds(75), for: press)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: rest, spy: spy, database: database, exercise: press)
    #expect(log(live))

    try live.discard()

    #expect(live.isDiscarded)
    #expect(spy.cancels == 1)
  }

  @Test("A discard refused because the workout is already finished still ends the rest")
  func refusedDiscardOfAFinishedWorkoutEndsTheRest() throws {
    let database = try migratedDatabase()
    let press = try seedExercise(database)
    let spy = TimerSpy()
    let live = try liveWorkout(restPreferences: scratchRest(), spy: spy, database: database, exercise: press)
    #expect(log(live))
    try LoggerStore(database: database).finishSession(
      live.sessionID, at: start.addingTimeInterval(300))

    #expect(throws: LoggerStoreError.sessionClosed) { try live.discard() }

    #expect(live.isFinished)
    #expect(spy.cancels == 1)
  }

  private final class ClockBox: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
  }
}
