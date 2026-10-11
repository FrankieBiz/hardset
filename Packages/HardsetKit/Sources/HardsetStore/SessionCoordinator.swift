import Foundation
// Explicit: on Apple platforms `@Observable` arrives transitively, on Linux it does not.
import Observation
import HardsetCore
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
  public private(set) var isFinished = false
  /// Records set by the most recently logged set, or empty. Cleared on the next log so a
  /// celebration cannot linger onto a set that did not earn it.
  public private(set) var lastRecords: [PersonalRecord] = []

  /// Maps an `ExerciseLogState.id` to its `sessionExercises` row id.
  ///
  /// Held here rather than on `ExerciseLogState` because a storage row id is a storage concern and
  /// `HardsetCore` must not learn about one. Without it, a machine change has nowhere to be
  /// written, and the plan in the database silently contradicts the sets that were logged.
  private var planRowIDs: [UUID: UUID] = [:]

  private let store: LoggerStore
  private let now: () -> Date
  private let restPreferences: any RestPreferenceStore
  private let onStartRest: (Duration, RestMetadata) -> Void

  /// - Parameters:
  ///   - restPreferences: Where the lifter's per-exercise rest choice is remembered. It is read
  ///     once, here, into `restChoices`. There is no built-in default: a rest prescription is a
  ///     training decision, and inventing 90 seconds would be the app asserting something it has
  ///     no basis for, so an exercise with no stored choice starts no timer.
  ///   - onStartRest: Where a rest request goes. Left empty in tests and in previews.
  /// The gym this session is at, when one is known.
  ///
  /// Retained rather than re-read per render: the machine picker needs it to offer the rest of the
  /// gym's equipment, and a view that queried for it on every body evaluation would hit the
  /// database inside the logging path.
  public private(set) var gymID: GymID?

  /// The lifter's rest choice per exercise, loaded once at start so the chip renders without
  /// touching storage. Two blocks of one movement share an entry — the choice is per exercise.
  public private(set) var restChoices: [ExerciseID: Duration] = [:]
  /// What is resting right now, set only after the rest was actually requested.
  public private(set) var activeRest: RestMetadata?

  /// Records each row earned, kept for the whole workout, keyed by `SetSlot.id`.
  ///
  /// `lastRecords` is the moment and is cleared by the next log. This is the trophy that stays on
  /// the row that earned it (spec 2.5). It is rebuilt from storage on resume, so a crash does not
  /// take it away.
  public private(set) var recordsBySlot: [UUID: [PersonalRecord]] = [:]

  /// The latest thing worth a haptic. A new value per occurrence, so two identical events in a row
  /// still play twice. Set only after the write it describes has succeeded or failed.
  public private(set) var feedback: FeedbackPulse?

  public init(
    store: LoggerStore,
    sessionID: SessionID,
    exercises: [ExerciseLogState],
    gymID: GymID? = nil,
    now: @escaping () -> Date = { Date() },
    restPreferences: any RestPreferenceStore = InMemoryRestPreferences(),
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) {
    self.store = store
    self.sessionID = sessionID
    self.exercises = exercises
    self.gymID = gymID
    self.now = now
    self.restPreferences = restPreferences
    self.onStartRest = onStartRest
    for exercise in exercises {
      loadRestChoice(for: exercise.exerciseID)
    }
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
    restPreferences: any RestPreferenceStore = InMemoryRestPreferences(),
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) throws -> SessionCoordinator {
    let startedAt = now()
    let sessionID = try store.startSession(gymID: gymID, title: title, at: startedAt)

    let snapshot = try store.priorPerformanceSnapshot(
      for: plan.map(\.progressionKey),
      excluding: sessionID,
      asOf: startedAt
    )

    var states: [ExerciseLogState] = []
    var rowIDs: [UUID: UUID] = [:]
    // Read from the machines table rather than trusting the caller. `start` used to take whatever
    // increment was passed in — and nothing in the app passed one — while `resume` read it from
    // storage, so the same set could be a record before a restart and not after.
    let increments = try store.machineIncrements(for: plan.compactMap(\.machineID))
    for (position, planned) in plan.enumerated() {
      let rowID = try store.addExercise(
        to: sessionID,
        exerciseID: planned.exerciseID,
        machineID: planned.machineID,
        position: position,
        plannedSets: planned.plannedSets
      )
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
      rowIDs[state.id] = rowID
      states.append(state)
    }

    let coordinator = SessionCoordinator(
      store: store,
      sessionID: sessionID,
      exercises: states,
      gymID: gymID,
      now: now,
      restPreferences: restPreferences,
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
    restPreferences: any RestPreferenceStore = InMemoryRestPreferences(),
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) throws -> SessionCoordinator? {
    guard let session = try store.openSession() else { return nil }

    let planned = try store.sessionExercises(in: session.id)
    let written = try store.sets(in: session.id)

    // One history read for the whole session, excluding the session itself so a recovered
    // workout cannot suggest values from its own sets.
    let snapshot = try store.priorPerformanceSnapshot(
      for: planned.map(\.progressionKey),
      excluding: session.id,
      asOf: now()
    )

    // Grouped by EXERCISE, not by progression key. A lifter who moves machines mid-exercise
    // produces sets with mixed machine ids under one plan row, and keying on the machine returned
    // only the subset that happened to match — reporting written sets as unlogged and inviting the
    // user to log them again. The set's machine is still recorded on the set itself; it is simply
    // not what identifies which plan row the set belongs to.
    //
    // Known limitation: the same exercise appearing twice in one session merges, because
    // `loggedSets` carries no reference to a `sessionExercises` row and so cannot distinguish them.
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
        .sorted { $0.setOrdinal < $1.setOrdinal }
        .map {
          ExerciseLogState.LoggedSetSummary(
            setID: $0.id, weightKg: $0.weightKg, reps: $0.reps, isWarmup: $0.isWarmup
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
      now: now,
      restPreferences: restPreferences,
      onStartRest: onStartRest
    )
    coordinator.planRowIDs = rowIDs
    // Trophies come back with the workout, and nothing is announced again. A failed read loses
    // only the trophies, never the workout, which is why this does not throw.
    if let earned = try? store.recordsBySet(in: session.id) {
      for exercise in states {
        for slot in exercise.slots {
          if let setID = slot.loggedSetID, let records = earned[setID], !records.isEmpty {
            coordinator.recordsBySlot[slot.id] = records
          }
        }
      }
    }
    return coordinator
  }

  /// Adds a movement to the workout in progress.
  ///
  /// Reads history for just this movement rather than re-reading the session's, so mid-workout
  /// additions cost one small query instead of redoing session start.
  @discardableResult
  public func addExercise(
    exerciseID: ExerciseID,
    exerciseName: String,
    machineID: MachineID? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    plannedSets: Int? = nil
  ) -> Bool {
    let key = ProgressionKey(exerciseID: exerciseID, machineID: machineID)
    do {
      let rowID = try store.addExercise(
        to: sessionID,
        exerciseID: exerciseID,
        machineID: machineID,
        position: exercises.count,
        plannedSets: plannedSets
      )
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
      planRowIDs[state.id] = rowID
      exercises.append(state)
      loadRestChoice(for: exerciseID)
      lastError = nil
      return true
    } catch {
      lastError = error
      return false
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
    guard
      let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let slotIndex = exercises[exerciseIndex].slots.firstIndex(where: { $0.id == slotID })
    else {
      lastError = SessionCoordinatorError.unknownSlot
      emit(.error, slotID: slotID)
      return false
    }

    let exercise = exercises[exerciseIndex]
    let slot = exercise.slots[slotIndex]
    // Already written: nothing new happened, so nothing plays.
    guard !slot.isLogged else { return true }

    do {
      // Read history BEFORE writing. Querying afterwards would include the set being tested, so
      // a new best would be compared against itself and could never win.
      let priorHistory =
        (try? store.completedSets(for: exercise.progressionKey)) ?? []

      let setID = try store.logSet(
        sessionID: sessionID,
        exerciseID: exercise.exerciseID,
        machineID: exercise.machineID,
        // Stamped so recovery can tell two blocks of the same movement apart. Without it,
        // grouping by exercise made both blocks claim the same sets and double-counted them.
        sessionExerciseID: planRowIDs[exercise.id],
        draft: slot.draft,
        // Derived by the store from what is already written, NOT from the slot index. Recovered
        // slots are renumbered, so a slot-index ordinal reissues one that is already taken.
        setOrdinal: nil,
        isWarmup: slot.isWarmup,
        at: now()
      )
      exercises[exerciseIndex].markLogged(slotID: slotID, setID: setID)
      lastError = nil

      // Records are announced only after a successful write, for the same reason the check mark
      // is: a celebration for a set that was not saved is worse than no celebration.
      let found: [PersonalRecord]
      if let resolved = slot.draft.resolved() {
        found = PersonalRecordDetector.records(
          for: .init(weightKg: resolved.weightKg, reps: resolved.reps, isWarmup: slot.isWarmup),
          history: priorHistory,
          increment: exercise.machineIncrementKg
        )
      } else {
        found = []
      }
      lastRecords = found
      if !found.isEmpty { recordsBySlot[slotID] = found }
      // One haptic per log, after the write. A record outranks an ordinary log.
      emit(.afterLogging(records: found), slotID: slotID)

      // Rest only if the lifter chose one for this exercise; never after a warm-up.
      if let rest = RestPlan.restAfterLogging(
        isWarmup: slot.isWarmup, choice: restChoices[exercise.exerciseID])
      {
        requestRest(rest, forExerciseAt: exerciseIndex, slotID: slotID)
      }
      return true
    } catch {
      lastError = error
      emit(.error, slotID: slotID)
      return false
    }
  }

  public func addSet(inExercise exerciseStateID: UUID, isWarmup: Bool = false) {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      lastError = SessionCoordinatorError.unknownExercise
      return
    }
    exercises[index].appendSlot(isWarmup: isWarmup)
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
      lastError = SessionCoordinatorError.unknownExercise
      return false
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
        lastError = SessionCoordinatorError.untrackedExercise
        return false
      }
      try store.setSessionExerciseMachine(rowID: rowID, machineID: machineID)
      // Same rule: the equipment's own step size, not whatever the caller happened to know.
      let resolvedIncrement =
        machineIncrementKg
        ?? (machineID.flatMap { try? store.machineIncrements(for: [$0])[$0] })
      exercises[index].changeMachine(
        to: machineID, machineName: machineName, machineIncrementKg: resolvedIncrement,
        prior: prior, priorNote: note
      )
      lastError = nil
      return true
    } catch {
      lastError = error
      return false
    }
  }

  // MARK: - Rest

  /// The only writer of `feedback`.
  private func emit(_ event: FeedbackEvent, slotID: UUID?) {
    feedback = FeedbackPulse.following(feedback, event: event, slotID: slotID)
  }

  /// Persists the lifter's choice for this movement, or forgets it when `rest` is nil.
  /// Out-of-range values are refused rather than clamped.
  public func setRestChoice(_ rest: Duration?, forExercise stateID: UUID) {
    guard let exercise = exercises.first(where: { $0.id == stateID }) else {
      lastError = SessionCoordinatorError.unknownExercise
      return
    }
    let validated = rest.flatMap(RestPlan.validated)
    guard rest == nil || validated != nil else { return }
    restPreferences.setRest(validated, for: exercise.exerciseID)
    restChoices[exercise.exerciseID] = validated
  }

  /// Starts this exercise's chosen rest now. Returns false, and starts nothing, without a choice.
  @discardableResult
  public func startRest(forExercise stateID: UUID) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == stateID }),
      let rest = restChoices[exercises[index].exerciseID]
    else { return false }
    requestRest(rest, forExerciseAt: index, slotID: nil)
    return true
  }

  /// The rest ended, was skipped, or the workout finished.
  public func endRest() { activeRest = nil }

  /// The only place `onStartRest` is called, so `activeRest` cannot disagree with what was asked
  /// of the timer.
  private func requestRest(_ rest: Duration, forExerciseAt index: Int, slotID: UUID?) {
    let exercise = exercises[index]
    let ordinal =
      slotID.flatMap { exercises[index].workingOrdinal(ofSlotID: $0) }
      ?? max(1, exercise.slots.filter { $0.isLogged && !$0.isWarmup }.count)
    let metadata = RestMetadata(
      exerciseName: exercise.exerciseName,
      setOrdinal: ordinal,
      plannedSets: exercises[index].workingSetCount,
      machineName: exercise.machineName
    )
    onStartRest(rest, metadata)
    activeRest = metadata
  }

  /// Reads one exercise's remembered choice into memory. Called at start, resume and when a
  /// movement is added — never per render.
  ///
  /// A stored value is validated like a typed one. It can predate the current range, come from
  /// an older build, or be written by hand, and an out-of-range rest is refused, not clamped, on
  /// every path in.
  private func loadRestChoice(for exerciseID: ExerciseID) {
    if let rest = restPreferences.rest(for: exerciseID).flatMap(RestPlan.validated) {
      restChoices[exerciseID] = rest
    }
  }

  // MARK: - Finishing

  /// Closes the session. Refuses to double-finish, so `finishedAt` cannot drift.
  public func finish() throws {
    try store.finishSession(sessionID, at: now())
    isFinished = true
    // After the write, like every other claim here: a rest must not outlive the workout.
    endRest()
  }

  public var loggedSetCount: Int {
    exercises.reduce(0) { $0 + $1.loggedCount }
  }
}

/// One exercise on today's plan, before the session exists.
public struct PlannedExercise: Hashable, Sendable {
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
}
