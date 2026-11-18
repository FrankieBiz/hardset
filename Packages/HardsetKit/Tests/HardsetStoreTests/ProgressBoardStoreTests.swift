import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The progress board reads every trained movement, once per machine")
struct ProgressBoardStoreTests {
  let now = Date(timeIntervalSince1970: 14_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func exercise(
    _ database: any DatabaseWriter, _ name: String, muscle: String = "unknown",
    modality: String = "machine", notes: String = "", archived: Bool = false
  ) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(
          id: id.rawValue, name: name, modality: modality, primaryMuscle: muscle, notes: notes,
          isArchived: archived)
      }
      .execute(db)
    }
    return id
  }

  private func machine(
    _ database: any DatabaseWriter, _ name: String, brand: String = "", step: Double? = nil
  ) throws -> MachineID {
    let gym = UUID()
    let id = MachineID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: gym, name: "Gym \(name)") }.execute(db)
      try Machine.insert {
        Machine.Draft(id: id.rawValue, gymID: gym, name: name, brand: brand, stackIncrementKg: step)
      }
      .execute(db)
    }
    return id
  }

  /// A finished session of working sets, `daysAgo` days before `now`.
  private func train(
    _ database: any DatabaseWriter, _ exercise: ExerciseID, machine: MachineID? = nil,
    sets: [(Double, Int)], daysAgo: Double
  ) throws {
    let store = LoggerStore(database: database)
    let date = now.addingTimeInterval(-daysAgo * 86_400)
    let id = try store.startSession(at: date)
    for (index, set) in sets.enumerated() {
      _ = try store.logSet(
        sessionID: id, exerciseID: exercise, machineID: machine,
        draft: SetEntryDraft(weightKg: set.0, reps: set.1), setOrdinal: index,
        at: date.addingTimeInterval(Double(index) * 60)
      )
    }
    try store.finishSession(id, at: date.addingTimeInterval(3600))
  }

  @Test("Movements are grouped by their body part, with untagged ones last")
  func boardGroupsByBodyPart() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press", muscle: "chest")
    let row = try exercise(database, "Lat Pulldown", muscle: "lats")
    let mystery = try exercise(database, "Mystery Lift")
    for lift in [press, row, mystery] { try train(database, lift, sets: [(40, 10)], daysAgo: 3) }

    let board = try await ProgressBoardStore(database: database).loadBoard()

    #expect(board.sections.map(\.category) == [.chest, .back, nil])
    #expect(board.sections.map { $0.rows.map(\.exerciseName) }
      == [["Chest Press"], ["Lat Pulldown"], ["Mystery Lift"]])
  }

  @Test("One movement on two machines is two rows, each with its own trend")
  func boardKeepsMachinesSeparate() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press", muscle: "chest")
    let hammer = try machine(database, "Chest Press", brand: "Hammer")
    let life = try machine(database, "Chest Press", brand: "Life Fitness")
    try train(database, press, machine: hammer, sets: [(40, 10)], daysAgo: 7)
    try train(database, press, machine: life, sets: [(80, 10)], daysAgo: 2)

    let board = try await ProgressBoardStore(database: database).loadBoard()

    let rows = try #require(board.sections.first).rows
    #expect(rows.count == 2)
    #expect(rows.map(\.machineName) == ["Life Fitness Chest Press", "Hammer Chest Press"])
    #expect(rows.map { $0.trend.sparkline } != [[], []])
    #expect(Set(rows.map(\.id)).count == 2)
  }

  @Test("A movement with no machine is still a row, labelled by having none")
  func freeWeightRowHasNoMachineName() async throws {
    let database = try migratedDatabase()
    let squat = try exercise(database, "Squat", muscle: "quadriceps", modality: "barbell")
    try train(database, squat, sets: [(100, 5)], daysAgo: 1)

    let board = try await ProgressBoardStore(database: database).loadBoard()

    let row = try #require(board.sections.first?.rows.first)
    #expect(row.machineName == nil)
    #expect(board.sections.first?.category == .quads)
  }

  @Test("Imported and archived movements are left off the board")
  func boardExcludesImportedAndArchived() async throws {
    let database = try migratedDatabase()
    let kept = try exercise(database, "Chest Press", muscle: "chest")
    let imported = try exercise(
      database, "Bench (Imported • Strong)", muscle: "chest",
      notes: "Imported • Unevaluated Machine. ")
    let archived = try exercise(database, "Old Lift", muscle: "chest", archived: true)
    for lift in [kept, imported, archived] { try train(database, lift, sets: [(40, 10)], daysAgo: 2) }

    let board = try await ProgressBoardStore(database: database).loadBoard()

    #expect(board.sections.flatMap(\.rows).map(\.exerciseName) == ["Chest Press"])
  }

  @Test("Warm-ups never reach a trend")
  func warmupsAreNotTrained() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press", muscle: "chest")
    let store = LoggerStore(database: database)
    let id = try store.startSession(at: now.addingTimeInterval(-86_400))
    _ = try store.logSet(
      sessionID: id, exerciseID: press, draft: SetEntryDraft(weightKg: 20, reps: 12),
      setOrdinal: 0, isWarmup: true, at: now.addingTimeInterval(-86_000))
    try store.finishSession(id, at: now.addingTimeInterval(-82_000))

    let board = try await ProgressBoardStore(database: database).loadBoard()

    #expect(board == ProgressBoard.empty)
  }

  @Test("Most improved holds at most three movements, the largest six-week gains first")
  func boardMostImprovedLimitedToThree() async throws {
    let database = try migratedDatabase()
    let gains: [(String, Double)] = [("A", 42.5), ("B", 50), ("C", 45), ("D", 41)]
    for (name, later) in gains {
      let lift = try exercise(database, name, muscle: "chest")
      try train(database, lift, sets: [(40, 10)], daysAgo: 42)
      try train(database, lift, sets: [(later, 10)], daysAgo: 0)
    }

    let board = try await ProgressBoardStore(database: database).loadBoard()

    #expect(board.mostImproved.map(\.exerciseName) == ["B", "C", "A"])
    #expect(board.mostImproved.allSatisfy { ($0.trend.sixWeekChange ?? 0) > 0 })
  }

  @Test("A movement that has not improved for three sessions is flagged as stalled")
  func boardCarriesStall() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press", muscle: "chest")
    let hammer = try machine(database, "Chest Press", step: 2.5)
    for daysAgo in [21.0, 14, 7, 0] {
      try train(database, press, machine: hammer, sets: [(40, 10)], daysAgo: daysAgo)
    }

    let board = try await ProgressBoardStore(database: database).loadBoard()

    #expect(board.sections.first?.rows.first?.trend.stalledSessions == 3)
    #expect(board.sections.first?.rows.first?.trend.sessionCount == 4)
  }

  @Test("A database with no workouts gives the empty board")
  func emptyDatabaseGivesEmptyBoard() async throws {
    let database = try migratedDatabase()

    let board = try await ProgressBoardStore(database: database).loadBoard()

    #expect(board == ProgressBoard.empty)
  }
}
