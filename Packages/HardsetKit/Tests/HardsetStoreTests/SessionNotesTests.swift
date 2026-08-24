import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// `sessions.notes` shipped in the first migration, was written once per workout as the empty
/// string by `startSession`, and read nowhere. Last of the dead columns.
@Suite("A workout carries its own note")
struct SessionNotesTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func fixture() throws -> (any DatabaseWriter, LoggerStore, HistoryStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    try CatalogSeeder(database: queue).seed(now: now)
    return (queue, LoggerStore(database: queue), HistoryStore(database: queue))
  }

  @Test("A note written on a workout reads back")
  func noteRoundTrips() throws {
    let (_, logger, history) = try fixture()
    let session = try logger.startSession(at: now)

    #expect(try history.notes(for: session).isEmpty)
    try logger.setSessionNotes("Slept four hours, everything felt heavy", for: session)
    #expect(try history.notes(for: session) == "Slept four hours, everything felt heavy")
  }

  @Test("Clearing a note removes it rather than storing whitespace")
  func clearingRemovesTheNote() throws {
    let (_, logger, history) = try fixture()
    let session = try logger.startSession(at: now)
    try logger.setSessionNotes("First session back", for: session)

    try logger.setSessionNotes("   \n  ", for: session)
    #expect(try history.notes(for: session).isEmpty)
  }

  @Test("A note is trimmed")
  func noteIsTrimmed() throws {
    let (_, logger, history) = try fixture()
    let session = try logger.startSession(at: now)
    try logger.setSessionNotes("  Felt strong  ", for: session)
    #expect(try history.notes(for: session) == "Felt strong")
  }

  @Test("A note on a session that does not exist reads as empty rather than throwing")
  func missingSessionReadsEmpty() throws {
    let (_, _, history) = try fixture()
    #expect(try history.notes(for: SessionID()).isEmpty)
  }

  /// The note belongs to the workout, so it has to survive the app being killed mid-session --
  /// the same failure that dropped modality, exercise notes and RPE.
  @MainActor
  @Test("A workout's note survives crash recovery")
  func noteSurvivesRecovery() throws {
    let (db, logger, _) = try fixture()
    let bench = try db.read { d in
      try Exercise.where { $0.catalogSlug.eq("barbell-bench-press") }.fetchOne(d)
    }
    let exercise = ExerciseID(rawValue: try #require(bench).id)

    let coordinator = try SessionCoordinator.start(
      store: logger,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Bench")],
      now: { self.now }
    )
    #expect(coordinator.setSessionNotes("Slept four hours"))
    #expect(coordinator.notes == "Slept four hours")

    let recovered = try #require(try SessionCoordinator.resume(store: logger, now: { self.now }))
    #expect(recovered.notes == "Slept four hours")
  }

  /// The session note and a movement note are different facts about different things.
  @MainActor
  @Test("A workout note and a movement note do not overwrite each other")
  func sessionAndExerciseNotesAreIndependent() throws {
    let (db, logger, history) = try fixture()
    let press = try db.read { d in
      try Exercise.where { $0.catalogSlug.eq("chest-press-machine") }.fetchOne(d)
    }
    let exercise = ExerciseID(rawValue: try #require(press).id)

    let coordinator = try SessionCoordinator.start(
      store: logger,
      plan: [PlannedExercise(exerciseID: exercise, exerciseName: "Chest Press")],
      now: { self.now }
    )
    #expect(coordinator.setSessionNotes("Felt awful"))
    #expect(coordinator.setNotes("Seat 4, pin 3", for: exercise))

    #expect(coordinator.notes == "Felt awful")
    #expect(coordinator.exercises.first?.notes == "Seat 4, pin 3")
    #expect(try history.notes(for: coordinator.sessionID) == "Felt awful")
    #expect(try logger.exerciseNotes(for: [exercise])[exercise] == "Seat 4, pin 3")
  }
}
