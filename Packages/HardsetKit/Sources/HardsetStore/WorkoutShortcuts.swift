import Foundation
import HardsetCore
import SQLiteData

/// Two shortcuts into a workout, both started by the lifter: the movements they did most recently,
/// and "repeat this workout".
///
/// Neither is a recommendation. Nothing here is preselected or offered unasked, and nothing
/// invents a plan the lifter did not perform (`HANDOFF.md` §6, no default program).
public nonisolated struct WorkoutShortcutsStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Movements most recently logged, newest first, each once. Archived movements are left out,
  /// because that is what archiving is for. Sets sharing a timestamp are ordered by their id, so the
  /// result is the same on every call.
  public func recentExercises(limit: Int = 8) throws -> [CatalogEntry] {
    guard limit > 0 else { return [] }
    return try database.read { db in
      // Archived movements are excluded before the bound, so they cannot crowd out older ones.
      let archived = Exercise.where { $0.isArchived }.select { $0.id }
      let sets = try LoggedSet
        .where { !$0.exerciseID.in(archived) }
        .order { ($0.completedAt.desc(), $0.id.asc()) }
        .limit(500)
        .fetchAll(db)
      var ordered: [UUID] = []
      var seen = Set<UUID>()
      for set in sets where seen.insert(set.exerciseID).inserted { ordered.append(set.exerciseID) }
      guard !ordered.isEmpty else { return [] }
      let rows = try Exercise.where { $0.id.in(ordered) }.where { !$0.isArchived }.fetchAll(db)
      let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
      return ordered.compactMap { byID[$0] }.prefix(limit).map(CatalogEntry.init(row:))
    }
  }

  /// What "repeat this workout" starts: the movements that were done, in order, on the machines
  /// they ended on. No loads and no set counts. Rows and prefills come from history at start, as
  /// they do for any workout.
  ///
  /// A machine comes along only if it is not archived and belongs to the past session's gym, and
  /// that gym only if it is not archived. Anything else would revive equipment the lifter removed.
  /// The movement still comes, and its chip asks for a machine.
  public func repeatPlan(of sessionID: SessionID) throws -> RepeatPlan {
    try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let rows = try SessionExercise
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { $0.position }
        .fetchAll(db)
      let sets = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchAll(db)

      // Which rows were performed, attributed exactly as `SessionCoordinator.resume` attributes
      // sets: by plan row where the set records one, and otherwise to the first row for the
      // movement.
      let rowsWithSets = Set(sets.compactMap(\.sessionExerciseID))
      let orphanExercises = Set(sets.filter { $0.sessionExerciseID == nil }.map(\.exerciseID))
      var claimed = Set<UUID>()
      let performed = rows.filter { row in
        var isPerformed = rowsWithSets.contains(row.id)
        if orphanExercises.contains(row.exerciseID), claimed.insert(row.exerciseID).inserted {
          isPerformed = true
        }
        return isPerformed
      }

      let gym = try session.gymID.flatMap { id in
        try Gym.where({ $0.id.eq(id) }).where({ !$0.isArchived }).fetchOne(db)
      }
      let machineIDs = Array(Set(performed.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: Machine]()) { $0[$1.id] = $1 }
      let exerciseIDs = Array(Set(performed.map(\.exerciseID)))
      let names =
        exerciseIDs.isEmpty
        ? [:]
        : try Exercise
          .where { $0.id.in(exerciseIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

      let items = performed.map { row -> RepeatPlan.Item in
        let machine = row.machineID
          .flatMap { machines[$0] }
          .flatMap { candidate -> Machine? in
            guard !candidate.isArchived, let gym, candidate.gymID == gym.id else { return nil }
            return candidate
          }
        return RepeatPlan.Item(
          exerciseID: ExerciseID(rawValue: row.exerciseID),
          exerciseName: names[row.exerciseID] ?? "Unknown movement",
          machineID: machine.map { MachineID(rawValue: $0.id) },
          machineName: machine.map { MachineRecord(row: $0).displayName },
          machineIncrementKg: machine?.stackIncrementKg
        )
      }
      return RepeatPlan(
        sourceSessionID: sessionID, gymID: gym.map { GymID(rawValue: $0.id) }, items: items)
    }
  }
}

/// A past workout's movements and machines, ready to start again. It holds no loads, by
/// construction.
public nonisolated struct RepeatPlan: Hashable, Sendable {
  public nonisolated struct Item: Hashable, Sendable {
    public let exerciseID: ExerciseID
    public let exerciseName: String
    public let machineID: MachineID?
    public let machineName: String?
    public let machineIncrementKg: Double?
  }

  public let sourceSessionID: SessionID
  public let gymID: GymID?
  public let items: [Item]

  public var isEmpty: Bool { items.isEmpty }
}

extension RepeatPlan {
  /// The plan `SessionCoordinator.start` takes. `plannedSets` is nil, so row counts come from
  /// history like any other start. MainActor, because `PlannedExercise` is (`DECISIONS.md` §11).
  @MainActor
  public var plannedExercises: [PlannedExercise] {
    items.map {
      PlannedExercise(
        exerciseID: $0.exerciseID, machineID: $0.machineID, exerciseName: $0.exerciseName,
        machineName: $0.machineName, machineIncrementKg: $0.machineIncrementKg, plannedSets: nil)
    }
  }
}
