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
    modality: String = "machine", notes: String = "", archived: Bool = false, curated: Bool = false
  ) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(
          id: id.rawValue, name: name, isCurated: curated, modality: modality, primaryMuscle: muscle, notes: notes,
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

  @Test("Legacy imported movements remain visible while archived movements stay retired")
  func boardIncludesImportedExcludesArchived() async throws {
    let database = try migratedDatabase()
    let kept = try exercise(database, "Chest Press", muscle: "chest")
    let imported = try exercise(
      database, "Bench (Imported • Strong)", muscle: "chest",
      notes: "Imported • Unevaluated Machine. ")
    let archived = try exercise(database, "Old Lift", muscle: "chest", archived: true)
    for lift in [kept, imported, archived] { try train(database, lift, sets: [(40, 10)], daysAgo: 2) }

    let board = try await ProgressBoardStore(database: database).loadBoard()

    let rows = board.sections.flatMap(\.rows)
    #expect(Set(rows.map(\.exerciseName)) == ["Chest Press", "Bench (Imported • Strong)"])
    #expect(rows.first { $0.id.exerciseID == imported }?.machineName == "Imported · machine not recorded")
  }

  @Test("Strong history matches two live movements, creates only the unknown one, and stays separate")
  func strongImportMatchesMovements() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press", muscle: "chest", curated: true)
    let pull = try exercise(database, "Lat Pulldown", muscle: "lats", curated: true)
    let hammer = try machine(database, "Hammer")
    let life = try machine(database, "Life")
    try train(database, press, machine: hammer, sets: [(80, 8)], daysAgo: 7)
    try train(database, press, machine: life, sets: [(100, 8)], daysAgo: 2)
    let url = try #require(Bundle.module.url(forResource: "strong-progress", withExtension: "csv", subdirectory: "Fixtures"))
    let csv = try String(contentsOf: url, encoding: .utf8)
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms, timeZone: TimeZone(secondsFromGMT: 0)!)
    let transfer = DataTransferStore(database: database)
    #expect(try await transfer.importWorkouts(preview) == 6)
    let stored = try await database.read { db in
      (try Exercise.fetchAll(db), try LoggedSet.fetchAll(db).filter { $0.machineID == nil })
    }
    #expect(stored.0.count == 3)
    #expect(stored.1.filter { $0.exerciseID == press.rawValue }.count == 2)
    #expect(stored.1.filter { $0.exerciseID == pull.rawValue }.count == 2)
    await #expect(throws: WorkoutImportError.alreadyImported) { try await transfer.importWorkouts(preview) }
    #expect(try await database.read { try LoggedSet.fetchAll($0).count } == 8)
    let board = try await ProgressBoardStore(database: database).loadBoard()
    let pressRows = board.sections.flatMap(\.rows).filter { $0.id.exerciseID == press }
    #expect(pressRows.count == 3)
    #expect(pressRows.contains { $0.machineName == "Imported · machine not recorded" })
    let chart = try await ProgressionStore(database: database).loadHistory(for: press)
    #expect(chart.series.count == 3)
    #expect(chart.series.contains { chart.label(for: $0.key) == "Imported · machine not recorded" && $0.points.count == 2 })
  }

  @Test("Matching a custom movement never seeds native free-weight comparisons")
  func importedAndNativeNoMachineStaySeparate() async throws {
    let database = try migratedDatabase()
    let seeder = CatalogSeeder(database: database)
    let lift = try seeder.createCustomExercise(named: "Custom Press")
    let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n"
      + "2026-09-20 10:00:00,Push,1h,custom  PRESS,1,200,8\n"
    let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms)
    _ = try await DataTransferStore(database: database).importWorkouts(preview)
    let logger = LoggerStore(database: database)
    let key = ProgressionKey(exerciseID: lift.id)
    #expect(try logger.priorPerformanceSnapshot(for: [key], asOf: now).prior(for: key) == nil)
    let date = preview.sessions[0].finishedAt.addingTimeInterval(86_400)
    let first = try logger.startSession(at: date)
    let result = try logger.logSet(sessionID: first, exerciseID: lift.id,
      draft: SetEntryDraft(weightKg: 40, reps: 8), recordIncrement: nil, at: date)
    #expect(result.records.isEmpty)
    try logger.finishSession(first, at: date.addingTimeInterval(3600))
    let receipt = try await ReceiptStore(database: database).load(first)
    #expect(receipt.scorecard?.entries.first?.outcome == .firstTime)
    let history = try await ProgressionStore(database: database).loadHistory(for: lift.id)
    #expect(history.series.count == 2)
    #expect(Set(history.series.map { $0.key.isImported }) == [false, true])
    #expect(history.machineChanges.isEmpty)
  }

  @Test("Machine and cable movements with nil equipment explain the missing identity",
    arguments: ["machine", "cable"])
  func missingMachineIsExplicit(modality: String) async throws {
    let database = try migratedDatabase()
    let lift = try exercise(database, "Unidentified press", muscle: "chest", modality: modality)
    try train(database, lift, sets: [(40, 8)], daysAgo: 1)
    let board = try await ProgressBoardStore(database: database).loadBoard()
    let row = try #require(board.sections.first?.rows.first)
    #expect(row.id.machineID == nil)
    #expect(row.machineName == "No machine recorded")
    #expect(ProgressCopy.spokenRow(row).contains("No machine recorded"))
    let chart = try await ProgressionStore(database: database).loadHistory(for: lift)
    #expect(chart.series.count == 1)
    #expect(chart.label(for: row.id) == "No machine recorded")
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
