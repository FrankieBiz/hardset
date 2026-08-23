import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Correcting a logged set. The app is otherwise append-only, and this is the one exception.
///
/// It exists because the alternative is worse: with no way back, a mistyped 500 kg is a permanent
/// personal record, a permanent spike in the progression chart and a permanently wrong week -- in
/// an app whose entire claim is that its numbers can be trusted.
@Suite("A logged set can be taken back")
struct UnlogSetTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  @MainActor
  @Test("Un-logging deletes the row and frees the slot, keeping the numbers")
  func unlogDeletesAndFreesTheSlot() throws {
    let (db, store) = try fixture()
    let squat = try exercise(db, "barbell-back-squat")
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: squat, exerciseName: "Squat", plannedSets: 1)]
    )
    let slot = try #require(coordinator.exercises.first?.slots.first)
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 500, reps: 5)

    #expect(coordinator.logSet(slotID: slot.id, inExercise: coordinator.exercises[0].id))
    #expect(coordinator.exercises[0].slots[0].isLogged)
    #expect(try store.sets(in: coordinator.sessionID).count == 1)

    #expect(coordinator.unlogSet(slotID: slot.id, inExercise: coordinator.exercises[0].id))

    // Gone from storage, so volume, the chart and history stop counting it.
    #expect(try store.sets(in: coordinator.sessionID).isEmpty)
    // Editable again, and the mistyped number is still there to be corrected rather than retyped.
    #expect(!coordinator.exercises[0].slots[0].isLogged)
    #expect(coordinator.exercises[0].slots[0].draft.weightKg == 500)
    #expect(coordinator.exercises[0].slots[0].draft.reps == 5)
  }

  @MainActor
  @Test("Correcting a typo and re-logging leaves exactly one set")
  func correctThenRelogLeavesOneRow() throws {
    let (db, store) = try fixture()
    let squat = try exercise(db, "barbell-back-squat")
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: squat, exerciseName: "Squat", plannedSets: 1)]
    )
    let exerciseStateID = coordinator.exercises[0].id
    let slotID = coordinator.exercises[0].slots[0].id

    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 500, reps: 5)
    _ = coordinator.logSet(slotID: slotID, inExercise: exerciseStateID)
    _ = coordinator.unlogSet(slotID: slotID, inExercise: exerciseStateID)
    coordinator.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 50, reps: 5)
    _ = coordinator.logSet(slotID: slotID, inExercise: exerciseStateID)

    let sets = try store.sets(in: coordinator.sessionID)
    #expect(sets.count == 1)
    #expect(sets.first?.weightKg == 50)
  }

  @MainActor
  @Test("Un-logging a slot that was never logged is refused, not silently accepted")
  func unlogUnloggedSlotFails() throws {
    let (db, store) = try fixture()
    let squat = try exercise(db, "barbell-back-squat")
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: squat, exerciseName: "Squat", plannedSets: 1)]
    )
    let slotID = coordinator.exercises[0].slots[0].id
    #expect(!coordinator.unlogSet(slotID: slotID, inExercise: coordinator.exercises[0].id))
  }

  @MainActor
  @Test("Deleting one set leaves its siblings alone")
  func deletingOneSetKeepsTheOthers() throws {
    let (db, store) = try fixture()
    let squat = try exercise(db, "barbell-back-squat")
    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: squat, exerciseName: "Squat", plannedSets: 2)]
    )
    let exerciseStateID = coordinator.exercises[0].id
    for index in 0..<2 {
      coordinator.exercises[0].slots[index].draft = SetEntryDraft(weightKg: 100, reps: 5)
      _ = coordinator.logSet(
        slotID: coordinator.exercises[0].slots[index].id, inExercise: exerciseStateID
      )
    }
    #expect(try store.sets(in: coordinator.sessionID).count == 2)

    _ = coordinator.unlogSet(
      slotID: coordinator.exercises[0].slots[0].id, inExercise: exerciseStateID
    )
    #expect(try store.sets(in: coordinator.sessionID).count == 1)
    #expect(coordinator.exercises[0].slots[1].isLogged)
  }
}

