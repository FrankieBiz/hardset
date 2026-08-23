import Foundation
import HardsetCore
import SQLiteData

/// One recorded bodyweight, as the UI sees it.
public nonisolated struct BodyweightRecord: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let weightKg: Double
  public let measuredAt: Date

  init(row: BodyweightEntry) {
    self.id = row.id
    self.weightKg = row.weightKg
    self.measuredAt = row.measuredAt
  }

  public var reading: BodyweightReading {
    BodyweightReading(weightKg: weightKg, measuredAt: measuredAt)
  }
}

/// Reading and writing bodyweight.
///
/// `bodyweightEntries` shipped in the first migration with no code at all -- no store, no screen,
/// no writer. The table was designed, documented, deliberately withheld from CloudKit under App
/// Review 5.1.3(ii), and then never given a way to hold anything.
///
/// Device-local, and this store never touches the sync engine, which is what keeps it that way.
/// Enabling sync later is an additive, permitted change; it is not made here by accident.
///
/// `nonisolated`, like every other store here: these run on GRDB's database queues, and isolating
/// them to the main actor would force the whole app -- and the test suite -- to hop actors to read a
/// row.
public nonisolated struct BodyweightStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Records a weight.
  ///
  /// One entry per instant, not one per day. Weighing twice in a morning is a real thing to do and
  /// the trend averages, so there is no reason to make the second reading overwrite the first --
  /// and a silent overwrite would be the app deciding which of the user's two facts is true.
  @discardableResult
  public func record(weightKg: Double, at date: Date = Date()) throws -> UUID {
    let id = UUID()
    try database.write { db in
      try BodyweightEntry.insert {
        BodyweightEntry.Draft(id: id, weightKg: weightKg, measuredAt: date, enteredBy: "manual")
      }
      .execute(db)
    }
    return id
  }

  /// Every reading, newest first.
  ///
  /// Unbounded by default because this table grows at one row a day at most: a decade of daily
  /// weighing is under four thousand rows, and the trend needs the history to draw anything.
  public func history(limit: Int = 5_000) throws -> [BodyweightRecord] {
    try database.read { db in
      try BodyweightEntry
        .order { $0.measuredAt.desc() }
        .limit(limit)
        .fetchAll(db)
        .map(BodyweightRecord.init(row:))
    }
  }

  /// The trailing average, and the fitted weekly rate, from one read.
  ///
  /// Both come out of `BodyweightTrend` rather than being computed here, so the rules about what
  /// the numbers are allowed to claim live in one pure, tested place.
  public func trend(asOf date: Date = Date()) throws -> (
    smoothedKg: Double?, weeklyRate: Claim<Double>, latest: BodyweightRecord?
  ) {
    let records = try history()
    let readings = records.map(\.reading)
    return (
      BodyweightTrend.smoothed(readings, endingAt: date),
      BodyweightTrend.weeklyRate(readings, asOf: date),
      records.first
    )
  }

  /// Removes one reading. A mistyped weight is a wrong fact, not history worth keeping.
  public func delete(_ id: UUID) throws {
    try database.write { db in
      try BodyweightEntry.where { $0.id.eq(id) }.delete().execute(db)
    }
  }
}
