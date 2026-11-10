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
public nonisolated struct LoggerStore: Sendable {
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
      if let gymID {
        let gym = try Gym.where { $0.id.eq(gymID.rawValue) }.select(\.id).fetchOne(db)
        guard gym != nil else { throw LoggerStoreError.gymNotFound }
      }
      for exerciseID in Set(plan.map(\.exerciseID)) {
        try Self.requireExercise(exerciseID, in: db)
      }
      for machineID in Set(plan.compactMap(\.machineID)) {
        try Self.requireMachine(machineID, at: gymID?.rawValue, in: db)
      }
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
      try Self.requireSingleChange(in: db)
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
        try Self.requireSingleChange(in: db)
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
      let gymID = try Self.requireOpenSession(sessionID, in: db)
      try Self.requireExercise(exerciseID, in: db)
      try Self.requireMachine(machineID, at: gymID, in: db)
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
      try Self.requireSingleChange(in: db)
    }
    return rowID
  }

  /// Records that an exercise moved to different equipment mid-session.
  ///
  /// Without this the plan row keeps the machine the exercise STARTED on while the logged sets
  /// carry the one it moved to, and recovery rebuilds from a plan that contradicts the record.
  /// Optional expected IDs let a coordinator reject a plan row reparented by
  /// another writer instead of changing a different workout's equipment.
  public func setSessionExerciseMachine(
    rowID: UUID,
    machineID: MachineID?,
    sessionID: SessionID? = nil,
    exerciseID: ExerciseID? = nil
  ) throws {
    try database.write { db in
      let row = try SessionExercise.where { $0.id.eq(rowID) }.fetchOne(db)
      guard let row else { throw LoggerStoreError.sessionExerciseNotFound }
      if let sessionID, row.sessionID != sessionID.rawValue {
        throw LoggerStoreError.sessionExerciseMismatch
      }
      if let exerciseID, row.exerciseID != exerciseID.rawValue {
        throw LoggerStoreError.sessionExerciseMismatch
      }
      let gymID = try Self.requireOpenSession(SessionID(rawValue: row.sessionID), in: db)
      try Self.requireExercise(ExerciseID(rawValue: row.exerciseID), in: db)
      try Self.requireMachine(machineID, at: gymID, in: db)
      try SessionExercise
        .where { $0.id.eq(rowID) }
        .update { $0.machineID = #bind(machineID?.rawValue) }
        .execute(db)
      try Self.requireSingleChange(in: db)
    }
  }

  /// Writes one completed set.
  ///
  /// Throws `LoggerStoreError.incompleteSet` when the draft has no usable weight-and-reps
  /// pair. Zero added load is accepted — bodyweight work is a real set — but a missing value
  /// is not, and the two are distinct because `SetEntryDraft` holds optionals.
  /// Session state and any supplied plan/equipment context are validated inside
  /// the save transaction, before reading record comparisons or inserting a set.
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
    commandID: SetID = SetID(),
    sessionExerciseID: UUID? = nil,
    draft: SetEntryDraft,
    setOrdinal: Int? = nil,
    isWarmup: Bool = false,
    rpe: Double? = nil,
    at completedAt: Date
  ) throws -> SetID {
    try logSet(
      sessionID: sessionID, exerciseID: exerciseID, machineID: machineID,
      commandID: commandID, sessionExerciseID: sessionExerciseID, draft: draft, setOrdinal: setOrdinal,
      isWarmup: isWarmup, rpe: rpe, recordIncrement: nil, detectingRecords: false,
      at: completedAt
    ).setID
  }

  /// Selects all-time comparisons and saves under the same write transaction.
  /// History-read failures suppress claims; the set save is still attempted.
  func logSet(
    sessionID: SessionID,
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    commandID: SetID = SetID(),
    sessionExerciseID: UUID? = nil,
    draft: SetEntryDraft,
    setOrdinal: Int? = nil,
    isWarmup: Bool = false,
    rpe: Double? = nil,
    recordIncrement: Double?,
    detectingRecords: Bool = true,
    at completedAt: Date
  ) throws -> (setID: SetID, records: [PersonalRecord]) {
    guard let resolved = draft.resolved() else {
      throw LoggerStoreError.incompleteSet
    }
    let id = commandID
    var records: [PersonalRecord] = []
    try database.write { db in
      // A lost acknowledgement may be retried even after the workout is closed.
      // Identity is local-command identity, never a synchronized ordinal constraint.
      if let existing = try LoggedSet.where({ $0.id.eq(id.rawValue) }).fetchOne(db) {
        guard existing.sessionID == sessionID.rawValue,
          existing.exerciseID == exerciseID.rawValue, existing.machineID == machineID?.rawValue,
          existing.sessionExerciseID == sessionExerciseID, existing.weightKg == resolved.weightKg,
          existing.reps == resolved.reps, existing.isWarmup == isWarmup, existing.rpe == rpe,
          setOrdinal == nil || existing.setOrdinal == setOrdinal
        else { throw SetCommandError.identityConflict }
        return
      }
      let gymID = try Self.requireOpenSession(sessionID, in: db)
      try Self.requireExercise(exerciseID, in: db)
      if let sessionExerciseID {
        let row = try SessionExercise.where { $0.id.eq(sessionExerciseID) }.fetchOne(db)
        guard let row else { throw LoggerStoreError.sessionExerciseNotFound }
        guard row.sessionID == sessionID.rawValue, row.exerciseID == exerciseID.rawValue,
          row.machineID == machineID?.rawValue
        else { throw LoggerStoreError.sessionExerciseMismatch }
      }
      try Self.requireMachine(machineID, at: gymID, in: db)
      if detectingRecords, !isWarmup {
        let candidate = PersonalRecordDetector.Candidate(weightKg: resolved.weightKg, reps: resolved.reps)
        let key = ProgressionKey(exerciseID: exerciseID, machineID: machineID)
        // These are real representative sets, not a recent sample. A failed
        // comparison read cannot justify a claim, but must not lose a workout.
        if let history = try? Self.recordComparisonSets(in: db, for: key, candidate: candidate) {
          records = PersonalRecordDetector.records(for: candidate, history: history, increment: recordIncrement)
        }
      }
      // Derived inside the write, so two sets logged in quick succession cannot collide.
      let ordinal: Int
      if let setOrdinal {
        ordinal = setOrdinal
      } else {
        let existing: Int? = try LoggedSet
          .where { $0.sessionID.eq(sessionID.rawValue) }
          .where { $0.exerciseID.eq(exerciseID.rawValue) }
          .select { $0.setOrdinal.max() }
          .fetchOne(db) ?? nil
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
      try Self.requireSingleChange(in: db)
    }
    return (id, records)
  }

  // Local command validation belongs in the writer transaction, not in schema
  // constraints that could reject an otherwise legitimate row arriving via sync.
  /// Returns the session's recorded gym. Project only the validation fields so
  /// every set save avoids reading notes or decoding unrelated timestamps.
  private static func requireOpenSession(_ id: SessionID, in db: Database) throws -> UUID? {
    let context = try Session.where { $0.id.eq(id.rawValue) }
      .select { ($0.gymID, $0.finishedAt.is(nil)) }.fetchOne(db)
    guard let context else { throw LoggerStoreError.sessionNotFound }
    guard context.1 else { throw LoggerStoreError.sessionClosed }
    return context.0
  }

  private static func requireExercise(_ id: ExerciseID, in db: Database) throws {
    let exercise = try Exercise.where { $0.id.eq(id.rawValue) }.select(\.id).fetchOne(db)
    guard exercise != nil else { throw LoggerStoreError.exerciseNotFound }
  }

  private static func requireMachine(_ id: MachineID?, at gymID: UUID?, in db: Database) throws {
    guard let id else { return }
    let machineGym = try Machine.where { $0.id.eq(id.rawValue) }.select(\.gymID).fetchOne(db)
    guard let machineGym else { throw LoggerStoreError.machineNotFound }
    // Legacy/local-only sessions without a recorded gym retain their equipment
    // provenance. A known gym must agree with the physical machine's inventory.
    if let gymID, machineGym != gymID { throw LoggerStoreError.machineGymMismatch }
  }

  private static func requireSingleChange(in db: Database) throws {
    guard db.changesCount == 1 else { throw LoggerStoreError.writeNotApplied }
  }

  /// At most 14 actual sets preserve every comparison the Core detector makes:
  /// all-time load, reps near the candidate load, and the best load at each
  /// estimable rep count. The estimate formula remains solely in HardsetCore.
  private static func recordComparisonSets(
    in db: Database,
    for key: ProgressionKey,
    candidate: PersonalRecordDetector.Candidate
  ) throws -> [PriorSetRecord] {
    let machineID = key.machineID?.rawValue
    let history = LoggedSet
      .where { $0.exerciseID.eq(key.exerciseID.rawValue) }
      .where { $0.machineID.is(machineID) }
      .where { !$0.isWarmup }
    var comparisons: [PriorSetRecord] = []
    let heaviest = try history
      .order { ($0.weightKg.desc(), $0.reps.desc(), $0.completedAt.desc(), $0.id.desc()) }
      .limit(1).fetchOne(db)
    guard let heaviest else { return [] }
    comparisons.append(record(from: heaviest))

    let tolerance = PersonalRecordDetector.loadMatchingTolerance
    // Widen the indexed interval by one representable value. The exact abs
    // predicate preserves the detector's floating-point boundary semantics.
    let lower = (candidate.weightKg - tolerance).nextDown
    let upper = (candidate.weightKg + tolerance).nextUp
    let mostReps = try history
      .where { $0.weightKg >= lower && $0.weightKg <= upper }
      .where { #sql("abs(\($0.weightKg) - \(candidate.weightKg)) < \(tolerance)", as: Bool.self) }
      .order { $0.reps.desc() }
      .limit(1).fetchOne(db)
    if let mostReps { comparisons.append(record(from: mostReps)) }

    if StrengthMath.estimatedOneRepMax(weightKg: candidate.weightKg, reps: candidate.reps).value != nil {
      for reps in 1...StrengthMath.maximumEstimableReps {
        let bestAtReps = try history
          .where { $0.reps.eq(reps) }
          .where { $0.weightKg > 0 && $0.weightKg <= StrengthMath.implausibleWeightKg }
          .order { $0.weightKg.desc() }
          .limit(1).fetchOne(db)
        if let bestAtReps { comparisons.append(record(from: bestAtReps)) }
      }
    }
    return comparisons
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
      try Self.requireSingleChange(in: db)
    }
  }

  // MARK: - Corrections to an open workout
  //
  // Every command below validates inside its own write transaction and changes only the open
  // workout it names, so a mistake can be put right while training without any path for
  // rewriting finished history. Deletes are plain deletes: with a sync engine running, its
  // triggers turn them into record deletions; without one there is nothing else to do.

  /// Deletes one saved set of the open workout, so a mistaken log can be taken back.
  ///
  /// A set that is already gone, for instance removed on another device, is not an error: the
  /// outcome asked for holds. A set belonging to a different workout is refused, so naming the
  /// open workout can never reach into history.
  public func deleteLoggedSet(_ id: SetID, in sessionID: SessionID) throws {
    try database.write { db in
      _ = try Self.requireOpenSession(sessionID, in: db)
      let owner = try LoggedSet.where { $0.id.eq(id.rawValue) }.select(\.sessionID).fetchOne(db)
      guard let owner else { return }
      guard owner == sessionID.rawValue else { throw LoggerStoreError.writeNotApplied }
      try LoggedSet
        .where { $0.id.eq(id.rawValue) && $0.sessionID.eq(sessionID.rawValue) }
        .delete()
        .execute(db)
      try Self.requireSingleChange(in: db)
    }
  }

  /// Removes a movement from the open workout: its plan row and this workout's sets for it, in
  /// one transaction, then closes the gap in the remaining positions.
  ///
  /// Sets are matched by the plan row they were logged against, plus any ids passed in
  /// `loggedSetIDs`, which is how a set written before sets recorded their plan row is reached.
  /// Those ids are limited to this workout and, when `exerciseID` is given, to this movement.
  /// Sets of the same movement in other workouts are history and are never touched. A plan row
  /// already removed elsewhere is not an error; its sets here are still cleared.
  public func removeSessionExercise(
    rowID: UUID,
    sessionID: SessionID,
    exerciseID: ExerciseID? = nil,
    loggedSetIDs: [SetID] = []
  ) throws {
    try database.write { db in
      _ = try Self.requireOpenSession(sessionID, in: db)
      let row = try SessionExercise.where { $0.id.eq(rowID) }.fetchOne(db)
      if let row {
        guard row.sessionID == sessionID.rawValue else {
          throw LoggerStoreError.sessionExerciseMismatch
        }
        if let exerciseID, row.exerciseID != exerciseID.rawValue {
          throw LoggerStoreError.sessionExerciseMismatch
        }
      }
      try LoggedSet
        .where { $0.sessionID.eq(sessionID.rawValue) && $0.sessionExerciseID.eq(rowID) }
        .delete()
        .execute(db)
      let explicit = loggedSetIDs.map(\.rawValue)
      if !explicit.isEmpty {
        if let exerciseID {
          try LoggedSet
            .where { $0.sessionID.eq(sessionID.rawValue) && $0.id.in(explicit) }
            .where { $0.exerciseID.eq(exerciseID.rawValue) }
            .delete()
            .execute(db)
        } else {
          try LoggedSet
            .where { $0.sessionID.eq(sessionID.rawValue) && $0.id.in(explicit) }
            .delete()
            .execute(db)
        }
      }
      if row != nil {
        try SessionExercise.where { $0.id.eq(rowID) }.delete().execute(db)
        try Self.requireSingleChange(in: db)
      }
      try Self.renumberPlan(of: sessionID, in: db)
    }
  }

  /// Rewrites the open workout's plan order. `orderedRowIDs` must name exactly the workout's
  /// plan rows, each once; anything else means memory and storage disagree, and nothing is
  /// written.
  public func setSessionExercisePositions(_ orderedRowIDs: [UUID], in sessionID: SessionID) throws {
    try database.write { db in
      _ = try Self.requireOpenSession(sessionID, in: db)
      let rows = try SessionExercise.where { $0.sessionID.eq(sessionID.rawValue) }.fetchAll(db)
      guard rows.count == orderedRowIDs.count, Set(rows.map(\.id)) == Set(orderedRowIDs) else {
        throw LoggerStoreError.sessionExerciseMismatch
      }
      let positions = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.position) })
      for (index, rowID) in orderedRowIDs.enumerated() where positions[rowID] != index {
        try SessionExercise.where { $0.id.eq(rowID) }.update { $0.position = #bind(index) }.execute(db)
        try Self.requireSingleChange(in: db)
      }
    }
  }

  /// Records or changes the open workout's gym, so a lifter who started without one, or at the
  /// wrong one, can still record machines.
  ///
  /// Refused with `machineGymMismatch` while any plan row or saved set of this workout carries a
  /// machine from a different gym (or any machine, when clearing the gym): machines belong to a
  /// gym, and moving the workout would contradict equipment already recorded. An unknown or
  /// archived gym is `gymNotFound`.
  public func setSessionGym(_ sessionID: SessionID, to gymID: GymID?) throws {
    try database.write { db in
      _ = try Self.requireOpenSession(sessionID, in: db)
      if let gymID {
        let live = try Gym.where { $0.id.eq(gymID.rawValue) && !$0.isArchived }
          .select(\.id).fetchOne(db)
        guard live != nil else { throw LoggerStoreError.gymNotFound }
      }
      let planned = try SessionExercise.where { $0.sessionID.eq(sessionID.rawValue) }
        .select(\.machineID).fetchAll(db)
      let performed = try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }
        .select(\.machineID).fetchAll(db)
      let machineIDs = Array(Set((planned + performed).compactMap { $0 }))
      if !machineIDs.isEmpty {
        let machineGyms = try Machine.where { $0.id.in(machineIDs) }.select(\.gymID).fetchAll(db)
        guard let gymID, machineGyms.allSatisfy({ $0 == gymID.rawValue }) else {
          throw LoggerStoreError.machineGymMismatch
        }
      }
      try Session
        .where { $0.id.eq(sessionID.rawValue) }
        .update { $0.gymID = #bind(gymID?.rawValue) }
        .execute(db)
      try Self.requireSingleChange(in: db)
    }
  }

  /// Deletes the open workout with its plan rows and sets, in one transaction, for a workout
  /// started by mistake. A finished workout is history and is refused with `sessionClosed`.
  ///
  /// Children are deleted explicitly rather than left to `ON DELETE CASCADE`: SQLiteData does not
  /// validate delete actions on tables with two or more foreign keys, which these are.
  public func discardOpenSession(_ sessionID: SessionID) throws {
    try database.write { db in
      _ = try Self.requireOpenSession(sessionID, in: db)
      try LoggedSet.where { $0.sessionID.eq(sessionID.rawValue) }.delete().execute(db)
      try SessionExercise.where { $0.sessionID.eq(sessionID.rawValue) }.delete().execute(db)
      try Session.where { $0.id.eq(sessionID.rawValue) }.delete().execute(db)
      try Self.requireSingleChange(in: db)
    }
  }

  /// Positions are contiguous, so a movement appended at `count` cannot share one with an
  /// existing row and come back in an arbitrary order after a relaunch.
  private static func renumberPlan(of sessionID: SessionID, in db: Database) throws {
    let rows = try SessionExercise
      .where { $0.sessionID.eq(sessionID.rawValue) }
      .order { ($0.position, $0.id) }
      .fetchAll(db)
    for (index, row) in rows.enumerated() where row.position != index {
      try SessionExercise.where { $0.id.eq(row.id) }.update { $0.position = #bind(index) }.execute(db)
      try requireSingleChange(in: db)
    }
  }

  /// The machine at `gymID` this movement was most recently logged on, if any and not archived.
  ///
  /// Recency is the right rule for the same reason the machine picker uses it: the machine used
  /// last time is overwhelmingly the one the lifter is standing at. Only this gym's machines are
  /// considered, so a recent trip elsewhere cannot hide the usual one.
  public func mostRecentMachine(for exerciseID: ExerciseID, at gymID: GymID) throws -> MachineRecord? {
    try database.read { db in
      let machines = try Machine
        .where { $0.gymID.eq(gymID.rawValue) && !$0.isArchived }
        .fetchAll(db)
      var best: (machine: Machine, at: Date)?
      for machine in machines {
        let latest = try LoggedSet
          .where { $0.exerciseID.eq(exerciseID.rawValue) && $0.machineID.eq(machine.id) }
          .order { $0.completedAt.desc() }
          .limit(1)
          .select(\.completedAt)
          .fetchOne(db)
        guard let latest else { continue }
        if let current = best, current.at >= latest { continue }
        best = (machine, latest)
      }
      return best.map { MachineRecord(row: $0.machine) }
    }
  }

  /// The most recently started session that is still open, if any.
  ///
  /// Used for crash recovery: the app was killed mid-workout and needs to offer to resume.
  /// Note it does not close anything on its own — an abandoned session is finished by an
  /// explicit user choice, never by assuming "now".
  public func openSession() throws -> SessionRecord? {
    try database.read { db in try Self.readOpenSession(in: db) }
  }

  private static func readOpenSession(in db: Database) throws -> SessionRecord? {
    try Session
      .where { $0.finishedAt.is(nil) }
      .order { $0.startedAt.desc() }
      .limit(1)
      .fetchOne(db)
      .map(SessionRecord.init(row:))
  }

  /// Sets belonging to a session, in performed order.
  public func sets(in sessionID: SessionID) throws -> [LoggedSetRecord] {
    try database.read { db in try Self.readSets(in: sessionID, db: db) }
  }

  private static func readSets(in sessionID: SessionID, db: Database) throws -> [LoggedSetRecord] {
    try LoggedSet
      .where { $0.sessionID.eq(sessionID.rawValue) }
      .order { $0.setOrdinal }
      .fetchAll(db)
      .map(LoggedSetRecord.init(row:))
  }

  /// The exercises on a session's plan, in order, with the names needed to render them.
  ///
  /// Deliberately three small reads merged in Swift rather than one join: the row counts here are
  /// a session's worth, the joins would be the only ones in the codebase, and a wrong join is a
  /// subtler bug than a wrong dictionary lookup.
  public func sessionExercises(in sessionID: SessionID) throws -> [PlannedExerciseRecord] {
    try database.read { db in try Self.readSessionExercises(in: sessionID, db: db) }
  }

  private static func readSessionExercises(
    in sessionID: SessionID, db: Database
  ) throws -> [PlannedExerciseRecord] {
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

  /// Recent completed working sets for one exercise-and-machine, newest first.
  ///
  /// A bounded browsing API, not an all-time record source. Record detection uses
  /// compact complete comparisons in the logging transaction instead. Warm-ups
  /// are excluded in SQL.
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

  /// All recovery inputs share one SQLite read snapshot. The connection never
  /// escapes this closure; callers receive immutable, Sendable records only.
  func recoverySnapshot(asOf: Date) throws -> SessionRecoverySnapshot? {
    try database.read { db in try Self.readRecoverySnapshot(asOf: asOf, in: db) }
  }

  func loadRecoverySnapshot(asOf: Date) async throws -> SessionRecoverySnapshot? {
    try Task.checkCancellation()
    return try await database.read { db in try Self.readRecoverySnapshot(asOf: asOf, in: db) }
  }

  private static func readRecoverySnapshot(asOf: Date, in db: Database) throws -> SessionRecoverySnapshot? {
    guard let session = try Self.readOpenSession(in: db) else { return nil }
    let planned = try Self.readSessionExercises(in: session.id, db: db)
    let written = try Self.readSets(in: session.id, db: db)
    let prior = try Self.readPriorPerformance(
      for: planned.map(\.progressionKey), excluding: session.id, asOf: asOf, in: db
    )
    return SessionRecoverySnapshot(session: session, planned: planned, written: written, prior: prior)
  }

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
    return try database.read { db in
      try Self.readPriorPerformance(for: keys, excluding: excludedSession, asOf: asOf, in: db)
    }
  }

  private static func readPriorPerformance(
    for keys: [ProgressionKey], excluding excludedSession: SessionID?, asOf: Date, in db: Database
  ) throws -> PriorPerformanceSnapshot {
    guard !keys.isEmpty else { return .empty(capturedAt: asOf) }
    let exerciseIDs = Set(keys.map(\.exerciseID.rawValue))
    let excluded = excludedSession?.rawValue

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

  private static func record(from row: LoggedSet) -> PriorSetRecord {
    PriorSetRecord(weightKg: row.weightKg, reps: row.reps, completedAt: row.completedAt)
  }
}

/// Internal composition input; it owns values rather than a database connection.
nonisolated struct SessionRecoverySnapshot: Hashable, Sendable {
  let session: SessionRecord
  let planned: [PlannedExerciseRecord]
  let written: [LoggedSetRecord]
  let prior: PriorPerformanceSnapshot
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
  case sessionClosed
  case exerciseNotFound
  case gymNotFound
  case machineNotFound
  case machineGymMismatch
  case sessionExerciseNotFound
  /// The plan row no longer matches the requested workout, movement, or equipment.
  case sessionExerciseMismatch
  /// A single-row insert or update completed without affecting exactly one row.
  case writeNotApplied
}

/// Reusing an acknowledged command identity cannot replace its saved payload.
public nonisolated enum SetCommandError: Error, Equatable, Sendable {
  case identityConflict
}
