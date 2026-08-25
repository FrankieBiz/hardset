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
        .map {
          CountableSet(
            exerciseID: ExerciseID(rawValue: $0.exerciseID),
            kind: SetKind(isWarmup: $0.isWarmup, isDropSet: $0.isDropSet)
          )
        }
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

  /// Every countable set belonging to one session, identified by the session rather than by time.
  public func countableSets(in sessionID: SessionID) throws -> [CountableSet] {
    try database.read { db in
      try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { $0.completedAt }
        .fetchAll(db)
        .map {
          CountableSet(
            exerciseID: ExerciseID(rawValue: $0.exerciseID),
            kind: SetKind(isWarmup: $0.isWarmup, isDropSet: $0.isDropSet)
          )
        }
    }
  }

  /// The report for one workout.
  ///
  /// Scoped by session id, not by its start and finish times. The summary screen used
  /// `report(from: startedAt, to: finishedAt)`, and that window is half-open at the top -- so a set
  /// logged in the same instant the workout was finished fell outside its own summary. It also could
  /// not tell whose sets it was counting: anything else logged in that span, from an overlapping or
  /// a back-dated session, was counted as part of this workout.
  ///
  /// The session id is the fact. The timestamps are a description of it.
  public func report(for sessionID: SessionID) throws -> MuscleVolumeReport {
    VolumeAnalyzer.report(
      sets: try countableSets(in: sessionID),
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
  /// filtered defensively there — that would hide it. Drops are excluded on the same line: the
  /// chart plots a session's best work, and a set continued at a reduced load is neither a
  /// heaviest load nor an estimable one-rep max.
  public func samples(for exerciseID: ExerciseID, limit: Int = 2_000) throws
    -> [ProgressionSample]
  {
    try database.read { db in
      try LoggedSet
        .where { $0.exerciseID.eq(exerciseID.rawValue) }
        .where { !$0.isWarmup && !$0.isDropSet }
        // Newest first, then reversed below. `.order { $0.completedAt }` is ASC, so pairing it
        // with `.limit` kept the OLDEST rows and silently dropped the newest -- a lifter past the
        // cap had a chart that stopped years ago and a "last trained" date to match. Truncating a
        // history has to drop the far end, not the near one.
        //
        // Reversed rather than handed back descending, because `ProgressionAnalyzer.machineChanges`
        // breaks timestamp ties on the input's own index to keep the result deterministic. Handing
        // it a reversed array would flip which machine reads as "from" and which as "to" for two
        // blocks sharing an instant.
        .order { $0.completedAt.desc() }
        .limit(limit)
        .fetchAll(db)
        .reversed()
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
/// One movement from a past workout, ready to be planned again.
public nonisolated struct RepeatableExercise: Hashable, Sendable, Identifiable {
  public let exerciseID: ExerciseID
  public let exerciseName: String
  /// How the movement is loaded.
  ///
  /// Carried because the repeated session is a *logging* session: without it a bodyweight day came
  /// back as loaded rows, so "Do it again" on a pull-up workout produced rows demanding a weight,
  /// showing an empty field where "Body" belongs. `LoggedSetDetail` already carries the modality --
  /// it was dropped building this.
  public let modality: ExerciseModality?
  public let machineID: MachineID?
  public let machineName: String?
  /// How many working sets were actually done, so the new session opens with the same number of
  /// rows rather than an invented default.
  public let workingSets: Int

  public var id: String { "\(exerciseID.rawValue)|\(machineID?.rawValue.uuidString ?? "-")" }

  public init(
    exerciseID: ExerciseID,
    exerciseName: String,
    modality: ExerciseModality? = nil,
    machineID: MachineID?,
    machineName: String?,
    workingSets: Int
  ) {
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.modality = modality
    self.machineID = machineID
    self.machineName = machineName
    self.workingSets = workingSets
  }
}

/// One logged set, as history reads it back.
public nonisolated struct LoggedSetDetail: Hashable, Sendable, Identifiable {
  public let id: SetID
  public let exerciseID: ExerciseID
  public let exerciseName: String
  /// How the movement is loaded. Needed so history does not read back a pull-up as "0 kg".
  public let modality: ExerciseModality?
  /// Which machine, so a repeated workout returns to the same equipment.
  public let machineID: MachineID?
  /// `nil` for free weights, or a machine whose row has been removed.
  public let machineName: String?
  public let weightKg: Double
  public let reps: Int
  /// Effort as recorded, or `nil` if none was.
  public let rpe: Double?
  /// Working, warm-up or drop. History has to be able to show a drop as one, or a chain reads as
  /// three unexplained sets at falling loads.
  public let kind: SetKind
  public let completedAt: Date

  public var isWarmup: Bool { kind == .warmup }

  public init(
    id: SetID,
    exerciseID: ExerciseID,
    exerciseName: String,
    modality: ExerciseModality? = nil,
    machineID: MachineID? = nil,
    machineName: String?,
    weightKg: Double,
    reps: Int,
    rpe: Double? = nil,
    kind: SetKind,
    completedAt: Date
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.modality = modality
    self.machineID = machineID
    self.machineName = machineName
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.kind = kind
    self.completedAt = completedAt
  }

  // No `isWarmup:` convenience, for the same reason `LoggedSetRow` has none: this is built by
  // mapping stored rows, and a Bool would silently promote a drop to a working set.
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

  /// The shape of a past workout, ready to start again.
  ///
  /// Rebuilt from the sets that were actually logged rather than from the plan rows, because the
  /// plan is what was intended and the sets are what happened -- a movement added and never used
  /// should not come back, and one added mid-session should.
  ///
  /// Machine is carried per movement, which is the point: repeating leg day at the same gym should
  /// put you back on the same leg press, and that is what makes the prefilled loads meaningful.
  public func plan(for sessionID: SessionID) throws -> [RepeatableExercise] {
    let logged = try sets(in: sessionID)
    var order: [String] = []
    var byKey: [String: RepeatableExercise] = [:]

    // Drops are skipped as well as warm-ups. Repeating a workout opens rows to log into, and a
    // drop is not a row you plan -- it is one you add when you get there.
    for set in logged where set.kind.countsAsWorkingSet {
      // Keyed on movement *and* machine, so two blocks on different equipment come back as two
      // entries rather than merging -- the same rule the chart follows.
      let key = "\(set.exerciseID.rawValue)|\(set.machineID?.rawValue.uuidString ?? "-")"
      if let existing = byKey[key] {
        byKey[key] = RepeatableExercise(
          exerciseID: existing.exerciseID,
          exerciseName: existing.exerciseName,
          modality: existing.modality,
          machineID: existing.machineID,
          machineName: existing.machineName,
          workingSets: existing.workingSets + 1
        )
      } else {
        order.append(key)
        byKey[key] = RepeatableExercise(
          exerciseID: set.exerciseID,
          exerciseName: set.exerciseName,
          modality: set.modality,
          machineID: set.machineID,
          machineName: set.machineName,
          workingSets: 1
        )
      }
    }
    return order.compactMap { byKey[$0] }
  }

  /// The workout's own note, or empty when it has none.
  ///
  /// A focused read rather than another field on every history row: the note is only ever displayed
  /// on the one screen that opens a single workout, and carrying it through the list would load a
  /// paragraph per row to show none of them.
  public func notes(for sessionID: SessionID) throws -> String {
    try database.read { db in
      try Session.where { $0.id.eq(sessionID.rawValue) }.fetchOne(db)?.notes ?? ""
    }
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
      // Logging order, not `setOrdinal`. Ordering by the ordinal interleaves movements: a warm-up
      // and the first working set both sit at 0, so three movements of three sets each came back as
      // ordinal-0-of-all-three, then ordinal-1-of-all-three. The screen groups consecutive runs, so
      // every movement shattered into one group per set and the same names repeated down the page.
      // `completedAt` is the order the workout actually happened in, with the ordinal breaking ties.
      let rows = try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { ($0.completedAt, $0.setOrdinal) }
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
          machineID: row.machineID.map(MachineID.init(rawValue:)),
          machineName: row.machineID.flatMap { machineNames[$0] },
          weightKg: row.weightKg,
          reps: row.reps,
          rpe: row.rpe,
          kind: SetKind(isWarmup: row.isWarmup, isDropSet: row.isDropSet),
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
      // Logging order for the same reason as `sets(in:)`: the movement names under each row are
      // collected first-seen, and ordering by ordinal would list them interleaved.
      let sets = try LoggedSet
        .where { $0.sessionID.in(sessionIDs) }
        .order { ($0.completedAt, $0.setOrdinal) }
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
    var dropSets = 0
    var volumeKg = 0.0
    var reps = 0
    for set in sets {
      switch SetKind(isWarmup: set.isWarmup, isDropSet: set.isDropSet) {
      case .warmup:
        warmupSets += 1
      case .working:
        workingSets += 1
        volumeKg += set.weightKg * Double(set.reps)
        reps += set.reps
      case .drop:
        // Tonnage and reps in full, no set added -- the same split `SessionVolume` makes, so the
        // history screen and the live screen cannot disagree about what a workout contained.
        dropSets += 1
        volumeKg += set.weightKg * Double(set.reps)
        reps += set.reps
      }
    }
    return SessionVolume(
      workingSets: workingSets, warmupSets: warmupSets, volumeKg: volumeKg, reps: reps,
      dropSets: dropSets
    )
  }
}
