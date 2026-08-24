import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// The summary's muscle breakdown was computed from `startedAt..<finishedAt`. That window is
/// half-open at the top, and it cannot tell whose sets it is counting.
@Suite("A workout's summary counts that workout's sets")
struct SessionScopedVolumeTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, VolumeStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), VolumeStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  /// The defect: finishing in the same instant as the last set dropped that set from its own summary.
  @Test("A set logged at the finishing instant is still in the summary")
  func setAtFinishInstantIsCounted() throws {
    let (db, logger, volume) = try fixture()
    let bench = try exercise(db, "barbell-bench-press")
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: bench,
      draft: SetEntryDraft(weightKg: 84, reps: 8), setOrdinal: 0, at: now.addingTimeInterval(600)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    // The old window excluded it, because the upper bound is exclusive.
    #expect(try volume.report(from: now, to: now.addingTimeInterval(600)).hardSets == 0)
    // Scoped by session, it is counted.
    let report = try volume.report(for: session)
    #expect(report.hardSets == 1)
    #expect(report.sets(for: .chest) == 1)
  }

  /// The other half: a window cannot tell whose sets it spans.
  @Test("Another workout's sets in the same span are not counted")
  func otherSessionsAreNotCounted() throws {
    let (db, logger, volume) = try fixture()
    let bench = try exercise(db, "barbell-bench-press")
    let squat = try exercise(db, "barbell-back-squat")

    // A first workout, finished.
    let first = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: first, exerciseID: bench,
      draft: SetEntryDraft(weightKg: 84, reps: 8), setOrdinal: 0, at: now.addingTimeInterval(60)
    )
    try logger.finishSession(first, at: now.addingTimeInterval(120))

    // A second workout whose span contains the first one's sets -- reachable through a back-dated
    // or imported session, and previously counted into whichever summary spanned it.
    let second = try logger.startSession(at: now.addingTimeInterval(200))
    _ = try logger.logSet(
      sessionID: second, exerciseID: squat,
      draft: SetEntryDraft(weightKg: 100, reps: 5), setOrdinal: 0, at: now.addingTimeInterval(30)
    )
    try logger.finishSession(second, at: now.addingTimeInterval(300))

    let secondReport = try volume.report(for: second)
    #expect(secondReport.hardSets == 1)
    #expect(secondReport.sets(for: .quadriceps) == 1)
    // The bench set belongs to the other workout and must not appear here.
    #expect(secondReport.sets(for: .chest) == 0)

    // And the time window really does conflate them, which is what this replaces.
    let windowed = try volume.report(from: now, to: now.addingTimeInterval(400))
    #expect(windowed.hardSets == 2)
  }

  @Test("Warm-ups are excluded from a session report, as everywhere else")
  func warmupsExcluded() throws {
    let (db, logger, volume) = try fixture()
    let bench = try exercise(db, "barbell-bench-press")
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: bench,
      draft: SetEntryDraft(weightKg: 40, reps: 12), setOrdinal: 0, isWarmup: true, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: bench,
      draft: SetEntryDraft(weightKg: 84, reps: 8), setOrdinal: 0, at: now.addingTimeInterval(120)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(300))

    #expect(try volume.report(for: session).hardSets == 1)
  }

  @Test("A workout with nothing logged reports nothing rather than failing")
  func emptySessionReportsNothing() throws {
    let (_, logger, volume) = try fixture()
    let session = try logger.startSession(at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(60))
    let report = try volume.report(for: session)
    #expect(report.hardSets == 0)
    #expect(report.unattributedHardSets == 0)
  }
}
