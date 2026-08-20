import Foundation
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
  public init(
    store: LoggerStore,
    sessionID: SessionID,
    exercises: [ExerciseLogState],
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) {
    self.store = store
    self.sessionID = sessionID
    self.exercises = exercises
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
    plan: [PlannedExercise],
    now: @escaping () -> Date = { Date() },
    restAfterSet: Duration? = nil,
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
    for (position, planned) in plan.enumerated() {
      try store.addExercise(
        to: sessionID,
        exerciseID: planned.exerciseID,
        machineID: planned.machineID,
        position: position,
        plannedSets: planned.plannedSets
      )
      states.append(
        ExerciseLogState.build(
          exerciseID: planned.exerciseID,
          machineID: planned.machineID,
          exerciseName: planned.exerciseName,
          machineName: planned.machineName,
          machineIncrementKg: planned.machineIncrementKg,
          snapshot: snapshot,
          plannedSets: planned.plannedSets
        )
      )
    }

    return SessionCoordinator(
      store: store,
      sessionID: sessionID,
      exercises: states,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
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

    let byKey = Dictionary(grouping: written) { $0.progressionKey }
    let states = planned.map { entry -> ExerciseLogState in
      let logged = (byKey[entry.progressionKey] ?? [])
        .sorted { $0.setOrdinal < $1.setOrdinal }
        .map {
          ExerciseLogState.LoggedSetSummary(
            setID: $0.id, weightKg: $0.weightKg, reps: $0.reps, isWarmup: $0.isWarmup
          )
        }
      return ExerciseLogState.resume(
        exerciseID: entry.exerciseID,
        machineID: entry.machineID,
        exerciseName: entry.exerciseName,
        machineName: entry.machineName,
        loggedSets: logged,
        snapshot: snapshot,
        plannedSets: entry.plannedSets
      )
    }

    return SessionCoordinator(
      store: store,
      sessionID: session.id,
      exercises: states,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: onStartRest
    )
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
      try store.addExercise(
        to: sessionID,
        exerciseID: exerciseID,
        machineID: machineID,
        position: exercises.count,
        plannedSets: plannedSets
      )
      let snapshot = try store.priorPerformanceSnapshot(
        for: [key], excluding: sessionID, asOf: now()
      )
      exercises.append(
        ExerciseLogState.build(
          exerciseID: exerciseID,
          machineID: machineID,
          exerciseName: exerciseName,
          machineName: machineName,
          machineIncrementKg: machineIncrementKg,
          snapshot: snapshot,
          plannedSets: plannedSets
        )
      )
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
        draft: slot.draft,
        // Storage ordinal counts every row including warm-ups, so the performed order is
        // recoverable exactly as it happened.
        setOrdinal: slotIndex,
        isWarmup: slot.isWarmup,
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
      } else {
        lastRecords = []
      }

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
      exercises[index].changeMachine(
        to: machineID, machineName: machineName, prior: prior, priorNote: note
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
    try store.finishSession(sessionID, at: now())
    isFinished = true
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
}
