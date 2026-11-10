import Foundation
import HardsetCore
import SQLiteData

/// A preview of performed work, not a training prescription. No logged facts are copied.
public nonisolated struct RepeatWorkout: Sendable {
  public let sourceID: SessionID
  public let title: String
  public let gymID: GymID?
  public nonisolated struct Entry: Sendable, Identifiable {
    public let id: UUID
    public let exercise: PlannedExercise
  }
  public let entries: [Entry]
  public var exercises: [PlannedExercise] { entries.map(\.exercise) }
  public let omittedMovements: Int
  public var workingSets: Int { exercises.reduce(0) { $0 + ($1.plannedSets ?? 0) } }
}

public nonisolated enum RepeatWorkoutError: Error, Equatable {
  case unfinishedOrMissing
  case noAvailableWorkingSets
  case gymChanged
}

public nonisolated struct RepeatWorkoutStore: Sendable {
  private let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  /// One consistent read, performed only when the lifter selects a source workout.
  public func load(_ id: SessionID, at gymID: GymID?) async throws -> RepeatWorkout {
    try Task.checkCancellation()
    return try await database.read { db in
      guard let session = try Session.where({ $0.id.eq(id.rawValue) }).fetchOne(db),
        session.finishedAt != nil else { throw RepeatWorkoutError.unfinishedOrMissing }
      let plan = try SessionExercise.where { $0.sessionID.eq(id.rawValue) }
        .order { ($0.position, $0.id) }.fetchAll(db)
      let sets = try LoggedSet.where { $0.sessionID.eq(id.rawValue) && !$0.isWarmup }
        .order { ($0.completedAt, $0.setOrdinal, $0.id) }.fetchAll(db)
      let ids = Set(sets.map(\.exerciseID))
      let exercises = try Exercise.where { $0.id.in(ids) }.fetchAll(db)
      let names = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
      let machineIDs = Set(sets.compactMap(\.machineID))
      let machines = try Machine.where { $0.id.in(machineIDs) }.fetchAll(db)
      let equipment = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
      // Keep repeated occurrences of a movement distinct, and split a mid-exercise
      // equipment change into separate entries. Legacy/imported sets have no plan row.
      struct Key: Hashable {
        let row: UUID?
        let exercise: UUID
        let machine: UUID?
      }
      let groups = Dictionary(grouping: sets) {
        Key(row: $0.sessionExerciseID, exercise: $0.exerciseID, machine: $0.machineID)
      }
      let positions = Dictionary(uniqueKeysWithValues: plan.enumerated().map { ($0.element.id, $0.offset) })
      let ordered = groups.keys.sorted { lhs, rhs in
        let l = lhs.row.flatMap { positions[$0] } ?? Int.max
        let r = rhs.row.flatMap { positions[$0] } ?? Int.max
        if l != r { return l < r }
        let a = groups[lhs]!.first!, b = groups[rhs]!.first!
        if a.completedAt != b.completedAt { return a.completedAt < b.completedAt }
        if a.setOrdinal != b.setOrdinal { return a.setOrdinal < b.setOrdinal }
        return a.id.uuidString < b.id.uuidString
      }
      var omitted = 0
      let entries = ordered.compactMap { key -> RepeatWorkout.Entry? in
        guard let exercise = names[key.exercise], !exercise.isArchived else {
          omitted += 1
          return nil
        }
        let recorded = key.machine.flatMap { equipment[$0] }
        let machine = recorded.flatMap { !$0.isArchived && $0.gymID == gymID?.rawValue ? $0 : nil }
        let exercisePlan = PlannedExercise(exerciseID: ExerciseID(rawValue: key.exercise),
          machineID: machine.map { MachineID(rawValue: $0.id) }, exerciseName: exercise.name,
          machineName: machine.map { [$0.brand, $0.name].filter { !$0.isEmpty }.joined(separator: " ") },
          machineIncrementKg: machine?.stackIncrementKg, plannedSets: groups[key]!.count)
        return RepeatWorkout.Entry(id: groups[key]!.first!.id, exercise: exercisePlan)
      }
      guard !entries.isEmpty else { throw RepeatWorkoutError.noAvailableWorkingSets }
      return RepeatWorkout(sourceID: id, title: session.title, gymID: gymID,
        entries: entries, omittedMovements: omitted)
    }
  }
}
