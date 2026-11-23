import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// A figure with an explanation that disagrees with it is worse than a figure with none. A Progress
/// row's change, a scorecard's gain and the live record notice are each read from the database in one
/// place and explained in another, so these hold each explanation to the figure on screen on a real
/// database, with the warm-ups, other machines and older sessions that must be left out.
@Suite("Worked from: a row's change, a scorecard gain and the live record notice match their figures")
@MainActor
struct ChangeWorkingStoreTests {
  let now = Date(timeIntervalSince1970: 14_000_000)
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func migratedDatabase() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func exercise(
    _ database: DatabaseQueue, _ name: String, modality: String = "machine"
  ) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: id.rawValue, name: name, modality: modality, primaryMuscle: "chest")
      }
      .execute(db)
    }
    return id
  }

  private func machine(_ database: DatabaseQueue, _ name: String, brand: String = "") throws -> MachineID {
    let gym = UUID()
    let id = MachineID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: gym, name: "Gym \(name)") }.execute(db)
      try Machine.insert { Machine.Draft(id: id.rawValue, gymID: gym, name: name, brand: brand) }
        .execute(db)
    }
    return id
  }

  private typealias Entry = (kg: Double, reps: Int, warmup: Bool, machine: MachineID?)

  /// A finished session `daysAgo` before `now`, its sets in the order given.
  @discardableResult
  private func train(
    _ database: DatabaseQueue, _ exercise: ExerciseID, sets: [Entry], daysAgo: Double
  ) throws -> SessionID {
    let store = LoggerStore(database: database)
    let date = now.addingTimeInterval(-daysAgo * 86_400)
    let id = try store.startSession(at: date)
    for (index, set) in sets.enumerated() {
      _ = try store.logSet(
        sessionID: id, exerciseID: exercise, machineID: set.machine,
        draft: SetEntryDraft(weightKg: set.kg, reps: set.reps), setOrdinal: index,
        isWarmup: set.warmup, at: date.addingTimeInterval(Double(index) * 60))
    }
    try store.finishSession(id, at: date.addingTimeInterval(3600))
    return id
  }

  // MARK: - The Progress row

  @Test("A row's account states the figure on the row and counts what it left out")
  func rowAccountMatchesTheBoard() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press")
    let hammer = try machine(database, "Chest Press", brand: "Hammer")
    let cybex = try machine(database, "Chest Press", brand: "Cybex")
    try train(
      database, press,
      sets: [
        (40, 10, true, hammer), (100, 5, false, hammer), (100, 8, false, hammer),
        (90, 8, false, cybex),
      ], daysAgo: 42)
    try train(database, press, sets: [(120, 5, false, hammer)], daysAgo: 0)

    let store = ProgressBoardStore(database: database)
    let board = try await store.loadBoard()
    let row = try #require(board.sections.flatMap(\.rows).first { $0.id.machineID == hammer })
    let change = try #require(row.trend.sixWeekChange)
    let account = try #require(try await store.loadChangeWorking(for: row.id, format: format))

    // The row's figure and the sheet's are one calculation.
    #expect(account.figure == ProgressCopy.signedPercent(change))
    #expect(account.figure == "+11%")
    #expect(account.figureCaption.hasPrefix("Moderate confidence · Hammer Chest Press · "))
    #expect(account.title == "Estimated max over six weeks")

    let baseline = try #require(account.sections.first { $0.id == "baseline" })
    #expect(baseline.lines.map(\.headline) == ["100 kg × 5", "100 kg × 8"])
    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines.map(\.headline) == ["1 warm-up set", "1 set on other equipment"])
    #expect(left.lines.allSatisfy { $0.standing == .excluded })
  }

  @Test("A row with no six-week change has no account to open")
  func rowWithoutAChangeHasNoAccount() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press")
    try train(database, press, sets: [(100, 5, false, nil)], daysAgo: 3)
    let store = ProgressBoardStore(database: database)
    let row = try #require(try await store.loadBoard().sections.flatMap(\.rows).first)
    #expect(row.trend.sixWeekChange == nil)
    #expect(try await store.loadChangeWorking(for: row.id, format: format) == nil)
  }

  // MARK: - The scorecard's biggest gain

  @Test("A gain's account states the gain on the receipt and counts what it left out")
  func gainAccountMatchesTheReceipt() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press")
    let hammer = try machine(database, "Chest Press", brand: "Hammer")
    let cybex = try machine(database, "Chest Press", brand: "Cybex")
    try train(database, press, sets: [(90, 8, false, hammer)], daysAgo: 14)
    try train(
      database, press,
      sets: [(40, 10, true, hammer), (100, 5, false, hammer), (100, 4, false, hammer)], daysAgo: 7)
    let current = try train(
      database, press,
      sets: [
        (40, 10, true, hammer), (50, 5, true, hammer), (100, 8, false, hammer),
        (100, 6, false, hammer), (80, 10, false, cybex),
      ], daysAgo: 0)

    let receipt = try await ReceiptStore(database: database).load(current)
    let gain = try #require(receipt.scorecard?.biggestGain)
    let working = try #require(ChangeWorking.lastTime(gain: gain))
    let account = working.account(format: format)

    // The gain on the receipt and the sheet's figure are one calculation.
    #expect(working.fraction == gain.fraction)
    #expect(account.figure == ProgressCopy.signedPercent(gain.fraction))
    #expect(account.sections[0].lines.map(\.headline) == ["100 kg × 8", "100 kg × 6"])
    #expect(account.sections[1].lines.map(\.headline) == ["100 kg × 5", "100 kg × 4"])

    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines.map(\.id) == ["current-warmups", "current-elsewhere", "baseline-warmups", "older"])
    #expect(left.lines.map(\.headline) == [
      "2 warm-up sets", "1 set on other equipment", "1 warm-up set", "1 session before last time",
    ])
    #expect(left.lines[3].context == "1 set")
  }

  // MARK: - The live record notice

  @Test("The notice's account explains the records the coordinator claimed, from the saved history")
  func liveNoticeAccount() async throws {
    let database = try migratedDatabase()
    let press = try exercise(database, "Chest Press", modality: "barbell")
    try train(database, press, sets: [(40, 10, true, nil), (100, 5, false, nil)], daysAgo: 7)
    let live = try SessionCoordinator.start(
      store: LoggerStore(database: database),
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Chest Press", plannedSets: 2)],
      now: { self.now })
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))

    // What the notice draws, and what it needs to open its working.
    #expect(Set(live.lastRecords.map(\.kind)) == [.repsAtLoad, .estimatedOneRepMax])
    let key = try #require(live.lastRecordsKey)
    #expect(key == ProgressionKey(exerciseID: press))
    #expect(live.lastRecordsIncrementKg == nil)

    let history = try await ProgressionStore(database: database).loadHistory(for: press)
    let name = try #require(live.lastRecordsExerciseName)
    let account = try #require(
      RecordWorking.liveAccount(
        records: live.lastRecords, exerciseName: name,
        sessionID: live.sessionID, key: key, samples: history.samples, warmups: history.warmupSamples,
        estimatesOneRepMax: history.estimatesOneRepMax, assumesAddedLoad: history.assumesAddedLoad,
        incrementKg: live.lastRecordsIncrementKg, label: history.label(for:), format: format))

    // One line per record on screen, each naming the earlier set it beat: the replay over the saved
    // history found the same records the logger's detector claimed.
    let records = account.sections[0]
    #expect(records.lines.map(\.headline) == live.lastRecords.map(\.qualifiedLabel))
    let reps = try #require(records.lines.first { $0.headline == PersonalRecordKind.repsAtLoad.label })
    #expect(reps.detail.hasPrefix("Beat 100 kg × 5 on "))
    #expect(account.rule.contains("weight × (1 + reps ÷ 30)"))
    let left = try #require(account.sections.first { $0.id == "comparison-left" })
    #expect(left.lines.map(\.headline) == ["1 warm-up set"])

    // A later set that earns nothing takes the notice, and so its working, away.
    live.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(live.logSet(slotID: state.slots[1].id, inExercise: state.id))
    #expect(live.lastRecords.isEmpty)
    #expect(live.lastRecordsKey == nil)
    #expect(live.lastRecordsIncrementKg == nil)
  }
}
