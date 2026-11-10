import Foundation
import HardsetCore
import Observation
import SQLiteData

/// Drives one live workout: holds the exercise states, persists sets, and asks for rest.
///
/// The ordering here is the whole point, and it is the opposite of what is convenient:
/// **the row is marked logged only after the write succeeds.** A coordinator that optimistically
/// ticks the check mark and then discovers the write failed has told the user a lie about their
/// training, which is unrecoverable in a way a spinner is not. Rest is likewise requested only
/// after a successful write — a timer running for a set that was not saved is worse than no
/// timer.
///
/// The rest timer arrives as a closure rather than as `RestTimerController` directly. AlarmKit
/// exists only in the iPhoneOS SDK, so depending on it here would drag this type — and its
/// tests — onto a simulator. Injected, the coordinator's logic runs on the host in
/// milliseconds and a test can assert exactly what rest was requested.
@MainActor
@Observable
public final class SessionCoordinator {
  public let sessionID: SessionID
  /// Settable, because SwiftUI binds directly into a row's draft as the user types — that is
  /// what `@Observable` plus `@Bindable` is for, and a `private(set)` here would force a
  /// pass-through mutator for every keystroke.
  ///
  /// The protected behaviour is not write access, it is ordering: `logSet` is the only thing
  /// that may set `loggedSetID` or request rest, because it is the only place that knows the
  /// write succeeded. Marking a slot logged by hand is how you end up with a check mark on a
  /// set that was never saved.
  public var exercises: [ExerciseLogState]
  /// Surfaced rather than swallowed: a failed write must be visible in the UI, because the
  /// user's alternative is discovering it days later in their history.
  public private(set) var lastError: (any Error)?
  /// Which command produced `lastError`, set and cleared with it. The same store error can come
  /// from different commands (a closed workout refuses a log, an undo and a reorder alike), so
  /// this is what lets the UI say what did not happen in the lifter's terms.
  public private(set) var lastFailedCommand: SessionCommand?
  public private(set) var isFinished = false
  /// True once `discard()` has deleted this workout. Like `isFinished`, it tells the root the
  /// coordinator is done with, so it can be dropped.
  public private(set) var isDiscarded = false
  /// When the workout began, as stored. Restored on resume rather than re-read from the clock,
  /// so a recovered workout keeps its real start.
  public let startedAt: Date
  /// Records set by the most recently logged set, or empty. Cleared on the next log so a
  /// celebration cannot linger onto a set that did not earn it, and when the set that earned it
  /// is undone or removed.
  public private(set) var lastRecords: [PersonalRecord] = []
  /// The saved sets across the workout.
  ///
  /// Stored, and updated only by the commands that save or delete sets, rather than derived from
  /// `exercises`. Every keypad digit writes into `exercises`, so a derived count made any view
  /// that showed it re-render on each keystroke.
  public private(set) var loggedSetCount = 0
  /// When the newest saved set was written, or `nil` when nothing is saved. Stored for the same
  /// reason as `loggedSetCount`. Useful as an honest finish time for a workout left open.
  public private(set) var lastLoggedAt: Date?

  /// The set whose save produced `lastRecords`, so undoing or removing it clears them.
  private var lastRecordsSetID: SetID?

  /// Maps an `ExerciseLogState.id` to its `sessionExercises` row id.
  ///
  /// Held here rather than on `ExerciseLogState` because a storage row id is a storage concern and
  /// `HardsetCore` must not learn about one. Without it, a machine change has nowhere to be
  /// written, and the plan in the database silently contradicts the sets that were logged.
  private var planRowIDs: [UUID: UUID] = [:]

  private let store: LoggerStore
  private let now: () -> Date
  private let restAfterSet: Duration?
  private let onStartRest: (Duration, RestMetadata) -> Void

  /// - Parameters:
  ///   - restAfterSet: Rest to request after a working set is logged. `nil` means the app does
  ///     not start a timer on its own. There is no built-in default: a rest prescription is a
  ///     training decision, and inventing 90 seconds here would be the app asserting something
  ///     it has no basis for.
  ///   - onStartRest: Where a rest request goes. Left empty in tests and in previews.
  /// The gym this session is at, when one is known.
  ///
  /// Retained rather than re-read per render: the machine picker needs it to offer the rest of the
  /// gym's equipment, and a view that queried for it on every body evaluation would hit the
  /// database inside the logging path.
  public private(set) var gymID: GymID?

