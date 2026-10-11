import Foundation
import HardsetCore
import SQLiteData

/// Reads one past workout for the session detail screen, from storage only.
///
/// The totals, records and length come from `WorkoutSummaryStore`, so the detail and the finish
/// summary cannot disagree. Archived machines and movements keep their names: archiving hides
/// equipment from pickers, it does not un-perform the sets.
public nonisolated struct SessionDetailStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func detail(for sessionID: SessionID) throws -> SessionDetail {
    let summary = try WorkoutSummaryStore(database: database).summary(for: sessionID)
    var records: [SetID: [PersonalRecord]] = [:]
    for line in summary.records { records[line.setID, default: []].append(line.record) }

    let entries = try database.read { db in
      let sets = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.fetchAll(db)
      let exerciseIDs = Array(Set(sets.map(\.exerciseID)))
      let names =
        exerciseIDs.isEmpty
        ? [:]
        : try Exercise
          .where { $0.id.in(exerciseIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
      let machineIDs = Array(Set(sets.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = MachineRecord(row: $1).displayName }
      return sets.map { set in
        let setID = SetID(rawValue: set.id)
        return SessionDetail.Entry(
          line: SessionDetail.SetLine(
            setID: setID, weightKg: set.weightKg, reps: set.reps, isWarmup: set.isWarmup,
            records: records[setID] ?? []),
          exerciseID: ExerciseID(rawValue: set.exerciseID),
          exerciseName: names[set.exerciseID] ?? "Unknown movement",
          machineID: set.machineID.map(MachineID.init(rawValue:)),
          // A machine id with no row left is still a machine, not free weight.
          machineName: set.machineID.map { machines[$0] ?? "Unnamed machine" },
          completedAt: set.completedAt,
          setOrdinal: set.setOrdinal)
      }
    }
    return SessionDetail(summary: summary, blocks: SessionDetail.blocks(from: entries))
  }
}
