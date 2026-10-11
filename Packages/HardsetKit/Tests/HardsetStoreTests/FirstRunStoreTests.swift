import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

@Suite("The first screen shows once, only to someone new, and asks nothing it does not need")
struct FirstRunStoreTests {
  let now = Date(timeIntervalSince1970: 43_000_000)

  private func database(migrated: Bool = true) throws -> any DatabaseWriter {
    var configuration = Configuration.forTesting()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    if migrated { try HardsetMigrations.migrator().migrate(queue) }
    return queue
  }

  @Test("A fresh install shows it, and finishing it hides it for good")
  func freshInstall() throws {
    let store = FirstRunStore(database: try database(), flag: InMemoryFirstRunFlag())
    #expect(try store.shouldShow())
    try store.complete(gymName: "", now: now)
    #expect(try !store.shouldShow())
  }

  /// Review Focus: an update reaches people with years of history and a flag that never existed.
  @Test("Someone with history never sees it, though the flag is new to them")
  func existingHistorySkipsFirstRun() throws {
    let db = try database()
    let logger = LoggerStore(database: db)
    let session = try logger.startSession(at: now)
    try logger.finishSession(session, at: now.addingTimeInterval(600))
    #expect(try !FirstRunStore(database: db, flag: InMemoryFirstRunFlag()).shouldShow())
  }

  /// Review Focus: a workout left open is offered back first; a welcome must not hide it.
  @Test("A workout left open is never hidden behind it")
  func openWorkoutSkipsFirstRun() throws {
    let db = try database()
    _ = try LoggerStore(database: db).startSession(at: now)
    #expect(try !FirstRunStore(database: db, flag: InMemoryFirstRunFlag()).shouldShow())
  }

  /// Review Focus: an optional field left as spaces must not create a nameless gym.
  @Test("A blank gym name creates no gym")
  func blankGymNameCreatesNoGym() throws {
    let db = try database()
    let flag = InMemoryFirstRunFlag()
    #expect(try FirstRunStore(database: db, flag: flag).complete(gymName: "   ", now: now) == nil)
    #expect(try GymStore(database: db).gyms().isEmpty)
    #expect(flag.isComplete)
  }

  @Test("A named gym is created, tidied, and returned so it can be selected")
  func namedGym() throws {
    let db = try database()
    let id = try FirstRunStore(database: db, flag: InMemoryFirstRunFlag())
      .complete(gymName: " Iron   Temple ", now: now)
    let gyms = try GymStore(database: db).gyms()
    #expect(gyms.map(\.name) == ["Iron Temple"])
    #expect(gyms.first?.id == id)
  }

  @Test("A gym that cannot be saved leaves the first screen unfinished")
  func failedGymLeavesItOpen() throws {
    let flag = InMemoryFirstRunFlag()
    let store = FirstRunStore(database: try database(migrated: false), flag: flag)
    #expect(throws: (any Error).self) { try store.complete(gymName: "Home", now: now) }
    #expect(!flag.isComplete)
  }

  @Test("The flag survives a relaunch")
  func flagPersists() {
    let defaults = UserDefaults(suiteName: "hardset.tests.\(UUID().uuidString)")!
    #expect(!UserDefaultsFirstRunFlag(defaults: defaults).isComplete)
    UserDefaultsFirstRunFlag(defaults: defaults).markComplete()
    #expect(UserDefaultsFirstRunFlag(defaults: defaults).isComplete)
  }
}
