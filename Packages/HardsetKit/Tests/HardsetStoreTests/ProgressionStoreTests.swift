import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Load history reads per machine from the database")
struct ProgressionStoreTests {
  let now = Date(timeIntervalSince1970: 14_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ProgressionStore, ExerciseID, GymID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    let gym = GymID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
      try Gym.insert { Gym.Draft(id: gym.rawValue, name: "Gym") }.execute(db)
    }
    return (database, LoggerStore(database: database), ProgressionStore(database: database), exercise, gym)
  }

  private func machine(
    _ database: any DatabaseWriter, _ gym: GymID, _ name: String
  ) throws -> MachineID {
    let id = MachineID()
    try database.write { db in
      try Machine.insert {
        Machine.Draft(id: id.rawValue, gymID: gym.rawValue, name: name)
      }
      .execute(db)
    }
    return id
  }

  private func session(
    _ store: LoggerStore, _ exercise: ExerciseID, _ machine: MachineID?,
    sets: [(Double, Int)], at date: Date, isWarmup: Bool = false
  ) throws {
    let id = try store.startSession(at: date)
    for (index, set) in sets.enumerated() {
      _ = try store.logSet(
        sessionID: id, exerciseID: exercise, machineID: machine,
        draft: SetEntryDraft(weightKg: set.0, reps: set.1), setOrdinal: index,
        isWarmup: isWarmup, at: date.addingTimeInterval(Double(index) * 60)
      )
    }
    try store.finishSession(id, at: date.addingTimeInterval(3600))
  }

  /// The differentiator, end to end: two machines stay two lines.
  @Test("Two machines produce two labelled series")
  func twoMachines() throws {
    let (database, logger, progression, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, "Hammer Strength")
    let cybex = try machine(database, gym, "Cybex")

    try session(logger, exercise, hammer, sets: [(100, 8), (100, 8)], at: now.addingTimeInterval(-14 * 86_400))
    try session(logger, exercise, hammer, sets: [(105, 8)], at: now.addingTimeInterval(-7 * 86_400))
    try session(logger, exercise, cybex, sets: [(80, 8)], at: now.addingTimeInterval(-86_400))

    let history = try progression.history(for: exercise)
    #expect(history.series.count == 2)
    // Most-trained machine leads.
    #expect(history.label(for: history.series[0].key) == "Hammer Strength")
    #expect(history.series[0].points.count == 2)
    #expect(history.label(for: history.series[1].key) == "Cybex")
  }

  @Test("The machine switch is detected with its load delta")
  func switchDetected() throws {
    let (database, logger, progression, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, "Hammer Strength")
    let cybex = try machine(database, gym, "Cybex")

    try session(logger, exercise, hammer, sets: [(100, 8)], at: now.addingTimeInterval(-7 * 86_400))
    try session(logger, exercise, cybex, sets: [(75, 8)], at: now.addingTimeInterval(-86_400))

    let history = try progression.history(for: exercise)
    #expect(history.machineChanges.count == 1)
    #expect(history.machineChanges[0].heaviestLoadDeltaKg == -25)
    #expect(history.machineChanges[0].explanation.contains("difference between the machines"))
  }

  @Test("Warm-ups never reach the history")
  func warmupsExcluded() throws {
    let (database, logger, progression, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, "Hammer Strength")

    try session(logger, exercise, hammer, sets: [(200, 1)], at: now.addingTimeInterval(-2 * 86_400), isWarmup: true)
    try session(logger, exercise, hammer, sets: [(100, 8)], at: now.addingTimeInterval(-86_400))

    let history = try progression.history(for: exercise)
    #expect(history.series.count == 1)
    #expect(history.series[0].points.count == 1)
    // The 200 kg "warm-up" must not become the peak of the chart.
    #expect(history.series[0].points[0].heaviestLoadKg == 100)
  }

  @Test("Free-weight work is a series labelled as such")
  func freeWeight() throws {
    let (_, logger, progression, exercise, _) = try fixture()
    try session(logger, exercise, nil, sets: [(100, 5)], at: now.addingTimeInterval(-86_400))

    let history = try progression.history(for: exercise)
    #expect(history.series.count == 1)
    #expect(history.label(for: history.series[0].key) == "Free weight")
  }

  /// A high-rep history has no estimate, and the chart must be told so rather than shown zero.
  @Test("A high-rep history carries no estimate")
  func noEstimate() throws {
    let (database, logger, progression, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, "Hammer Strength")
    try session(logger, exercise, hammer, sets: [(60, 25), (60, 22)], at: now.addingTimeInterval(-86_400))

    let history = try progression.history(for: exercise)
    #expect(history.series[0].hasNoEstimates)
    #expect(history.series[0].points[0].bestEstimatedOneRepMaxKg == nil)
    #expect(history.series[0].points[0].heaviestLoadKg == 60)
  }

  @Test("An exercise never logged has an empty history rather than an error")
  func emptyHistory() throws {
    let (_, _, progression, exercise, _) = try fixture()
    let history = try progression.history(for: exercise)
    #expect(history.isEmpty)
    #expect(history.machineChanges.isEmpty)
  }

  /// A deleted machine still has logged sets, and they must not vanish from the chart.
  @Test("A deleted machine's series is labelled rather than dropped")
  func deletedMachine() throws {
    let (database, logger, progression, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, "Hammer Strength")
    try session(logger, exercise, hammer, sets: [(100, 8)], at: now.addingTimeInterval(-86_400))

    // ON DELETE SET NULL on loggedSets.machineID would orphan the sets; the row is archived
    // instead, which is what the app does. Either way the series must survive.
    try database.write { db in
      try Machine.where { $0.id.eq(hammer.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }

    let history = try progression.history(for: exercise)
    #expect(history.series.count == 1)
    #expect(history.series[0].points.count == 1)
    // Still named: archiving the machine does not un-perform the sets.
    #expect(history.label(for: history.series[0].key) == "Hammer Strength")
  }
}
