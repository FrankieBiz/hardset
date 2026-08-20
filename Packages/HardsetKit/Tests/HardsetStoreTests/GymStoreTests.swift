import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("Gyms and machines, without which machine-level tracking is unreachable")
struct GymStoreTests {
  let now = Date(timeIntervalSince1970: 16_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private func fixture() throws -> (any DatabaseWriter, GymStore, LoggerStore, ExerciseID) {
    let database = try migratedDatabase()
    let exercise = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Leg Press") }.execute(db)
    }
    return (database, GymStore(database: database), LoggerStore(database: database), exercise)
  }

  @Test("A gym and its machines can be created and read back")
  func createAndRead() throws {
    let (_, gyms, _, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym Holloway", now: now)
    try gyms.createMachine(at: gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)

    #expect(try gyms.gyms().map(\.name) == ["PureGym Holloway"])
    let machines = try gyms.machines(at: gym)
    #expect(machines.count == 2)
    // The brand leads, because distinguishing brands is the entire point of tracking machines.
    #expect(Set(machines.map(\.displayName)) == ["Hammer Strength Leg Press", "Cybex Leg Press"])
  }

  @Test("A machine with no brand shows just its name")
  func unbrandedMachine() throws {
    let (_, gyms, _, _) = try fixture()
    let gym = try gyms.createGym(name: "Home", now: now)
    try gyms.createMachine(at: gym, name: "Squat rack", now: now)
    #expect(try gyms.machines(at: gym).map(\.displayName) == ["Squat rack"])
  }

  /// Two devices creating "Home Gym" offline is a legitimate state, not a conflict — which is why
  /// there is no uniqueness constraint and duplicates must be allowed.
  @Test("Duplicate names are allowed")
  func duplicateNamesAllowed() throws {
    let (_, gyms, _, _) = try fixture()
    _ = try gyms.createGym(name: "Home Gym", now: now)
    _ = try gyms.createGym(name: "Home Gym", now: now)
    #expect(try gyms.gyms().count == 2)
  }

  /// Archiving rather than deleting: logged sets reference these machines, and a hard delete would
  /// either orphan real training history or cascade it away.
  @Test("Archiving hides a gym without touching its logged sets")
  func archivingIsNonDestructive() throws {
    let (_, gyms, logger, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Old gym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", now: now)

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(3600))

    try gyms.archiveGym(gym)
    #expect(try gyms.gyms().isEmpty)
    // The set survives, and still knows which machine it was performed on.
    let sets = try logger.sets(in: session)
    #expect(sets.count == 1)
    #expect(sets[0].machineID == machine)
  }

  @Test("An archived machine is not offered")
  func archivedMachineHidden() throws {
    let (_, gyms, _, _) = try fixture()
    let gym = try gyms.createGym(name: "Gym", now: now)
    let a = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    _ = try gyms.createMachine(at: gym, name: "Hack Squat", now: now)

    try gyms.archiveMachine(a)
    #expect(try gyms.machines(at: gym).map(\.name) == ["Hack Squat"])
  }

  // MARK: - Recency, which is what makes the common case free

  /// The machine you used last time is overwhelmingly the one you are standing at now, so recency
  /// is the right order for the set row's picker.
  @Test("Recent machines are ordered most-recently-used first")
  func recencyOrder() throws {
    let (_, gyms, logger, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Gym", now: now)
    let hammer = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Leg Press", brand: "Cybex", now: now)

    // Hammer three weeks ago, Cybex last week.
    for (machine, daysAgo) in [(hammer, 21), (cybex, 7)] {
      let start = now.addingTimeInterval(Double(-daysAgo) * 86_400)
      let session = try logger.startSession(gymID: gym, at: start)
      _ = try logger.logSet(
        sessionID: session, exerciseID: exercise, machineID: machine,
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: start
      )
      try logger.finishSession(session, at: start.addingTimeInterval(3600))
    }

    let recent = try gyms.recentMachines(for: exercise)
    #expect(recent.map(\.id) == [cybex, hammer])
  }

  @Test("A machine never used for this exercise is not suggested")
  func onlyUsedMachinesSuggested() throws {
    let (_, gyms, logger, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Gym", now: now)
    let used = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    _ = try gyms.createMachine(at: gym, name: "Chest Press", now: now)

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: used,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(3600))

    #expect(try gyms.recentMachines(for: exercise).map(\.id) == [used])
  }

  @Test("A never-performed exercise suggests nothing rather than guessing")
  func noHistoryNoSuggestion() throws {
    let (_, gyms, _, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Gym", now: now)
    _ = try gyms.createMachine(at: gym, name: "Leg Press", now: now)
    #expect(try gyms.recentMachines(for: exercise).isEmpty)
  }

  @Test("Suggestions can be scoped to one gym")
  func scopedToGym() throws {
    let (_, gyms, logger, exercise) = try fixture()
    let home = try gyms.createGym(name: "Home", now: now)
    let away = try gyms.createGym(name: "Away", now: now)
    let homeMachine = try gyms.createMachine(at: home, name: "Leg Press", now: now)
    let awayMachine = try gyms.createMachine(at: away, name: "Leg Press", now: now)

    for machine in [homeMachine, awayMachine] {
      let session = try logger.startSession(at: now)
      _ = try logger.logSet(
        sessionID: session, exerciseID: exercise, machineID: machine,
        draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: now
      )
      try logger.finishSession(session, at: now.addingTimeInterval(3600))
    }

    #expect(try gyms.recentMachines(for: exercise, at: home).map(\.id) == [homeMachine])
    #expect(try gyms.recentMachines(for: exercise, at: away).map(\.id) == [awayMachine])
  }

  @Test("An archived machine drops out of suggestions but its sets remain")
  func archivedMachineNotSuggested() throws {
    let (_, gyms, logger, exercise) = try fixture()
    let gym = try gyms.createGym(name: "Gym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Leg Press", now: now)

    let session = try logger.startSession(gymID: gym, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: exercise, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), setOrdinal: 0, at: now
    )
    try logger.finishSession(session, at: now.addingTimeInterval(3600))

    try gyms.archiveMachine(machine)
    #expect(try gyms.recentMachines(for: exercise).isEmpty)
    #expect(try logger.sets(in: session).count == 1)
  }

  /// The stack increment is what keeps a progression suggestion honest.
  @Test("A machine's stack increment round-trips")
  func stackIncrement() throws {
    let (_, gyms, _, _) = try fixture()
    let gym = try gyms.createGym(name: "Gym", now: now)
    try gyms.createMachine(at: gym, name: "Leg Press", stackIncrementKg: 10, now: now)
    try gyms.createMachine(at: gym, name: "Cable", now: now)

    let machines = try gyms.machines(at: gym)
    let byName = Dictionary(uniqueKeysWithValues: machines.map { ($0.name, $0) })
    #expect(byName["Leg Press"]?.stackIncrementKg == 10)
    // Unknown stays nil rather than defaulting to a plausible-looking number.
    #expect(byName["Cable"]?.stackIncrementKg == nil)
  }
}
