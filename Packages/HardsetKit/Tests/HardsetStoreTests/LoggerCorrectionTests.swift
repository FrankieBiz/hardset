import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// The store's correction commands: each validates inside its own write transaction, changes
/// only the open workout it names, and either applies completely or not at all.
@Suite("Corrections to an open workout are validated and atomic")
struct LoggerCorrectionTests {
  let start = Date(timeIntervalSince1970: 8_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func seedExercise(_ database: any DatabaseWriter, name: String = "Leg Press") throws
    -> ExerciseID
  {
    let id = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
    }
    return id
  }

  private func count(_ table: String, _ database: any DatabaseWriter) throws -> Int {
    try database.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table)") ?? -1 }
  }

  private func log(
    _ store: LoggerStore, _ session: SessionID, _ exercise: ExerciseID,
    machine: MachineID? = nil, row: UUID? = nil, weight: Double = 100, at offset: TimeInterval = 0
  ) throws -> SetID {
    try store.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine, sessionExerciseID: row,
      draft: SetEntryDraft(weightKg: weight, reps: 8), at: start.addingTimeInterval(offset)
    )
  }

  // MARK: - Deleting a saved set

  @Test("Deleting a saved set removes only that row of the open workout")
  func deleteLoggedSet() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    let kept = try log(store, session, exercise)
    let typo = try log(store, session, exercise, weight: 1000, at: 60)

    try store.deleteLoggedSet(typo, in: session)
    #expect(try store.sets(in: session).map(\.id) == [kept])
    // Already gone, for instance removed on another device: the outcome asked for holds.
    try store.deleteLoggedSet(typo, in: session)
    #expect(try store.sets(in: session).map(\.id) == [kept])
  }

  @Test("A saved set cannot be deleted from a finished, missing or different workout")
  func deleteLoggedSetGuards() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let finished = try store.startSession(at: start)
    let finishedSet = try log(store, finished, exercise)
    try store.finishSession(finished, at: start.addingTimeInterval(600))
    #expect(throws: LoggerStoreError.sessionClosed) {
      try store.deleteLoggedSet(finishedSet, in: finished)
    }
    #expect(throws: LoggerStoreError.sessionNotFound) {
      try store.deleteLoggedSet(finishedSet, in: SessionID())
    }
    // Naming the open workout does not reach into another one.
    let open = try store.startSession(at: start.addingTimeInterval(700))
    #expect(throws: LoggerStoreError.writeNotApplied) {
      try store.deleteLoggedSet(finishedSet, in: open)
    }
    #expect(try store.sets(in: finished).count == 1)
  }

  @Test("An ignored delete cannot report success")
  func ignoredDeleteFails() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let exercise = try seedExercise(database)
    let session = try store.startSession(at: start)
    let set = try log(store, session, exercise)
    try database.write { db in
      try db.execute(sql: "CREATE TEMP TRIGGER ignore_delete BEFORE DELETE ON loggedSets BEGIN SELECT RAISE(IGNORE); END")
    }
    #expect(throws: LoggerStoreError.writeNotApplied) {
      try store.deleteLoggedSet(set, in: session)
    }
  }

  // MARK: - Removing a movement

  @Test("Removing a movement deletes its plan row and this workout's sets for it, nothing else")
  func removeSessionExercise() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, name: "Press")
    let curl = try seedExercise(database, name: "Curl")
    // An earlier workout's set on the same movement is history and must survive.
    let earlier = try store.startSession(at: start.addingTimeInterval(-86_400))
    let history = try log(store, earlier, press, at: -86_400)
    try store.finishSession(earlier, at: start.addingTimeInterval(-82_800))

    let session = try store.startSession(at: start)
    let pressRow = try store.addExercise(to: session, exerciseID: press, position: 0)
    let curlRow = try store.addExercise(to: session, exerciseID: curl, position: 1)
    let laterPressRow = try store.addExercise(to: session, exerciseID: press, position: 2)
    _ = try log(store, session, press, row: pressRow)
    // A set written before plan rows were recorded on sets: only reachable by its id.
    let orphan = try log(store, session, press, at: 30)
    let curlSet = try log(store, session, curl, row: curlRow, at: 60)
    let laterPressSet = try log(store, session, press, row: laterPressRow, at: 90)

    try store.removeSessionExercise(
      rowID: pressRow, sessionID: session, exerciseID: press, loggedSetIDs: [orphan]
    )

    let plan = try store.sessionExercises(in: session)
    #expect(plan.map(\.id) == [curlRow, laterPressRow])
    // Renumbered, so the next movement added at the end cannot share a position.
    #expect(plan.map(\.position) == [0, 1])
    #expect(Set(try store.sets(in: session).map(\.id)) == [curlSet, laterPressSet])
    #expect(try store.sets(in: earlier).map(\.id) == [history])
  }

  @Test("Set ids passed for another movement are not deleted with this one")
  func removeSessionExerciseScopesExplicitSets() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database, name: "Press")
    let curl = try seedExercise(database, name: "Curl")
    let session = try store.startSession(at: start)
    let pressRow = try store.addExercise(to: session, exerciseID: press, position: 0)
    let curlSet = try log(store, session, curl)
    try store.removeSessionExercise(
      rowID: pressRow, sessionID: session, exerciseID: press, loggedSetIDs: [curlSet]
    )
    #expect(try store.sets(in: session).map(\.id) == [curlSet])
  }

  @Test("A movement cannot be removed from a finished or different workout")
  func removeSessionExerciseGuards() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let row = try store.addExercise(to: session, exerciseID: press, position: 0)
    _ = try log(store, session, press, row: row)

    let other = try store.startSession(at: start.addingTimeInterval(10))
    #expect(throws: LoggerStoreError.sessionExerciseMismatch) {
      try store.removeSessionExercise(rowID: row, sessionID: other)
    }
    let curl = try seedExercise(database, name: "Curl")
    #expect(throws: LoggerStoreError.sessionExerciseMismatch) {
      try store.removeSessionExercise(rowID: row, sessionID: session, exerciseID: curl)
    }
    try store.finishSession(session, at: start.addingTimeInterval(600))
    #expect(throws: LoggerStoreError.sessionClosed) {
      try store.removeSessionExercise(rowID: row, sessionID: session)
    }
    #expect(try store.sessionExercises(in: session).count == 1)
    #expect(try store.sets(in: session).count == 1)
  }

  @Test("A failed plan-row delete keeps the movement's sets")
  func removeSessionExerciseIsAtomic() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let row = try store.addExercise(to: session, exerciseID: press, position: 0)
    _ = try log(store, session, press, row: row)
    try database.write { db in
      try db.execute(sql: "CREATE TEMP TRIGGER refuse_plan_delete BEFORE DELETE ON sessionExercises BEGIN SELECT RAISE(ABORT, 'injected'); END")
    }
    #expect(throws: (any Error).self) {
      try store.removeSessionExercise(rowID: row, sessionID: session)
    }
    #expect(try store.sets(in: session).count == 1)
    #expect(try store.sessionExercises(in: session).count == 1)
  }

  @Test("A plan row already removed elsewhere still clears this workout's sets for it")
  func removeMissingRowIsIdempotent() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let row = try store.addExercise(to: session, exerciseID: press, position: 0)
    _ = try log(store, session, press, row: row)
    try database.write { db in
      try db.execute(sql: "DELETE FROM sessionExercises WHERE id = ?", arguments: [row.uuidString.lowercased()])
    }
    try store.removeSessionExercise(rowID: row, sessionID: session, exerciseID: press)
    #expect(try store.sets(in: session).isEmpty)
  }

  // MARK: - Reordering

  @Test("Reordering writes every position, so recovery restores the new order")
  func reorderPlan() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let rows = try (0..<3).map { try store.addExercise(to: session, exerciseID: press, position: $0) }

    try store.setSessionExercisePositions([rows[2], rows[0], rows[1]], in: session)
    let plan = try store.sessionExercises(in: session)
    #expect(plan.map(\.id) == [rows[2], rows[0], rows[1]])
    #expect(plan.map(\.position) == [0, 1, 2])
  }

  @Test("A reorder that does not name exactly the workout's rows changes nothing",
        arguments: ["missing", "extra", "duplicate"])
  func reorderMustMatchPlan(variant: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let rows = try (0..<2).map { try store.addExercise(to: session, exerciseID: press, position: $0) }
    let order: [UUID]
    switch variant {
    case "missing": order = [rows[1]]
    case "extra": order = [rows[1], rows[0], UUID()]
    default: order = [rows[1], rows[1]]
    }
    #expect(throws: LoggerStoreError.sessionExerciseMismatch) {
      try store.setSessionExercisePositions(order, in: session)
    }
    #expect(try store.sessionExercises(in: session).map(\.id) == rows)
  }

  @Test("A finished workout cannot be reordered")
  func reorderClosed() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let rows = try (0..<2).map { try store.addExercise(to: session, exerciseID: press, position: $0) }
    try store.finishSession(session, at: start.addingTimeInterval(60))
    #expect(throws: LoggerStoreError.sessionClosed) {
      try store.setSessionExercisePositions(rows.reversed(), in: session)
    }
  }

  // MARK: - Setting the gym

  @Test("An open workout's gym can be set, changed and cleared while no machine is recorded")
  func setSessionGym() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let away = try gyms.createGym(name: "Away")
    let session = try store.startSession(at: start)

    try store.setSessionGym(session, to: home)
    #expect(try store.openSession()?.gymID == home)
    try store.setSessionGym(session, to: away)
    #expect(try store.openSession()?.gymID == away)
    try store.setSessionGym(session, to: nil)
    #expect(try store.openSession()?.gymID == nil)
  }

  @Test("An unknown or archived gym is refused")
  func setSessionGymRequiresLiveGym() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let closedDown = try gyms.createGym(name: "Closed")
    try gyms.archiveGym(closedDown)
    let session = try store.startSession(at: start)
    #expect(throws: LoggerStoreError.gymNotFound) { try store.setSessionGym(session, to: GymID()) }
    #expect(throws: LoggerStoreError.gymNotFound) { try store.setSessionGym(session, to: closedDown) }
    #expect(try store.openSession()?.gymID == nil)
  }

  @Test("A recorded machine pins the workout to its gym", arguments: ["plan", "set"])
  func recordedMachinePinsGym(source: String) throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let away = try gyms.createGym(name: "Away")
    let machine = try gyms.createMachine(at: home, name: "Press")
    let press = try seedExercise(database)
    let session = try store.startSession(gymID: home, at: start)
    let row = try store.addExercise(to: session, exerciseID: press, machineID: machine, position: 0)
    if source == "set" {
      // The plan row went back to "not recorded", but a set was performed on the machine.
      _ = try log(store, session, press, machine: machine, row: row)
      try store.setSessionExerciseMachine(rowID: row, machineID: nil)
    }
    #expect(throws: LoggerStoreError.machineGymMismatch) { try store.setSessionGym(session, to: away) }
    #expect(throws: LoggerStoreError.machineGymMismatch) { try store.setSessionGym(session, to: nil) }
    #expect(try store.openSession()?.gymID == home)
    // Naming the machine's own gym again is consistent and allowed.
    try store.setSessionGym(session, to: home)
  }

  @Test("A finished workout's gym cannot be changed")
  func setSessionGymClosed() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let session = try store.startSession(at: start)
    try store.finishSession(session, at: start.addingTimeInterval(60))
    #expect(throws: LoggerStoreError.sessionClosed) { try store.setSessionGym(session, to: home) }
  }

  // MARK: - Discarding

  @Test("Discarding deletes the open workout with its plan and sets, and nothing else")
  func discardOpenSession() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let earlier = try store.startSession(at: start.addingTimeInterval(-86_400))
    let earlierRow = try store.addExercise(to: earlier, exerciseID: press, position: 0)
    _ = try log(store, earlier, press, row: earlierRow, at: -86_400)
    try store.finishSession(earlier, at: start.addingTimeInterval(-82_800))

    let session = try store.startSession(at: start)
    let row = try store.addExercise(to: session, exerciseID: press, position: 0)
    _ = try log(store, session, press, row: row)

    try store.discardOpenSession(session)
    #expect(try store.openSession() == nil)
    #expect(try count("sessions", database) == 1)
    #expect(try count("sessionExercises", database) == 1)
    #expect(try count("loggedSets", database) == 1)
    #expect(try store.sets(in: earlier).count == 1)
  }

  @Test("A finished or missing workout cannot be discarded")
  func discardGuards() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    _ = try log(store, session, press)
    try store.finishSession(session, at: start.addingTimeInterval(60))
    #expect(throws: LoggerStoreError.sessionClosed) { try store.discardOpenSession(session) }
    #expect(throws: LoggerStoreError.sessionNotFound) { try store.discardOpenSession(SessionID()) }
    #expect(try count("loggedSets", database) == 1)
  }

  @Test("A failed discard leaves the whole workout in place")
  func discardIsAtomic() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let press = try seedExercise(database)
    let session = try store.startSession(at: start)
    let row = try store.addExercise(to: session, exerciseID: press, position: 0)
    _ = try log(store, session, press, row: row)
    try database.write { db in
      try db.execute(sql: "CREATE TEMP TRIGGER refuse_session_delete BEFORE DELETE ON sessions BEGIN SELECT RAISE(ABORT, 'injected'); END")
    }
    #expect(throws: (any Error).self) { try store.discardOpenSession(session) }
    #expect(try store.openSession()?.id == session)
    #expect(try store.sets(in: session).count == 1)
    #expect(try store.sessionExercises(in: session).count == 1)
  }

  // MARK: - The machine used last time

  @Test("The most recent machine for a movement is found at this gym only, skipping archived ones")
  func mostRecentMachineAtGym() throws {
    let database = try migratedDatabase()
    let store = LoggerStore(database: database)
    let gyms = GymStore(database: database)
    let home = try gyms.createGym(name: "Home")
    let away = try gyms.createGym(name: "Away")
    let older = try gyms.createMachine(at: home, name: "Leg Press", brand: "Cybex", stackIncrementKg: 5)
    let newer = try gyms.createMachine(at: home, name: "Leg Press", brand: "Hammer Strength", stackIncrementKg: 10)
    let elsewhere = try gyms.createMachine(at: away, name: "Leg Press")
    let press = try seedExercise(database)
    #expect(try store.mostRecentMachine(for: press, at: home) == nil)

    let past = try store.startSession(gymID: home, at: start.addingTimeInterval(-3_000))
    _ = try log(store, past, press, machine: older, at: -3_000)
    _ = try log(store, past, press, machine: newer, at: -2_000)
    try store.finishSession(past, at: start.addingTimeInterval(-1_500))
    let trip = try store.startSession(gymID: away, at: start.addingTimeInterval(-1_000))
    _ = try log(store, trip, press, machine: elsewhere, at: -1_000)
    try store.finishSession(trip, at: start.addingTimeInterval(-500))

    let found = try #require(try store.mostRecentMachine(for: press, at: home))
    #expect(found.id == newer)
    #expect(found.displayName == "Hammer Strength Leg Press")
    #expect(found.stackIncrementKg == 10)

    try gyms.archiveMachine(newer)
    #expect(try store.mostRecentMachine(for: press, at: home)?.id == older)
  }
}
