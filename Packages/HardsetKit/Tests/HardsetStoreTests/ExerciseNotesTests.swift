import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Per-movement notes. `exercises.notes` shipped in the first migration with no reader and no
/// writer: the column existed, every row held "", and no screen could show or set one.
@Suite("A movement carries the lifter's own note")
struct ExerciseNotesTests {
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

  @Test("A note written on a movement reads back")
  func noteRoundTrips() throws {
    let (db, store) = try fixture()
    let press = try exercise(db, "chest-press-machine")

    #expect(try store.exerciseNotes(for: [press]).isEmpty)
    try store.setExerciseNotes("Seat 4, pin 3", for: press)
    #expect(try store.exerciseNotes(for: [press])[press] == "Seat 4, pin 3")
  }

  /// Clearing the field is the delete gesture, so blank has to mean gone rather than "a note that
  /// is blank" -- otherwise the menu keeps offering "Edit note" for nothing.
  @Test("Clearing a note removes it rather than storing an empty one")
  func clearingRemovesTheNote() throws {
    let (db, store) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    try store.setExerciseNotes("Seat 4", for: press)

    try store.setExerciseNotes("", for: press)
    #expect(try store.exerciseNotes(for: [press]).isEmpty)

    // Whitespace is the same as empty, or a stray space would resurrect a note nobody can see.
    try store.setExerciseNotes("Seat 4", for: press)
    try store.setExerciseNotes("   \n ", for: press)
    #expect(try store.exerciseNotes(for: [press]).isEmpty)
  }

  @Test("Notes are trimmed, and only the movements that have one come back")
  func trimmedAndSparse() throws {
    let (db, store) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let bench = try exercise(db, "barbell-bench-press")
    try store.setExerciseNotes("  Wide grip  ", for: press)

    let notes = try store.exerciseNotes(for: [press, bench])
    #expect(notes[press] == "Wide grip")
    #expect(notes[bench] == nil)
    #expect(notes.count == 1)
  }

  /// A note belongs to the movement, so both blocks of it in one workout must show the same text.
  @MainActor
  @Test("Setting a note updates every block of that movement in the open session")
  func noteAppliesToEveryBlockOfTheMovement() throws {
    let (db, store) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let gyms = GymStore(database: db)
    let gym = try gyms.createGym(name: "Iron Works")
    let first = try gyms.createMachine(at: gym, name: "Hammer Strength")
    let second = try gyms.createMachine(at: gym, name: "Cybex")

    let coordinator = try SessionCoordinator.start(
      store: store,
      gymID: gym,
      plan: [
        PlannedExercise(exerciseID: press, machineID: first, exerciseName: "Chest Press"),
        PlannedExercise(exerciseID: press, machineID: second, exerciseName: "Chest Press"),
      ],
      now: { self.now }
    )
    #expect(coordinator.exercises.count == 2)

    #expect(coordinator.setNotes("Seat 4", for: press))
    #expect(coordinator.exercises.allSatisfy { $0.notes == "Seat 4" })
    // And it is in the database, not only on screen.
    #expect(try store.exerciseNotes(for: [press])[press] == "Seat 4")
  }

  /// The note has to be there when the movement is opened, not only after it is edited.
  @MainActor
  @Test("An existing note is loaded when a session starts and when a movement is added")
  func existingNoteIsLoaded() throws {
    let (db, store) = try fixture()
    let press = try exercise(db, "chest-press-machine")
    let bench = try exercise(db, "barbell-bench-press")
    try store.setExerciseNotes("Seat 4", for: press)
    try store.setExerciseNotes("Bar 2 is bent", for: bench)

    let coordinator = try SessionCoordinator.start(
      store: store,
      plan: [PlannedExercise(exerciseID: press, exerciseName: "Chest Press")],
      now: { self.now }
    )
    #expect(coordinator.exercises.first?.notes == "Seat 4")

    #expect(coordinator.addExercise(exerciseID: bench, exerciseName: "Bench Press"))
    #expect(coordinator.exercises.last?.notes == "Bar 2 is bent")
  }
}
