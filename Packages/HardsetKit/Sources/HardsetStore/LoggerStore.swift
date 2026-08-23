import Foundation
import HardsetCore
import SQLiteData

/// The logger's write path and its one read.
///
/// Two invariants are enforced here rather than trusted to callers:
///
/// 1. **A set that is not complete cannot be written.** `logSet` takes a `SetEntryDraft` and
///    goes through `resolved()`, so there is no overload that accepts a bare weight. The
///    reference app accepted an empty weight field and persisted 0 kg, which zeroed session
///    volume while the row on screen appeared to read 60.
/// 2. **Duration is never stored and never derived from the wall clock.** `finishSession`
///    routes through `SessionTimeline.finish`, which refuses to re-finish a closed session
///    and refuses a finish instant that precedes the start. The reference app assigned
///    `finishedAt = Date()` on a resume path and shipped multi-hour workouts.
///
// `nonisolated` is deliberate, matching the rest of this module: the work happens on GRDB's
// database queues, and isolating it to the main actor would force every caller to hop for
// no reason.
public nonisolated struct LoggerStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  // MARK: - Session lifecycle

  /// Opens a session. `startedAt` is immutable from here on.
  public func startSession(
    gymID: GymID? = nil,
    title: String = "",
    at startedAt: Date
  ) throws -> SessionID {
    let id = SessionID()
    try database.write { db in
      try Session.insert {
        Session.Draft(
          id: id.rawValue,
          gymID: gymID?.rawValue,
          title: title,
          notes: "",
          startedAt: startedAt,
          finishedAt: nil
        )
      }
      .execute(db)
    }
    return id
  }

  /// Adds an exercise slot to a session. `position` orders the session; it is not an id.
  @discardableResult
  public func addExercise(
    to sessionID: SessionID,
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    position: Int,
    plannedSets: Int? = nil
  ) throws -> UUID {
    let rowID = UUID()
    try database.write { db in
      try SessionExercise.insert {
        SessionExercise.Draft(
          id: rowID,
          sessionID: sessionID.rawValue,
          exerciseID: exerciseID.rawValue,
          machineID: machineID?.rawValue,
          position: position,
          plannedSets: plannedSets
        )
      }
      .execute(db)
    }
    return rowID
  }

  /// Records that an exercise moved to different equipment mid-session.
  ///
  /// Without this the plan row keeps the machine the exercise STARTED on while the logged sets
  /// carry the one it moved to, and recovery rebuilds from a plan that contradicts the record.
  public func setSessionExerciseMachine(rowID: UUID, machineID: MachineID?) throws {
    try database.write { db in
      try SessionExercise
        .where { $0.id.eq(rowID) }
        .update { $0.machineID = #bind(machineID?.rawValue) }
        .execute(db)
    }
  }

  /// Writes one completed set.
  ///
  /// Throws `LoggerStoreError.incompleteSet` when the draft has no usable weight-and-reps
  /// pair. Zero added load is accepted — bodyweight work is a real set — but a missing value
  /// is not, and the two are distinct because `SetEntryDraft` holds optionals.
  /// - Parameters:
  ///   - sessionExerciseID: The plan row this set belongs to. Supplying it is what lets recovery
  ///     tell two blocks of the same movement apart.
  ///   - setOrdinal: Position within the exercise. Pass `nil` to have it derived from what is
  ///     already stored, which is the safe choice: a caller computing it from a slot index will
  ///     reissue an ordinal after a recovery, because recovered slots are renumbered.
  @discardableResult
  public func logSet(
    sessionID: SessionID,
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    sessionExerciseID: UUID? = nil,
    draft: SetEntryDraft,
    setOrdinal: Int? = nil,
    isWarmup: Bool = false,
    rpe: Double? = nil,
    at completedAt: Date
  ) throws -> SetID {
    guard let resolved = draft.resolved() else {
      throw LoggerStoreError.incompleteSet
    }
    let id = SetID()
    try database.write { db in
      // Derived inside the write, so two sets logged in quick succession cannot collide.
      let ordinal: Int
      if let setOrdinal {
        ordinal = setOrdinal
      } else {
        let existing = try LoggedSet
          .where { $0.sessionID.eq(sessionID.rawValue) }
          .where { $0.exerciseID.eq(exerciseID.rawValue) }
          .fetchAll(db)
          .map(\.setOrdinal)
          .max()
        ordinal = (existing ?? -1) + 1
      }
      try LoggedSet.insert {
        LoggedSet.Draft(
          id: id.rawValue,
          sessionID: sessionID.rawValue,
          exerciseID: exerciseID.rawValue,
          machineID: machineID?.rawValue,
          sessionExerciseID: sessionExerciseID,
          setOrdinal: ordinal,
          weightKg: resolved.weightKg,
          reps: resolved.reps,
          rpe: rpe,
          isWarmup: isWarmup,
          completedAt: completedAt
        )
      }
      .execute(db)
    }
    return id
  }

  /// Stack increments for the given machines, keyed by id.
  ///
  /// Exists so every path that builds an `ExerciseLogState` reads the equipment's real step size
  /// from storage instead of trusting a caller to know it. When `start` trusted the caller and
  /// `resume` read the database, the same set could be a record before a restart and not after.
  public func machineIncrements(for ids: [MachineID]) throws -> [MachineID: Double] {
    guard !ids.isEmpty else { return [:] }
    let raws = Array(Set(ids.map(\.rawValue)))
    return try database.read { db in
      try Machine
        .where { $0.id.in(raws) }
        .fetchAll(db)
        .reduce(into: [MachineID: Double]()) { result, row in
          if let increment = row.stackIncrementKg {
            result[MachineID(rawValue: row.id)] = increment
          }
        }
    }
  }

  /// Closes a session at `finishedAt`, going through `SessionTimeline`'s guards.
  /// Removes a whole workout, with its sets and its plan rows.
  ///
  /// One statement: `sessions` is the parent and both `loggedSets.sessionID` and
  /// `sessionExercises.sessionID` are `ON DELETE CASCADE`, so the children go with it rather than
  /// being swept up by hand -- which is what would eventually leave orphans.
  ///
  /// Requires foreign keys to be enabled on the connection. `HardsetDatabase.open` sets that; a
  /// test harness that forgets it would silently leave the sets behind, which `deleteSessionCascades`
  /// pins.
  public func deleteSession(_ sessionID: SessionID) throws {
    try database.write { db in
      try Session.where { $0.id.eq(sessionID.rawValue) }.delete().execute(db)
    }
  }

  /// Removes one movement from a session, and any sets logged against it.
  ///
  /// The plan row is the parent of nothing, so the sets are removed explicitly. Scoped to the
  /// session on purpose: the same movement in a different workout is untouched.
  public func removeSessionExercise(rowID: UUID, from sessionID: SessionID) throws {
    try database.write { db in
      try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) && $0.sessionExerciseID.eq(rowID) }
        .delete()
        .execute(db)
      try SessionExercise.where { $0.id.eq(rowID) }.delete().execute(db)
    }
  }

  /// Removes one logged set.
  ///
  /// A hard delete rather than a flag. Everything downstream -- weekly volume, the progression
  /// chart, records, tonnage -- is derived from these rows by reading them, so a set that a lifter
  /// says did not happen has to actually stop existing or it keeps contributing. SQLiteData
  /// propagates the deletion through CloudKit as a tombstone.
  ///
  /// The app is otherwise append-only, and that is deliberate. This is the one exception, and it
  /// exists because the alternative is worse: without it a mistyped 500 kg is a permanent personal
  /// record, a permanent spike in the chart, and a permanently wrong week -- in an app whose whole
  /// claim is that its numbers can be trusted.
  public func deleteSet(_ setID: SetID) throws {
    try database.write { db in
      try LoggedSet.where { $0.id.eq(setID.rawValue) }.delete().execute(db)
    }
  }

  public func finishSession(_ sessionID: SessionID, at finishedAt: Date) throws {
    try database.write { db in
      guard
        let session = try Session.where({ $0.id.eq(sessionID.rawValue) }).fetchOne(db)
      else {
        throw LoggerStoreError.sessionNotFound
      }
      // The invariant lives in HardsetCore and is unit-tested there; this is the only
      // place it is applied to storage, so there is no second implementation to drift.
      var timeline = SessionTimeline(startedAt: session.startedAt, finishedAt: session.finishedAt)
      try timeline.finish(at: finishedAt)
      try Session
        .where { $0.id.eq(sessionID.rawValue) }
        .update { $0.finishedAt = timeline.finishedAt }
        .execute(db)
    }
  }

  /// The most recently started session that is still open, if any.
  ///
  /// Used for crash recovery: the app was killed mid-workout and needs to offer to resume.
  /// Note it does not close anything on its own — an abandoned session is finished by an
  /// explicit user choice, never by assuming "now".
  public func openSession() throws -> SessionRecord? {
    try database.read { db in
      try Session
        .where { $0.finishedAt.is(nil) }
        .order { $0.startedAt.desc() }
        .limit(1)
        .fetchOne(db)
        .map(SessionRecord.init(row:))
    }
  }

  /// Sets belonging to a session, in performed order.
  public func sets(in sessionID: SessionID) throws -> [LoggedSetRecord] {
    try database.read { db in
      try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { $0.setOrdinal }
        .fetchAll(db)
        .map(LoggedSetRecord.init(row:))
    }
  }

  /// The exercises on a session's plan, in order, with the names needed to render them.
  ///
  /// Deliberately three small reads merged in Swift rather than one join: the row counts here are
  /// a session's worth, the joins would be the only ones in the codebase, and a wrong join is a
  /// subtler bug than a wrong dictionary lookup.
  public func sessionExercises(in sessionID: SessionID) throws -> [PlannedExerciseRecord] {
    try database.read { db in
      let rows = try SessionExercise
        .where { $0.sessionID.eq(sessionID.rawValue) }
        .order { $0.position }
        .fetchAll(db)
      guard !rows.isEmpty else { return [] }

      let exerciseIDs = Array(Set(rows.map(\.exerciseID)))
      let exercises = try Exercise
        .where { $0.id.in(exerciseIDs) }
        .fetchAll(db)
        .reduce(into: [UUID: Exercise]()) { $0[$1.id] = $1 }

      let machineIDs = Array(Set(rows.compactMap(\.machineID)))
      let machines =
        machineIDs.isEmpty
        ? [:]
        : try Machine
          .where { $0.id.in(machineIDs) }
          .fetchAll(db)
          .reduce(into: [UUID: Machine]()) { $0[$1.id] = $1 }

      return rows.map { row in
        PlannedExerciseRecord(
          id: row.id,
          exerciseID: ExerciseID(rawValue: row.exerciseID),
          machineID: row.machineID.map(MachineID.init(rawValue:)),
          // A missing name means a deleted exercise row, which the foreign key should prevent.
          // Shown as unknown rather than crashing a recovery path.
          exerciseName: exercises[row.exerciseID]?.name ?? "Unknown movement",
          // Read back from storage so a recovered session still knows a pull-up is bodyweight.
          modality: exercises[row.exerciseID].flatMap { ExerciseModality(rawValue: $0.modality) },
          machineName: row.machineID.flatMap { machines[$0]?.name },
          position: row.position,
          plannedSets: row.plannedSets,
          machineIncrementKg: row.machineID.flatMap { machines[$0]?.stackIncrementKg }
        )
      }
    }
  }

  /// Every completed working set for one exercise-and-machine, newest first.
  ///
  /// Used for record detection, which needs the all-time best rather than the most recent
  /// session. Warm-ups are excluded in SQL: a heavy warm-up is not a record and not a benchmark.
  /// Bounded, so a lifter with years of history does not pay for it on the tap path.
  public func completedSets(
    for key: ProgressionKey,
    limit: Int = 1_000
  ) throws -> [PriorSetRecord] {
    try database.read { db in
      let rows: [LoggedSet]
      if let machineID = key.machineID?.rawValue {
        rows = try LoggedSet
          .where { $0.exerciseID.eq(key.exerciseID.rawValue) }
          .where { $0.machineID.eq(machineID) }
          .where { !$0.isWarmup }
          .order { $0.completedAt.desc() }
          .limit(limit)
          .fetchAll(db)
      } else {
        rows = try LoggedSet
          .where { $0.exerciseID.eq(key.exerciseID.rawValue) }
          .where { $0.machineID.is(nil) }
          .where { !$0.isWarmup }
          .order { $0.completedAt.desc() }
          .limit(limit)
          .fetchAll(db)
      }
      return rows.map { PriorSetRecord(weightKg: $0.weightKg, reps: $0.reps, completedAt: $0.completedAt) }
    }
  }

  // MARK: - The one hoisted read

  /// Reads every exercise's history in a single query and returns it as an immutable value.
  ///
  /// This is the whole of invariant 3. `PriorPerformanceSnapshot` holds no database handle,
  /// so once the logger has one it *cannot* query again per render even by mistake. The
  /// reference app instead ran three unbounded fetches per exercise inside a `ForEach` body
  /// while a 1 Hz timer invalidated the list — roughly thirty queries a second.
  ///
  /// - Parameters:
  ///   - keys: The exercise/machine pairs on today's plan.
  ///   - excluding: A session to ignore, normally the one being logged. Without this, a
  ///     recovered session would suggest values from its own sets.
  ///   - asOf: Stamped onto the snapshot so staleness is visible rather than assumed.
  ///   - rowLimit: Hard bound on rows examined, so history size cannot slow session start.
  public func priorPerformanceSnapshot(
    for keys: [ProgressionKey],
    excluding excludedSession: SessionID? = nil,
    asOf: Date,
    rowLimit: Int = 500
  ) throws -> PriorPerformanceSnapshot {
    guard !keys.isEmpty else { return .empty(capturedAt: asOf) }

    let exerciseIDs = Array(Set(keys.map(\.exerciseID.rawValue)))
    let excluded = excludedSession?.rawValue

    // One query. Warm-ups are excluded here rather than filtered later: a warm-up load must
    // never pre-fill a working set, and doing it in SQL keeps the row budget honest.
    let rows: [LoggedSet] = try database.read { db in
      try LoggedSet
        .where { $0.exerciseID.in(exerciseIDs) }
        .where { !$0.isWarmup }
        .order { $0.completedAt.desc() }
        .limit(rowLimit)
        .fetchAll(db)
    }

    var grouped: [ProgressionKey: [LoggedSet]] = [:]
    for row in rows where row.sessionID != excluded {
      let key = ProgressionKey(
        exerciseID: ExerciseID(rawValue: row.exerciseID),
        machineID: row.machineID.map(MachineID.init(rawValue:))
      )
      grouped[key, default: []].append(row)
    }

    var entries: [ProgressionKey: PriorPerformance] = [:]
    for (key, rowsForKey) in grouped {
      // `rows` arrived newest-first, so the first element identifies the most recent
      // session this key was trained in.
      guard let mostRecentSession = rowsForKey.first?.sessionID else { continue }
      let lastSets = rowsForKey
        .filter { $0.sessionID == mostRecentSession }
        .sorted { $0.setOrdinal < $1.setOrdinal }
        .map(Self.record(from:))

      // Heaviest ever seen within the examined window. Ties break toward more reps, since
      // the same load for more reps is the better set.
      let heaviest = rowsForKey
        .max { lhs, rhs in
          (lhs.weightKg, lhs.reps) < (rhs.weightKg, rhs.reps)
        }
        .map(Self.record(from:))

      entries[key] = PriorPerformance(key: key, lastSets: lastSets, heaviestSet: heaviest)
    }

    return PriorPerformanceSnapshot(entries: entries, capturedAt: asOf)
  }

  private static func record(from row: LoggedSet) -> PriorSetRecord {
    PriorSetRecord(weightKg: row.weightKg, reps: row.reps, completedAt: row.completedAt)
  }
}

