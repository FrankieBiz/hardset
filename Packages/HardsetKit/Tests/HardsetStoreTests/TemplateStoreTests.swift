import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Saved workouts are stored as plans and never rewrite history")
struct TemplateStoreTests {
  let start = Date(timeIntervalSince1970: 11_000_000)

  private func migratedDatabase() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

  private func seedExercise(_ database: DatabaseQueue, name: String) throws -> ExerciseID {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  private func seedMachine(
    _ database: DatabaseQueue, name: String, brand: String = ""
  ) throws -> MachineID {
    let gym = UUID()
    let id = MachineID()
    try database.write { db in
      try Gym.insert { Gym.Draft(id: gym, name: "Gym") }.execute(db)
      try Machine.insert {
        Machine.Draft(id: id.rawValue, gymID: gym, name: name, brand: brand)
      }
      .execute(db)
    }
    return id
  }

  private func template(
    _ name: String, position: Int = 0, _ exercises: [TemplateExercise]
  ) -> WorkoutTemplate {
    WorkoutTemplate(name: name, position: position, exercises: exercises)
  }

  private func planned(
    _ exercise: ExerciseID, _ name: String, machine: MachineID? = nil, sets: Int = 3,
    range: RepRange? = nil, rest: Int? = nil
  ) -> TemplateExercise {
    TemplateExercise(
      exerciseID: exercise, exerciseName: name, machineID: machine, plannedSets: sets,
      repRange: range, restSeconds: rest
    )
  }

  /// A session started from a template, with one planned movement per row, as a finished or open
  /// workout. Written directly so these tests do not depend on how a session is started.
  @discardableResult
  private func seedSession(
    _ database: DatabaseQueue, template: TemplateID?, startedAt: Date, finished: Bool,
    movements: [(exercise: ExerciseID, machine: MachineID?, range: RepRange?)] = []
  ) throws -> (session: SessionID, planRows: [UUID]) {
    let session = SessionID()
    let rows = movements.map { _ in UUID() }
    try database.write { db in
      try Session.insert {
        Session.Draft(
          id: session.rawValue, title: "Upper A", startedAt: startedAt,
          finishedAt: finished ? startedAt.addingTimeInterval(3600) : nil,
          templateID: template?.rawValue
        )
      }
      .execute(db)
      for (index, movement) in movements.enumerated() {
        try SessionExercise.insert {
          SessionExercise.Draft(
            id: rows[index], sessionID: session.rawValue, exerciseID: movement.exercise.rawValue,
            machineID: movement.machine?.rawValue, position: index, plannedSets: 3,
            repRangeLower: movement.range?.lower, repRangeUpper: movement.range?.upper
          )
        }
        .execute(db)
      }
    }
    return (session, rows)
  }

  private func count(_ table: String, in database: DatabaseQueue) throws -> Int {
    try database.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table)\"") ?? 0
    }
  }

  @Test("A saved workout reads back as it was saved, with names resolved")
  func saveAndLoadRoundTrip() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let row = try seedExercise(database, name: "Cable Row")
    let machine = try seedMachine(database, name: "Chest Press", brand: "Hammer Strength")
    let range = try #require(RepRange(lower: 8, upper: 12))
    let saved = template(
      "Upper A", position: 2,
      [
        planned(press, "stale name", machine: machine, sets: 4, range: range, rest: 90),
        planned(row, "stale name", sets: 3),
      ]
    )

    try await store.save(saved, now: start)
    let loaded = try await store.loadTemplates()

    #expect(loaded.count == 1)
    let first = try #require(loaded.first)
    #expect(first.id == saved.id)
    #expect(first.name == "Upper A")
    #expect(first.position == 2)
    #expect(first.lastDoneAt == nil)
    #expect(first.exercises.map(\.id) == saved.exercises.map(\.id))
    #expect(first.exercises.map(\.exerciseName) == ["Chest Press", "Cable Row"])
    #expect(first.exercises.map(\.machineID) == [machine, nil])
    #expect(first.exercises.map(\.machineName) == ["Hammer Strength Chest Press", nil])
    #expect(first.exercises.map(\.plannedSets) == [4, 3])
    #expect(first.exercises.map(\.repRange) == [range, nil])
    #expect(first.exercises.map(\.restSeconds) == [90, nil])
  }

  @Test("Saving again replaces the movements, and keeps the ones that stay")
  func saveReplacesExercises() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let row = try seedExercise(database, name: "Cable Row")
    let curl = try seedExercise(database, name: "Curl")
    let kept = planned(press, "Chest Press", sets: 3)
    let removed = planned(row, "Cable Row", sets: 3)
    let original = template("Upper A", [kept, removed])
    try await store.save(original, now: start)

    let added = planned(curl, "Curl", sets: 2)
    let edited = WorkoutTemplate(
      id: original.id, name: "Upper A2", position: 0,
      exercises: [
        added,
        TemplateExercise(
          id: kept.id, exerciseID: press, exerciseName: "Chest Press", plannedSets: 5,
          repRange: RepRange(lower: 6, upper: 10)),
      ]
    )
    try await store.save(edited, now: start.addingTimeInterval(60))

    let loaded = try await store.loadTemplates()
    let first = try #require(loaded.first)
    #expect(loaded.count == 1)
    #expect(first.name == "Upper A2")
    #expect(first.exercises.map(\.exerciseName) == ["Curl", "Chest Press"])
    #expect(first.exercises.map(\.id) == [added.id, kept.id])
    #expect(first.exercises.last?.plannedSets == 5)
    #expect(first.exercises.last?.repRange == RepRange(lower: 6, upper: 10))
    #expect(try count("templateExercises", in: database) == 2)
    #expect(try count("workoutTemplates", in: database) == 1)
  }

  @Test("A blank name is refused and nothing is written")
  func blankNameRejected() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")

    await #expect(throws: TemplateStoreError.blankName) {
      try await store.save(self.template("   ", [self.planned(press, "Chest Press")]), now: self.start)
    }
    #expect(try count("workoutTemplates", in: database) == 0)
  }

  @Test("A workout with no movements is refused")
  func emptyTemplateRejected() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)

    await #expect(throws: TemplateStoreError.noExercises) {
      try await store.save(self.template("Upper A", []), now: self.start)
    }
    #expect(try count("workoutTemplates", in: database) == 0)
  }

  @Test("A movement that does not exist is refused, and the template is not half saved")
  func unknownExerciseRejected() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")

    await #expect(throws: TemplateStoreError.unknownExercise) {
      try await store.save(
        self.template(
          "Upper A", [self.planned(press, "Chest Press"), self.planned(ExerciseID(), "Ghost")]),
        now: self.start
      )
    }
    #expect(try count("workoutTemplates", in: database) == 0)
    #expect(try count("templateExercises", in: database) == 0)
  }

  @Test("A machine that no longer exists is saved as no machine")
  func vanishedMachineIsDropped() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")

    try await store.save(
      template("Upper A", [planned(press, "Chest Press", machine: MachineID())]), now: start)

    let loaded = try await store.loadTemplates()
    #expect(loaded.first?.exercises.first?.machineID == nil)
  }

  @Test("Archived workouts are hidden, and archiving one that does not exist says so")
  func archivedTemplatesHidden() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let a = template("Upper A", position: 0, [planned(press, "Chest Press")])
    let b = template("Upper B", position: 1, [planned(press, "Chest Press")])
    try await store.save(a, now: start)
    try await store.save(b, now: start)

    try await store.archive(a.id)

    let visible = try await store.loadTemplates().map(\.name)
    #expect(visible == ["Upper B"])
    #expect(try count("workoutTemplates", in: database) == 2)
    await #expect(throws: TemplateStoreError.notFound) { try await store.archive(TemplateID()) }
  }

  @Test("Workouts come back in the lifter's order, and reordering changes only that")
  func reorderChangesPositions() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let a = template("A", position: 0, [planned(press, "Chest Press")])
    let b = template("B", position: 1, [planned(press, "Chest Press")])
    let c = template("C", position: 2, [planned(press, "Chest Press")])
    for item in [a, b, c] { try await store.save(item, now: start) }

    try await store.reorder([c.id, a.id])

    let loaded = try await store.loadTemplates()
    #expect(loaded.map(\.name) == ["C", "A", "B"])
    #expect(loaded.map(\.position) == [0, 1, 2])
    await #expect(throws: TemplateStoreError.notFound) {
      try await store.reorder([a.id, TemplateID()])
    }
    let unchanged = try await store.loadTemplates().map(\.name)
    #expect(unchanged == ["C", "A", "B"])
  }

  @Test("Last done is the latest finished session, never an open one")
  func lastDoneAtIgnoresOpenSessions() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let done = template("Upper A", position: 0, [planned(press, "Chest Press")])
    let neverFinished = template("Upper B", position: 1, [planned(press, "Chest Press")])
    try await store.save(done, now: start)
    try await store.save(neverFinished, now: start)
    try seedSession(database, template: done.id, startedAt: day(-5), finished: true)
    try seedSession(database, template: done.id, startedAt: day(-2), finished: true)
    try seedSession(database, template: done.id, startedAt: day(0), finished: false)
    try seedSession(database, template: neverFinished.id, startedAt: day(0), finished: false)

    let loaded = try await store.loadTemplates()

    #expect(loaded.first { $0.id == done.id }?.lastDoneAt == day(-2))
    #expect(loaded.first { $0.id == neverFinished.id }?.lastDoneAt == nil)
  }

  @Test("The last finished session of a workout is the most recent one")
  func lastFinishedSessionIsTheLatest() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let template = TemplateID()
    let older = try seedSession(database, template: template, startedAt: day(-4), finished: true)
    let latest = try seedSession(database, template: template, startedAt: day(-1), finished: true)
    try seedSession(database, template: template, startedAt: day(0), finished: false)

    let found = try await store.lastFinishedSession(for: template)
    let missing = try await store.lastFinishedSession(for: TemplateID())
    #expect(found == latest.session)
    #expect(latest.session != older.session)
    #expect(missing == nil)
  }

  @Test("A draft from a session counts the working sets, not the warm-ups")
  func draftFromSessionCountsWorkingSetsOnly() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let row = try seedExercise(database, name: "Cable Row")
    let machine = try seedMachine(database, name: "Press")
    let range = try #require(RepRange(lower: 8, upper: 12))
    let existing = template("Other", position: 4, [planned(press, "Chest Press")])
    try await store.save(existing, now: start)
    let seeded = try seedSession(
      database, template: nil, startedAt: day(-1), finished: true,
      movements: [(press, machine, range), (row, nil, nil)]
    )
    try await database.write { db in
      for (ordinal, isWarmup) in [true, false, false, false].enumerated() {
        try LoggedSet.insert {
          LoggedSet.Draft(
            id: UUID(), sessionID: seeded.session.rawValue, exerciseID: press.rawValue,
            machineID: machine.rawValue, sessionExerciseID: seeded.planRows[0],
            setOrdinal: ordinal, weightKg: 40, reps: 10, isWarmup: isWarmup,
            completedAt: self.day(-1)
          )
        }
        .execute(db)
      }
    }

    let draft = try await store.draft(fromSession: seeded.session, name: "Upper A")

    #expect(draft.name == "Upper A")
    #expect(draft.position == 5)
    #expect(draft.lastDoneAt == nil)
    #expect(draft.exercises.map(\.exerciseID) == [press, row])
    #expect(draft.exercises.map(\.exerciseName) == ["Chest Press", "Cable Row"])
    #expect(draft.exercises.map(\.plannedSets) == [3, 1])
    #expect(draft.exercises.map(\.machineID) == [machine, nil])
    #expect(draft.exercises.map(\.repRange) == [range, nil])
    let stillSaved = try await store.loadTemplates().map(\.id)
    #expect(stillSaved == [existing.id])
    await #expect(throws: TemplateStoreError.notFound) {
      try await store.draft(fromSession: SessionID(), name: "Nothing")
    }
  }

  /// A plan is copied into the session when it starts, so changing or archiving the plan later
  /// cannot change what the session says it was.
  @Test("Editing or archiving a workout does not touch the sessions it started")
  func editingTemplateDoesNotTouchPastSessions() async throws {
    let database = try migratedDatabase()
    let store = TemplateStore(database: database)
    let press = try seedExercise(database, name: "Chest Press")
    let row = try seedExercise(database, name: "Cable Row")
    let range = try #require(RepRange(lower: 8, upper: 12))
    let original = template("Upper A", [planned(press, "Chest Press", sets: 3, range: range)])
    try await store.save(original, now: start)
    let started = try seedSession(
      database, template: original.id, startedAt: day(-1), finished: true,
      movements: [(press, nil, range)]
    )
    let before = try await database.read { db in
      (
        try Session.fetchAll(db),
        try SessionExercise.fetchAll(db)
      )
    }

    let edited = WorkoutTemplate(
      id: original.id, name: "Renamed", position: 0,
      exercises: [planned(row, "Cable Row", sets: 6, range: RepRange(lower: 5, upper: 6))]
    )
    try await store.save(edited, now: start)
    try await store.archive(original.id)

    let after = try await database.read { db in
      (
        try Session.fetchAll(db),
        try SessionExercise.fetchAll(db)
      )
    }
    #expect(after.0 == before.0)
    #expect(after.1 == before.1)
    #expect(after.0.first?.templateID == original.id.rawValue)
    #expect(after.1.first?.repRangeLower == 8)
    let lastFinished = try await store.lastFinishedSession(for: original.id)
    #expect(lastFinished == started.session)
  }
}
