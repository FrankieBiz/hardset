import Foundation

/// How much of one workout's own plan the lifter actually did.
///
/// The spine is the session's plan rows, in the order they were planned. A row is present only
/// when the plan stated a working-set count; a plan row with no count is absent rather than a
/// "0 of 0", and a movement removed from the plan is absent with it. A workout with no plan at all
/// has no block. Counts only: no percentage, no grade, and no failure state for a movement that
/// was not done.
///
/// The logged sets are the other half. A working set counts for the plan row it names. A set
/// written before sets recorded their plan row counts only when its movement and machine name
/// exactly one plan row in the session; two rows sharing that pair make it ambiguous, and a guess
/// would be worse than no figure. Warm-ups are never part of either side.
public struct PlannedVsDone: Hashable, Sendable {
  /// One planned movement, as the session's plan row states it.
  public struct PlanRow: Hashable, Sendable {
    public let id: UUID
    public let exerciseID: ExerciseID?
    public let exerciseName: String
    public let equipment: WorkoutReceipt.Equipment
    /// The count the plan stated. `nil` and zero both produce no row.
    public let plannedSets: Int?
    public let machineID: MachineID?

    public init(
      id: UUID, exerciseID: ExerciseID?, exerciseName: String,
      equipment: WorkoutReceipt.Equipment, plannedSets: Int?, machineID: MachineID?
    ) {
      self.id = id
      self.exerciseID = exerciseID
      self.exerciseName = exerciseName
      self.equipment = equipment
      self.plannedSets = plannedSets
      self.machineID = machineID
    }
  }

  /// One logged set, as far as counting planned against done needs it.
  public struct LoggedSet: Hashable, Sendable {
    public let sessionExerciseID: UUID?
    public let exerciseID: ExerciseID
    public let machineID: MachineID?
    public let isWarmup: Bool

    public init(
      sessionExerciseID: UUID?, exerciseID: ExerciseID, machineID: MachineID?, isWarmup: Bool
    ) {
      self.sessionExerciseID = sessionExerciseID
      self.exerciseID = exerciseID
      self.machineID = machineID
      self.isWarmup = isWarmup
    }
  }

  /// One planned movement and the working sets it got.
  public struct Row: Hashable, Sendable, Identifiable {
    /// The sessionExercises row id.
    public let id: UUID
    public let exerciseID: ExerciseID?
    public let exerciseName: String
    public let equipment: WorkoutReceipt.Equipment
    public let plannedSets: Int
    public let doneSets: Int

    public init(
      id: UUID, exerciseID: ExerciseID?, exerciseName: String,
      equipment: WorkoutReceipt.Equipment, plannedSets: Int, doneSets: Int
    ) {
      self.id = id
      self.exerciseID = exerciseID
      self.exerciseName = exerciseName
      self.equipment = equipment
      self.plannedSets = plannedSets
      self.doneSets = doneSets
    }
  }

  public let rows: [Row]

  public var plannedTotal: Int { rows.reduce(0) { $0 + $1.plannedSets } }
  public var doneTotal: Int { rows.reduce(0) { $0 + $1.doneSets } }

  /// Builds a block from rows that are already known, for a preview or a snapshot.
  public init(rows: [Row]) {
    self.rows = rows
  }

  /// The block for one session, or nil when there is nothing honest to compare.
  ///
  /// Nil for an imported workout: the plan in an imported file was never an intention recorded in
  /// this app. Nil too when no plan row states a positive count, rather than an empty table.
  public init?(
    planRows: [PlanRow], loggedSets: [LoggedSet], notes: String = ""
  ) {
    guard !notes.hasPrefix("Imported from ") else { return nil }
    let planned = planRows.filter { ($0.plannedSets ?? 0) > 0 }
    guard !planned.isEmpty else { return nil }

    // A set with no plan row can be attributed only when the plan has one row for its movement
    // and machine. Count every plan row here, including one with no stated count: it still makes
    // the set's owner ambiguous.
    var rowsByPair: [Pair: Int] = [:]
    for plan in planRows {
      rowsByPair[Pair(exerciseID: plan.exerciseID, machineID: plan.machineID), default: 0] += 1
    }
    var doneByRow: [UUID: Int] = [:]
    var doneByPair: [Pair: Int] = [:]
    for set in loggedSets where !set.isWarmup {
      if let rowID = set.sessionExerciseID {
        doneByRow[rowID, default: 0] += 1
      } else {
        doneByPair[Pair(exerciseID: set.exerciseID, machineID: set.machineID), default: 0] += 1
      }
    }

    rows = planned.map { plan in
      let pair = Pair(exerciseID: plan.exerciseID, machineID: plan.machineID)
      let named = doneByRow[plan.id] ?? 0
      let unassigned = rowsByPair[pair] == 1 ? doneByPair[pair] ?? 0 : 0
      return Row(
        id: plan.id, exerciseID: plan.exerciseID, exerciseName: plan.exerciseName,
        equipment: plan.equipment, plannedSets: plan.plannedSets ?? 0, doneSets: named + unassigned)
    }
  }

  /// The pair a set with no plan row must match to belong to a plan row.
  private struct Pair: Hashable {
    let exerciseID: ExerciseID?
    let machineID: MachineID?
  }
}

/// The words on the planned-against-done block, held apart from any view so they are tested
/// without one.
///
/// Every phrase is a count. Nothing here calls a movement missed or failed, offers advice, or
/// turns a shortfall into a percentage.
public enum PlannedVsDoneCopy {
  public static let heading = "Planned against done"

  /// "3 of 4 planned sets": a lower-case count phrase with no verb.
  public static func rowText(done: Int, planned: Int) -> String {
    "\(done) of \(planned) planned sets"
  }

  public static func rowText(_ row: PlannedVsDone.Row) -> String {
    rowText(done: row.doneSets, planned: row.plannedSets)
  }

  /// The total is stated only when there is more than one row, where adding them says something
  /// the rows do not.
  public static func totalText(_ planned: PlannedVsDone) -> String? {
    guard planned.rows.count > 1 else { return nil }
    return rowText(done: planned.doneTotal, planned: planned.plannedTotal)
  }

  public static func accessibilityLabel(_ row: PlannedVsDone.Row) -> String {
    "\(row.exerciseName), \(rowText(row))"
  }
}
