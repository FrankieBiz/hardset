import Foundation
import HardsetCore
import HardsetFeature
import HardsetStore
import Testing

/// The staged tour environment is produced by the engine, not typed in, so these read it back the
/// way a screen does: through the stores and the coordinator. They render nothing, which is why
/// the file is not wrapped in the UIKit guard the snapshot suites use.
@MainActor
@Suite("Tour fixtures are built through the real write path")
struct TourFixturesTests {
  /// A fixed instant at or before the real clock, because the open workout is reopened with it.
  private static let now = Date(timeIntervalSince1970: 1_793_000_000)

  @Test func startStageHasTheStagedGymAndTwelveFinishedWorkouts() async throws {
    let staged = try TourFixtures.make(stage: .start, now: Self.now)

    #expect(staged.gymName == "Downtown")
    let gyms = try staged.environment.gyms.gyms()
    #expect(gyms.map(\.name) == ["Downtown"])
    let machines = try staged.environment.gyms.machines(at: staged.gymID)
    #expect(machines.count == 3)
    #expect(staged.machines.count == 3)
    #expect(staged.liveSession == nil)

    let sessions = try staged.environment.history.recentSessions(limit: 50)
    #expect(sessions.count == 12)
    let weekAgo = Self.now.addingTimeInterval(-7 * 86_400)
    #expect(sessions.filter { $0.timeline.startedAt >= weekAgo }.count == 3)
    #expect(sessions.allSatisfy { $0.timeline.startedAt <= Self.now })
  }

  @Test func theWeeksVolumeAndTheNewestWorkoutsRecordComeFromTheEngine() async throws {
    let staged = try TourFixtures.make(stage: .start, now: Self.now)

    let week = try staged.environment.volume.rollingWeek(endingAt: Self.now)
    #expect(week.hardSets > 0)

    // Newest first: the last finished workout raised the leg press over the weights before it, so
    // the engine's own receipt carries a record. The count is the engine's to decide (R45).
    let sessions = try staged.environment.history.recentSessions(limit: 50)
    let newest = try #require(sessions.first)
    let receipt = try await staged.environment.receipts.load(newest.id)
    #expect(receipt.lines.contains { !$0.records.isEmpty })
  }

  @Test func liveStageHasTwoMovementsThreeLoggedSetsAndSetsStillToLog() async throws {
    let staged = try TourFixtures.make(stage: .liveSession, now: Self.now)

    let live = try #require(staged.liveSession)
    #expect(live.exercises.count == 2)
    let slots = live.exercises.flatMap(\.slots)
    #expect(slots.filter { $0.loggedSetID != nil }.count == 3)
    #expect(slots.contains { $0.loggedSetID == nil })

    // The workout was staged 24 minutes before `now`, and history is unchanged by it.
    let expectedStart = Self.now.addingTimeInterval(-24 * 60)
    #expect(abs(live.startedAt.timeIntervalSince(expectedStart)) < 1)
    let sessions = try staged.environment.history.recentSessions(limit: 50)
    #expect(sessions.count == 12)
  }
}
