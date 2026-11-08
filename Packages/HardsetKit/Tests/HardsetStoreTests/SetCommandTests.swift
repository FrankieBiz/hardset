import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Stable set command identity")
struct SetCommandTests {
  @Test("Lost acknowledgements do not duplicate a set, including after finish")
  func replay() throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute(db)
    }
    let store = LoggerStore(database: database)
    let start = Date(timeIntervalSince1970: 1000)
    let session = try store.startSession(at: start)
    let command = SetID()
    let draft = SetEntryDraft(weightKg: 80, reps: 8)
    let first = try store.logSet(sessionID: session, exerciseID: exercise, commandID: command,
      draft: draft, at: start)
    try store.finishSession(session, at: start.addingTimeInterval(60))
    let replay = try store.logSet(sessionID: session, exerciseID: exercise, commandID: command,
      draft: draft, at: start.addingTimeInterval(120))
    #expect(first == replay)
    let sets = try store.sets(in: session)
    #expect(sets.count == 1)
    #expect(sets.first?.completedAt == start)
    #expect(throws: SetCommandError.identityConflict) {
      try store.logSet(sessionID: session, exerciseID: exercise, commandID: command,
        draft: SetEntryDraft(weightKg: 90, reps: 8), at: start)
    }
    #expect(try store.sets(in: session).first?.weightKg == 80)
  }

  @Test("A failed transaction can retry the same identity")
  func rollback() throws {
    let database = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(database)
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute(db)
      try db.execute(sql: "CREATE TRIGGER refuseSet BEFORE INSERT ON loggedSets BEGIN SELECT RAISE(ABORT, 'full'); END")
    }
    let store = LoggerStore(database: database)
    let session = try store.startSession(at: .distantPast)
    let command = SetID()
    #expect(throws: (any Error).self) {
      try store.logSet(sessionID: session, exerciseID: exercise, commandID: command,
        draft: .init(weightKg: 20, reps: 10), at: .now)
    }
    #expect(try store.sets(in: session).isEmpty)
    try database.write { db in try db.execute(sql: "DROP TRIGGER refuseSet") }
    #expect(try store.logSet(sessionID: session, exerciseID: exercise, commandID: command,
      draft: .init(weightKg: 20, reps: 10), at: .now) == command)
    #expect(try store.sets(in: session).count == 1)
  }
}
