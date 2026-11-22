import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// D13: a finished workout's set can be corrected, not only removed. The write is one narrow update;
/// what these tests hold is the part that makes it different from an open workout, which is that
/// everything else reads the result. Volume, records, load history and the stall flag are all
/// derived from the stored sets on every read, so each of them is checked against the corrected
/// figures through the store that serves it.
@Suite("A finished set can be corrected, and everything that reads history follows")
struct FinishedSetCorrectionTests {
  private let t0 = Date(timeIntervalSince1970: 20_000)
  private static let day: TimeInterval = 86_400

  // MARK: - Fixtures

  private struct Fixture: Sendable {
    let db: DatabaseQueue
    let logger: LoggerStore
    let bench: ExerciseID
    let receipts: ReceiptStore
  }

  /// Bench is a barbell movement with no machine, so records compare against its own free-weight
  /// history.
  private func fixture() throws -> Fixture {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let bench = ExerciseID()
    try db.write { db in
      try Exercise.insert {
        Exercise.Draft(id: bench.rawValue, name: "Bench", modality: "barbell", primaryMuscle: "chest")
      }.execute(db)
    }
    return Fixture(db: db, logger: LoggerStore(database: db), bench: bench, receipts: ReceiptStore(database: db))
  }

  /// A finished session of working sets `daysAfter` days after `t0`, returning the id of each set.
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

  private func rows(_ f: Fixture, in session: SessionID) throws -> [LoggedSet] {
    try f.db.read { db in
      try LoggedSet.where { $0.sessionID.eq(session.rawValue) }
        .order { ($0.setOrdinal, $0.id) }.fetchAll(db)
    }
  }

  private func volume(_ f: Fixture, of session: SessionID) async throws -> SessionVolume {
    let page = try await HistoryStore(database: f.db).loadHistory(limit: 50)
    return try #require(page.sessions.first { $0.id == session }).volume
  }

  // MARK: - Volume

  @Test("A corrected set changes the session's volume, and the working-set count stays")
  func correctionChangesVolume() async throws {
    let f = try fixture()
    // The second set was typed 80, and was 110.
    let a = try train(f, sets: [(100, 5), (80, 5)], daysAfter: 0)
    let before = try await volume(f, of: a.session)
    #expect(before.volumeKg == 100 * 5 + 80 * 5)

    try await f.receipts.correctSet(
      a.sets[1], inSession: a.session, to: SetEntryDraft(weightKg: 110, reps: 5))

    let after = try await volume(f, of: a.session)
    #expect(after.volumeKg == 100 * 5 + 110 * 5)
    #expect(after.workingSets == before.workingSets)
    #expect(after.reps == before.reps)
    // The receipt a lifter opens from History reads the same figures.
    let receipt = try await f.receipts.load(a.session)
    #expect(receipt.lines.map(\.weightKg) == [100, 110])
  }

  @Test("A corrected rep count changes volume and reps, and the weight is not rewritten")
  func correctedRepsChangeVolume() async throws {
    let f = try fixture()
    // 100 reps typed for 10.
    let a = try train(f, sets: [(60, 100)], daysAfter: 0)
    try await f.receipts.correctSet(
      a.sets[0], inSession: a.session, to: SetEntryDraft(weightKg: 60, reps: 10))
    let after = try await volume(f, of: a.session)
    #expect(after.volumeKg == 600)
    #expect(after.reps == 10)
    #expect(try rows(f, in: a.session).map(\.weightKg) == [60])
  }

  // MARK: - Records

