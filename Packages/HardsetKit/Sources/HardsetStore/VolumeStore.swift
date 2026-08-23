import Foundation
import HardsetCore
import SQLiteData

/// Reads the sets and the attribution a volume report needs.
///
/// Two queries, both bounded by a date window, and then pure arithmetic in `VolumeAnalyzer`. The
/// counting itself has no database handle, so a volume figure cannot depend on when it was asked
/// for — which is what makes the report reproducible from the same window.
public nonisolated struct VolumeStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Completed sets in `[from, to)`.
  ///
  /// Half-open on purpose. A closed range double-counts any set landing exactly on a week boundary
  /// when two adjacent weeks are compared, which shows up as a phantom set in both.
  public func countableSets(from: Date, to: Date) throws -> [CountableSet] {
    try database.read { db in
      try LoggedSet
        .where { $0.completedAt >= from }
        .where { $0.completedAt < to }
        .order { $0.completedAt }
        .fetchAll(db)
        .map { CountableSet(exerciseID: ExerciseID(rawValue: $0.exerciseID), isWarmup: $0.isWarmup) }
    }
  }

  /// Attribution for every exercise that is not archived.
  ///
  /// Read from the database rather than from `ExerciseCatalog`, so a user's own exercises and any
  /// row a newer app version wrote are both included. An exercise whose stored attribution is
  /// unreadable is deliberately absent, which makes its sets *unattributed* rather than silently
  /// zero — the distinction the report is built on.
  public func attributionIndex() throws -> AttributionIndex {
    let entries = try database.read { db in
      try Exercise.where { !$0.isArchived }.fetchAll(db).map(CatalogEntry.init(row:))
    }
    return AttributionIndex(entries: entries)
  }

  /// The report for one window.
  public func report(from: Date, to: Date) throws -> MuscleVolumeReport {
    VolumeAnalyzer.report(
      sets: try countableSets(from: from, to: to),
      attribution: try attributionIndex()
    )
  }

  /// The report for the seven days ending at `now`.
  ///
  /// A rolling window, not a calendar week. A calendar week makes Monday morning look like a
  /// catastrophic drop in volume, which is an artefact of the boundary rather than anything about
  /// the training. If a calendar week is ever wanted it should be a separate, named function so
  /// the two can never be confused.
  public func rollingWeek(endingAt now: Date) throws -> MuscleVolumeReport {
    try report(from: now.addingTimeInterval(-7 * 86_400), to: now)
  }
}

/// Reads load history for one exercise, per machine.
public nonisolated struct ProgressionStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Completed working sets for one exercise, across every machine, oldest first.
  ///
  /// Warm-ups are excluded in SQL. A warm-up reaching the analyser would be a bug, so it is not
  /// filtered defensively there — that would hide it.
  public func samples(for exerciseID: ExerciseID, limit: Int = 2_000) throws
    -> [ProgressionSample]
  {
    try database.read { db in
      try LoggedSet
        .where { $0.exerciseID.eq(exerciseID.rawValue) }
        .where { !$0.isWarmup }
        .order { $0.completedAt }
        .limit(limit)
        .fetchAll(db)
        .map {
          ProgressionSample(
            sessionID: SessionID(rawValue: $0.sessionID),
            machineID: $0.machineID.map(MachineID.init(rawValue:)),
            weightKg: $0.weightKg,
            reps: $0.reps,
            completedAt: $0.completedAt
          )
        }
    }
  }

  /// Machine names, for labelling the series. A machine the user deleted resolves to `nil` and the
  /// series is labelled generically rather than dropped — the sets were still performed.
  public func machineNames(_ ids: [MachineID]) throws -> [MachineID: String] {
    guard !ids.isEmpty else { return [:] }
    let raws = ids.map(\.rawValue)
    return try database.read { db in
      try Machine
        .where { $0.id.in(raws) }
        .fetchAll(db)
        .reduce(into: [MachineID: String]()) { $0[MachineID(rawValue: $1.id)] = $1.name }
    }
  }

  /// Everything a load-history chart needs for one exercise.
  /// Which gym each machine belongs to.
  ///
  /// Read so the chart can spend colour on the gym and stroke on the machine. Two leg presses in
  /// one gym are the same hue and different dashes; the same movement at another gym is a
  /// different hue, which is the distinction the whole per-machine feature exists to draw.
  public func machineGyms(_ ids: [MachineID]) throws -> [MachineID: GymID] {
    guard !ids.isEmpty else { return [:] }
    let raws = ids.map(\.rawValue)
    return try database.read { db in
      try Machine
        .where { $0.id.in(raws) }
        .fetchAll(db)
        .reduce(into: [MachineID: GymID]()) {
          $0[MachineID(rawValue: $1.id)] = GymID(rawValue: $1.gymID)
        }
    }
  }

  public func history(for exerciseID: ExerciseID) throws -> ProgressionHistory {
    let samples = try samples(for: exerciseID)
    let series = ProgressionAnalyzer.series(from: samples, exerciseID: exerciseID)
    let changes = ProgressionAnalyzer.machineChanges(from: samples)
    let machineIDs = series.compactMap(\.key.machineID)
    let names = try machineNames(machineIDs)
    let gyms = try machineGyms(machineIDs)
    return ProgressionHistory(
      series: series, machineChanges: changes, machineNames: names, machineGyms: gyms
    )
  }
}

