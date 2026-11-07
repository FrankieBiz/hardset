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
    try startSession(gymID: gymID, title: title, at: startedAt, plan: []).sessionID
  }

  /// Saves the session and its entire plan in one transaction. A failed plan row
  /// must not leave an open session or a partial plan for recovery to discover.
  func startSession(
    gymID: GymID?,
    title: String,
    at startedAt: Date,
    plan: [PlannedExercise]
  ) throws -> (sessionID: SessionID, planRowIDs: [UUID]) {
    let id = SessionID()
    let rowIDs = plan.map { _ in UUID() }
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
      for (position, planned) in plan.enumerated() {
        try SessionExercise.insert {
          SessionExercise.Draft(
            id: rowIDs[position],
            sessionID: id.rawValue,
            exerciseID: planned.exerciseID.rawValue,
            machineID: planned.machineID?.rawValue,
            position: position,
            plannedSets: planned.plannedSets
          )
        }
        .execute(db)
      }
    }
    return (id, rowIDs)
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
      let names = try Exercise
        .where { $0.id.in(exerciseIDs) }
        .fetchAll(db)
        .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }

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
          exerciseName: names[row.exerciseID] ?? "Unknown movement",
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

  /// Loads complete latest-session sets and an all-time heaviest set per machine.
  ///
  /// Selection runs inside one database read transaction. Only the latest session's
  /// rows and one benchmark row are decoded per key; older sets remain in SQLite.
  /// There is no shared row cap: a busy exercise or the session being recovered
  /// cannot consume another exercise's history budget.
  ///
  /// `PriorPerformanceSnapshot` holds no database handle, so the logger still does
  /// zero database work per render. Other-machine entries are retained for the
  /// explicitly labelled fallback supported by the snapshot.
  ///
  /// - Parameters:
  ///   - keys: The exercise/machine pairs on today's plan.
  ///   - excluding: A session to ignore, normally the one being logged. Applied
  ///     in SQL before selecting machines, latest sessions, or benchmarks.
  ///   - asOf: A capture timestamp, not a historical cutoff.
  public func priorPerformanceSnapshot(
    for keys: [ProgressionKey],
    excluding excludedSession: SessionID? = nil,
    asOf: Date
  ) throws -> PriorPerformanceSnapshot {
    guard !keys.isEmpty else { return .empty(capturedAt: asOf) }
    let exerciseIDs = Set(keys.map(\.exerciseID.rawValue))
    let excluded = excludedSession?.rawValue

    return try database.read { db in
      var entries: [ProgressionKey: PriorPerformance] = [:]
      for exerciseID in exerciseIDs {
        let history = LoggedSet
          .where { $0.exerciseID.eq(exerciseID) }
          .where { !$0.isWarmup }
          .where { #sql("\($0.sessionID) IS NOT \(excluded)", as: Bool.self) }
        // Discover only equipment identifiers, rather than decoding every prior
        // set. DISTINCT uses the exercise/machine index and includes free weights.
        let machineIDs = try history.distinct().select(\.machineID).fetchAll(db)
        for machineID in machineIDs {
          let exact = history.where { $0.machineID.is(machineID) }
          let latest = try exact
            .order { ($0.completedAt.desc(), $0.id.desc()) }
            .limit(1)
            .fetchOne(db)
          guard let latest else { continue }

          let lastSets = try exact
            .where { $0.sessionID.eq(latest.sessionID) }
            .order { ($0.setOrdinal, $0.completedAt, $0.id) }
            .fetchAll(db)
            .map(Self.record(from:))
          let heaviest = try exact
            .order { ($0.weightKg.desc(), $0.reps.desc(), $0.completedAt.desc(), $0.id.desc()) }
            .limit(1)
            .fetchOne(db)
            .map(Self.record(from:))
          let key = ProgressionKey(
            exerciseID: ExerciseID(rawValue: exerciseID),
            machineID: machineID.map(MachineID.init(rawValue:))
          )
          entries[key] = PriorPerformance(key: key, lastSets: lastSets, heaviestSet: heaviest)
        }
      }
      return PriorPerformanceSnapshot(entries: entries, capturedAt: asOf)
    }
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