  @Test("A corrected set that becomes a best is recorded as one, on the receipt and on the chart")
  func correctionThatBecomesABestIsRecorded() async throws {
    let f = try fixture()
    let earlier = try train(f, sets: [(100, 5)], daysAfter: 0)
    // The typed 80 was 110, which beats everything before it.
    let later = try train(f, sets: [(80, 5)], daysAfter: 7)
    let before = try await f.receipts.load(later.session)
    #expect(before.lines[0].records.isEmpty)
    #expect(before.scorecard?.recordMovementCount == 0)
    let chartBefore = try await ProgressionStore(database: f.db).loadHistory(for: f.bench)
    #expect(chartBefore.recordSessionIDs.values.allSatisfy { !$0.contains(later.session) })

    try await f.receipts.correctSet(
      later.sets[0], inSession: later.session, to: SetEntryDraft(weightKg: 110, reps: 5))

    let after = try await f.receipts.load(later.session)
    #expect(after.lines[0].records.contains { $0.kind == .heaviestLoad })
    let heaviest = try #require(after.lines[0].records.first { $0.kind == .heaviestLoad })
    #expect(heaviest.previousWeightKg == 100)
    #expect(after.scorecard?.recordMovementCount == 1)
    // History's per-movement chart marks the session as one that set a record.
    let chartAfter = try await ProgressionStore(database: f.db).loadHistory(for: f.bench)
    #expect(chartAfter.recordSessionIDs.values.contains { $0.contains(later.session) })
    // The earlier session is untouched by any of it.
    #expect(try rows(f, in: earlier.session).map(\.weightKg) == [100])
  }

  @Test("A correction that took the record away takes it off the receipt too")
  func correctionThatLosesARecord() async throws {
    let f = try fixture()
    try train(f, sets: [(100, 5)], daysAfter: 0)
    // 120 was typed for 102.5, so the receipt claimed a record the set never earned.
    let later = try train(f, sets: [(120, 5)], daysAfter: 7)
    #expect(try await f.receipts.load(later.session).lines[0].records.contains { $0.kind == .heaviestLoad })

    try await f.receipts.correctSet(
      later.sets[0], inSession: later.session, to: SetEntryDraft(weightKg: 90, reps: 5))

    let after = try await f.receipts.load(later.session)
    #expect(after.lines[0].records.isEmpty)
    let chart = try await ProgressionStore(database: f.db).loadHistory(for: f.bench)
    #expect(chart.recordSessionIDs.values.allSatisfy { !$0.contains(later.session) })
  }

  @Test("A correction to an earlier session leaves a later session's rows and its records where they were")
  func earlierCorrectionLeavesLaterSessionAlone() async throws {
    let f = try fixture()
    // The second set of the earlier session was typed 10 reps for 12, a lighter set that is nowhere
    // near anything the later session is judged against.
    let earlier = try train(f, sets: [(100, 5), (60, 10)], daysAfter: 0)
    let later = try train(f, sets: [(105, 5), (105, 4)], daysAfter: 7)
    let laterRowsBefore = try rows(f, in: later.session)
    let laterBefore = try await f.receipts.load(later.session)
    let kindsBefore = laterBefore.lines.map { Set($0.records.map(\.kind)) }
    #expect(kindsBefore[0].contains(.heaviestLoad))

    try await f.receipts.correctSet(
      earlier.sets[1], inSession: earlier.session, to: SetEntryDraft(weightKg: 60, reps: 12))

    #expect(try rows(f, in: later.session) == laterRowsBefore)
    let laterAfter = try await f.receipts.load(later.session)
    #expect(laterAfter.lines.map { Set($0.records.map(\.kind)) } == kindsBefore)
    #expect(try rows(f, in: earlier.session).map(\.reps) == [5, 12])
  }

  /// Records are replayed from the stored sets on every read, never stored, so a baseline that was
  /// wrong is wrong for everything after it. This is the ledger being true, and it is why the
  /// correction does not freeze later workouts' records: there is nothing stored to freeze.
  @Test("An earlier correction that raises the baseline is felt by a later workout's records")
  func raisedBaselineIsFeltLater() async throws {
    let f = try fixture()
    let earlier = try train(f, sets: [(100, 5)], daysAfter: 0)
    let later = try train(f, sets: [(105, 5)], daysAfter: 7)
    #expect(try await f.receipts.load(later.session).lines[0].records.contains { $0.kind == .heaviestLoad })

    // The earlier set was really 120, so 105 never beat anything.
    try await f.receipts.correctSet(
      earlier.sets[0], inSession: earlier.session, to: SetEntryDraft(weightKg: 120, reps: 5))

    #expect(try await f.receipts.load(later.session).lines[0].records.isEmpty)
    // And the later session's own rows were never written.
    #expect(try rows(f, in: later.session).map(\.weightKg) == [105])
  }

