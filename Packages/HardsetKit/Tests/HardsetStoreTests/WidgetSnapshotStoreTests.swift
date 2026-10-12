import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The widget shows the last finished time on each machine, and nothing still being done")
struct WidgetSnapshotStoreTests {
  let now = Date(timeIntervalSince1970: 95_000_000)

  private struct Fixture {
    let db: any DatabaseWriter
    let logger: LoggerStore
    let gyms: GymStore
    let gym: GymID
    let exercises: [ExerciseID]
    let store: WidgetSnapshotStore
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let db = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(db)
    try CatalogSeeder(database: db).seed(now: now)
    let exercises = try db.read { try Exercise.limit(4).fetchAll($0) }.map { ExerciseID(rawValue: $0.id) }
    let gyms = GymStore(database: db)
    let gym = try gyms.createGym(name: "Iron Temple", now: now)
    return Fixture(
      db: db, logger: LoggerStore(database: db), gyms: gyms, gym: gym, exercises: exercises,
      store: WidgetSnapshotStore(database: db))
  }

  /// One session at `start`, logging `sets` as (exercise, machine, kg, reps, warm-up), finished
  /// unless `open`.
  @discardableResult
  private func session(
    _ f: Fixture, at start: Date, open: Bool = false,
    _ sets: [(ExerciseID, MachineID?, Double, Int, Bool)]
  ) throws -> SessionID {
    let id = try f.logger.startSession(gymID: f.gym, at: start)
    for (index, set) in sets.enumerated() {
      try f.logger.logSet(
        sessionID: id, exerciseID: set.0, machineID: set.1,
        draft: SetEntryDraft(weightKg: set.2, reps: set.3), isWarmup: set.4,
        at: start.addingTimeInterval(Double(index + 1) * 90))
    }
    if !open { try f.logger.finishSession(id, at: start.addingTimeInterval(3_000)) }
    return id
  }

