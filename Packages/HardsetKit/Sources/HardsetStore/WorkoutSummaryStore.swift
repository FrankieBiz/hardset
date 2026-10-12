import Foundation
import HardsetCore
import SQLiteData

/// Reads the summary of one workout, from storage only.
///
/// Nothing here comes from the live screen. Totals reuse the history screen's count, records are
/// re-judged by `recordsBySet`, and muscles are counted by `VolumeAnalyzer` against the same
/// attribution as the volume screen. So no screen can disagree with another about the same
/// session.
public nonisolated struct WorkoutSummaryStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func summary(for sessionID: SessionID) throws -> WorkoutSummary {
    let records = try LoggerStore(database: database).recordsBySet(in: sessionID)
    let attribution = try VolumeStore(database: database).attributionIndex()
    return try database.read { db in
      guard let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db) else {
        throw LoggerStoreError.sessionNotFound
      }
      let sets = try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { ($0.completedAt, $0.setOrdinal) }
        .fetchAll(db)

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

      var lines: [WorkoutSummary.RecordLine] = []
      var used: [String] = []
      var seenMachines = Set<UUID>()
      for set in sets {
        // A machine id with no row left is still a machine, named as the session detail names it.
        if let machineID = set.machineID, seenMachines.insert(machineID).inserted {
          used.append(machines[machineID] ?? "Unnamed machine")
        }
        let setID = SetID(rawValue: set.id)
        for record in records[setID] ?? [] {
          lines.append(
            WorkoutSummary.RecordLine(
              setID: setID,
              exerciseName: names[set.exerciseID] ?? "Unknown movement",
              machineName: set.machineID.map { machines[$0] ?? "Unnamed machine" },
              record: record
            )
          )
        }
      }

      let report = VolumeAnalyzer.report(
        sets: sets.map {
          CountableSet(exerciseID: ExerciseID(rawValue: $0.exerciseID), isWarmup: $0.isWarmup)
        },
        attribution: attribution
      )
      return WorkoutSummary(
        sessionID: sessionID,
        timeline: SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt),
        volume: HistoryStore.volume(of: sets),
        records: lines,
        muscles: WorkoutSummary.muscleLines(from: report),
        unattributedSets: report.unattributedHardSets,
        machinesUsed: used
      )
    }
  }
}
