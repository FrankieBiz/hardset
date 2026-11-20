import Foundation

/// A saved workout: an ordered list of movements the lifter starts in one tap.
///
/// A template is a plan, never a record. Sessions remember their own movements, rep ranges and
/// machines, so editing or archiving a template cannot rewrite history.
public struct WorkoutTemplate: Hashable, Sendable, Identifiable {
  public let id: TemplateID
  public let name: String
  /// The lifter's rotation order. "Up next" uses it to break ties between equally stale plans.
  public let position: Int
  public let exercises: [TemplateExercise]
  /// The most recent finished session started from this template, or nil when never done.
  public let lastDoneAt: Date?

  public init(
    id: TemplateID = TemplateID(),
    name: String,
    position: Int,
    exercises: [TemplateExercise] = [],
    lastDoneAt: Date? = nil
  ) {
    self.id = id
    self.name = name
    self.position = position
    self.exercises = exercises
    self.lastDoneAt = lastDoneAt
  }
}

/// One movement inside a saved workout, with the plan for its sets.
public struct TemplateExercise: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let exerciseID: ExerciseID
  public let exerciseName: String
  public let machineID: MachineID?
  public let machineName: String?
  /// Clamped to 1...10. A plan never asks for zero sets or an unbounded list.
  public let plannedSets: Int
  public let repRange: RepRange?
  /// The lifter's remembered rest for this movement. Non-positive values are stored as nil.
  public let restSeconds: Int?

  public init(
    id: UUID = UUID(),
    exerciseID: ExerciseID,
    exerciseName: String,
    machineID: MachineID? = nil,
    machineName: String? = nil,
    plannedSets: Int,
    repRange: RepRange? = nil,
    restSeconds: Int? = nil
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.machineID = machineID
    self.machineName = machineName
    self.plannedSets = min(max(plannedSets, 1), 10)
    self.repRange = repRange
    self.restSeconds = restSeconds.flatMap { $0 > 0 ? $0 : nil }
  }
}

/// The reps a movement is planned for, for example 8 to 12.
public struct RepRange: Hashable, Sendable, Codable {
  public let lower: Int
  public let upper: Int

  /// Nil unless the range is a real, bounded one: `1 <= lower <= upper <= 50`.
  public init?(lower: Int, upper: Int) {
    guard 1 <= lower, lower <= upper, upper <= 50 else { return nil }
    self.lower = lower
    self.upper = upper
  }

  /// The range as the lifter reads it: "8–12", or "10" for a fixed rep count.
  public var label: String {
    lower == upper ? "\(lower)" : "\(lower)–\(upper)"
  }
}

/// Decides which saved workout is offered next.
public enum WorkoutRotation {
  /// Never-done workouts come first by position, then the longest-ago workout, ties by position.
  ///
  /// Alternating Upper A and Upper B needs no schedule: the plan done longest ago is the one
  /// offered, so a rotation of two simply swaps.
  public static func upNextOrder(_ templates: [WorkoutTemplate]) -> [WorkoutTemplate] {
    templates.sorted { lhs, rhs in
      switch (lhs.lastDoneAt, rhs.lastDoneAt) {
      case (nil, nil):
        return lhs.position < rhs.position
      case (nil, _):
        return true
      case (_, nil):
        return false
      case let (left?, right?):
        if left != right { return left < right }
        return lhs.position < rhs.position
      }
    }
  }
}