  @Test("A movement with no dated set is left out, never shown as trained on a made-up date")
  func noDateNoEntry() {
    let key = ProgressionKey(exerciseID: ExerciseID(), machineID: nil)
    #expect(
      WidgetSnapshotStore.lastTime(key: key, sets: [], exerciseName: "Squat", machineName: nil)
        == nil)
  }

  @Test("With nothing finished, the snapshot is empty")
  func nothingYet() throws {
    let f = try fixture()
    let snapshot = try f.store.snapshot(unit: .kilograms, now: now)
    #expect(snapshot.lastWorkout == nil)
    #expect(snapshot.lastTimes.isEmpty)
    #expect(snapshot.unit == .kilograms)
    #expect(snapshot.version == WidgetSnapshot.currentVersion)
  }

  @Test("The last workout carries its totals and its honest length")
  func lastWorkoutTotals() throws {
    let f = try fixture()
    try session(f, at: now, [(f.exercises[0], nil, 60, 10, true), (f.exercises[0], nil, 100, 8, false),
      (f.exercises[0], nil, 100, 8, false)])
    let workout = try #require(try f.store.snapshot(unit: .pounds, now: now).lastWorkout)
    #expect(workout.workingSets == 2)
    #expect(workout.volumeKg == 1_600)
    #expect(workout.lengthSeconds == 3_000)
    #expect(workout.movementCount == 1)
  }

  /// Review Focus: the widget refreshes while a workout is open. Its half-done sets are not "last
  /// time", and it is not the last workout.
  @Test("An open workout is never last time, nor the last workout")
  func openWorkoutNeverLastTime() throws {
    let f = try fixture()
    let press = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    try session(f, at: now, [(f.exercises[0], press, 100, 8, false)])
    try session(f, at: now.addingTimeInterval(86_400), open: true,
      [(f.exercises[0], press, 120, 5, false), (f.exercises[1], nil, 40, 12, false)])

    let snapshot = try f.store.snapshot(unit: .kilograms, now: now.addingTimeInterval(90_000))
    #expect(snapshot.lastTimes.map(\.sets) == [[WidgetSnapshot.SetLine(weightKg: 100, reps: 8)]])
    #expect(snapshot.lastWorkout?.startedAt == now)
  }

  @Test("Warm-ups are not last time")
  func warmupsExcluded() throws {
    let f = try fixture()
    try session(f, at: now, [(f.exercises[0], nil, 40, 10, true), (f.exercises[0], nil, 100, 8, false)])
    let lastTime = try #require(try f.store.snapshot(unit: .kilograms, now: now).lastTimes.first)
    #expect(lastTime.sets == [WidgetSnapshot.SetLine(weightKg: 100, reps: 8)])
    #expect(lastTime.machineName == nil)
  }

  /// Review Focus: one movement on two machines, two of which share a name, are three entries,
  /// each with its own sets and a label of its own.
  @Test("Each machine keeps its own entry and its own label")
  func machinesStayApart() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let plainA = try f.gyms.createMachine(at: f.gym, name: "Leg Press", now: now)
    let plainB = try f.gyms.createMachine(at: f.gym, name: "Leg Press", now: now)
    try session(f, at: now, [(f.exercises[0], hammer, 110, 8, false), (f.exercises[0], plainA, 90, 8, false),
      (f.exercises[0], plainB, 80, 8, false)])

    let lastTimes = try f.store.snapshot(unit: .kilograms, now: now).lastTimes
    #expect(lastTimes.count == 3)
    #expect(Set(lastTimes.map(\.machineID)) == [hammer, plainA, plainB])
    let labels = Set(lastTimes.compactMap(\.machineName))
    #expect(labels == ["Hammer Strength Leg Press", "Leg Press", "Leg Press (2)"])
    let hammerSets = lastTimes.first { $0.machineID == hammer }?.sets
    #expect(hammerSets == [WidgetSnapshot.SetLine(weightKg: 110, reps: 8)])
  }

  @Test("A machine archived since keeps its name")
  func archivedMachineStillNamed() throws {
    let f = try fixture()
    let press = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Cybex", now: now)
    try session(f, at: now, [(f.exercises[0], press, 100, 8, false)])
    try f.gyms.archiveMachine(press)
    #expect(try f.store.snapshot(unit: .kilograms, now: now).lastTimes.first?.machineName == "Cybex Leg Press")
  }

  @Test("Most recently trained first, each from its own last session, at most three")
  func mostRecentFirstAndLimited() throws {
    let f = try fixture()
    try session(f, at: now, [(f.exercises[0], nil, 100, 8, false), (f.exercises[1], nil, 50, 10, false)])
    try session(f, at: now.addingTimeInterval(86_400),
      [(f.exercises[2], nil, 30, 12, false), (f.exercises[3], nil, 20, 15, false)])
    try session(f, at: now.addingTimeInterval(2 * 86_400), [(f.exercises[0], nil, 105, 6, false)])

    let lastTimes = try f.store.snapshot(unit: .kilograms, now: now).lastTimes
    #expect(lastTimes.map(\.exerciseID) == [f.exercises[0], f.exercises[3], f.exercises[2]])
    #expect(lastTimes.first?.sets == [WidgetSnapshot.SetLine(weightKg: 105, reps: 6)])
  }

  @Test("A workout left open overnight and finished has no length")
  func implausibleLengthUnknown() throws {
    let f = try fixture()
    let id = try f.logger.startSession(at: now)
    try f.logger.logSet(
      sessionID: id, exerciseID: f.exercises[0], draft: SetEntryDraft(weightKg: 60, reps: 10),
      at: now.addingTimeInterval(60))
    try f.logger.finishSession(id, at: now.addingTimeInterval(10 * 3_600))
    #expect(try f.store.snapshot(unit: .kilograms, now: now).lastWorkout?.lengthSeconds == nil)
  }
}