  /// The reverse of the test above, found by writing it wrongly: one more rep on an earlier working
  /// set lifts its estimated maximum enough that a later 105 x 5 no longer clears the 2.5% margin.
  /// A correction's reach is whatever the baseline's reach is, and the records say so.
  @Test("Even one rep on an earlier working set can move a later workout's estimated-max record")
  func earlierRepCanMoveALaterEstimateRecord() async throws {
    let f = try fixture()
    let earlier = try train(f, sets: [(100, 5)], daysAfter: 0)
    let later = try train(f, sets: [(105, 5)], daysAfter: 7)
    let before = try await f.receipts.load(later.session).lines[0].records.map(\.kind)
    #expect(before.contains(.estimatedOneRepMax) && before.contains(.heaviestLoad))

    try await f.receipts.correctSet(
      earlier.sets[0], inSession: earlier.session, to: SetEntryDraft(weightKg: 100, reps: 6))

    let after = try await f.receipts.load(later.session).lines[0].records.map(\.kind)
    #expect(after == [.heaviestLoad])
  }

  // MARK: - Progress and stall

  @Test("The stall flag reads the corrected set: a record in the last three sessions clears it")
  func stallFollowsTheCorrection() async throws {
    let db = try DatabaseQueue(configuration: foreignKeys())
    try HardsetMigrations.migrator().migrate(db)
    let logger = LoggerStore(database: db)
    let press = ExerciseID(), machine = MachineID(), gym = UUID()
    try await db.write { db in
      try Exercise.insert {
        Exercise.Draft(id: press.rawValue, name: "Chest Press", modality: "machine", primaryMuscle: "chest")
      }.execute(db)
      try Gym.insert { Gym.Draft(id: gym, name: "Gym") }.execute(db)
      try Machine.insert {
        Machine.Draft(id: machine.rawValue, gymID: gym, name: "Hammer", stackIncrementKg: 2.5)
      }.execute(db)
    }
    var last: (session: SessionID, set: SetID)?
    for index in 0..<4 {
      let start = t0.addingTimeInterval(Double(index) * 7 * Self.day)
      let session = try logger.startSession(at: start)
      // The last session typed 35 for 45, and 45 is the first load that session beat.
      let set = try logger.logSet(
        sessionID: session, exerciseID: press, machineID: machine,
        draft: SetEntryDraft(weightKg: index == 3 ? 35 : 40, reps: 10), setOrdinal: 0,
        at: start.addingTimeInterval(60))
      try logger.finishSession(session, at: start.addingTimeInterval(3600))
      last = (session, set)
    }
    let board = ProgressBoardStore(database: db)
    let stalledBefore = try await board.loadBoard().sections.first?.rows.first?.trend.stalledSessions
    #expect(stalledBefore == 3)

    let target = try #require(last)
    try await ReceiptStore(database: db).correctSet(
      target.set, inSession: target.session, to: SetEntryDraft(weightKg: 45, reps: 10))

    let row = try #require(try await board.loadBoard().sections.first?.rows.first)
    #expect(row.trend.stalledSessions == nil)
    #expect(row.trend.sessionCount == 4)
  }

  // MARK: - What a correction leaves alone

