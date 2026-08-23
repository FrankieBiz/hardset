import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// `bodyweightEntries` shipped in the first migration with no store, no screen, and no writer.
@Suite("Bodyweight readings are stored and read back as a trend")
struct BodyweightStoreTests {
  let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func fixture() throws -> (any DatabaseWriter, BodyweightStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return (queue, BodyweightStore(database: queue))
  }

  @Test("A reading round-trips, newest first")
  func readingsRoundTrip() throws {
    let (_, store) = try fixture()
    try store.record(weightKg: 84, at: now.addingTimeInterval(-86_400))
    try store.record(weightKg: 83.6, at: now)

    let history = try store.history()
    #expect(history.count == 2)
    #expect(history.first?.weightKg == 83.6)
    #expect(history.last?.weightKg == 84)
  }

  /// Weighing twice in one morning is a real thing to do, and the app must not pick which of the
  /// two facts is true.
  @Test("Two readings on the same day are both kept")
  func sameDayReadingsBothKept() throws {
    let (_, store) = try fixture()
    try store.record(weightKg: 84, at: now)
    try store.record(weightKg: 84.4, at: now.addingTimeInterval(600))

    #expect(try store.history().count == 2)
  }

  @Test("A mistyped reading can be deleted")
  func deleteRemovesOne() throws {
    let (_, store) = try fixture()
    let wrong = try store.record(weightKg: 840, at: now)
    try store.record(weightKg: 84, at: now.addingTimeInterval(-86_400))

    try store.delete(wrong)
    let history = try store.history()
    #expect(history.count == 1)
    #expect(history.first?.weightKg == 84)
  }

  @Test("The trend comes back with the average, the rate, and the latest reading")
  func trendIsAssembled() throws {
    let (_, store) = try fixture()
    // Four weeks of daily readings, losing half a kilogram a week.
    for day in 0..<28 {
      try store.record(
        weightKg: 85 - 0.5 * (Double(day) / 7),
        at: now.addingTimeInterval(-Double(27 - day) * 86_400)
      )
    }

    let trend = try store.trend(asOf: now)
    let average = try #require(trend.smoothedKg)
    // The seven-day average sits below the newest reading while weight is falling.
    #expect(average > 83 && average < 84)
    #expect(trend.weeklyRate.certainty == .high)
    let perWeek = try #require(trend.weeklyRate.value)
    #expect(abs(perWeek - -0.5) < 0.01)
    #expect(trend.latest?.measuredAt == now)
  }

  @Test("An empty table claims nothing")
  func emptyClaimsNothing() throws {
    let (_, store) = try fixture()
    let trend = try store.trend(asOf: now)
    #expect(trend.smoothedKg == nil)
    #expect(trend.weeklyRate.value == nil)
    #expect(trend.latest == nil)
    #expect(try store.history().isEmpty)
  }

  /// The table is deliberately outside CloudKit under App Review 5.1.3(ii). A regression that
  /// quietly added it to the synced list would ship health data to iCloud with no way to recall it.
  @Test("Bodyweight is not registered for synchronization")
  func bodyweightIsNotSynced() {
    #expect(!HardsetMigrations.syncedTableNames.contains("bodyweightEntries"))
    #expect(HardsetMigrations.deferredSyncTableNames.contains("bodyweightEntries"))
  }
}
