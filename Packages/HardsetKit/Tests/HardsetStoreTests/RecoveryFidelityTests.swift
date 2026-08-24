import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// What survives a crash, and what survives "Do it again".
///
/// Both paths rebuild an `ExerciseLogState` from storage, and both were dropping fields that the
/// store already carried -- the classic defect in this codebase: the capability exists, a comment
/// claims it works, and the wiring is missing one hop.
@Suite("A recovered or repeated workout keeps what made its rows loggable")
struct RecoveryFidelityTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, HistoryStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), HistoryStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  /// A pull-up is loaded by the lifter's own body. Recovered as a loaded movement, its row asks for
  /// a weight and shows an empty field where "Body" belongs.
  @MainActor
  @Test("Crash recovery keeps a bodyweight movement bodyweight")
  func recoveryKeepsModality() throws {
    let (db, store, _) = try fixture()
    let pullUp = try exercise(db, "pull-up")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: pullUp, exerciseName: "Pull-up", modality: .bodyweight)],
      now: { self.now }
    )
    #expect(opened.exercises.first?.modality == .bodyweight)

    // The app is killed and relaunched.
    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    #expect(recovered.exercises.first?.modality == .bodyweight)
  }

  @MainActor
  @Test("Crash recovery keeps the lifter's note on the movement")
  func recoveryKeepsNotes() throws {
    let (db, store, _) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    try store.setExerciseNotes("Seat 4, pin 3", for: press)

    _ = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Chest Press")],
      now: { self.now }
    )

    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    #expect(recovered.exercises.first?.notes == "Seat 4, pin 3")
  }

  /// "Do it again" on a bodyweight day produced rows demanding a weight.
  @MainActor
  @Test("Repeating a workout keeps each movement's modality")
  func repeatKeepsModality() throws {
    let (db, store, history) = try fixture()
    let pullUp = try exercise(db, "pull-up")
    let bench = try exercise(db, "barbell-bench-press")

    let session = try store.startSession(at: now)
    for ordinal in 0..<3 {
      _ = try store.logSet(
        sessionID: session, exerciseID: pullUp,
        draft: SetEntryDraft(weightKg: 0, reps: 8), setOrdinal: ordinal,
        at: now.addingTimeInterval(Double(ordinal) * 120)
      )
    }
    _ = try store.logSet(
      sessionID: session, exerciseID: bench,
      draft: SetEntryDraft(weightKg: 84, reps: 8), setOrdinal: 0,
      at: now.addingTimeInterval(600)
    )
    try store.finishSession(session, at: now.addingTimeInterval(3600))

    let plan = try history.plan(for: session)
    #expect(plan.count == 2)
    let repeated = try #require(plan.first { $0.exerciseID == pullUp })
    #expect(repeated.modality == .bodyweight)
    #expect(repeated.workingSets == 3)
    // And the loaded movement is not mislabelled the other way.
    #expect(plan.first { $0.exerciseID == bench }?.modality == .barbell)
  }

  /// A bodyweight set at zero added load is a real set. If modality is lost it reads as no load.
  @MainActor
  @Test("A recovered bodyweight set is still a logged set, not an empty row")
  func recoveredBodyweightSetSurvives() throws {
    let (db, store, _) = try fixture()
    let pullUp = try exercise(db, "pull-up")

    let opened = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: pullUp, exerciseName: "Pull-up", modality: .bodyweight)],
      now: { self.now }
    )
    let slot = try #require(opened.exercises.first?.slots.first)
    opened.exercises[0].slots[0].draft = SetEntryDraft(weightKg: 0, reps: 10)
    #expect(opened.logSet(slotID: slot.id, inExercise: opened.exercises[0].id))

    let recovered = try #require(try SessionCoordinator.resume(store: store, now: { self.now }))
    let state = try #require(recovered.exercises.first)
    #expect(state.modality == .bodyweight)
    #expect(state.loggedCount == 1)
    #expect(state.slots.first?.draft.weightKg == 0)
  }
}