  @Test("Only weight and reps change: the set keeps its identity, machine, plan row, ordinal, flag, RPE and save time")
  func identityFieldsAreUntouched() async throws {
    let db = try DatabaseQueue(configuration: foreignKeys())
    try HardsetMigrations.migrator().migrate(db)
    let press = ExerciseID(), machine = MachineID(), gym = UUID()
    let sessionID = SessionID(), plan = UUID(), warmup = UUID(), working = UUID()
    let start = t0
    try await db.write { db in
      try Exercise.insert {
        Exercise.Draft(id: press.rawValue, name: "Press", modality: "machine", primaryMuscle: "chest")
      }.execute(db)
      try Gym.insert { Gym.Draft(id: gym, name: "Gym") }.execute(db)
      try Machine.insert {
        Machine.Draft(id: machine.rawValue, gymID: gym, name: "Sled", stackIncrementKg: 2.5)
      }.execute(db)
      try Session.insert {
        Session.Draft(
          id: sessionID.rawValue, gymID: gym, title: "Push", notes: "a note", startedAt: start,
          finishedAt: start.addingTimeInterval(3600))
      }.execute(db)
      try SessionExercise.insert {
        SessionExercise.Draft(
          id: plan, sessionID: sessionID.rawValue, exerciseID: press.rawValue,
          machineID: machine.rawValue, position: 0, repRangeLower: 8, repRangeUpper: 12)
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(
          id: warmup, sessionID: sessionID.rawValue, exerciseID: press.rawValue,
          machineID: machine.rawValue, sessionExerciseID: plan, setOrdinal: 0, weightKg: 20, reps: 10,
          rpe: nil, isWarmup: true, completedAt: start.addingTimeInterval(60))
      }.execute(db)
      try LoggedSet.insert {
        LoggedSet.Draft(
          id: working, sessionID: sessionID.rawValue, exerciseID: press.rawValue,
          machineID: machine.rawValue, sessionExerciseID: plan, setOrdinal: 1, weightKg: 40, reps: 100,
          rpe: 8.5, isWarmup: false, completedAt: start.addingTimeInterval(123))
      }.execute(db)
    }
    let all = { try db.read { db in try LoggedSet.order { $0.setOrdinal }.fetchAll(db) } }
    let sessionRow = { try db.read { db in try Session.fetchOne(db) } }
    let setsBefore = try all()
    let sessionBefore = try sessionRow()

    try await ReceiptStore(database: db).correctSet(
      SetID(rawValue: working), inSession: sessionID, to: SetEntryDraft(weightKg: 42.5, reps: 10))

    let setsAfter = try all()
    #expect(setsAfter.count == 2)
    // The warm-up beside it is not touched at all.
    #expect(setsAfter[0] == setsBefore[0])
    var expected = setsBefore[1]
    expected.weightKg = 42.5
    expected.reps = 10
    #expect(setsAfter[1] == expected)
    let corrected = setsAfter[1]
    #expect(corrected.id == working)
    #expect(corrected.machineID == machine.rawValue)
    #expect(corrected.sessionExerciseID == plan)
    #expect(corrected.setOrdinal == 1)
    #expect(corrected.isWarmup == false)
    #expect(corrected.rpe == 8.5)
    #expect(corrected.completedAt == start.addingTimeInterval(123))
    // The workout itself keeps its start, its finish and everything else it says.
    #expect(try sessionRow() == sessionBefore)
  }

  @Test("A warm-up is corrected as a warm-up and still counts toward no working volume")
  func warmupStaysAWarmup() async throws {
    let f = try fixture()
    let start = t0
    let session = try f.logger.startSession(at: start)
    let warm = try f.logger.logSet(
      sessionID: session, exerciseID: f.bench, draft: SetEntryDraft(weightKg: 20, reps: 10),
      isWarmup: true, at: start.addingTimeInterval(60))
    try f.logger.finishSession(session, at: start.addingTimeInterval(3600))

    try await f.receipts.correctSet(warm, inSession: session, to: SetEntryDraft(weightKg: 40, reps: 8))

    let after = try await volume(f, of: session)
    #expect(after.warmupSets == 1 && after.workingSets == 0 && after.volumeKg == 0)
    #expect(try rows(f, in: session).first?.isWarmup == true)
  }

  // MARK: - Refusals