// MARK: - Public records
//
// The `@Table` row types are deliberately internal: they are a storage detail whose column
// names are permanently frozen, and leaking them would make every caller depend on that
// shape. These are the store's public vocabulary instead — typed identifiers rather than raw
// `UUID`s, and a `SessionTimeline` rather than two loose dates, so a caller gets the duration
// invariant for free instead of being trusted to reconstruct it.

public nonisolated struct SessionRecord: Hashable, Sendable {
  public let id: SessionID
  public let gymID: GymID?
  public let title: String
  public let timeline: SessionTimeline

  init(row: Session) {
    self.id = SessionID(rawValue: row.id)
    self.gymID = row.gymID.map(GymID.init(rawValue:))
    self.title = row.title
    self.timeline = SessionTimeline(startedAt: row.startedAt, finishedAt: row.finishedAt)
  }
}

public nonisolated struct LoggedSetRecord: Hashable, Sendable {
  public let id: SetID
  public let sessionID: SessionID
  public let exerciseID: ExerciseID
  public let machineID: MachineID?
  public let setOrdinal: Int
  public let weightKg: Double
  public let reps: Int
  public let rpe: Double?
  public let isWarmup: Bool
  public let completedAt: Date
  /// The plan row this set was logged against, when known.
  public let sessionExerciseID: UUID?

  init(row: LoggedSet) {
    self.id = SetID(rawValue: row.id)
    self.sessionID = SessionID(rawValue: row.sessionID)
    self.exerciseID = ExerciseID(rawValue: row.exerciseID)
    self.machineID = row.machineID.map(MachineID.init(rawValue:))
    self.setOrdinal = row.setOrdinal
    self.weightKg = row.weightKg
    self.reps = row.reps
    self.rpe = row.rpe
    self.isWarmup = row.isWarmup
    self.completedAt = row.completedAt
    self.sessionExerciseID = row.sessionExerciseID
  }

  /// The progression unit this set belongs to.
  public var progressionKey: ProgressionKey {
    ProgressionKey(exerciseID: exerciseID, machineID: machineID)
  }
}

public nonisolated struct PlannedExerciseRecord: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let exerciseID: ExerciseID
  public let machineID: MachineID?
  public let exerciseName: String
  /// How the movement is loaded, when the stored value is a modality this build knows.
  public let modality: ExerciseModality?
  public let machineName: String?
  public let position: Int
  public let plannedSets: Int?
  /// The machine's real load step, when known. Carried here so recovery restores it — without it,
  /// a recovered session falls back to a default step the equipment may not be able to hit.
  public let machineIncrementKg: Double?

  public var progressionKey: ProgressionKey {
    ProgressionKey(exerciseID: exerciseID, machineID: machineID)
  }
}

public enum LoggerStoreError: Error, Equatable, Sendable {
  /// The draft had no usable weight-and-reps pair. Bind the log control to
  /// `SetEntryDraft.isLoggable` so this is unreachable from the UI.
  case incompleteSet
  case sessionNotFound
}
