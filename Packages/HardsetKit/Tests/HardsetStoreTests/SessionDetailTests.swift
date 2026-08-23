import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// Reading one workout back. History listed sessions and could not open them, because nothing
/// could answer "what was in this one".
@Suite("A past workout can be read back set by set")
struct SessionDetailTests {
  let now = Date(timeIntervalSince1970: 12_000_000)

  private func migrated() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  @MainActor
  @Test("Sets come back in logging order, with the movement and machine named")
  func setsReadBack() throws {
    let database = try migrated()
    try CatalogSeeder(database: database).seed(now: now)
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let gyms = GymStore(database: database)

    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Hammer Strength")
    let exercise = try #require(
      try database.read { db in try Exercise.where { $0.catalogSlug.eq("chest-press-machine") }.fetchOne(db) }
    )
    let exerciseID = ExerciseID(rawValue: exercise.id)

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exerciseID, machineID: machine,
      draft: SetEntryDraft(weightKg: 40, reps: 10), isWarmup: true, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: exerciseID, machineID: machine,
      draft: SetEntryDraft(weightKg: 70, reps: 8), isWarmup: false,
      at: now.addingTimeInterval(120)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    let sets = try history.sets(in: session)
    #expect(sets.count == 2)
    #expect(sets.map(\.weightKg) == [40, 70])
    #expect(sets.first?.isWarmup == true)
    #expect(sets.last?.isWarmup == false)
    // Named, because a load is only meaningful next to the equipment it was lifted on.
    #expect(sets.allSatisfy { $0.exerciseName == "Chest Press" })
    #expect(sets.allSatisfy { $0.machineName == "Hammer Strength" })
  }

  @MainActor
  @Test("A session with no sets reads back empty rather than failing")
  func emptySession() throws {
    let database = try migrated()
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let session = try logger.startSession(at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(60))
    #expect(try history.sets(in: session).isEmpty)
  }

  @MainActor
  @Test("Free-weight sets carry no machine name rather than an invented one")
  func freeWeightHasNoMachine() throws {
    let database = try migrated()
    try CatalogSeeder(database: database).seed(now: now)
    let logger = LoggerStore(database: database)
    let history = HistoryStore(database: database)
    let exercise = try #require(
      try database.read { db in
        try Exercise.where { $0.catalogSlug.eq("barbell-back-squat") }.fetchOne(db)
      }
    )
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: ExerciseID(rawValue: exercise.id), machineID: nil,
      draft: SetEntryDraft(weightKg: 100, reps: 5), isWarmup: false, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(300))

    let sets = try history.sets(in: session)
    #expect(sets.count == 1)
    #expect(sets.first?.machineName == nil)
  }
}
