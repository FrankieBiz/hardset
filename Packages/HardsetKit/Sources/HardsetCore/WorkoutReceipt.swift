import Foundation

/// A shareable ledger of committed facts, prepared once outside the view render loop.
public struct WorkoutReceipt: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public let title: String
  public let startedAt: Date
  public let finishedAt: Date
  /// In the order the sets were performed.
  public let lines: [Line]
  public let notes: String

  public init(id: SessionID, title: String, startedAt: Date, finishedAt: Date, lines: [Line], notes: String = "") {
    self.id = id; self.title = title; self.startedAt = startedAt
    self.finishedAt = finishedAt; self.lines = lines; self.notes = notes
  }

  /// What a set was performed on, as far as the record shows.
  ///
  /// A set with no machine means two different things, and the receipt must not merge them. For a
  /// barbell, dumbbell or bodyweight movement there is no machine to record: the bar is the bar, and
  /// the live logger compares records on exactly that basis. For a machine or cable movement, or one
  /// whose modality is unknown, it means the machine was never recorded, and nothing about it can
  /// be evaluated.
  public enum Equipment: Hashable, Sendable {
    /// A recorded machine, by its display name.
    case machine(String)
    /// Barbell or dumbbell work with no machine recorded.
    case freeWeight
    /// Bodyweight work with no machine recorded, with or without added load.
    case bodyweight
    /// A machine, cable or unknown-modality movement logged with no machine recorded.
    case unrecorded

    /// Resolves a set's equipment from its machine, when there is one, and otherwise from the
    /// movement's modality. `nil` modality is a value this build does not know, so it is unrecorded.
    public init(machineName: String?, modality: ExerciseModality?) {
      if let machineName {
        self = .machine(machineName)
        return
      }
      switch modality {
      case .barbell, .dumbbell: self = .freeWeight
      case .bodyweight: self = .bodyweight
      case .machine, .cable, nil: self = .unrecorded
      }
    }

    public var label: String {
      switch self {
      case .machine(let name): name.isEmpty ? "Unnamed machine" : name
      case .freeWeight: "Free weight"
      case .bodyweight: "Bodyweight"
      case .unrecorded: "No machine recorded"
      }
    }

    /// What a record on this equipment was compared against, in words.
    public var recordScope: String {
      switch self {
      case .machine: "same recorded machine"
      case .freeWeight, .bodyweight, .unrecorded: "same movement with no machine recorded"
      }
    }
  }

  public struct Line: Hashable, Sendable, Identifiable {
    public let id: SetID
    /// The movement, so a screen can open its load history. `nil` only for a line built without
    /// one, such as a preview's.
    public let exerciseID: ExerciseID?
    public let exerciseName: String
    public let equipment: Equipment
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let records: [PersonalRecord]
    public let isImported: Bool

    public init(
      id: SetID, exerciseID: ExerciseID?, exerciseName: String, equipment: Equipment,
      weightKg: Double, reps: Int, isWarmup: Bool, records: [PersonalRecord] = [],
      isImported: Bool = false
    ) {
      self.id = id; self.exerciseID = exerciseID; self.exerciseName = exerciseName
      self.equipment = equipment; self.weightKg = weightKg; self.reps = reps
      self.isWarmup = isWarmup; self.records = records; self.isImported = isImported
    }

    /// A line known only by its machine name, as previews build them. With no machine the
    /// equipment is treated as unrecorded, which never claims more than is known.
    public init(id: SetID, exerciseName: String, machineName: String?, weightKg: Double,
      reps: Int, isWarmup: Bool, records: [PersonalRecord] = [], isImported: Bool = false) {
      self.init(
        id: id, exerciseID: nil, exerciseName: exerciseName,
        equipment: machineName.map(Equipment.machine) ?? .unrecorded, weightKg: weightKg,
        reps: reps, isWarmup: isWarmup, records: records, isImported: isImported)
    }

    /// The recorded machine's name, or `nil` when the set has none.
    public var machineName: String? {
      if case .machine(let name) = equipment { return name }
      return nil
    }

    /// Imported history never recorded equipment, whatever its movement.
    public var equipmentLabel: String {
      isImported && machineName == nil ? "Imported • Unevaluated Machine" : equipment.label
    }

    /// Whether the equipment is known well enough for a same-equipment comparison to mean
    /// something.
    public var isEquipmentKnown: Bool {
      !isImported && equipment != .unrecorded
    }
  }

  /// One movement on the receipt, for linking to its load history.
  public struct Movement: Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String
    public var id: ExerciseID { exerciseID }
  }

  /// Consecutive sets of one movement on one piece of equipment, read as a single entry.
  public struct Block: Hashable, Sendable, Identifiable {
    /// The first line's id, which is unique on the receipt.
    public let id: SetID
    public let exerciseName: String
    public let equipmentLabel: String
    public let lines: [Line]
  }

  /// `.high` only when every set's equipment is known: a recorded machine, free weight or
  /// bodyweight. An empty receipt, an import or an unrecorded machine is unevaluated.
  public var certainty: Certainty {
    guard !lines.isEmpty, lines.allSatisfy(\.isEquipmentKnown) else { return .unevaluated }
    return .high
  }

  /// Each movement once, in the order it was first performed.
  public var movements: [Movement] {
    var seen = Set<ExerciseID>()
    var result: [Movement] = []
    for line in lines {
      guard let exerciseID = line.exerciseID, seen.insert(exerciseID).inserted else { continue }
      result.append(Movement(exerciseID: exerciseID, name: line.exerciseName))
    }
    return result
  }

  /// The lines grouped into runs of the same movement on the same equipment, in order. A movement
  /// performed again later in the workout starts a new block, because that is what happened.
  public var blocks: [Block] {
    var result: [Block] = []
    var current: [Line] = []
    func close() {
      guard let first = current.first else { return }
      result.append(Block(
        id: first.id, exerciseName: first.exerciseName, equipmentLabel: first.equipmentLabel,
        lines: current))
      current = []
    }
    for line in lines {
      if let previous = current.last,
        previous.exerciseID != line.exerciseID || previous.exerciseName != line.exerciseName
          || previous.equipmentLabel != line.equipmentLabel
      {
        close()
      }
      current.append(line)
    }
    close()
    return result
  }

  /// Plain text fallback stays useful in iMessage and preserves equipment provenance.
  public func text(unit: WeightUnit, locale: Locale = .current) -> String {
    var rows = ["HARDSET · Workout receipt", title.isEmpty ? "Workout" : title,
      startedAt.formatted(date: .abbreviated, time: .shortened)]
    for block in blocks {
      rows.append("\(block.exerciseName) · \(block.equipmentLabel)")
      for line in block.lines {
        let load = LoadText.entered(line.weightKg, in: unit, locale: locale)
        rows.append("  \(load) \(unit.abbreviation) × \(line.reps)\(line.isWarmup ? " · Warm-up" : "")")
        for record in line.records {
          rows.append("    \(record.kind.label) · \(line.equipment.recordScope)")
        }
      }
    }
    rows.append("Recorded training log; loads and equipment are user-entered, not independently verified.")
    if !notes.isEmpty { rows.append(notes) }
    return rows.joined(separator: "\n")
  }
}