  @Test("Nothing is written for an open workout, a stranger's set, a missing set or an incomplete draft")
  func refusalsWriteNothing() async throws {
    let f = try fixture()
    let finished = try train(f, sets: [(100, 5)], daysAfter: 0)
    let other = try train(f, sets: [(90, 5)], daysAfter: 1)
    let open = try f.logger.startSession(at: t0.addingTimeInterval(2 * Self.day))
    let openSet = try f.logger.logSet(
      sessionID: open, exerciseID: f.bench, draft: SetEntryDraft(weightKg: 100, reps: 5),
      at: t0.addingTimeInterval(2 * Self.day + 60))
    let snapshot = try await f.db.read { try LoggedSet.order { ($0.sessionID, $0.setOrdinal) }.fetchAll($0) }
    let draft = SetEntryDraft(weightKg: 105, reps: 5)

    await #expect(throws: ReceiptError.sessionNotFinished) {
      try await f.receipts.correctSet(openSet, inSession: open, to: draft)
    }
    await #expect(throws: ReceiptError.sessionNotFound) {
      try await f.receipts.correctSet(finished.sets[0], inSession: SessionID(), to: draft)
    }
    await #expect(throws: ReceiptError.setNotFound) {
      try await f.receipts.correctSet(finished.sets[0], inSession: other.session, to: draft)
    }
    await #expect(throws: ReceiptError.setNotFound) {
      try await f.receipts.correctSet(SetID(), inSession: finished.session, to: draft)
    }
    for incomplete in [
      SetEntryDraft(weightKg: nil, reps: 5), SetEntryDraft(weightKg: 105, reps: nil),
      SetEntryDraft(weightKg: 105, reps: 0), SetEntryDraft(weightKg: -5, reps: 5),
      SetEntryDraft(weightKg: .infinity, reps: 5), SetEntryDraft(weightKg: .nan, reps: 5),
    ] {
      await #expect(throws: ReceiptError.incompleteSet) {
        try await f.receipts.correctSet(finished.sets[0], inSession: finished.session, to: incomplete)
      }
    }

    let after = try await f.db.read { try LoggedSet.order { ($0.sessionID, $0.setOrdinal) }.fetchAll($0) }
    #expect(after == snapshot)
  }

  @Test("Correcting to the figures a set already holds writes nothing and succeeds")
  func sameFiguresIsANoOp() async throws {
    let f = try fixture()
    let a = try train(f, sets: [(100, 5)], daysAfter: 0)
    let before = try rows(f, in: a.session)
    try await f.receipts.correctSet(
      a.sets[0], inSession: a.session, to: SetEntryDraft(weightKg: 100, reps: 5))
    #expect(try rows(f, in: a.session) == before)
  }

  @Test("Zero added load is a legitimate correction, as it is when logging")
  func zeroLoadIsAccepted() async throws {
    let f = try fixture()
    let a = try train(f, sets: [(20, 8)], daysAfter: 0)
    try await f.receipts.correctSet(
      a.sets[0], inSession: a.session, to: SetEntryDraft(weightKg: 0, reps: 8))
    #expect(try rows(f, in: a.session).map(\.weightKg) == [0])
  }

  // MARK: - Removal still works beside it

  @Test("Removing a set still works after another set has been corrected")
  func removalKeepsWorking() async throws {
    let f = try fixture()
    let a = try train(f, sets: [(100, 5), (80, 5), (999, 5)], daysAfter: 0)

    try await f.receipts.correctSet(
      a.sets[1], inSession: a.session, to: SetEntryDraft(weightKg: 110, reps: 5))
    try await f.receipts.deleteSet(a.sets[2], inSession: a.session)

    let after = try await volume(f, of: a.session)
    #expect(after.workingSets == 2)
    #expect(after.volumeKg == 100 * 5 + 110 * 5)
    #expect(try rows(f, in: a.session).map(\.weightKg) == [100, 110])
    // A set that was removed cannot then be corrected back into existence.
    await #expect(throws: ReceiptError.setNotFound) {
      try await f.receipts.correctSet(a.sets[2], inSession: a.session, to: SetEntryDraft(weightKg: 100, reps: 5))
    }
  }

  private func foreignKeys() -> Configuration {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    return configuration
  }
}
