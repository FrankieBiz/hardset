import Foundation
import HardsetCore
import SQLiteData

/// Builds the widgets' snapshot from finished workouts only.
///
/// An open workout is still being done: its sets are not "last time" yet, and a half-finished
/// session is not the last workout. Warm-ups are not what a lifter means by last time either.
public nonisolated struct WidgetSnapshotStore {
  /// Finished sessions examined for "last time". Bounded, so years of history cost nothing.
  static let sessionWindow = 30

  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  public func snapshot(unit: WeightUnit, now: Date = Date()) throws -> WidgetSnapshot {
    let last = try HistoryStore(database: database).recentSessions(limit: 1).first
    let lastWorkout = last.flatMap { summary -> WidgetSnapshot.LastWorkout? in
      guard let finishedAt = summary.timeline.finishedAt else { return nil }
      let length = summary.timeline.isImplausible ? nil : summary.timeline.duration
      return WidgetSnapshot.LastWorkout(
        startedAt: summary.timeline.startedAt, finishedAt: finishedAt,
        lengthSeconds: length.flatMap { $0 > .zero ? $0.seconds : nil },
        workingSets: summary.volume.workingSets, volumeKg: summary.volume.volumeKg,
        movementCount: summary.exerciseNames.count)
    }
    return WidgetSnapshot(
      writtenAt: now, unit: unit, lastWorkout: lastWorkout, lastTimes: try lastTimes())
  }

  /// The most recently trained movements-on-machines, each with its own last finished session.
  private func lastTimes() throws -> [WidgetSnapshot.LastTime] {
    try database.read { db in
      let sessions = try Session
        .where { $0.finishedAt.isNot(nil) }
        .order { $0.startedAt.desc() }
        .limit(Self.sessionWindow)
        .fetchAll(db)
      guard !sessions.isEmpty else { return [] }
      let sets = try LoggedSet
        .where { $0.sessionID.in(sessions.map(\.id)) }
        .where { !$0.isWarmup }
        .fetchAll(db)

      // Newest set first decides which key was trained most recently, and in which session.
      var order: [ProgressionKey] = []
      var latestSession: [ProgressionKey: UUID] = [:]
      for set in sets.sorted(by: { $0.completedAt > $1.completedAt }) {
        let key = ProgressionKey(
          exerciseID: ExerciseID(rawValue: set.exerciseID),
          machineID: set.machineID.map(MachineID.init(rawValue:)))
        if latestSession[key] == nil {
          latestSession[key] = set.sessionID
          order.append(key)
        }
      }
      let keys = Array(order.prefix(WidgetSnapshot.lastTimeLimit))
      guard !keys.isEmpty else { return [] }

      let exerciseIDs = Array(Set(keys.map(\.exerciseID.rawValue)))
      let names = try Exercise.where { $0.id.in(exerciseIDs) }.fetchAll(db)
        .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
      let machineIDs = Array(Set(keys.compactMap(\.machineID?.rawValue)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine.where { $0.id.in(machineIDs) }.fetchAll(db)
          .reduce(into: [MachineID: String]()) {
            $0[MachineID(rawValue: $1.id)] = MachineRecord(row: $1).displayName
          }
      let labels = Self.distinctLabels(for: keys, names: machines)

      return keys.compactMap { key in
        let own = sets
          .filter {
            $0.sessionID == latestSession[key] && $0.exerciseID == key.exerciseID.rawValue
              && $0.machineID == key.machineID?.rawValue
          }
          .sorted { ($0.completedAt, $0.setOrdinal) < ($1.completedAt, $1.setOrdinal) }
        return Self.lastTime(
          key: key, sets: own, exerciseName: names[key.exerciseID.rawValue] ?? "Unknown movement",
          machineName: labels[key])
      }
    }
  }

  /// One "last time" entry from a movement's sets in its last session, oldest first. Without a
  /// set there is no date, and a widget must never show one the lifter did not train on.
  static func lastTime(
    key: ProgressionKey, sets own: [LoggedSet], exerciseName: String, machineName: String?
  ) -> WidgetSnapshot.LastTime? {
    guard let performedAt = own.last?.completedAt else { return nil }
    return WidgetSnapshot.LastTime(
      exerciseID: key.exerciseID, machineID: key.machineID,
      exerciseName: exerciseName, machineName: machineName,
      performedAt: performedAt,
      sets: own.map { WidgetSnapshot.SetLine(weightKg: $0.weightKg, reps: $0.reps) })
  }

  /// Machine names, numbered when two in the snapshot share one, so the widget never shows two
  /// machines as if they were one (`DECISIONS.md` §20). Numbered by machine id, as the chart is,
  /// so a label does not change with habits.
  static func distinctLabels(
    for keys: [ProgressionKey], names: [MachineID: String]
  ) -> [ProgressionKey: String] {
    let machineKeys = keys.filter { $0.machineID != nil }
    let byName = Dictionary(grouping: machineKeys) { names[$0.machineID!] ?? "Unnamed machine" }
    var labels: [ProgressionKey: String] = [:]
    for (name, group) in byName {
      // Same machine, different movements, share a label; only different machines are numbered.
      let machines = Array(Set(group.compactMap(\.machineID))).sorted {
        $0.rawValue.uuidString < $1.rawValue.uuidString
      }
      for key in group {
        let index = machines.firstIndex(of: key.machineID!) ?? 0
        labels[key] = index == 0 ? name : "\(name) (\(index + 1))"
      }
    }
    return labels
  }
}
