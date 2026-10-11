import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Gyms and machines can be renamed, and a blank name never reaches the database")
struct GymRenameTests {
  let now = Date(timeIntervalSince1970: 42_000_000)

  private func fixture() throws -> (any DatabaseWriter, GymStore) {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    return (database, GymStore(database: database))
  }

  @Test("A gym's new name is tidied and read back")
  func renameGym() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    try gyms.renameGym(gym, to: "  Iron   Temple ")
    #expect(try gyms.gyms().map(\.name) == ["Iron Temple"])
  }

  /// Review Focus: a name of only spaces would be a blank row in every picker.
  @Test("Renaming to a blank name is refused and the old name stays")
  func renameToBlankLeavesName() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)

    #expect(throws: GymStoreError.blankName) { try gyms.renameGym(gym, to: "   ") }
    #expect(throws: GymStoreError.blankName) {
      try gyms.renameMachine(machine, name: "\n", brand: "Hammer Strength")
    }
    #expect(try gyms.gyms().map(\.name) == ["Home"])
    #expect(try gyms.machines(at: gym).map(\.displayName) == ["Cybex Leg Press"])
  }

  @Test("A machine's name and brand change together, and a blank brand means none")
  func renameMachine() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)

    try gyms.renameMachine(machine, name: " Leg Press 45° ", brand: " Hammer  Strength ")
    #expect(try gyms.machines(at: gym).map(\.displayName) == ["Hammer Strength Leg Press 45°"])

    try gyms.renameMachine(machine, name: "Leg Press", brand: "  ")
    let renamed = try #require(try gyms.machines(at: gym).first)
    #expect(renamed.brand == "")
    #expect(renamed.displayName == "Leg Press")
  }

  @Test("Renaming something that is not there says so")
  func notFound() throws {
    let (_, gyms) = try fixture()
    #expect(throws: GymStoreError.gymNotFound) { try gyms.renameGym(GymID(), to: "Home") }
    #expect(throws: GymStoreError.machineNotFound) {
      try gyms.renameMachine(MachineID(), name: "Leg Press", brand: "")
    }
  }

  @Test("History follows the machine, so past sessions read the new name")
  func historyReadsNewName() throws {
    let (database, gyms) = try fixture()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    let gym = try gyms.createGym(name: "Home", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    let logger = LoggerStore(database: database)
    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(60))
    try logger.finishSession(session, at: now.addingTimeInterval(600))

    try gyms.renameMachine(machine, name: "Leg Press", brand: "Hammer Strength")

    let summary = try WorkoutSummaryStore(database: database).summary(for: session)
    #expect(summary.machinesUsed == ["Hammer Strength Leg Press"])
  }

  @Test("An archived gym leaves the list, and its machines stay readable")
  func archive() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Old gym", now: now)
    _ = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    try gyms.archiveGym(gym)
    #expect(try gyms.gyms().isEmpty)
    #expect(try gyms.machines(at: gym).map(\.name) == ["Leg Press"])
  }
}
