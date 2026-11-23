import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// D13 lets a finished set be corrected in place. "Worked from" explains records and estimates from
/// what the stores read on each load, so a correction must show up in the explanation as it does in
/// the figure: the working may never read a copy of the receipt, the history or a baseline from before
/// the correction. Each test corrects a finished set through `ReceiptStore.correctSet` and reads the
/// account fresh, as the screens do.
@Suite("Worked from follows a corrected set, never a copy from before it")
struct WorkedFromCorrectionTests {
  private let t0 = Date(timeIntervalSince1970: 20_000)
  private static let day: TimeInterval = 86_400
  private let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private struct Fixture: Sendable {
    let db: DatabaseQueue
    let logger: LoggerStore
    let bench: ExerciseID
    let receipts: ReceiptStore
    let progression: ProgressionStore
  }

  private func fixture() throws -> Fixture {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let bench = ExerciseID()
    try db.write { db in
      try Exercise.insert {
        Exercise.Draft(id: bench.rawValue, name: "Bench", modality: "barbell", primaryMuscle: "chest")
      }.execute(db)
    }
    return Fixture(
      db: db, logger: LoggerStore(database: db), bench: bench, receipts: ReceiptStore(database: db),
      progression: ProgressionStore(database: db))
  }

  @discardableResult
  private func train(
    _ f: Fixture, sets: [(Double, Int)], daysAfter: Double
  ) throws -> (session: SessionID, sets: [SetID]) {
    let start = t0.addingTimeInterval(daysAfter * Self.day)
    let session = try f.logger.startSession(at: start)
    var ids: [SetID] = []
    for (index, set) in sets.enumerated() {
      ids.append(
        try f.logger.logSet(
          sessionID: session, exerciseID: f.bench, draft: SetEntryDraft(weightKg: set.0, reps: set.1),
          setOrdinal: index, at: start.addingTimeInterval(Double(index + 1) * 60)))
    }
    try f.logger.finishSession(session, at: start.addingTimeInterval(3600))
    return (session, ids)
  }

  private func receiptAccount(_ f: Fixture, _ session: SessionID) async throws -> WorkedFromAccount? {
    RecordWorking.receiptAccount(receipt: try await f.receipts.load(session), format: format)
  }

  private func chartRecords(_ f: Fixture) async throws -> RecordWorking {
    let history = try await f.progression.loadHistory(for: f.bench)
    return RecordWorking.derive(
      keys: history.series.map(\.key), samples: history.samples,
      estimatesOneRepMax: history.estimatesOneRepMax, incrementKg: history.incrementKg(for:),
      label: history.label(for:))
  }

  @Test("A set corrected into a best is explained as one, on the receipt and on the chart")
  func correctedIntoARecord() async throws {
    let f = try fixture()
    let earlier = try train(f, sets: [(100, 5)], daysAfter: 0)
    // The typed 80 was 110.
    let later = try train(f, sets: [(80, 5)], daysAfter: 7)
    #expect(try await receiptAccount(f, later.session) == nil)
    #expect(try await chartRecords(f).groups.isEmpty)

    try await f.receipts.correctSet(
      later.sets[0], inSession: later.session, to: SetEntryDraft(weightKg: 110, reps: 5))

    let account = try #require(try await receiptAccount(f, later.session))
    #expect(account.sections.map(\.heading) == ["Bench, 110 kg × 5"])
    let heaviest = try #require(account.sections[0].lines.first { $0.headline == "Heaviest weight" })
    #expect(heaviest.detail.hasPrefix("Beat your previous heaviest weight, 100 kg, by 10 kg (+10%)."))

    // The chart's account is built from the history as it is now: the corrected set, beating the
    // earlier one, which is named.
    let working = try await chartRecords(f)
    #expect(working.groups.count == 1)
    let entry = try #require(working.groups[0].entries.first { $0.record.kind == .heaviestLoad })
    #expect(entry.record.weightKg == 110)
    #expect(entry.beaten == PriorSetRecord(weightKg: 100, reps: 5, completedAt: t0.addingTimeInterval(60)))
    _ = earlier
  }

  @Test("A set corrected out of a record is no longer explained as one anywhere")
  func correctedOutOfARecord() async throws {
    let f = try fixture()
    try train(f, sets: [(100, 5)], daysAfter: 0)
    let later = try train(f, sets: [(120, 5)], daysAfter: 7)
    let before = try #require(try await receiptAccount(f, later.session))
    #expect(before.sections[0].heading == "Bench, 120 kg × 5")
    #expect(try await chartRecords(f).groups.count == 1)

    try await f.receipts.correctSet(
      later.sets[0], inSession: later.session, to: SetEntryDraft(weightKg: 90, reps: 5))

    #expect(try await receiptAccount(f, later.session) == nil)
    #expect(try await chartRecords(f).groups.isEmpty)
  }

  @Test("A correction to the set a record beat changes what the record is said to have beaten")
  func correctedBaselineIsTheStatedBaseline() async throws {
    let f = try fixture()
    let earlier = try train(f, sets: [(100, 5)], daysAfter: 0)
    let later = try train(f, sets: [(110, 5)], daysAfter: 7)
    let before = try #require(try await receiptAccount(f, later.session))
    #expect(before.sections[0].lines[0].detail.hasPrefix("Beat your previous heaviest weight, 100 kg, by 10 kg (+10%)."))

    // The 100 was typed for 104.
    try await f.receipts.correctSet(
      earlier.sets[0], inSession: earlier.session, to: SetEntryDraft(weightKg: 104, reps: 5))

    let after = try #require(try await receiptAccount(f, later.session))
    let detail = try #require(after.sections[0].lines.first { $0.headline == "Heaviest weight" }?.detail)
    #expect(detail.hasPrefix("Beat your previous heaviest weight, 104 kg, by 6 kg (+5.8%)."))
    // The chart names the corrected set as the one beaten, with its figures.
    let entry = try #require(try await chartRecords(f).groups.first?.entries.first { $0.record.kind == .heaviestLoad })
    #expect(entry.beaten?.weightKg == 104)
  }

  @Test("A corrected set changes the estimate's working: the set, its arithmetic and the figure")
  func correctedSetIsTheEstimatesSet() async throws {
    let f = try fixture()
    let session = try train(f, sets: [(100, 5), (80, 8)], daysAfter: 0)
    func working() async throws -> EstimateWorking {
      let history = try await f.progression.loadHistory(for: f.bench)
      return try #require(
        EstimateWorking.deriveLatest(
          key: history.series[0].key, samples: history.samples, warmups: history.warmupSamples,
          estimatesOneRepMax: history.estimatesOneRepMax, label: history.label(for:)))
    }
    let before = try await working()
    #expect(before.figureKg == StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 5).value)

    // The 80 for 8 was 90 for 8, which now makes the heavier estimate.
    try await f.receipts.correctSet(
      session.sets[1], inSession: session.session, to: SetEntryDraft(weightKg: 120, reps: 8))

    let after = try await working()
    #expect(after.figureKg == StrengthMath.estimatedOneRepMax(weightKg: 120, reps: 8).value)
    let account = after.account(format: format)
    let fed = try #require(account.sections.first { $0.id == "fed" })
    #expect(fed.lines.map(\.headline) == ["100 kg × 5", "120 kg × 8"])
    #expect(fed.lines[1].standing == .produced)
    // The account's figure is the chart's point on the same read.
    let history = try await f.progression.loadHistory(for: f.bench)
    #expect(after.figureKg == history.series[0].points.last?.bestEstimatedOneRepMaxKg)
  }
}
