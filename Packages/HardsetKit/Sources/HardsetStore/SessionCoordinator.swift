import Foundation
import HardsetCore
import SQLiteData

private nonisolated struct SessionStartPreparation: Sendable {
  let sessionID: SessionID
  let states: [ExerciseLogState]
  let rowIDs: [UUID: UUID]
}

private nonisolated struct SessionResumePreparation: Sendable {
  let session: SessionRecord
  let states: [ExerciseLogState]
  let rowIDs: [UUID: UUID]
}

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
  /// What the last rest request was for, so the rest bar can say which station the lifter left.
  ///
  /// Held here rather than in the view. The coordinator has always built a full `RestMetadata` --
  /// exercise, working-set ordinal, planned count, machine -- and handed it to `onStartRest`, but
  /// the only place that could display it kept its own `@State` copy that was never assigned from
  /// anything. So the rest bar showed an unlabelled countdown while the data sat one layer away.
  /// The coordinator is constructed before that view exists, which is exactly why the view could
  /// not be the owner.
  public private(set) var lastRestMetadata: RestMetadata?

  /// Every record set during this session, accumulated.
  ///
  /// `lastRecords` is reset on each write because it drives the per-set announcement. The summary
  /// needs the whole session, and recomputing it at the end is not an option: detection compares a
  /// set against the history that existed *before* it was written, and by the time the workout ends
  /// that history includes the very sets being judged. So it is captured as it happens or not at
  /// all.
  public private(set) var sessionRecords: [PersonalRecord] = []

  /// Maps an `ExerciseLogState.id` to its `sessionExercises` row id.
  ///
  /// Held here rather than on `ExerciseLogState` because a storage row id is a storage concern and
  /// `HardsetCore` must not learn about one. Without it, a machine change has nowhere to be
  /// written, and the plan in the database silently contradicts the sets that were logged.
  private var planRowIDs: [UUID: UUID] = [:]

  private let store: LoggerStore
  private let now: () -> Date
  /// Rest to request after a working set. **Mutable on purpose.**
  ///
  /// This used to be captured at construction, which meant a lifter who turned the rest timer on
  /// part-way through a workout got nothing until the next session -- the coordinator was already
  /// holding the old value, and a resumed session held whatever the setting was at launch. The
  /// root keeps this in step with the stored preference instead.
  public var restAfterSet: Duration?
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

  /// What the lifter called this workout, or empty. Held here so the header can show it without a
  /// query per render.
  public private(set) var title: String = ""
  /// The workout's own note: how the session went, rather than how a movement is set up.
  ///
  /// `sessions.notes` was written once per workout as the empty string and read nowhere. Slept
  /// badly, first session back, felt strong -- the context that makes a log worth reading later.
  public private(set) var notes: String = ""

  /// When this session began and, once closed, when it ended.
  ///
  /// Held as a `SessionTimeline` rather than two loose dates so the derived-never-stored rule and
  /// its guards come along for free: an open session has no duration at all, rather than "however
  /// long ago it started", which is the bug that shipped 9,749-minute workouts.
  public private(set) var timeline: SessionTimeline

  /// What this workout amounted to. Read when the summary is shown.
  public var outcome: SessionOutcome {
    SessionOutcome(exercises: exercises, timeline: timeline, records: sessionRecords)
  }

  public init(
    store: LoggerStore,
    sessionID: SessionID,
    exercises: [ExerciseLogState],
    gymID: GymID? = nil,
    startedAt: Date? = nil,
    title: String = "",
    notes: String = "",
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) {
    self.store = store
    self.sessionID = sessionID
    self.exercises = exercises
    self.gymID = gymID
    self.timeline = SessionTimeline(startedAt: startedAt ?? now())
    self.title = title
    self.notes = notes
    self.now = now
    self.restAfterSet = restAfterSet
    self.onStartRest = onStartRest
  }

  /// Opens a session and builds its exercise states from one history read.
  ///
  /// The snapshot is taken here, once, and excludes the session being started so a resumed
  /// workout cannot suggest values from its own sets.
  public static func start(
    store: LoggerStore,
    gymID: GymID? = nil,
    title: String = "",
    /// The plan day this workout is being started from, when it is. Carried so the planner can say
    /// when each day was last trained without inferring it from what the session contained.
    splitDayID: SplitDayID? = nil,
    plan: [PlannedExercise],
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) throws -> SessionCoordinator {
    let startedAt = now()
    let prepared = try prepareStart(
      store: store,
      gymID: gymID,
      title: title,
      splitDayID: splitDayID,
      plan: plan,
      startedAt: startedAt
    )
    return coordinator(
      from: prepared,
      store: store,
      gymID: gymID,
      title: title,
      startedAt: startedAt,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
  }

  /// The same start contract with database preparation moved off the UI actor. The synchronous
  /// entry point remains for tests and non-UI callers; the app uses this one so a large prior-
  /// performance snapshot cannot stall the Start button.
  public static func startAsync(
    store: LoggerStore,
    gymID: GymID? = nil,
    title: String = "",
    splitDayID: SplitDayID? = nil,
    plan: [PlannedExercise],
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) async throws -> SessionCoordinator {
    let startedAt = now()
    let prepared = try await Task.detached(priority: .userInitiated) {
      try prepareStart(
        store: store,
        gymID: gymID,
        title: title,
        splitDayID: splitDayID,
        plan: plan,
        startedAt: startedAt
      )
    }.value
    return coordinator(
      from: prepared,
      store: store,
      gymID: gymID,
      title: title,
      startedAt: startedAt,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
  }

  private nonisolated static func prepareStart(
    store: LoggerStore,
    gymID: GymID?,
    title: String,
    splitDayID: SplitDayID?,
    plan: [PlannedExercise],
    startedAt: Date
  ) throws -> SessionStartPreparation {
    let sessionID = try store.startSession(
      gymID: gymID, title: title, splitDayID: splitDayID, at: startedAt
    )

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
        modality: planned.modality,
        machineName: planned.machineName,
        machineIncrementKg: planned.machineID.flatMap { increments[$0] }
          ?? planned.machineIncrementKg,
        snapshot: snapshot,
        plannedSets: planned.plannedSets
      )
      rowIDs[state.id] = rowID
      states.append(state)
    }

    // One query for the whole plan rather than one per movement.
    let notes = try store.exerciseNotes(for: states.map(\.exerciseID))
    for index in states.indices {
      states[index].notes = notes[states[index].exerciseID] ?? ""
    }

    return SessionStartPreparation(sessionID: sessionID, states: states, rowIDs: rowIDs)
  }

  private static func coordinator(
    from prepared: SessionStartPreparation,
    store: LoggerStore,
    gymID: GymID?,
    title: String,
    startedAt: Date,
    now: @escaping () -> Date,
    restAfterSet: Duration?,
    onStartRest: @escaping (Duration, RestMetadata) -> Void
  ) -> SessionCoordinator {
    let coordinator = SessionCoordinator(
      store: store,
      sessionID: prepared.sessionID,
      exercises: prepared.states,
      gymID: gymID,
      startedAt: startedAt,
      // Carried, not dropped. `startSession` wrote this to the row while the coordinator kept "",
      // so a titled workout rendered as "Name this workout" until a force-quit sent it through
      // `resume`, which does read it back -- and then the name appeared out of nowhere. Harmless
      // while nothing passed a title; a visible disagreement the moment a plan day does.
      title: title,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
    coordinator.planRowIDs = prepared.rowIDs
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
    guard let prepared = try prepareResume(store: store, asOf: now()) else { return nil }
    return resumedCoordinator(
      from: prepared,
      store: store,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
  }

  /// Recovery can read years of prior performance. The app uses this entry point during launch
  /// so reopening an interrupted workout never monopolises the first interactive frame.
  public static func resumeAsync(
    store: LoggerStore,
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) async throws -> SessionCoordinator? {
    let asOf = now()
    let prepared = try await Task.detached(priority: .userInitiated) {
      try prepareResume(store: store, asOf: asOf)
    }.value
    guard let prepared else { return nil }
    return resumedCoordinator(
      from: prepared,
      store: store,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
  }

  private nonisolated static func prepareResume(
    store: LoggerStore,
    asOf: Date
  ) throws -> SessionResumePreparation? {
    guard let session = try store.openSession() else { return nil }

    let planned = try store.sessionExercises(in: session.id)
    let written = try store.sets(in: session.id)
    // One query for the whole session, matching what `start` does. Recovery previously dropped
    // notes entirely, so a lifter who wrote down a seat height lost it to a crash.
    let resumedNotes = try store.exerciseNotes(for: planned.map(\.exerciseID))

    // One history read for the whole session, excluding the session itself so a recovered
    // workout cannot suggest values from its own sets.
    let snapshot = try store.priorPerformanceSnapshot(
      for: planned.map(\.progressionKey),
      excluding: session.id,
      asOf: asOf
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
            setID: $0.id, weightKg: $0.weightKg, reps: $0.reps,
            // Restored, like the modality and the notes above it. The row otherwise came back
            // claiming no effort was recorded for a set the lifter had rated.
            rpe: $0.rpe, kind: $0.kind
          )
        }
      var state = ExerciseLogState.resume(
        exerciseID: entry.exerciseID,
        machineID: entry.machineID,
        exerciseName: entry.exerciseName,
        // Restored for the same reason as the increment below. Without it every recovered
        // bodyweight movement came back as a loaded one, so a pull-up asked for a weight.
        modality: entry.modality,
        machineName: entry.machineName,
        // Restored, not defaulted. Dropping it makes record detection fall back to a step size the
        // equipment may be unable to hit.
        machineIncrementKg: entry.machineIncrementKg,
        loggedSets: logged,
        snapshot: snapshot,
        plannedSets: entry.plannedSets,
        notes: resumedNotes[entry.exerciseID] ?? ""
      )
      rowIDs[state.id] = entry.id
      // Restored with everything else. Without it a force-quit dissolves the superset silently
      // and the rest timer goes back to arming after every set, mid-workout, unexplained.
      state.supersetGroup = entry.supersetGroup
      return state
    }

    return SessionResumePreparation(session: session, states: states, rowIDs: rowIDs)
  }

  private static func resumedCoordinator(
    from prepared: SessionResumePreparation,
    store: LoggerStore,
    now: @escaping () -> Date,
    restAfterSet: Duration?,
    onStartRest: @escaping (Duration, RestMetadata) -> Void
  ) -> SessionCoordinator {
    let coordinator = SessionCoordinator(
      store: store,
      sessionID: prepared.session.id,
      exercises: prepared.states,
      // Read back from the session row, so a recovered workout offers the same gym's equipment.
      gymID: prepared.session.gymID,
      // From storage, never from `now()`. A recovered session started when it started, and
      // re-stamping it here is exactly how a workout becomes nine thousand minutes long.
      startedAt: prepared.session.timeline.startedAt,
      title: prepared.session.title,
      // Restored with the rest of the session, or a recovered workout loses the note the lifter
      // wrote about it.
      notes: prepared.session.notes,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
    coordinator.planRowIDs = prepared.rowIDs
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
    modality: ExerciseModality? = nil,
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
        modality: modality,
        machineName: machineName,
        machineIncrementKg: resolvedIncrement,
        snapshot: snapshot,
        plannedSets: plannedSets,
        notes: (try? store.exerciseNotes(for: [exerciseID])[exerciseID]) ?? ""
      )
      planRowIDs[state.id] = rowID
      exercises.append(state)
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
      modality: entry.modality,
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
      return false
    }

    let exercise = exercises[exerciseIndex]
    let slot = exercise.slots[slotIndex]
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
        kind: slot.kind,
        // Recorded when the lifter supplied one. The column has existed unused since the first
        // migration.
        rpe: slot.draft.validatedRPE,
        at: now()
      )
      exercises[exerciseIndex].markLogged(slotID: slotID, setID: setID)
      lastError = nil

      // Records are announced only after a successful write, for the same reason the check mark
      // is: a celebration for a set that was not saved is worse than no celebration.
      if let resolved = slot.draft.resolved() {
        lastRecords = PersonalRecordDetector.records(
          for: .init(
            weightKg: resolved.weightKg, reps: resolved.reps, isWarmup: slot.isWarmup
          ),
          history: priorHistory,
          increment: exercise.machineIncrementKg
        )
        sessionRecords.append(contentsOf: lastRecords)
      } else {
        lastRecords = []
      }

      // Whether this set ends a piece of work, or is followed immediately by more of it.
      //
      // Warm-ups never armed rest. A set with a drop queued behind it does not either, because
      // the point of a drop is that no rest is taken; nor does a set inside a superset until the
      // rest of the round is done. All three live in one pure, tested rule rather than as
      // conditions accumulating here.
      let armsRest = SupersetRest.shouldArmRest(
        afterLogging: slotID,
        in: exercises[exerciseIndex],
        session: exercises
      )
      if let restAfterSet, armsRest {
        let metadata = RestMetadata(
          exerciseName: exercise.exerciseName,
          setOrdinal: exercises[exerciseIndex].workingOrdinal(ofSlotID: slotID) ?? 1,
          plannedSets: exercises[exerciseIndex].workingSetCount,
          machineName: exercise.machineName
        )
        lastRestMetadata = metadata
        onStartRest(restAfterSet, metadata)
      }
      return true
    } catch {
      lastError = error
      return false
    }
  }

  /// Removes an empty set row. Tapping "Add set" twice should not leave a row that cannot go away.
  @discardableResult
  public func removeSlot(slotID: UUID, inExercise exerciseStateID: UUID) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      lastError = SessionCoordinatorError.unknownSlot
      return false
    }
    // Nothing is persisted per slot until it is logged, so an unlogged row exists only in memory
    // and removing it touches no storage.
    return exercises[index].removeSlot(slotID: slotID)
  }

  /// Adds a drop continuing the last row of a movement.
  ///
  /// Touches no storage, like every other row that has not been logged yet. Returns the new row's
  /// id, or `nil` when there is nothing to continue — an empty movement, or one whose last row is
  /// a warm-up.
  @discardableResult
  public func addDropSet(inExercise exerciseStateID: UUID) -> UUID? {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      lastError = SessionCoordinatorError.unknownSlot
      return nil
    }
    return exercises[index].appendDropSet()
  }

  /// Pairs a movement with the one after it, so rest waits for the round rather than the set.
  ///
  /// Joining with the *next* movement rather than an arbitrary one is what keeps a group
  /// contiguous by construction. A superset whose members are scattered down the screen is a
  /// scrolling problem during the one part of a workout where scrolling is hardest, and nothing
  /// about the rule needs them adjacent — so the constraint costs nothing and buys the ordering.
  ///
  /// Extends an existing group rather than starting a new one when either side already has one,
  /// which is how a third movement joins a pair.
  @discardableResult
  public func joinSupersetWithNext(exerciseStateID: UUID) -> Bool {
    guard
      let index = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      exercises.indices.contains(index + 1)
    else {
      lastError = SessionCoordinatorError.unknownSlot
      return false
    }

    let group =
      exercises[index].supersetGroup
      ?? exercises[index + 1].supersetGroup
      ?? SupersetGrouping.nextGroup(in: exercises)

    for offset in [index, index + 1] where exercises[offset].supersetGroup != group {
      exercises[offset].supersetGroup = group
      persistSupersetGroup(at: offset)
    }
    return true
  }

  /// Takes a movement back out of its superset.
  ///
  /// If that leaves exactly one movement behind, it is ungrouped too. A group of one is not a
  /// superset, and leaving the number on the row would keep it lettered "A" with no partner while
  /// the rest rule waited for a round that can never complete.
  @discardableResult
  public func leaveSuperset(exerciseStateID: UUID) -> Bool {
    guard
      let index = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let group = exercises[index].supersetGroup
    else {
      lastError = SessionCoordinatorError.unknownSlot
      return false
    }

    exercises[index].supersetGroup = nil
    persistSupersetGroup(at: index)

    let remaining = exercises.indices.filter { exercises[$0].supersetGroup == group }
    if remaining.count == 1 {
      exercises[remaining[0]].supersetGroup = nil
      persistSupersetGroup(at: remaining[0])
    }
    return true
  }

  /// Writes one movement's group to its plan row.
  ///
  /// A failure is recorded rather than thrown: the grouping is already reflected on screen, and a
  /// workout must not be interrupted because a rest-timing preference could not be saved. What is
  /// lost if it fails is the grouping surviving a force-quit, not any part of the record.
  private func persistSupersetGroup(at index: Int) {
    guard let rowID = planRowIDs[exercises[index].id] else { return }
    do {
      try store.setSessionExerciseSupersetGroup(
        rowID: rowID, group: exercises[index].supersetGroup
      )
    } catch {
      lastError = error
    }
  }

  /// Removes a movement from the workout, along with anything logged against it.
  ///
  /// The confirmation belongs to the caller. This is the one path that can discard recorded sets in
  /// bulk, and it is deliberately explicit about that rather than silently refusing when the
  /// movement turns out to have sets -- refusing would leave a lifter who added the wrong exercise,
  /// logged into it, and noticed, with no way out at all.
  @discardableResult
  public func removeExercise(_ exerciseStateID: UUID) -> Bool {
    guard let index = exercises.firstIndex(where: { $0.id == exerciseStateID }) else {
      lastError = SessionCoordinatorError.unknownSlot
      return false
    }
    do {
      if let rowID = planRowIDs[exerciseStateID] {
        try store.removeSessionExercise(rowID: rowID, from: sessionID)
        planRowIDs[exerciseStateID] = nil
      }
      exercises.remove(at: index)
      lastError = nil
      return true
    } catch {
      // Storage first again: a movement gone from the screen whose sets are still counted in the
      // week is the worst of both.
      lastError = error
      return false
    }
  }

  /// Un-logs a set: deletes the stored row and returns the slot to editable with its numbers
  /// intact.
  ///
  /// **Deletes before it forgets**, which is the mirror of `logSet` persisting before it claims. If
  /// the delete fails the slot stays logged, because a row still in the database and a check mark
  /// gone from the screen is the disagreement this codebase exists to prevent.
  ///
  /// Records already announced for the session are deliberately not retracted here. They were
  /// computed against the history that existed at the time, and re-deriving them would mean
  /// recomputing every record in the session against a changed past -- a bigger piece of work than
  /// this, and one that needs its own thought. What *is* immediately correct again is everything
  /// read from the rows: volume, tonnage, the chart, and history.
  /// Names the workout. Persists first, so a name on screen is a name in the database.
  @discardableResult
  public func rename(to newTitle: String) -> Bool {
    do {
      try store.renameSession(sessionID, to: newTitle)
      title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      lastError = nil
      return true
    } catch {
      lastError = error
      return false
    }
  }

  /// Forgets what the last rest was for. Called when rest is skipped or cancelled, so a stale
  /// label cannot outlive the timer it described.
  public func clearRestMetadata() {
    lastRestMetadata = nil
  }

  /// Writes the workout's own note, then reflects it on screen.
  ///
  /// Persists first, like `rename`: a note visible in the app is a note in the database.
  @discardableResult
  public func setSessionNotes(_ text: String) -> Bool {
    do {
      try store.setSessionNotes(text, for: sessionID)
      notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
      lastError = nil
      return true
    } catch {
      lastError = error
      return false
    }
  }

  /// Writes one movement's note, then reflects it on screen.
  ///
  /// Persists first, for the same reason `rename` does: a note visible in the app is a note in the
  /// database, never the other way round.
  ///
  /// Applied to *every* state for that exercise, not just the one whose menu was used. A movement
  /// can legitimately appear twice in one workout -- two blocks on different machines -- and a note
  /// belongs to the movement, so it must not go stale on the other block.
  @discardableResult
  public func setNotes(_ text: String, for exerciseID: ExerciseID) -> Bool {
    do {
      try store.setExerciseNotes(text, for: exerciseID)
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      for index in exercises.indices where exercises[index].exerciseID == exerciseID {
        exercises[index].notes = trimmed
      }
      lastError = nil
      return true
    } catch {
      lastError = error
      return false
    }
  }

  @discardableResult
  public func unlogSet(slotID: UUID, inExercise exerciseStateID: UUID) -> Bool {
    guard
      let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseStateID }),
      let slot = exercises[exerciseIndex].slots.first(where: { $0.id == slotID }),
      let setID = slot.loggedSetID
    else {
      lastError = SessionCoordinatorError.unknownSlot
      return false
    }

    do {
      try store.deleteSet(setID)
      exercises[exerciseIndex].markUnlogged(slotID: slotID)
      lastError = nil
      return true
    } catch {
      lastError = error
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

  // MARK: - Finishing

  /// Closes the session. Refuses to double-finish, so `finishedAt` cannot drift.
  public func finish() throws {
    let finishedAt = now()
    // The store is the authority, so it goes first: advancing the timeline before a write that
    // then failed would claim a finish that did not happen, and the session is still open.
    try store.finishSession(sessionID, at: finishedAt)
    timeline = SessionTimeline(startedAt: timeline.startedAt, finishedAt: finishedAt)
    isFinished = true
  }

  /// Sets performed so far, as the workout bar reports them.
  ///
  /// Counted in working sets rather than written rows. Summing `loggedCount` counted each drop as
  /// another set, so a lifter who dropped twice saw the bar jump from three to five -- the app
  /// contradicting its own counting convention on the most visible number in a live workout.
  public var loggedSetCount: Int {
    exercises.reduce(0) { $0 + $1.loggedWorkingSetCount }
  }
}