  /// - Parameter startedAt: The stored start of the session. Defaults to `now()` for previews and
  ///   tests that build a coordinator by hand; `start` and `resume` always pass the stored value.
  public init(
    store: LoggerStore,
    sessionID: SessionID,
    exercises: [ExerciseLogState],
    gymID: GymID? = nil,
    startedAt: Date? = nil,
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) {
    self.store = store
    self.sessionID = sessionID
    self.exercises = exercises
    self.gymID = gymID
    self.startedAt = startedAt ?? now()
    self.now = now
    self.restAfterSet = restAfterSet
    self.onStartRest = onStartRest
    refreshSavedSummary()
  }

  /// Opens a session and builds its exercise states from one history read.
  ///
  /// The snapshot is taken here, once, and excludes the session being started so a resumed
  /// workout cannot suggest values from its own sets.
  public static func start(
    store: LoggerStore,
    gymID: GymID? = nil,
    title: String = "",
    plan: [PlannedExercise],
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) throws -> SessionCoordinator {
    let startedAt = now()
    // Prepare fallible reads before creating durable state. There is no new
    // session to exclude yet, and a read failure must not abandon an empty one.
    let snapshot = try store.priorPerformanceSnapshot(
      for: plan.map(\.progressionKey),
      asOf: startedAt
    )

    var states: [ExerciseLogState] = []
    var rowIDs: [UUID: UUID] = [:]
    // Read from the machines table rather than trusting the caller. `start` used to take whatever
    // increment was passed in — and nothing in the app passed one — while `resume` read it from
    // storage, so the same set could be a record before a restart and not after.
    let increments = try store.machineIncrements(for: plan.compactMap(\.machineID))
    let saved = try store.startSession(gymID: gymID, title: title, at: startedAt, plan: plan)
    for (position, planned) in plan.enumerated() {
      let state = ExerciseLogState.build(
        exerciseID: planned.exerciseID,
        machineID: planned.machineID,
        exerciseName: planned.exerciseName,
        machineName: planned.machineName,
        machineIncrementKg: planned.machineID.flatMap { increments[$0] }
          ?? planned.machineIncrementKg,
        snapshot: snapshot,
        plannedSets: planned.plannedSets
      )
      rowIDs[state.id] = saved.planRowIDs[position]
      states.append(state)
    }

    let coordinator = SessionCoordinator(
      store: store,
      sessionID: saved.sessionID,
      exercises: states,
      gymID: gymID,
      startedAt: startedAt,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
    coordinator.planRowIDs = rowIDs
    return coordinator
  }

  /// Rebuilds a coordinator for a workout that was left open.
  ///
  /// This is the crash-recovery path: the app was killed mid-set, the phone died, or the session
  /// was left running overnight. Nothing is assumed about how long ago that was and nothing is
  /// closed automatically — an abandoned session is finished by an explicit choice, never by the
  /// app deciding "now" is the end. That is the bug the ancestor app shipped as 9,749-minute
  /// workouts.
  ///
  /// Returns `nil` when no session is open, which is the normal case.
  public static func resume(
    store: LoggerStore,
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) throws -> SessionCoordinator? {
    guard let recovery = try store.recoverySnapshot(asOf: now()) else { return nil }
    return restore(recovery, store: store, now: now, restAfterSet: restAfterSet, onStartRest: onStartRest)
  }

  /// Asynchronously reads the complete recovery snapshot, then builds actor-owned state.
  public static func loadResume(
    store: LoggerStore,
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) async throws -> SessionCoordinator? {
    guard let recovery = try await store.loadRecoverySnapshot(asOf: now()) else { return nil }
    try Task.checkCancellation()
    return restore(recovery, store: store, now: now, restAfterSet: restAfterSet, onStartRest: onStartRest)
  }

  private static func restore(
    _ recovery: SessionRecoverySnapshot, store: LoggerStore, now: @escaping () -> Date,
    restAfterSet: Duration?, onStartRest: @escaping (Duration, RestMetadata) -> Void
  ) -> SessionCoordinator {
    let session = recovery.session
    let planned = recovery.planned
    let written = recovery.written
    let snapshot = recovery.prior

    // Previously grouped by EXERCISE, not by progression key. A lifter who moves machines mid-exercise
    // produces sets with mixed machine ids under one plan row, and keying on the machine returned
    // only the subset that happened to match — reporting written sets as unlogged and inviting the
    // user to log them again. The set's machine is still recorded on the set itself; it is simply
    // not what identifies which plan row the set belongs to.
    //
    // Grouping only by exercise would merge two blocks of the same movement.
    // Grouped by PLAN ROW where the set records one. That is what distinguishes two blocks of the
    // same movement, which neither of the earlier keys could: grouping by machine lost sets when a
    // lifter moved mid-exercise, and grouping by exercise made both blocks claim the same sets.
    //
    // Sets written before the column existed carry no plan row, so they fall back to exercise
    // matching — and only into the FIRST plan row for that exercise, so they are attributed once
    // rather than to every block.
    let byPlanRow = Dictionary(
      grouping: written.filter { $0.sessionExerciseID != nil }
    ) { $0.sessionExerciseID! }
    let orphansByExercise = Dictionary(
      grouping: written.filter { $0.sessionExerciseID == nil }
    ) { $0.exerciseID }
    var claimedOrphans = Set<ExerciseID>()

    var rowIDs: [UUID: UUID] = [:]
    let states = planned.map { entry -> ExerciseLogState in
      var own = byPlanRow[entry.id] ?? []
      if !claimedOrphans.contains(entry.exerciseID),
        let orphans = orphansByExercise[entry.exerciseID]
      {
        claimedOrphans.insert(entry.exerciseID)
        own += orphans
      }
      let logged = own
        .sorted {
          if $0.setOrdinal != $1.setOrdinal { return $0.setOrdinal < $1.setOrdinal }
          if $0.completedAt != $1.completedAt { return $0.completedAt < $1.completedAt }
          return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
        .map {
          ExerciseLogState.LoggedSetSummary(
            setID: $0.id, weightKg: $0.weightKg, reps: $0.reps, isWarmup: $0.isWarmup,
            machineID: $0.machineID, completedAt: $0.completedAt
          )
        }
      let state = ExerciseLogState.resume(
        exerciseID: entry.exerciseID,
        machineID: entry.machineID,
        exerciseName: entry.exerciseName,
        machineName: entry.machineName,
        // Restored, not defaulted. Dropping it makes record detection fall back to a step size the
        // equipment may be unable to hit.
        machineIncrementKg: entry.machineIncrementKg,
        loggedSets: logged,
        snapshot: snapshot,
        plannedSets: entry.plannedSets
      )
      rowIDs[state.id] = entry.id
      return state
    }

    let coordinator = SessionCoordinator(
      store: store,
      sessionID: session.id,
      exercises: states,
      // Read back from the session row, so a recovered workout offers the same gym's equipment.
      gymID: session.gymID,
      startedAt: session.timeline.startedAt,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
    coordinator.planRowIDs = rowIDs
    return coordinator
  }

  /// Adds a movement to the workout in progress.
  ///
  /// Reads history for just this movement rather than re-reading the session's, so mid-workout
  /// additions cost one small query instead of redoing session start.
  ///
  /// With no machine named and a gym known, the movement opens on the machine it was most
  /// recently logged on at this gym, with that machine's name and step, so "Last time" and the
  /// prefill are there without two extra taps. It is the lifter's own last choice rather than a
  /// guess, and the chip stays changeable. Without a gym, or with no such machine, nothing is
  /// preselected; a failed lookup adds the movement without one rather than not at all.
  @discardableResult
  public func addExercise(
    exerciseID: ExerciseID,
    exerciseName: String,
    machineID: MachineID? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    plannedSets: Int? = nil
  ) -> Bool {
    var machineID = machineID
    var machineName = machineName
    var machineIncrementKg = machineIncrementKg
    if machineID == nil, let gymID,
      let recent = try? store.mostRecentMachine(for: exerciseID, at: gymID)
    {
      machineID = recent.id
      machineName = recent.displayName
      machineIncrementKg = recent.stackIncrementKg
    }
    let key = ProgressionKey(exerciseID: exerciseID, machineID: machineID)
    do {
      let snapshot = try store.priorPerformanceSnapshot(
        for: [key], excluding: sessionID, asOf: now()
      )
      let resolvedIncrement =
        machineIncrementKg
        ?? (machineID.flatMap { try? store.machineIncrements(for: [$0])[$0] })
      let state = ExerciseLogState.build(
        exerciseID: exerciseID,
        machineID: machineID,
        exerciseName: exerciseName,
        machineName: machineName,
        machineIncrementKg: resolvedIncrement,
        snapshot: snapshot,
        plannedSets: plannedSets
      )
      let rowID = try store.addExercise(
        to: sessionID,
        exerciseID: exerciseID,
        machineID: machineID,
        position: exercises.count,
        plannedSets: plannedSets
      )
      planRowIDs[state.id] = rowID
      exercises.append(state)
      clearError()
      return true
    } catch {
      return fail(error, .addExercise)
    }
  }

  /// Convenience for the picker, which hands back a `CatalogEntry`.
  @discardableResult
  public func addExercise(
    _ entry: CatalogEntry,
    machineID: MachineID? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    plannedSets: Int? = nil
  ) -> Bool {
    addExercise(
      exerciseID: entry.id,
      exerciseName: entry.name,
      machineID: machineID,
      machineName: machineName,
      machineIncrementKg: machineIncrementKg,
      plannedSets: plannedSets
    )
  }

  // MARK: - Logging

  /// Persists one row, then — and only then — marks it logged and requests rest.
  ///
  /// Returns `true` when the set was written. A `false` result leaves the row untouched and
  /// populates `lastError`.
  @discardableResult
  public func logSet(slotID: UUID, inExercise exerciseStateID: UUID) -> Bool {
    lastRecords = []
    lastRecordsSetID = nil
    guard
      let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let slotIndex = exercises[exerciseIndex].slots.firstIndex(where: { $0.id == slotID })
    else {
      return fail(SessionCoordinatorError.unknownSlot, .logSet)
    }

    let exercise = exercises[exerciseIndex]
    let slot = exercise.slots[slotIndex]
    guard !slot.isLogged else { return true }

    do {
      // The Store compares complete benchmarks before insertion, within the save
      // transaction. Claims are returned only after the transaction commits.
      let completedAt = now()
      let saved = try store.logSet(
        sessionID: sessionID,
        exerciseID: exercise.exerciseID,
        machineID: exercise.machineID,
        // The row's write identity, not its view identity: an undone row is re-saved as a new
        // record rather than under the primary key of the one that was deleted.
        commandID: SetID(rawValue: slot.commandID),
        // Stamped so recovery can tell two blocks of the same movement apart. Without it,
        // grouping by exercise made both blocks claim the same sets and double-counted them.
        sessionExerciseID: planRowIDs[exercise.id],
        draft: slot.draft,
        // Derived by the store from what is already written, NOT from the slot index. Recovered
        // slots are renumbered, so a slot-index ordinal reissues one that is already taken.
        setOrdinal: nil,
        isWarmup: slot.isWarmup,
        recordIncrement: exercise.machineIncrementKg,
        at: completedAt
      )
      exercises[exerciseIndex].markLogged(slotID: slotID, setID: saved.setID, completedAt: completedAt)
      refreshSavedSummary()
      clearError()

      // Records are announced only after a successful write, for the same reason the check mark
      // is: a celebration for a set that was not saved is worse than no celebration.
      lastRecords = saved.records
      lastRecordsSetID = saved.records.isEmpty ? nil : saved.setID

      // Warm-ups do not start a rest timer: the user is still warming up.
      if let restAfterSet, !slot.isWarmup {
        onStartRest(
          restAfterSet,
          RestMetadata(
            exerciseName: exercise.exerciseName,
            setOrdinal: exercises[exerciseIndex].workingOrdinal(ofSlotID: slotID) ?? 1,
            plannedSets: exercises[exerciseIndex].workingSetCount,
            machineName: exercise.machineName
          )
        )
      }
      return true
    } catch {
      return fail(error, .logSet)
    }
  }

  /// Takes back a saved set: deletes its row, then returns the slot to unlogged with its weight
  /// and reps kept as the draft. Editing a saved set is undo, then log again.
  ///
  /// Persist first, as `logSet` does: a failed delete leaves the row ticked, because it is still
  /// saved. The row keeps its id and place; a later log writes a new record. A running rest timer
  /// is left alone; that is the caller's decision. The celebration is cleared when it belonged
  /// to this set. Undoing a row that is not saved is a no-op that succeeds.
  @discardableResult
  public func undoSet(slotID: UUID, inExercise exerciseStateID: UUID) -> Bool {
    guard
      let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let slot = exercises[exerciseIndex].slots.first(where: { $0.id == slotID })
    else {
      return fail(SessionCoordinatorError.unknownSlot, .undoSet)
    }
    guard let setID = slot.loggedSetID else { return true }
    do {
      try store.deleteLoggedSet(setID, in: sessionID)
      exercises[exerciseIndex].unmarkLogged(slotID: slotID)
      forgetRecords(earnedByAnyOf: [setID])
      refreshSavedSummary()
      clearError()
      return true
    } catch {
      return fail(error, .undoSet)
    }
  }

  public func addSet(inExercise exerciseStateID: UUID, isWarmup: Bool = false) {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      _ = fail(SessionCoordinatorError.unknownExercise, .addSet)
      return
    }
    exercises[index].appendSlot(isWarmup: isWarmup)
  }

  /// Removes a row that was never saved, such as an accidental "Add set". In memory only,
  /// because unsaved rows are never stored. A saved row fails with `.slotIsLogged`: undo it first.
  @discardableResult
  public func removeSlot(slotID: UUID, inExercise exerciseStateID: UUID) -> Bool {
    guard
      let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let slot = exercises[exerciseIndex].slots.first(where: { $0.id == slotID })
    else {
      return fail(SessionCoordinatorError.unknownSlot, .removeSlot)
    }
    guard !slot.isLogged else { return fail(SessionCoordinatorError.slotIsLogged, .removeSlot) }
    exercises[exerciseIndex].removeSlot(id: slotID)
    clearError()
    return true
  }

  /// Removes a movement from the workout: its plan row and this workout's saved sets for it are
  /// deleted in one transaction, and only then does it leave memory. Its sets in other workouts
  /// are history and stay. The UI asks for confirmation first when the movement has saved sets.
  @discardableResult
  public func removeExercise(_ exerciseStateID: UUID) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      return fail(SessionCoordinatorError.unknownExercise, .removeExercise)
    }
    guard let rowID = planRowIDs[exerciseStateID] else {
      return fail(SessionCoordinatorError.untrackedExercise, .removeExercise)
    }
    let exercise = exercises[index]
    let savedSetIDs = exercise.slots.compactMap(\.loggedSetID)
    do {
      try store.removeSessionExercise(
        rowID: rowID, sessionID: sessionID, exerciseID: exercise.exerciseID,
        loggedSetIDs: savedSetIDs
      )
      exercises.remove(at: index)
      planRowIDs[exerciseStateID] = nil
      forgetRecords(earnedByAnyOf: savedSetIDs)
      refreshSavedSummary()
      clearError()
      return true
    } catch {
      return fail(error, .removeExercise)
    }
  }

