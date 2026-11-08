import Foundation

/// A shareable ledger of committed facts, prepared once outside the view render loop.
public struct WorkoutReceipt: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public let title: String
  public let startedAt: Date
  public let finishedAt: Date
  public let lines: [Line]
  public let notes: String

  public init(id: SessionID, title: String, startedAt: Date, finishedAt: Date, lines: [Line], notes: String = "") {
    self.id = id; self.title = title; self.startedAt = startedAt
    self.finishedAt = finishedAt; self.lines = lines; self.notes = notes
  }

  public struct Line: Hashable, Sendable, Identifiable {
    public let id: SetID
    public let exerciseName: String
    public let machineName: String?
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let records: [PersonalRecord]
    public let isImported: Bool
    public init(id: SetID, exerciseName: String, machineName: String?, weightKg: Double,
      reps: Int, isWarmup: Bool, records: [PersonalRecord] = [], isImported: Bool = false) {
      self.id = id; self.exerciseName = exerciseName; self.machineName = machineName
      self.weightKg = weightKg; self.reps = reps; self.isWarmup = isWarmup
      self.records = records; self.isImported = isImported
    }
  }

  /// Plain text fallback stays useful in iMessage and preserves equipment provenance.
  public func text(unit: WeightUnit) -> String {
    var rows = ["HARDSET · Workout receipt", title.isEmpty ? "Workout" : title,
      startedAt.formatted(date: .abbreviated, time: .shortened)]
    for line in lines {
      rows.append("\(line.exerciseName) · \(line.machineName ?? "Unevaluated Machine") · \(unit.fromKilograms(line.weightKg).formatted()) \(unit.abbreviation) × \(line.reps)\(line.isWarmup ? " · Warm-up" : "")")
      for record in line.records { rows.append("  \(record.kind.label) · same recorded machine") }
    }
    rows.append("Recorded training log; loads and equipment are user-entered, not independently verified.")
    if !notes.isEmpty { rows.append(notes) }
    return rows.joined(separator: "\n")
  }
}