/// One exercise's load history, ready to plot.
public nonisolated struct ProgressionHistory: Hashable, Sendable {
  public let series: [ProgressionSeries]
  public let machineChanges: [MachineChange]
  public let machineNames: [MachineID: String]
  /// Which gym each machine sits in. Empty for free-weight series, and for a machine whose gym
  /// row has gone.
  public let machineGyms: [MachineID: GymID]

  public init(
    series: [ProgressionSeries],
    machineChanges: [MachineChange],
    machineNames: [MachineID: String],
    machineGyms: [MachineID: GymID] = [:]
  ) {
    self.series = series
    self.machineChanges = machineChanges
    self.machineNames = machineNames
    self.machineGyms = machineGyms
  }

  /// Label for a series. Free-weight work and a deleted machine are named rather than blank.
  public func label(for key: ProgressionKey) -> String {
    guard let machineID = key.machineID else { return "Free weight" }
    return machineNames[machineID] ?? "Unnamed machine"
  }

  public var isEmpty: Bool { series.isEmpty }

  /// Gyms in the order the caller's series mention them, so a hue attaches to a gym permanently
  /// for one chart rather than shifting when a series is filtered out.
  ///
  /// Free-weight series -- and machines whose gym is unknown -- share the last slot rather than
  /// claiming a hue, because "no gym" is one bucket, not several.
  public func gymOrder(for keys: [ProgressionKey]) -> [GymID] {
    var seen: [GymID] = []
    for key in keys {
      guard let machineID = key.machineID, let gym = machineGyms[machineID] else { continue }
      if !seen.contains(gym) { seen.append(gym) }
    }
    return seen
  }
}

/// One past session, summarised for a list.
/// One logged set, as history reads it back.
public nonisolated struct LoggedSetDetail: Hashable, Sendable, Identifiable {
  public let id: SetID
  public let exerciseID: ExerciseID
  public let exerciseName: String
  /// How the movement is loaded. Needed so history does not read back a pull-up as "0 kg".
  public let modality: ExerciseModality?
  /// `nil` for free weights, or a machine whose row has been removed.
  public let machineName: String?
  public let weightKg: Double
  public let reps: Int
  /// Effort as recorded, or `nil` if none was.
  public let rpe: Double?
  public let isWarmup: Bool
  public let completedAt: Date

  public init(
    id: SetID,
    exerciseID: ExerciseID,
    exerciseName: String,
    modality: ExerciseModality? = nil,
    machineName: String?,
    weightKg: Double,
    reps: Int,
    rpe: Double? = nil,
    isWarmup: Bool,
    completedAt: Date
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.modality = modality
    self.machineName = machineName
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.isWarmup = isWarmup
    self.completedAt = completedAt
  }
}

public nonisolated struct SessionSummary: Hashable, Sendable, Identifiable {
  public let id: SessionID
  public let title: String
  public let timeline: SessionTimeline
  /// Distinct movements performed, in the order they were first logged.
  public let exerciseNames: [String]
  public let volume: SessionVolume

  public init(
    id: SessionID,
    title: String,
    timeline: SessionTimeline,
    exerciseNames: [String],
    volume: SessionVolume
  ) {
    self.id = id
    self.title = title
    self.timeline = timeline
    self.exerciseNames = exerciseNames
    self.volume = volume
  }

  /// A session recorded as implausibly long is quarantined rather than displayed as an
  /// achievement. The ancestor shipped 9,749-minute workouts to its history screen.
  public var hasImplausibleDuration: Bool { timeline.isImplausible }
}