  /// Moves a movement up (`-1`) or down (`+1`) the workout, persisting the whole order first.
  ///
  /// Larger offsets are clamped to the ends. Returns `false` without an error when the movement
  /// is already at that end, because nothing failed: there was nothing to move.
  @discardableResult
  public func moveExercise(_ exerciseStateID: UUID, by offset: Int) -> Bool {
    guard let from = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      return fail(SessionCoordinatorError.unknownExercise, .moveExercise)
    }
    let to = min(max(from + offset, 0), exercises.count - 1)
    guard to != from else { return false }
    var reordered = exercises
    reordered.insert(reordered.remove(at: from), at: to)
    let rowIDs = reordered.compactMap { planRowIDs[$0.id] }
    guard rowIDs.count == reordered.count else {
      return fail(SessionCoordinatorError.untrackedExercise, .moveExercise)
    }
    do {
      try store.setSessionExercisePositions(rowIDs, in: sessionID)
      // Moved in place rather than assigning `reordered`, so nothing typed into a row since the
      // copy was taken can be lost.
      exercises.insert(exercises.remove(at: from), at: to)
      clearError()
      return true
    } catch {
      return fail(error, .moveExercise)
    }
  }

  /// Records or changes this workout's gym, so a lifter who started without one, or at the
  /// wrong one, can still record machines. Persisted before `gymID` changes.
  ///
  /// Fails with `.gymChangeConflictsWithMachines` once any movement or saved set carries a
  /// machine from another gym, and with `LoggerStoreError.gymNotFound` for an unknown or archived
  /// gym. Naming the gym the workout already has succeeds without a write.
  @discardableResult
  public func setGym(_ gymID: GymID?) -> Bool {
    guard gymID != self.gymID else {
      clearError()
      return true
    }
    do {
      try store.setSessionGym(sessionID, to: gymID)
      self.gymID = gymID
      clearError()
      return true
    } catch LoggerStoreError.machineGymMismatch {
      return fail(SessionCoordinatorError.gymChangeConflictsWithMachines, .setGym)
    } catch {
      return fail(error, .setGym)
    }
  }

  /// Dismisses the current failure, for instance when the lifter closes its banner.
  public func clearError() {
    lastError = nil
    lastFailedCommand = nil
  }

  /// Moves an exercise to a different machine, re-prefilling from that machine's history.
  ///
  /// Reads history for just the new key. Logged sets keep the machine they were performed on,
  /// because they were performed on it.
  @discardableResult
  public func changeMachine(
    to machineID: MachineID?,
    machineName: String?,
    machineIncrementKg: Double? = nil,
    inExercise exerciseStateID: UUID
  ) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      return fail(SessionCoordinatorError.unknownExercise, .changeMachine)
    }
    let exercise = exercises[index]
    let key = ProgressionKey(exerciseID: exercise.exerciseID, machineID: machineID)
    do {
      let snapshot = try store.priorPerformanceSnapshot(
        for: [key], excluding: sessionID, asOf: now()
      )
      var prior = snapshot.prior(for: key)
      var note: String?
      if prior == nil, let fallback = snapshot.priorAllowingOtherMachines(for: key) {
        prior = fallback.performance
        if fallback.wasOtherMachine { note = "From another machine" }
      }
      // Persist before mutating in memory, so a failed write leaves the two in agreement rather
      // than leaving the app believing something the database does not.
      //
      // A missing row id is refused rather than skipped. Silently not persisting is precisely the
      // defect being fixed here — the app would show the new machine while the database kept the
      // old one — so an untracked exercise fails loudly instead of appearing to succeed.
      guard let rowID = planRowIDs[exercise.id] else {
        return fail(SessionCoordinatorError.untrackedExercise, .changeMachine)
      }
      try store.setSessionExerciseMachine(
        rowID: rowID, machineID: machineID, sessionID: sessionID, exerciseID: exercise.exerciseID
      )
      // Same rule: the equipment's own step size, not whatever the caller happened to know.
      let resolvedIncrement =
        machineIncrementKg
        ?? (machineID.flatMap { try? store.machineIncrements(for: [$0])[$0] })
      exercises[index].changeMachine(
        to: machineID, machineName: machineName, machineIncrementKg: resolvedIncrement,
        prior: prior, priorNote: note
      )
      clearError()
      return true
    } catch {
      return fail(error, .changeMachine)
    }
  }

  // MARK: - Finishing

  /// Closes the session now. Refuses to double-finish, so `finishedAt` cannot drift.
  ///
  /// A workout the store reports as already finished (on another device, or by a finish that
  /// raced a recovery) is not an error here: the stored instant stands and `isFinished` becomes
  /// true, so the root can let go of it. Any other failure leaves the workout open and throws.
  public func finish() throws {
    try close(at: now())
  }

  /// Closes the session at a chosen instant, for a workout left open after training ended.
  ///
  /// `endedAt` must lie between the start and now, and not before the newest saved set: a
  /// workout cannot end before work it contains. Anything else throws
  /// `SessionCoordinatorError.invalidFinishTime` and leaves the workout open.
  public func finish(at endedAt: Date) throws {
    guard endedAt >= startedAt, endedAt <= now(), endedAt >= (lastLoggedAt ?? startedAt) else {
      throw SessionCoordinatorError.invalidFinishTime
    }
    try close(at: endedAt)
  }

  private func close(at endedAt: Date) throws {
    do {
      try store.finishSession(sessionID, at: endedAt)
    } catch SessionTimelineError.alreadyFinished {
      // Closed already, so the truthful state is finished. Throwing would leave the screen
      // stuck: the root drops a coordinator only once it reports finished.
    }
    isFinished = true
  }

  /// Deletes this open workout with its plan and saved sets, for a workout started by mistake.
  /// Sets `isDiscarded`, so the root can drop the coordinator.
  ///
  /// A workout already gone is the outcome asked for, so that succeeds too. A workout already
  /// finished is history and is kept: this throws `LoggerStoreError.sessionClosed` and sets
  /// `isFinished`, which is the truth about it.
  public func discard() throws {
    do {
      try store.discardOpenSession(sessionID)
    } catch LoggerStoreError.sessionNotFound {
      // Removed elsewhere already.
    } catch LoggerStoreError.sessionClosed {
      isFinished = true
      throw LoggerStoreError.sessionClosed
    }
    isDiscarded = true
    lastRecords = []
    lastRecordsSetID = nil
  }

  // MARK: - Bookkeeping

  /// Records a failure beside the command that produced it. Always returns `false`, so a
  /// command can `return fail(...)`.
  private func fail(_ error: any Error, _ command: SessionCommand) -> Bool {
    lastError = error
    lastFailedCommand = command
    return false
  }

  /// Recomputes the stored summaries from the exercises. Assigned only on change, so observers
  /// of the count are not invalidated by a save that leaves it the same.
  private func refreshSavedSummary() {
    let count = exercises.reduce(0) { $0 + $1.loggedCount }
    if count != loggedSetCount { loggedSetCount = count }
    let newest = exercises.compactMap(\.lastLoggedAt).max()
    if newest != lastLoggedAt { lastLoggedAt = newest }
  }

  private func forgetRecords(earnedByAnyOf setIDs: [SetID]) {
    guard let earned = lastRecordsSetID, setIDs.contains(earned) else { return }
    lastRecords = []
    lastRecordsSetID = nil
  }
}

