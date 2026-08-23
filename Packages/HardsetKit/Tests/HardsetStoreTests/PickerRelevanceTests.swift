import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Relevance in the exercise picker: the user's own recent movements, and what the gym they are
/// standing in has equipment for.
///
/// Carried over from the ancestor app's smart sort, whose research concluded the defensible version
/// ranks by the equipment a gym actually has -- and that doing so needs a machine-to-exercise join
/// it never had. This app had the table from its first migration and had never written a row to it.
///
/// Neither signal is a recommendation. One is history and one is inventory; the app still declines
/// to say what anyone should train.
@Suite("The picker can rank by history and by what the gym has")
struct PickerRelevanceTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, GymStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), GymStore(database: queue))
  }

  private func exercise(_ db: any DatabaseWriter, _ slug: String) throws -> ExerciseID {
    let row = try db.read { d in try Exercise.where { $0.catalogSlug.eq(slug) }.fetchOne(d) }
    return ExerciseID(rawValue: try #require(row).id)
  }

  @MainActor
  @Test("Naming a machine for a movement records what it is for")
  func creationPopulatesTheJoin() throws {
    let (db, _, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let legPress = try exercise(db, "leg-press")

    _ = try gyms.createMachine(at: gym, name: "Hammer Strength", forExercise: legPress)

    // Known before a single set has been logged, which is the whole point: on a first visit the
    // app can still say what the building has.
    #expect(try gyms.exercisesWithEquipment(at: gym) == [legPress])
  }

  @MainActor
  @Test("A machine named with no movement records nothing rather than guessing")
  func creationWithoutExerciseRecordsNothing() throws {
    let (_, _, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Hotel gym")
    _ = try gyms.createMachine(at: gym, name: "Some machine")
    #expect(try gyms.exercisesWithEquipment(at: gym).isEmpty)
  }

  @MainActor
  @Test("Logging on a machine also counts as the gym having equipment for it")
  func loggedSetsCountAsEquipment() throws {
    let (db, logger, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Cybex")
    let squat = try exercise(db, "hack-squat")

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: squat, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now
    )

    #expect(try gyms.exercisesWithEquipment(at: gym).contains(squat))
  }

  @MainActor
  @Test("Equipment is per gym, so another gym's machines do not leak in")
  func equipmentDoesNotLeakBetweenGyms() throws {
    let (db, _, gyms) = try fixture()
    let mine = try gyms.createGym(name: "Iron Works")
    let theirs = try gyms.createGym(name: "Hotel gym")
    let legPress = try exercise(db, "leg-press")
    _ = try gyms.createMachine(at: mine, name: "Hammer", forExercise: legPress)

    #expect(try gyms.exercisesWithEquipment(at: mine) == [legPress])
    // The distinction the whole per-machine feature exists to draw.
    #expect(try gyms.exercisesWithEquipment(at: theirs).isEmpty)
  }

  @MainActor
  @Test("Recent movements come back newest first, without repeats")
  func recentIsRecencyOrderedAndDeduplicated() throws {
    let (db, logger, gyms) = try fixture()
    let bench = try exercise(db, "barbell-bench-press")
    let squat = try exercise(db, "barbell-back-squat")

    let session = try logger.startSession(at: now)
    // Bench first, then squat, then bench again. Bench is the most recent and must appear once.
    for (index, id) in [bench, squat, bench].enumerated() {
      _ = try logger.logSet(
        sessionID: session, exerciseID: id,
        draft: SetEntryDraft(weightKg: 60, reps: 5),
        at: now.addingTimeInterval(Double(index) * 60)
      )
    }

    #expect(try gyms.recentlyLoggedExercises() == [bench, squat])
  }

  @MainActor
  @Test("Recent honours its limit")
  func recentRespectsLimit() throws {
    let (db, logger, gyms) = try fixture()
    let slugs = ["barbell-bench-press", "barbell-back-squat", "leg-press", "hack-squat"]
    let session = try logger.startSession(at: now)
    for (index, slug) in slugs.enumerated() {
      _ = try logger.logSet(
        sessionID: session, exerciseID: try exercise(db, slug),
        draft: SetEntryDraft(weightKg: 50, reps: 5),
        at: now.addingTimeInterval(Double(index) * 60)
      )
    }
    #expect(try gyms.recentlyLoggedExercises(limit: 2).count == 2)
  }

  @MainActor
  @Test("An archived machine stops counting as equipment the gym has")
  func archivedMachinesDropOut() throws {
    let (db, _, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let legPress = try exercise(db, "leg-press")
    let machine = try gyms.createMachine(at: gym, name: "Hammer", forExercise: legPress)
    #expect(try gyms.exercisesWithEquipment(at: gym) == [legPress])

    try gyms.archiveMachine(machine)
    // Equipment that is gone must not keep recommending itself.
    #expect(try gyms.exercisesWithEquipment(at: gym).isEmpty)
  }
}

/// Repairing a name. Machines are named at the rack in a hurry, so typos are likely -- and the
/// repair has to be a rename rather than archive-and-recreate, because load history is keyed to the
/// machine id and recreating would split one piece of equipment into two series.
@Suite("Gyms and machines can be renamed and retired")
struct GymEditingTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, GymStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), GymStore(database: queue))
  }

  @MainActor
  @Test("Renaming a machine keeps its identity, so history survives")
  func renameKeepsHistory() throws {
    let (db, logger, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Hamer Strenth")
    let exercise = try #require(
      try db.read { d in try Exercise.where { $0.catalogSlug.eq("leg-press") }.fetchOne(d) }
    )
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: exercise.id), machineID: machine,
      draft: SetEntryDraft(weightKg: 120, reps: 8), at: now
    )

    try gyms.renameMachine(machine, to: "Hammer Strength")

    let renamed = try #require(try gyms.machines(at: gym).first { $0.id == machine })
    #expect(renamed.name == "Hammer Strength")
    // Same id, so the set still points at it and the chart keeps its point.
    #expect(try logger.sets(in: session).first?.machineID == machine)
  }

  @MainActor
  @Test("An empty or whitespace name is refused rather than blanking the label")
  func renameRefusesEmpty() throws {
    let (_, _, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    try gyms.renameGym(gym, to: "   ")
    #expect(try gyms.gyms().first { $0.id == gym }?.name == "Iron Works")
  }

  @MainActor
  @Test("A renamed name is trimmed, so a stray space does not become part of it")
  func renameTrims() throws {
    let (_, _, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    try gyms.renameGym(gym, to: "  Southside  ")
    #expect(try gyms.gyms().first { $0.id == gym }?.name == "Southside")
  }

  @MainActor
  @Test("Archiving retires equipment without erasing what was logged on it")
  func archiveKeepsSets() throws {
    let (db, logger, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Cybex")
    let exercise = try #require(
      try db.read { d in try Exercise.where { $0.catalogSlug.eq("leg-press") }.fetchOne(d) }
    )
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: exercise.id), machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 10), at: now
    )

    try gyms.archiveMachine(machine)

    // Out of the picker, but the training that happened on it still happened.
    #expect(try gyms.machines(at: gym).isEmpty)
    #expect(try logger.sets(in: session).count == 1)
  }
}
