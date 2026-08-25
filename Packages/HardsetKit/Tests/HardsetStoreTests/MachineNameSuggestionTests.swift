import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Offering back machine names the lifter has already used.
///
/// The feature is one word away from reading as "merge my machines", which invariant #10 forbids
/// outright. These tests pin the two halves that keep it honest: a name from *another* gym creates
/// a new machine with its own empty history, and a name already at *this* gym resolves to the
/// machine that is there rather than minting a second id for one physical unit.
@Suite("Suggested machine names never merge two machines, and never duplicate one")
struct MachineNameSuggestionTests {
  let now = Date(timeIntervalSince1970: 16_000_000)

  private func fixture() throws -> (GymStore, LoggerStore, ExerciseID) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    let press = ExerciseID()
    try queue.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Leg Press") }.execute(db)
    }
    return (GymStore(database: queue), LoggerStore(database: queue), press)
  }

  @Test("Names used at other gyms are offered, and say where they are from")
  func offersNamesFromOtherGyms() throws {
    let (gyms, _, _) = try fixture()
    let holloway = try gyms.createGym(name: "PureGym Holloway", now: now)
    let angel = try gyms.createGym(name: "PureGym Angel", now: now)
    _ = try gyms.createMachine(at: holloway, name: "Cybex Leg Press", now: now)

    let suggestion = try #require(try gyms.machineNameSuggestions(at: angel).first)
    #expect(suggestion.name == "Cybex Leg Press")
    #expect(suggestion.existingHere == nil, "It is not at this gym, so it must not resolve here.")
    #expect(suggestion.otherGymNames == ["PureGym Holloway"])
  }

  /// The risk the whole design turns on. Autocomplete makes re-picking a name that is already here
  /// *likely* rather than rare, and an unconditional insert would answer "that one" with a second
  /// machine holding no history -- unrecoverable, because #10 forbids merging them back.
  @Test("A name already at this gym resolves to that machine instead of creating a second")
  func nameAlreadyHereResolves() throws {
    let (gyms, _, press) = try fixture()
    let gym = try gyms.createGym(name: "PureGym Holloway", now: now)
    let original = try gyms.createMachine(at: gym, name: "Cybex Leg Press", now: now)

    let resolved = try gyms.resolveMachine(at: gym, named: "Cybex Leg Press", forExercise: press)
    #expect(resolved.id == original)
    #expect(resolved.created == false)
    #expect(try gyms.machines(at: gym).count == 1, "No second row for one physical machine.")
  }

  /// A lifter typing at a rack does not reproduce capitalisation or spacing. Treating those as
  /// different machines is precisely how a typo becomes a permanent second history.
  @Test("Matching ignores case and extra spacing")
  func matchingIsForgiving() throws {
    let (gyms, _, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym Holloway", now: now)
    let original = try gyms.createMachine(at: gym, name: "Hammer Strength Row", now: now)

    #expect(try gyms.existingMachine(named: "hammer  strength   row", at: gym) == original)
    #expect(try gyms.existingMachine(named: "  HAMMER STRENGTH ROW  ", at: gym) == original)
    let resolved = try gyms.resolveMachine(at: gym, named: "hammer strength row")
    #expect(resolved.created == false)
    #expect(try gyms.machines(at: gym).count == 1)
  }

  /// Invariant #10. Two Nautilus chest presses in two buildings are two machines with two
  /// histories, and no convenience feature may quietly join them.
  @Test("The same name at a different gym is a different machine, with its own empty history")
  func sameNameAtAnotherGymIsANewMachine() throws {
    let (gyms, logger, press) = try fixture()
    let holloway = try gyms.createGym(name: "PureGym Holloway", now: now)
    let angel = try gyms.createGym(name: "PureGym Angel", now: now)
    let atHolloway = try gyms.createMachine(at: holloway, name: "Cybex Leg Press", now: now)

    let session = try logger.startSession(gymID: holloway, at: now)
    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: atHolloway,
      draft: SetEntryDraft(weightKg: 140, reps: 8), isWarmup: false, at: now
    )

    let resolved = try gyms.resolveMachine(at: angel, named: "Cybex Leg Press")
    #expect(resolved.created, "A machine in another building is a different machine.")
    #expect(resolved.id != atHolloway)

    // And its history really does start empty, which is the claim the sheet makes to the lifter.
    let atAngel = try #require(try gyms.machineLibrary(at: angel).first)
    #expect(atAngel.workingSetCount == 0)
    #expect(atAngel.heaviestKg == nil)
    let stillAtHolloway = try #require(try gyms.machineLibrary(at: holloway).first)
    #expect(stillAtHolloway.heaviestKg == 140)
  }

  @Test("Names already at this gym are offered first, and the list is deterministic")
  func orderingIsStable() throws {
    let (gyms, _, _) = try fixture()
    let here = try gyms.createGym(name: "Here", now: now)
    let there = try gyms.createGym(name: "There", now: now)
    _ = try gyms.createMachine(at: there, name: "Alpha Machine", now: now)
    _ = try gyms.createMachine(at: here, name: "Zulu Machine", now: now)

    // Alphabetically Alpha comes first, but it is not here -- and only a name that is here can
    // resolve rather than create, so it leads.
    let names = try gyms.machineNameSuggestions(at: here).map(\.name)
    #expect(names == ["Zulu Machine", "Alpha Machine"])
    // Stable across calls: a dictionary's order is not, and a list that reshuffles between
    // presentations is unusable.
    #expect(try gyms.machineNameSuggestions(at: here).map(\.name) == names)
  }

  @Test("An archived machine is not offered, and does not block re-adding its name")
  func archivedNamesAreNotOffered() throws {
    let (gyms, _, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym Holloway", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Cybex Leg Press", now: now)
    try gyms.setMachineArchived(true, for: machine)

    #expect(try gyms.machineNameSuggestions(at: gym).isEmpty)
    #expect(try gyms.existingMachine(named: "Cybex Leg Press", at: gym) == nil)
    // Re-adding creates a live machine rather than silently reviving the archived one, which would
    // be a surprising resurrection of a history the lifter put away.
    #expect(try gyms.resolveMachine(at: gym, named: "Cybex Leg Press").created)
  }

  /// The association is free at the moment a machine is named from inside an exercise's picker and
  /// unrecoverable afterwards, so resolving to an existing machine must still record it.
  @Test("Resolving to an existing machine still records what it is equipment for")
  func resolvingStillLinksTheExercise() throws {
    let (gyms, _, press) = try fixture()
    let gym = try gyms.createGym(name: "PureGym Holloway", now: now)
    _ = try gyms.createMachine(at: gym, name: "Cybex Leg Press", now: now)

    _ = try gyms.resolveMachine(at: gym, named: "Cybex Leg Press", forExercise: press)
    #expect(try gyms.exercisesWithEquipment(at: gym).contains(press))
    #expect(try gyms.machineLibrary(at: gym).first?.linkedExerciseNames == ["Leg Press"])
  }
}
