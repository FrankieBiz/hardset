import Foundation
import GRDB
import SQLiteData
import Testing

@testable import HardsetStore

/// Saved workouts add two synced tables and three nullable columns. Nothing already stored may
/// change shape or value, and a plan must never be able to delete or rewrite a session.
@Suite("Saved workouts have their own tables and leave history alone")
struct SavedWorkoutSchemaTests {
  private func migratedDatabase() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(_ database: DatabaseQueue) throws -> UUID {
    let id = UUID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id, name: "Chest Press") }.execute(db)
    }
    return id
  }

  private func seedTemplate(
    _ database: DatabaseQueue, exercise: UUID, machine: UUID? = nil, rows: Int = 2
  ) throws -> UUID {
    let template = UUID()
    try database.write { db in
      try StoredTemplate.insert { StoredTemplate.Draft(id: template, name: "Upper A") }.execute(db)
      for position in 0..<rows {
        try StoredTemplateExercise.insert {
          StoredTemplateExercise.Draft(
            id: UUID(), templateID: template, exerciseID: exercise, machineID: machine,
            position: position, plannedSets: 3, repRangeLower: 8, repRangeUpper: 12,
            restSeconds: 90
          )
        }
        .execute(db)
      }
    }
    return template
  }

  @Test("The last migration is the saved workouts one")
  func migratesToV11() {
    #expect(HardsetMigrations.migrator().migrations.last == "v11_savedWorkouts")
  }

  @Test("Both new tables are synchronized, the parent before its children")
  func newTablesAreSynced() throws {
    let names = HardsetMigrations.syncedTableNames
    let parent = try #require(names.firstIndex(of: "workoutTemplates"))
    let child = try #require(names.firstIndex(of: "templateExercises"))
    #expect(parent < child)
  }

  /// SQLiteData's own ON DELETE check skips a table with more than one foreign key, and this one
  /// has three, so the audit in the migration's comment is asserted here instead of trusted.
  @Test("Every foreign key of a template's movements cascades or clears, and points at a synced table")
  func templateExerciseForeignKeysAreAudited() throws {
    let database = try migratedDatabase()
    let keys = try database.read { db in
      try Row.fetchAll(
        db, sql: "SELECT \"table\", \"from\", \"on_delete\" FROM pragma_foreign_key_list('templateExercises')"
      )
      .map { ($0["from"] as String, $0["table"] as String, $0["on_delete"] as String) }
    }
    let actions = Dictionary(uniqueKeysWithValues: keys.map { ($0.0, $0.2) })
    #expect(actions == ["templateID": "CASCADE", "exerciseID": "CASCADE", "machineID": "SET NULL"])
    for (_, target, _) in keys {
      #expect(HardsetMigrations.syncedTableNames.contains(target), "\(target) is not synced")
    }
  }

  @Test("Deleting a template deletes its movements and nothing else")
  func templateExercisesCascadeWithTemplate() throws {
    let database = try migratedDatabase()
    let exercise = try seedExercise(database)
    let template = try seedTemplate(database, exercise: exercise)
    let other = try seedTemplate(database, exercise: exercise, rows: 1)

    try database.write { db in
      try StoredTemplate.where { $0.id.eq(template) }.delete().execute(db)
    }

    let (deleted, kept, exercises) = try database.read { db in
      (
        try StoredTemplateExercise.where { $0.templateID.eq(template) }.fetchCount(db),
        try StoredTemplateExercise.where { $0.templateID.eq(other) }.fetchCount(db),
        try Exercise.where { $0.id.eq(exercise) }.fetchCount(db)
      )
    }
    #expect(deleted == 0)
    #expect(kept == 1)
    #expect(exercises == 1)
  }

  @Test("Deleting a machine leaves the planned movement and clears its machine")
  func deletingMachineNullsTemplateMachine() throws {
    let database = try migratedDatabase()
    let exercise = try seedExercise(database)
    let gym = UUID()
    let machine = UUID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: gym, name: "Gym") }.execute(db)
      try Machine.insert { Machine.Draft(id: machine, gymID: gym, name: "Hammer") }.execute(db)
    }
    let template = try seedTemplate(database, exercise: exercise, machine: machine, rows: 1)

    try database.write { db in
      try Machine.where { $0.id.eq(machine) }.delete().execute(db)
    }

    let rows = try database.read { db in
      try StoredTemplateExercise.where { $0.templateID.eq(template) }.fetchAll(db)
    }
    #expect(rows.count == 1)
    #expect(rows.first?.machineID == nil)
    #expect(rows.first?.repRangeLower == 8)
  }

  @Test("A session started without a plan has no template and no rep range")
  func sessionTemplateIDDefaultsToNull() throws {
    let database = try migratedDatabase()
    let exercise = try seedExercise(database)
    let session = UUID()
    try database.write { db in
      try Session.insert { Session.Draft(id: session, title: "Free workout") }.execute(db)
      try SessionExercise.insert {
        SessionExercise.Draft(id: UUID(), sessionID: session, exerciseID: exercise)
      }
      .execute(db)
    }

    let (stored, planned) = try database.read { db in
      (
        try Session.where { $0.id.eq(session) }.fetchOne(db),
        try SessionExercise.where { $0.sessionID.eq(session) }.fetchOne(db)
      )
    }
    #expect(try #require(stored).templateID == nil)
    #expect(try #require(planned).repRangeLower == nil)
    #expect(try #require(planned).repRangeUpper == nil)
  }

  /// A session names its template with plain text and no foreign key, so a template can be
  /// archived or removed without touching, nulling or cascading into history.
  @Test("A session's template is plain text, not a foreign key")
  func sessionTemplateIDIsNotAForeignKey() throws {
    let database = try migratedDatabase()
    let (columns, indexes) = try database.read { db in
      (
        try String.fetchAll(db, sql: "SELECT \"from\" FROM pragma_foreign_key_list('sessions')"),
        try String.fetchAll(
          db, sql: "SELECT name FROM pragma_index_list('sessions') WHERE name LIKE 'sessions_on_%'")
      )
    }
    #expect(columns == ["gymID"])
    #expect(indexes.contains("sessions_on_templateStartedAt"))
  }

  @Test("Sessions and their movements recorded before the upgrade come through unchanged")
  func existingSessionsSurviveMigration() throws {
    let queue = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(queue, upTo: "v10_importLedgerDigests")
    let exercise = UUID().uuidString.lowercased()
    let session = UUID().uuidString.lowercased()
    let planned = UUID().uuidString.lowercased()
    try queue.write { db in
      try db.execute(sql: "INSERT INTO exercises(id, name) VALUES (?, 'Chest Press')", arguments: [exercise])
      try db.execute(
        sql: "INSERT INTO sessions(id, title, notes) VALUES (?, 'Push day', 'felt strong')",
        arguments: [session])
      try db.execute(
        sql: "INSERT INTO sessionExercises(id, sessionID, exerciseID, position, plannedSets) VALUES (?, ?, ?, 2, 4)",
        arguments: [planned, session, exercise])
    }

    try HardsetMigrations.migrator().migrate(queue)

    let (sessionRow, plannedRow) = try queue.read { db in
      (
        try Row.fetchOne(db, sql: "SELECT * FROM sessions WHERE id = ?", arguments: [session]),
        try Row.fetchOne(
          db, sql: "SELECT * FROM sessionExercises WHERE id = ?", arguments: [planned])
      )
    }
    let sessionValues = try #require(sessionRow)
    #expect(sessionValues["title"] as String == "Push day")
    #expect(sessionValues["notes"] as String == "felt strong")
    #expect((sessionValues["templateID"] as String?) == nil)
    let plannedValues = try #require(plannedRow)
    #expect(plannedValues["position"] as Int == 2)
    #expect(plannedValues["plannedSets"] as Int? == 4)
    #expect((plannedValues["repRangeLower"] as Int?) == nil)
    #expect((plannedValues["repRangeUpper"] as Int?) == nil)
  }
}
