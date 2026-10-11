import Foundation

/// One past workout, opened from history (spec 3.6): what was done, grouped by movement and
/// machine, with its records and an honest length.
///
/// A value with no database handle, read by `SessionDetailStore`. The totals, records and length
/// are the finish summary's own (`WorkoutSummary`), so the two screens cannot disagree about the
/// same session.
public struct SessionDetail: Hashable, Sendable {
  /// One logged set, as the detail lists it.
  public struct SetLine: Hashable, Sendable, Identifiable {
    public let setID: SetID
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    /// Records this set earned, judged as the summary judges them.
    public let records: [PersonalRecord]

    public init(setID: SetID, weightKg: Double, reps: Int, isWarmup: Bool, records: [PersonalRecord]) {
      self.setID = setID
      self.weightKg = weightKg
      self.reps = reps
      self.isWarmup = isWarmup
      self.records = records
    }

    public var id: SetID { setID }
  }

  /// One movement on one machine. A movement done on two machines is two blocks, never one: the
  /// numbers on different equipment are not the same effort (`DECISIONS.md` §20).
  public struct Block: Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public let machineID: MachineID?
    /// Nil for free-weight work.
    public let machineName: String?
    /// In the order they were logged.
    public let sets: [SetLine]

    public init(
      exerciseID: ExerciseID, exerciseName: String, machineID: MachineID?, machineName: String?,
      sets: [SetLine]
    ) {
      self.exerciseID = exerciseID
      self.exerciseName = exerciseName
      self.machineID = machineID
      self.machineName = machineName
      self.sets = sets
    }

    public var id: ProgressionKey { ProgressionKey(exerciseID: exerciseID, machineID: machineID) }
  }

  /// A logged set with the names it is shown under, before grouping.
  public struct Entry: Hashable, Sendable {
    public let line: SetLine
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public let machineID: MachineID?
    public let machineName: String?
    public let completedAt: Date
    public let setOrdinal: Int

    public init(
      line: SetLine, exerciseID: ExerciseID, exerciseName: String, machineID: MachineID?,
      machineName: String?, completedAt: Date, setOrdinal: Int
    ) {
      self.line = line
      self.exerciseID = exerciseID
      self.exerciseName = exerciseName
      self.machineID = machineID
      self.machineName = machineName
      self.completedAt = completedAt
      self.setOrdinal = setOrdinal
    }
  }

  public let summary: WorkoutSummary
  public let blocks: [Block]

  public init(summary: WorkoutSummary, blocks: [Block]) {
    self.summary = summary
    self.blocks = blocks
  }

  /// Groups sets by movement and machine. Blocks are ordered by their first set, and sets within
  /// a block by when they were logged. Coming back to a machine later in the workout adds to its
  /// block; moving to a different machine starts another.
  public static func blocks(from entries: [Entry]) -> [Block] {
    let ordered = entries.sorted {
      ($0.completedAt, $0.setOrdinal, $0.line.setID.description)
        < ($1.completedAt, $1.setOrdinal, $1.line.setID.description)
    }
    var order: [ProgressionKey] = []
    var grouped: [ProgressionKey: [Entry]] = [:]
    for entry in ordered {
      let key = ProgressionKey(exerciseID: entry.exerciseID, machineID: entry.machineID)
      if grouped[key] == nil { order.append(key) }
      grouped[key, default: []].append(entry)
    }
    return order.compactMap { key in
      guard let entries = grouped[key], let first = entries.first else { return nil }
      return Block(
        exerciseID: first.exerciseID, exerciseName: first.exerciseName,
        machineID: first.machineID, machineName: first.machineName,
        sets: entries.map(\.line))
    }
  }
}
