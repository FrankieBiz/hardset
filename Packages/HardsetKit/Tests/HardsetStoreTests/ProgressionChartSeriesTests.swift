import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Every machine keeps its own line, even when two share a name")
struct ProgressionChartSeriesTests {
  let now = Date(timeIntervalSince1970: 41_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, ExerciseID, GymID) {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    let gym = GymID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
      try Gym.insert { Gym.Draft(id: gym.rawValue, name: "Gym") }.execute(db)
    }
    return (database, LoggerStore(database: database), exercise, gym)
  }

  private func machine(
    _ database: any DatabaseWriter, _ gym: GymID, id: String, name: String, brand: String = ""
  ) throws -> MachineID {
    let machine = MachineID(rawValue: UUID(uuidString: id)!)
    try database.write { db in
      try Machine.insert {
        Machine.Draft(id: machine.rawValue, gymID: gym.rawValue, name: name, brand: brand)
      }
      .execute(db)
    }
    return machine
  }

  private func session(
    _ logger: LoggerStore, _ exercise: ExerciseID, _ machine: MachineID, _ weight: Double,
    daysAgo: Double
  ) throws {
    let start = now.addingTimeInterval(-daysAgo * 86_400)
    let id = try logger.startSession(at: start)
    _ = try logger.logSet(
      sessionID: id, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: 8), at: start.addingTimeInterval(60))
    try logger.finishSession(id, at: start.addingTimeInterval(1_800))
  }

  /// Review Focus: two unbranded "Leg Press" stacks were one label, and the chart keys a line by
  /// its label, so it drew one line through two machines.
  @Test("Two machines that share a name get two labels, numbered in a fixed order")
  func sameNamedMachinesStayApart() throws {
    let (database, logger, exercise, gym) = try fixture()
    let first = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000A", name: "Leg Press")
    let second = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000B", name: "Leg Press")
    try session(logger, exercise, second, 120, daysAgo: 1)
    try session(logger, exercise, first, 100, daysAgo: 7)

    let lines = try ProgressionStore(database: database).history(for: exercise).chartSeries()
    #expect(lines.count == 2)
    #expect(Set(lines.map(\.label)).count == 2)
    // Most recent first, and numbered by machine id rather than by recency, so a label is stable.
    #expect(lines.map(\.label) == ["Leg Press (2)", "Leg Press"])
    #expect(lines[0].points.map(\.heaviestLoadKg) == [120])
  }

  @Test("A series is labelled brand first, as the machine is everywhere else")
  func brandLeads() throws {
    let (database, logger, exercise, gym) = try fixture()
    let hammer = try machine(
      database, gym, id: "00000000-0000-0000-0000-00000000000C", name: "Leg Press",
      brand: "Hammer Strength")
    let cybex = try machine(
      database, gym, id: "00000000-0000-0000-0000-00000000000D", name: "Leg Press", brand: "Cybex")
    try session(logger, exercise, hammer, 100, daysAgo: 7)
    try session(logger, exercise, cybex, 90, daysAgo: 1)

    let lines = try ProgressionStore(database: database).history(for: exercise).chartSeries()
    #expect(lines.map(\.label) == ["Cybex Leg Press", "Hammer Strength Leg Press"])
  }

  @Test("The machine used most recently leads, even when another was used more")
  func mostRecentFirst() throws {
    let (database, logger, exercise, gym) = try fixture()
    let hammer = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000E", name: "Hammer")
    let cybex = try machine(database, gym, id: "00000000-0000-0000-0000-00000000000F", name: "Cybex")
    try session(logger, exercise, hammer, 100, daysAgo: 21)
    try session(logger, exercise, hammer, 105, daysAgo: 14)
    try session(logger, exercise, cybex, 80, daysAgo: 1)

    let history = try ProgressionStore(database: database).history(for: exercise)
    // The analyser orders by sessions logged; the chart orders by recency.
    #expect(history.label(for: history.series[0].key) == "Hammer")
    #expect(history.chartSeries().map(\.label) == ["Cybex", "Hammer"])
  }
}