/// Reads finished sessions for the history screen.
public nonisolated struct HistoryStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Discards a workout and, by cascade, its sets and plan rows.
  ///
  /// Exposed on `HistoryStore` so the history screen does not need a `LoggerStore` just to delete
  /// what it is already displaying.
  public func deleteSession(_ sessionID: SessionID) throws {
    try database.write { db in
      try Session.where { $0.id.eq(sessionID.rawValue) }.delete().execute(db)
    }
  }

  /// Every set logged in one session, in order, with the names needed to read it back.
  ///
  /// The counterpart to `recentSessions`: that answers "what workouts have I done", this answers
  /// "what did I actually do in that one". History was a dead end without it -- `HistoryView` has
  /// always taken an `onSelect`, and nothing passed one, so every row was a disabled button.
  ///
  /// Machine names come along because a set's load is only meaningful next to the equipment it was
  /// lifted on, which is the whole premise of tracking per machine.
  public func sets(in sessionID: SessionID) throws -> [LoggedSetDetail] {
    try database.read { db in
      let rows = try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { $0.setOrdinal }
        .fetchAll(db)
      guard !rows.isEmpty else { return [] }

      let exercises = try Exercise
        .where { $0.id.in(Array(Set(rows.map(\.exerciseID)))) }
        .fetchAll(db)
        .reduce(into: [UUID: Exercise]()) { $0[$1.id] = $1 }

      let machineIDs = Array(Set(rows.compactMap(\.machineID)))
      let machineNames = machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

      return rows.map { row in
        LoggedSetDetail(
          id: SetID(rawValue: row.id),
          exerciseID: ExerciseID(rawValue: row.exerciseID),
          exerciseName: exercises[row.exerciseID]?.name ?? "Unknown movement",
          modality: exercises[row.exerciseID].flatMap { ExerciseModality(rawValue: $0.modality) },
          machineName: row.machineID.flatMap { machineNames[$0] },
          weightKg: row.weightKg,
          reps: row.reps,
          rpe: row.rpe,
          isWarmup: row.isWarmup,
          completedAt: row.completedAt
        )
      }
    }
  }

  /// Finished sessions, newest first.
  ///
  /// Open sessions are excluded: an unfinished workout belongs in the recovery path, not in
  /// history, and showing it with no duration invites the reader to think it lasted zero minutes.
  public func recentSessions(limit: Int = 50) throws -> [SessionSummary] {
    try database.read { db in
      let sessions = try Session
        .where { $0.finishedAt.isNot(nil) }
        .order { $0.startedAt.desc() }
        .limit(limit)
        .fetchAll(db)
      guard !sessions.isEmpty else { return [] }

      let sessionIDs = sessions.map(\.id)
      let sets = try LoggedSet
        .where { $0.sessionID.in(sessionIDs) }
        .order { $0.setOrdinal }
        .fetchAll(db)

      let exerciseIDs = Array(Set(sets.map(\.exerciseID)))
      let names = exerciseIDs.isEmpty
        ? [:]
        : try Exercise
          .where { $0.id.in(exerciseIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

      let setsBySession = Dictionary(grouping: sets, by: \.sessionID)

      return sessions.map { session in
        let own = setsBySession[session.id] ?? []
        var seen = Set<UUID>()
        var ordered: [String] = []
        for set in own where !seen.contains(set.exerciseID) {
          seen.insert(set.exerciseID)
          ordered.append(names[set.exerciseID] ?? "Unknown movement")
        }
        return SessionSummary(
          id: SessionID(rawValue: session.id),
          title: session.title,
          timeline: SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt),
          exerciseNames: ordered,
          volume: Self.volume(of: own)
        )
      }
    }
  }

  /// Reuses `SessionVolume`'s rules so the history screen and the live screen cannot disagree
  /// about what a session contained.
  private static func volume(of sets: [LoggedSet]) -> SessionVolume {
    var workingSets = 0
    var warmupSets = 0
    var volumeKg = 0.0
    var reps = 0
    for set in sets {
      if set.isWarmup {
        warmupSets += 1
      } else {
        workingSets += 1
        volumeKg += set.weightKg * Double(set.reps)
        reps += set.reps
      }
    }
    return SessionVolume(
      workingSets: workingSets, warmupSets: warmupSets, volumeKg: volumeKg, reps: reps
    )
  }
}
