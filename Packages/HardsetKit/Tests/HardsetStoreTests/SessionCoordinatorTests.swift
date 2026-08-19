import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The coordinator's ordering guarantees: nothing is marked logged, and no rest starts, until
/// the write has actually succeeded.
@Suite("A live session persists before it claims to")
@MainActor
struct SessionCoordinatorTests {
  let start = Date(timeIntervalSince1970: 6_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(
    _ database: any DatabaseWriter, name: String = "Leg Press"
  ) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  /// Records what rest was asked for, so the assertion is about behaviour and not about
  /// AlarmKit — which does not exist on the host.
  private final class RestSpy {
    var requests: [(Duration, RestMetadata)] = []
  }

  // MARK: - Starting

  @Test("Starting a session opens it and builds a row per planned set")
  func startBuildsPlan() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press", plannedSets: 3)
      ],
      now: { self.start }
    )

    #expect(coordinator.exercises.count == 1)
    #expect(coordinator.exercises[0].slots.count == 3)
    // No history exists, so nothing is prefilled and nothing is loggable yet.
    let anyLoggable = coordinator.exercises[0].slots.contains { $0.draft.isLoggable }
    #expect(!anyLoggable)
    #expect(try store.openSession()?.id == coordinator.sessionID)
  }

  /// A resumed session must not suggest values from its own sets.
  @Test("The new session is excluded from its own history")
  func excludesOwnSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    // A completed prior session, so there is real history to prefill from.
    let previous = try store.startSession(at: start.addingTimeInterval(-86_400))
    _ = try store.logSet(
      sessionID: previous, exerciseID: exercise,
      draft: SetEntryDraft(weightKg: 90, reps: 10), setOrdinal: 0,
      at: start.addingTimeInterval(-86_400)
    )
    try store.finishSession(previous, at: start.addingTimeInterval(-82_800))

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    #expect(coordinator.exercises[0].slots[0].draft.weightKg == 90)
  }

  // MARK: - Logging order

  @Test("A successful write marks the row and requests rest")
  func successMarksAndRests() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(
          exerciseID: exercise, exerciseName: "Leg Press",
          machineName: "Hammer Strength", plannedSets: 2
        )
      ],
      now: { self.start },
      restAfterSet: .seconds(120),
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )

    let state = coordinator.exercises[0]
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    let didLog = coordinator.logSet(slotID: state.slots[0].id, inExercise: state.id)

    #expect(didLog)
    #expect(coordinator.exercises[0].slots[0].isLogged)
    #expect(coordinator.loggedSetCount == 1)
    #expect(coordinator.lastError == nil)
    #expect(try store.sets(in: coordinator.sessionID).count == 1)

    #expect(spy.requests.count == 1)
    #expect(spy.requests[0].0 == .seconds(120))
    #expect(spy.requests[0].1.exerciseName == "Leg Press")
    #expect(spy.requests[0].1.machineName == "Hammer Strength")
    #expect(spy.requests[0].1.setLabel == "Set 1 of 2")
  }

  /// The guarantee that matters: an incomplete row must not show a check mark, and must not
  /// start a rest timer for a set that was never saved.
  @Test("A refused write leaves the row unlogged and starts no rest")
  func failureLeavesRowAlone() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restAfterSet: .seconds(120),
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )

    let state = coordinator.exercises[0]
    // Draft is empty — there is no history and nothing was typed.
    let didLog = coordinator.logSet(slotID: state.slots[0].id, inExercise: state.id)

    #expect(!didLog)
    #expect(!coordinator.exercises[0].slots[0].isLogged)
    #expect(coordinator.loggedSetCount == 0)
    #expect(coordinator.lastError as? LoggerStoreError == .incompleteSet)
    #expect(spy.requests.isEmpty)
    #expect(try store.sets(in: coordinator.sessionID).isEmpty)
  }

  @Test("A warm-up is written but starts no rest")
  func warmupStartsNoRest() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      restAfterSet: .seconds(120),
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )
    coordinator.addSet(inExercise: coordinator.exercises[0].id, isWarmup: true)
    let warmupSlot = coordinator.exercises[0].slots.last!
    coordinator.exercises[0].slots[1].draft = SetEntryDraft(weightKg: 40, reps: 15)

    #expect(coordinator.logSet(slotID: warmupSlot.id, inExercise: coordinator.exercises[0].id))
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
    #expect(spy.requests.isEmpty)
  }

  @Test("With no rest prescription, nothing is invented")
  func noRestByDefault() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let spy = RestSpy()

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start },
      onStartRest: { duration, metadata in spy.requests.append((duration, metadata)) }
    )
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    #expect(coordinator.logSet(
      slotID: coordinator.exercises[0].slots[0].id,
      inExercise: coordinator.exercises[0].id
    ))
    #expect(spy.requests.isEmpty)
  }

  @Test("Logging the same row twice writes once")
  func doubleLogIsIdempotent() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    let slotID = coordinator.exercises[0].slots[0].id
    let stateID = coordinator.exercises[0].id

    #expect(coordinator.logSet(slotID: slotID, inExercise: stateID))
    #expect(coordinator.logSet(slotID: slotID, inExercise: stateID))
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
  }

  @Test("An unknown slot is reported rather than trapping")
  func unknownSlot() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start }
    )
    #expect(!coordinator.logSet(slotID: UUID(), inExercise: coordinator.exercises[0].id))
    #expect(coordinator.lastError as? SessionCoordinatorError == .unknownSlot)
  }

  // MARK: - Finishing

  @Test("Finishing closes the session once")
  func finishing() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Leg Press")],
      now: { self.start.addingTimeInterval(0) }
    )

    try coordinator.finish()
    #expect(coordinator.isFinished)
    #expect(try store.openSession() == nil)

    // The second attempt is refused by the same invariant the store enforces.
    #expect(throws: SessionTimelineError.alreadyFinished) {
      try coordinator.finish()
    }
  }
}