/// Removing things: an empty row, a movement added by mistake, a junk workout.
@Suite("Mistakes can be removed at every level")
struct RemovalTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  @MainActor
  private func coordinator(
    _ db: any DatabaseWriter, _ store: LoggerStore, slug: String, sets: Int = 1
  ) throws -> SessionCoordinator {
    let id = try exercise(db, slug)
    return try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: id, exerciseName: slug, plannedSets: sets)]
    )
  }

  @MainActor
  @Test("An empty set row can be removed; a logged one cannot")
  func removeSlotRefusesLoggedSets() throws {
    let (db, store) = try fixture()
    let c = try coordinator(db, store, slug: "barbell-back-squat", sets: 2)
    let exerciseStateID = c.exercises[0].id

    #expect(c.removeSlot(slotID: c.exercises[0].slots[1].id, inExercise: exerciseStateID))
    #expect(c.exercises[0].slots.count == 1)

    c.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 5)
    _ = c.logSet(slotID: c.exercises[0].slots[0].id, inExercise: exerciseStateID)

    // Conflating "remove this row" with "delete this set" would let a mis-tap discard a record.
    #expect(!c.removeSlot(slotID: c.exercises[0].slots[0].id, inExercise: exerciseStateID))
    #expect(c.exercises[0].slots.count == 1)
  }

  @MainActor
  @Test("A movement added by mistake can be removed, with its sets")
  func removeExerciseTakesItsSets() throws {
    let (db, store) = try fixture()
    let c = try coordinator(db, store, slug: "barbell-back-squat")
    let exerciseStateID = c.exercises[0].id
    c.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 5)
    _ = c.logSet(slotID: c.exercises[0].slots[0].id, inExercise: exerciseStateID)
    #expect(try store.sets(in: c.sessionID).count == 1)

    #expect(c.removeExercise(exerciseStateID))
    #expect(c.exercises.isEmpty)
    // The sets must go too, or the week keeps counting a movement the lifter says did not happen.
    #expect(try store.sets(in: c.sessionID).isEmpty)
  }

  @MainActor
  @Test("Removing one movement leaves the others and their sets alone")
  func removeExerciseIsScoped() throws {
    let (db, store) = try fixture()
    let squat = try exercise(db, "barbell-back-squat")
    let bench = try exercise(db, "barbell-bench-press")
    let c = try SessionCoordinator.start(
      store: store,
      plan: [
        PlannedExercise(exerciseID: squat, exerciseName: "Squat", plannedSets: 1),
        PlannedExercise(exerciseID: bench, exerciseName: "Bench", plannedSets: 1),
      ]
    )
    for index in 0..<2 {
      c.exercises[index].slots[0].draft = SetEntryDraft(weightKg: 80, reps: 5)
      _ = c.logSet(slotID: c.exercises[index].slots[0].id, inExercise: c.exercises[index].id)
    }
    #expect(try store.sets(in: c.sessionID).count == 2)

    #expect(c.removeExercise(c.exercises[0].id))
    #expect(c.exercises.count == 1)
    #expect(try store.sets(in: c.sessionID).count == 1)
  }

  @MainActor
  @Test("Deleting a workout cascades to its sets and plan rows")
  func deleteSessionCascades() throws {
    let (db, store) = try fixture()
    let c = try coordinator(db, store, slug: "barbell-back-squat")
    c.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 100, reps: 5)
    _ = c.logSet(slotID: c.exercises[0].slots[0].id, inExercise: c.exercises[0].id)
    try c.finish()

    try store.deleteSession(c.sessionID)

    // Relies on foreign keys being on. Without them the sets would survive as orphans and keep
    // counting toward the week, which is why this asserts the children and not just the parent.
    #expect(try store.sets(in: c.sessionID).isEmpty)
    #expect(try store.sessionExercises(in: c.sessionID).isEmpty)
    #expect(try store.openSession() == nil)
  }
}
