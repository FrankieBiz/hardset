import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("A past workout reads back from storage, by movement and machine")
struct SessionDetailStoreTests {
  let now = Date(timeIntervalSince1970: 45_000_000)

  private struct Fixture {
    let database: any DatabaseWriter
    let logger: LoggerStore
    let gyms: GymStore
    let details: SessionDetailStore
    let press: ExerciseID
    let gym: GymID
  }

  private func fixture() throws -> Fixture {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let database = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(database)
    let press = ExerciseID()
    try database.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Leg Press") }.execute(db)
    }
    let gyms = GymStore(database: database)
    return Fixture(
      database: database, logger: LoggerStore(database: database), gyms: gyms,
      details: SessionDetailStore(database: database), press: press,
      gym: try gyms.createGym(name: "Home", now: now))
  }

  private func log(
    _ f: Fixture, _ session: SessionID, _ machine: MachineID?, _ weight: Double,
    warmup: Bool = false, at minute: Double
  ) throws -> SetID {
    try f.logger.logSet(
      sessionID: session, exerciseID: f.press, machineID: machine,
      draft: SetEntryDraft(weightKg: weight, reps: 8), isWarmup: warmup,
      at: now.addingTimeInterval(minute * 60))
  }

  /// Review Focus: the lifter moved from the Hammer to the Cybex mid-exercise. Those are two
  /// different efforts, and the detail must show them apart.
  @Test("One movement on two machines reads as two blocks, each named")
  func sameExerciseTwoMachinesTwoBlocks() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let cybex = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try f.logger.startSession(gymID: f.gym, at: now)
    _ = try log(f, session, hammer, 100, at: 1)
    _ = try log(f, session, hammer, 100, at: 4)
    _ = try log(f, session, cybex, 80, at: 10)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let detail = try f.details.detail(for: session)
    #expect(detail.blocks.count == 2)
    #expect(detail.blocks.map(\.machineName) == ["Hammer Strength Leg Press", "Cybex Leg Press"])
    #expect(detail.blocks.map(\.sets.count) == [2, 1])
    #expect(detail.blocks.allSatisfy { $0.exerciseName == "Leg Press" })
  }

  /// Review Focus: archiving a machine must not turn its past sets into free weight.
  @Test("An archived machine keeps its name in the past")
  func archivedMachineStillNamed() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Hammer Strength", now: now)
    let session = try f.logger.startSession(gymID: f.gym, at: now)
    _ = try log(f, session, hammer, 100, at: 1)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))
    try f.gyms.archiveMachine(hammer)

    let detail = try f.details.detail(for: session)
    #expect(detail.blocks.first?.machineName == "Hammer Strength Leg Press")
    #expect(detail.blocks.first?.machineID == hammer)
  }

  @Test("A record sits on the set that earned it, and warm-ups are listed as warm-ups")
  func recordsAndWarmups() throws {
    let f = try fixture()
    let hammer = try f.gyms.createMachine(at: f.gym, name: "Leg Press", now: now)
    let before = try f.logger.startSession(gymID: f.gym, at: now.addingTimeInterval(-7 * 86_400))
    _ = try f.logger.logSet(
      sessionID: before, exerciseID: f.press, machineID: hammer,
      draft: SetEntryDraft(weightKg: 100, reps: 8), at: now.addingTimeInterval(-7 * 86_400 + 60))
    try f.logger.finishSession(before, at: now.addingTimeInterval(-7 * 86_400 + 1_800))

    let session = try f.logger.startSession(gymID: f.gym, at: now)
    let warmup = try log(f, session, hammer, 60, warmup: true, at: 1)
    let best = try log(f, session, hammer, 110, at: 5)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let sets = try #require(try f.details.detail(for: session).blocks.first).sets
    #expect(sets.map(\.setID) == [warmup, best])
    #expect(sets[0].isWarmup)
    #expect(sets[0].records.isEmpty)
    #expect(sets[1].records.map(\.kind).contains(.heaviestLoad))
  }

  @Test("A session left open overnight has no length, only the words")
  func honestLength() throws {
    let f = try fixture()
    let session = try f.logger.startSession(at: now)
    _ = try log(f, session, nil, 100, at: 1)
    try f.logger.finishSession(session, at: now.addingTimeInterval(7 * 3_600))

    let detail = try f.details.detail(for: session)
    #expect(detail.summary.length == nil)
    #expect(detail.summary.lengthText == "Length unknown")
    #expect(detail.blocks.first?.machineName == nil)
  }

  @Test("A session that is not there says so")
  func missing() throws {
    let f = try fixture()
    #expect(throws: LoggerStoreError.sessionNotFound) { try f.details.detail(for: SessionID()) }
  }

  @Test("A session never finished has no length, and reading it does not throw")
  func openSessionHasNoLength() throws {
    let f = try fixture()
    let session = try f.logger.startSession(at: now)
    _ = try log(f, session, nil, 100, at: 1)

    let detail = try f.details.detail(for: session)
    #expect(detail.summary.length == nil)
    #expect(detail.summary.lengthText == "Length unknown")
    #expect(detail.blocks.count == 1)
  }

  @Test("Two machines with identical names are still two blocks")
  func identicalNamesStayApart() throws {
    let f = try fixture()
    let first = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Cybex", now: now)
    let second = try f.gyms.createMachine(at: f.gym, name: "Leg Press", brand: "Cybex", now: now)
    let session = try f.logger.startSession(gymID: f.gym, at: now)
    _ = try log(f, session, first, 100, at: 1)
    _ = try log(f, session, second, 100, at: 4)
    try f.logger.finishSession(session, at: now.addingTimeInterval(1_800))

    let blocks = try f.details.detail(for: session).blocks
    #expect(blocks.count == 2)
    #expect(blocks.map(\.machineID) == [first, second])
    #expect(blocks.map(\.machineName) == ["Cybex Leg Press", "Cybex Leg Press"])
  }
}