/// A coordinator command, named so a failure can be described by what the lifter was doing.
public nonisolated enum SessionCommand: Equatable, Sendable {
  case addExercise
  case logSet
  case undoSet
  case addSet
  case removeSlot
  case removeExercise
  case moveExercise
  case changeMachine
  case setGym
}

/// One exercise on today's plan, before the session exists.
public nonisolated struct PlannedExercise: Hashable, Sendable {
  public let exerciseID: ExerciseID
  public let machineID: MachineID?
  public let exerciseName: String
  public let machineName: String?
  public let machineIncrementKg: Double?
  public let plannedSets: Int?

  public init(
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    plannedSets: Int? = nil
  ) {
    self.exerciseID = exerciseID
    self.machineID = machineID
    self.exerciseName = exerciseName
    self.machineName = machineName
    self.machineIncrementKg = machineIncrementKg
    self.plannedSets = plannedSets
  }

  public var progressionKey: ProgressionKey {
    ProgressionKey(exerciseID: exerciseID, machineID: machineID)
  }
}

public enum SessionCoordinatorError: Error, Equatable, Sendable {
  case unknownExercise
  case unknownSlot
  /// The exercise exists in memory but has no `sessionExercises` row id, so a machine change has
  /// nowhere to be written. Only reachable through the public initialiser; `start`, `resume` and
  /// `addExercise` all record the id.
  case untrackedExercise
  /// `removeSlot` was asked to remove a saved row. Saved work is taken back with `undoSet`, which
  /// deletes it from storage first; a row is never dropped from the screen while still saved.
  case slotIsLogged
  /// `setGym` was refused because a movement or saved set already carries a machine from another
  /// gym. Machines belong to a gym, so moving the workout would contradict recorded equipment.
  case gymChangeConflictsWithMachines
  /// `finish(at:)` was given an instant before the start or the newest saved set, or in the
  /// future. Nothing was written and the workout is still open.
  case invalidFinishTime
}
