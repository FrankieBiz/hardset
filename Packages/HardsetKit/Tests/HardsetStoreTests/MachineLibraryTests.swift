import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Reviewing the machines you have named, outside a workout.
///
/// Machines could only ever be created inside a session. That is the right primary path — the
/// ancestor app's setup flow went uncompleted and every set after it logged against nothing — but
/// it left no way to see what you had named, fix a typo, set a stack step you learned later, or
/// find the duplicate a mistyped name created.
@Suite("The machine library says what each machine is and what you press on it")
struct MachineLibraryTests {
  let now = Date(timeIntervalSince1970: 16_000_000)

  private func fixture() throws -> (GymStore, LoggerStore, ExerciseID, ExerciseID) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    let press = ExerciseID()
    let row = ExerciseID()
    try queue.write { db in
      try Exercise.insert { Exercise.Draft(id: press.rawValue, name: "Leg Press") }.execute(db)
      try Exercise.insert { Exercise.Draft(id: row.rawValue, name: "Chest Supported Row") }
        .execute(db)
    }
    return (GymStore(database: queue), LoggerStore(database: queue), press, row)
  }

  @Test("A machine reports the movements it is equipment for")
  func reportsLinkedMovements() throws {
    let (gyms, _, press, row) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Hammer Leg Press", forExercise: press, now: now)
    try gyms.linkMachine(machine, toExercise: row, now: now)

    let entry = try #require(try gyms.machineLibrary(at: gym).first)
    #expect(entry.linkedExerciseNames == ["Chest Supported Row", "Leg Press"])
  }

  @Test("A machine reports its heaviest working set and when it was last used")
  func reportsBestAndLastUsed() throws {
    let (gyms, logger, press, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Hammer Leg Press", now: now)
    let session = try logger.startSession(gymID: gym, at: now)

    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), isWarmup: false, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 120, reps: 5), isWarmup: false,
      at: now.addingTimeInterval(300)
    )
    try logger.finishSession(session, at: now.addingTimeInterval(3600))

    let entry = try #require(try gyms.machineLibrary(at: gym).first)
    #expect(entry.heaviestKg == 120)
    #expect(entry.heaviestReps == 5)
    #expect(entry.workingSetCount == 2)
    #expect(entry.lastUsed == now.addingTimeInterval(300))
    #expect(!entry.isUnused)
  }

  /// The same exclusion the progression chart makes. A warm-up is not a heaviest load, and a drop
  /// set's reduced weight is not a lighter attempt at the same thing.
  @Test("Warm-ups and drop sets are not the best set, and are not counted as working")
  func warmupsAndDropsExcluded() throws {
    let (gyms, logger, press, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Hammer Leg Press", now: now)
    let session = try logger.startSession(gymID: gym, at: now)

    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 200, reps: 1), kind: .warmup, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 180, reps: 3), kind: .drop,
      at: now.addingTimeInterval(60)
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 8), kind: .working,
      at: now.addingTimeInterval(120)
    )

    let entry = try #require(try gyms.machineLibrary(at: gym).first)
    #expect(entry.heaviestKg == 100, "A 200 kg warm-up single is not a best set.")
    #expect(entry.workingSetCount == 1)
    // `lastUsed` deliberately counts any set: the question is "when was I last at this machine",
    // and a warm-up means you were there.
    #expect(entry.lastUsed == now.addingTimeInterval(120))
  }

  /// Otherwise the reported best depends on the order rows come back in, which is not a fact about
  /// the lifter's training.
  @Test("A tie on load breaks on reps, not on row order")
  func tieBreaksOnReps() throws {
    let (gyms, logger, press, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Hammer Leg Press", now: now)
    let session = try logger.startSession(gymID: gym, at: now)

    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 10), isWarmup: false, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: machine,
      draft: SetEntryDraft(weightKg: 100, reps: 6), isWarmup: false,
      at: now.addingTimeInterval(300)
    )

    let entry = try #require(try gyms.machineLibrary(at: gym).first)
    #expect(entry.heaviestReps == 10)
  }

  /// Usually a duplicate created by a typo. The library is where a lifter finds it, so it has to be
  /// distinguishable from a machine that is simply new.
  @Test("A machine named and never trained on reads as unused")
  func neverUsedIsVisible() throws {
    let (gyms, _, _, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    _ = try gyms.createMachine(at: gym, name: "Nautilus Pullover", now: now)

    let entry = try #require(try gyms.machineLibrary(at: gym).first)
    #expect(entry.isUnused)
    #expect(entry.lastUsed == nil)
    #expect(entry.heaviestKg == nil)
  }

  /// Archiving from a review screen has to be reversible. Invariant #10 forbids merging two
  /// machines' history, so there is no second route back to what an archived row owns.
  @Test("A machine can be put away and brought back")
  func archiveIsReversible() throws {
    let (gyms, _, _, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let machine = try gyms.createMachine(at: gym, name: "Cybex Row", now: now)

    try gyms.setMachineArchived(true, for: machine)
    #expect(try gyms.machines(at: gym).isEmpty, "Archived machines leave the pickers.")
    #expect(try gyms.machineLibrary(at: gym).first?.isArchived == true)
    #expect(try gyms.machineLibrary(at: gym, includeArchived: false).isEmpty)

    try gyms.setMachineArchived(false, for: machine)
    #expect(try gyms.machines(at: gym).count == 1)
    #expect(try gyms.machineLibrary(at: gym).first?.isArchived == false)
  }

  /// Two machines at one gym never pool their sets. This is the invariant the whole app is built
  /// on, and a library that summed across them would contradict the chart.
  @Test("Two machines keep two histories")
  func historiesNeverMerge() throws {
    let (gyms, logger, press, _) = try fixture()
    let gym = try gyms.createGym(name: "PureGym", now: now)
    let hammer = try gyms.createMachine(at: gym, name: "Hammer Leg Press", now: now)
    let cybex = try gyms.createMachine(at: gym, name: "Cybex Leg Press", now: now)
    let session = try logger.startSession(gymID: gym, at: now)

    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: hammer,
      draft: SetEntryDraft(weightKg: 140, reps: 8), isWarmup: false, at: now
    )
    _ = try logger.logSet(
      sessionID: session, exerciseID: press, machineID: cybex,
      draft: SetEntryDraft(weightKg: 80, reps: 8), isWarmup: false,
      at: now.addingTimeInterval(600)
    )

    let library = try gyms.machineLibrary(at: gym)
    let byName = Dictionary(uniqueKeysWithValues: library.map { ($0.name, $0) })
    #expect(byName["Hammer Leg Press"]?.heaviestKg == 140)
    #expect(byName["Cybex Leg Press"]?.heaviestKg == 80)
    #expect(byName["Hammer Leg Press"]?.workingSetCount == 1)
    #expect(byName["Cybex Leg Press"]?.workingSetCount == 1)
  }
}