/// One exercise on today's plan, before the session exists.
///
/// `nonisolated` because it is a pure value type that stores build on database queues. This module
/// defaults to MainActor isolation, which silently made this initialiser MainActor-only and
/// unreachable from `SplitStore` -- the same leak the table types carry an explicit `nonisolated`
/// for. Relaxing it cannot break a MainActor caller.
/// A plan day, handed to whoever owns the session, ready to become today's workout.
///
/// Exists so the day's identity and its name travel with its movements. Both used to be dropped at
/// this hop: the session could not be attributed back to the day afterwards, and it opened nameless
/// even though the lifter had already named that day when they built the plan.
public nonisolated struct PlannedDayStart: Sendable {
  public let dayID: SplitDayID
  /// The lifter's own name for the day, used as the workout's title.
  public let name: String
  public let exercises: [PlannedExercise]

  public init(dayID: SplitDayID, name: String, exercises: [PlannedExercise]) {
    self.dayID = dayID
    self.name = name
    self.exercises = exercises
  }
}

public nonisolated struct PlannedExercise: Hashable, Sendable {
  public let exerciseID: ExerciseID
  public let machineID: MachineID?
  public let exerciseName: String
  /// How the movement is loaded, when known. Carried so a planned pull-up is still a bodyweight
  /// movement by the time it reaches the set row.
  public var modality: ExerciseModality?
  public let machineName: String?
  public let machineIncrementKg: Double?
  public let plannedSets: Int?

  public init(
    exerciseID: ExerciseID,
    machineID: MachineID? = nil,
    exerciseName: String,
    modality: ExerciseModality? = nil,
    machineName: String? = nil,
    machineIncrementKg: Double? = nil,
    plannedSets: Int? = nil
  ) {
    self.exerciseID = exerciseID
    self.machineID = machineID
    self.exerciseName = exerciseName
    self.modality = modality
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
