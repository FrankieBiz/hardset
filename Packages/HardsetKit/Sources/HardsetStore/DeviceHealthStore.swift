import Foundation
import GRDB
import HardsetCore
import SQLiteData

/// Opt-in Apple Health observations remain device-local and never enter machine history.
public nonisolated struct DeviceHealthStore: Sendable {
  private let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  public struct Sample: Sendable {
    public let id: UUID
    public let kind: String
    public let value: Double
    public let unit: String
    public let startedAt: Date
    public let endedAt: Date?
    public init(id: UUID, kind: String, value: Double, unit: String, startedAt: Date, endedAt: Date?) {
      self.id = id; self.kind = kind; self.value = value; self.unit = unit
      self.startedAt = startedAt; self.endedAt = endedAt
    }
  }

  public struct Workout: Sendable {
    public let id: SessionID
    public let start: Date
    public let end: Date
  }

  public func save(_ samples: [Sample]) async throws {
    try await database.write { db in
      for sample in samples {
        guard sample.value.isFinite, sample.startedAt.timeIntervalSince1970.isFinite,
          sample.endedAt.map({ $0 >= sample.startedAt && $0.timeIntervalSince1970.isFinite }) ?? true
        else { throw DeviceHealthError.invalidSample }
        try DeviceHealthSample.upsert {
          DeviceHealthSample(id: sample.id, kind: sample.kind, value: sample.value, unit: sample.unit,
            startedAt: sample.startedAt, endedAt: sample.endedAt)
        }.execute(db)
      }
    }
  }

  /// Only finished, plausible, native sessions can become strength workouts in Health.
  /// Imported files do not establish a training modality and are deliberately excluded.
  public func workoutsToExport() async throws -> [Workout] {
    try await database.read { db in
      try Session.where { $0.finishedAt.isNot(nil) }.order { ($0.startedAt, $0.id) }.fetchAll(db)
        .compactMap { row in
          guard let end = row.finishedAt, !row.notes.hasPrefix("Imported from "),
            end > row.startedAt, end.timeIntervalSince(row.startedAt) <= 6 * 3600 else { return nil }
          return Workout(id: SessionID(rawValue: row.id), start: row.startedAt, end: end)
        }
    }
  }
}

public nonisolated enum DeviceHealthError: Error, Sendable { case invalidSample }
