import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Plans persist, reshape, and add equipment to the gym's library on the way past.
@Suite("A plan persists, reshapes, and teaches the library what equipment exists")
struct SplitStoreTests {
  let now = Date(timeIntervalSince1970: 16_000_000)

  private func migratedDatabase() throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return queue
  }

  private struct Fixture {
    let database: any DatabaseWriter
    let splits: SplitStore
    let gyms: GymStore
    let bench: ExerciseID
    let squat: ExerciseID
    let curl: ExerciseID
  }

  private func fixture() throws -> Fixture {
    let database = try migratedDatabase()
    let bench = ExerciseID()
    let squat = ExerciseID()
    let curl = ExerciseID()
    try database.write { db in
      for (id, name) in [(bench, "Bench Press"), (squat, "Back Squat"), (curl, "Barbell Curl")] {
        try Exercise.insert { Exercise.Draft(id: id.rawValue, name: name) }.execute(db)
      }
    }
    return Fixture(
      database: database,
      splits: SplitStore(database: database),
      gyms: GymStore(database: database),
      bench: bench, squat: squat, curl: curl
    )
  }

  // MARK: - Plans, days, entries

  @Test("A plan can be created, named, read back and archived")
  func lifecycle() throws {
    let f = try fixture()
    let id = try f.splits.createSplit(name: "Upper / Lower", now: now)
    #expect(try f.splits.splits().map(\.name) == ["Upper / Lower"])

    try f.splits.renameSplit(id, to: "Full body")
    #expect(try f.splits.split(id)?.name == "Full body")

    try f.splits.archiveSplit(id)
    #expect(try f.splits.splits().isEmpty)
    // Archived, not deleted -- it comes back.
    try f.splits.unarchiveSplit(id)
    #expect(try f.splits.splits().map(\.name) == ["Full body"])
  }

/// A soft delete with no way back is worse than a hard one: the rows keep syncing to iCloud while
  /// the lifter has been told the plan is gone. So archiving has to be a round trip, and the list of
  /// archived plans is what makes the restore path reachable at all.
  @Test("An archived plan is listed as archived and can be brought back")
  func archivingIsARoundTrip() throws {
    let f = try fixture()
    let keep = try f.splits.createSplit(name: "Upper / Lower", now: now)
    let away = try f.splits.createSplit(name: "Old PPL", now: now)

    try f.splits.archiveSplit(away)

    #expect(try f.splits.splits().map(\.name) == ["Upper / Lower"])
    #expect(try f.splits.archivedSplits().map(\.name) == ["Old PPL"])
    // The archived plan is still readable by id -- it was put away, not deleted.
    #expect(try f.splits.split(away)?.name == "Old PPL")

    try f.splits.unarchiveSplit(away)
    #expect(try f.splits.archivedSplits().isEmpty)
    #expect(Set(try f.splits.splits().map(\.name)) == ["Upper / Lower", "Old PPL"])
    _ = keep
  }

  /// Putting a plan away must not take its days and movements with it, or "bring it back" returns an
  /// empty shell and the round trip is a lie.
  @Test("Archiving keeps the plan's days and movements intact")
  func archivingPreservesContents() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    try f.splits.addEntry(to: day, exercise: f.bench, now: now)

    try f.splits.archiveSplit(split)
    try f.splits.unarchiveSplit(split)

    let restored = try f.splits.plan(for: split)
    #expect(restored.dayCount == 1)
    #expect(restored.allMovements == [f.bench])
  }

    @Test("An empty rename is refused rather than blanking the name")
  func emptyRenameRefused() throws {
    let f = try fixture()
    let id = try f.splits.createSplit(name: "PPL", now: now)
    try f.splits.renameSplit(id, to: "   ")
    #expect(try f.splits.split(id)?.name == "PPL")
  }

  @Test("Days are appended in order and read back by position")
  func daysAreOrdered() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    for name in ["Day 1", "Day 2", "Day 3"] {
      try f.splits.addDay(to: split, name: name, now: now)
    }
    let days = try f.splits.days(in: split)
    #expect(days.map(\.name) == ["Day 1", "Day 2", "Day 3"])
    #expect(days.map(\.position) == [0, 1, 2])
  }

  /// Two days may legitimately share a name, so position is the only ordering. A store that
  /// ordered by name would silently reorder someone's week.
  @Test("Two days may share a name and still keep their order")
  func duplicateDayNames() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let first = try f.splits.addDay(to: split, name: "Full body", now: now)
    let second = try f.splits.addDay(to: split, name: "Full body", now: now)
    let days = try f.splits.days(in: split)
    #expect(days.count == 2)
    #expect(days.map(\.id) == [first, second])
  }

  @Test("Deleting a day takes its entries and closes the gap in positions")
  func deletingADayCompacts() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let one = try f.splits.addDay(to: split, name: "A", now: now)
    let two = try f.splits.addDay(to: split, name: "B", now: now)
    let three = try f.splits.addDay(to: split, name: "C", now: now)
    try f.splits.addEntry(to: two, exercise: f.bench, now: now)

    try f.splits.deleteDay(two)

    let days = try f.splits.days(in: split)
    #expect(days.map(\.id) == [one, three])
    // Contiguous, so nothing renders "Day 1, Day 3".
    #expect(days.map(\.position) == [0, 1])
    // The entry went with it rather than being orphaned.
    let orphans = try f.database.read { db in try SplitEntry.fetchAll(db) }
    #expect(orphans.isEmpty)
  }

  @Test("Entries are appended in order, and removing one closes the gap")
  func entriesAreOrdered() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "A", now: now)
    let first = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    let second = try f.splits.addEntry(to: day, exercise: f.squat, now: now)
    let third = try f.splits.addEntry(to: day, exercise: f.curl, now: now)

    #expect(try f.splits.entries(in: day).map(\.position) == [0, 1, 2])

    try f.splits.removeEntry(second)
    let remaining = try f.splits.entries(in: day)
    #expect(remaining.map(\.id) == [first, third])
    #expect(remaining.map(\.position) == [0, 1])
  }

  // MARK: - Reshaping, which is the whole interaction

  /// The dealer's arrangement is a starting point, not a verdict, so moving a movement between days
  /// is the interaction the feature exists for.
  @Test("A movement moves between days and lands where it was dropped")
  func moveBetweenDays() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let dayA = try f.splits.addDay(to: split, name: "A", now: now)
    let dayB = try f.splits.addDay(to: split, name: "B", now: now)
    let bench = try f.splits.addEntry(to: dayA, exercise: f.bench, now: now)
    try f.splits.addEntry(to: dayA, exercise: f.squat, now: now)
    try f.splits.addEntry(to: dayB, exercise: f.curl, now: now)

    // Drop the bench at the very top of day B.
    try f.splits.moveEntry(bench, toDay: dayB, at: 0)

    let a = try f.splits.entries(in: dayA)
    let b = try f.splits.entries(in: dayB)
    #expect(a.map(\.exerciseID) == [f.squat])
    #expect(a.map(\.position) == [0], "the origin day did not close its gap")
    #expect(b.map(\.exerciseID) == [f.bench, f.curl])
    #expect(b.map(\.position) == [0, 1])
  }

  @Test("A movement reorders within its own day without counting itself twice")
  func reorderWithinADay() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "A", now: now)
    let bench = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    try f.splits.addEntry(to: day, exercise: f.squat, now: now)
    try f.splits.addEntry(to: day, exercise: f.curl, now: now)

    try f.splits.moveEntry(bench, toDay: day, at: 2)

    let entries = try f.splits.entries(in: day)
    #expect(entries.map(\.exerciseID) == [f.squat, f.curl, f.bench])
    #expect(entries.map(\.position) == [0, 1, 2])
    #expect(entries.count == 3, "the moved entry was duplicated or lost")
  }

  @Test("A position past the end appends rather than failing")
  func outOfRangePositionIsClamped() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let dayA = try f.splits.addDay(to: split, name: "A", now: now)
    let dayB = try f.splits.addDay(to: split, name: "B", now: now)
    let bench = try f.splits.addEntry(to: dayA, exercise: f.bench, now: now)
    try f.splits.addEntry(to: dayB, exercise: f.curl, now: now)

    try f.splits.moveEntry(bench, toDay: dayB, at: 99)
    #expect(try f.splits.entries(in: dayB).map(\.exerciseID) == [f.curl, f.bench])

    try f.splits.moveEntry(bench, toDay: dayB, at: -5)
    #expect(try f.splits.entries(in: dayB).map(\.exerciseID) == [f.bench, f.curl])
  }

  // MARK: - Naming a machine adds it to the library

  /// The payoff the join table was built for. `exercisesWithEquipment(at:)` is what lets the picker
  /// know a gym has equipment for a movement *before* anything has been logged there, and planning a
  /// split is the earliest moment that association can be recorded.
  @Test("Naming a machine in a plan adds it to that gym's library for the movement")
  func planningNamesEquipment() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "PureGym", now: now)
    let machine = try f.gyms.createMachine(at: gym, name: "Hammer Strength Bench", now: now)

    // Nothing logged yet, and the machine was created without naming a movement.
    #expect(try f.gyms.exercisesWithEquipment(at: gym).isEmpty)

    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    try f.splits.addEntry(to: day, exercise: f.bench, machine: machine, now: now)

    // The library now knows this gym can do a bench press, with no set ever logged.
    #expect(try f.gyms.exercisesWithEquipment(at: gym) == [f.bench])
  }

  /// No UNIQUE constraint is permitted on a synchronized table, so idempotency is by hand and has
  /// to be tested rather than assumed.
  @Test("Naming the same machine twice does not duplicate the library association")
  func libraryLinkIsIdempotent() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "PureGym", now: now)
    let machine = try f.gyms.createMachine(at: gym, name: "Bench", now: now)
    let split = try f.splits.createSplit(name: "Week", now: now)
    let dayA = try f.splits.addDay(to: split, name: "A", now: now)
    let dayB = try f.splits.addDay(to: split, name: "B", now: now)

    try f.splits.addEntry(to: dayA, exercise: f.bench, machine: machine, now: now)
    try f.splits.addEntry(to: dayB, exercise: f.bench, machine: machine, now: now)

    let links = try f.database.read { db in try MachineExercise.fetchAll(db) }
    #expect(links.count == 1, "the same machine-movement pair was recorded twice")
    #expect(try f.gyms.exercisesWithEquipment(at: gym) == [f.bench])
  }

  @Test("Naming a machine for a movement already planned also adds it to the library")
  func setMachineAfterwardsLinks() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "PureGym", now: now)
    let machine = try f.gyms.createMachine(at: gym, name: "Bench", now: now)
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "A", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, now: now)

    #expect(try f.gyms.exercisesWithEquipment(at: gym).isEmpty)
    try f.splits.setMachine(machine, forEntry: entry, now: now)

    #expect(try f.splits.entries(in: day).first?.machineID == machine)
    #expect(try f.gyms.exercisesWithEquipment(at: gym) == [f.bench])
  }

  /// `machineID` is SET NULL rather than CASCADE: retiring equipment must not delete the movement
  /// from someone's plan.
  @Test("Deleting a machine leaves the movement in the plan without its machine")
  func machineDeletionKeepsTheMovement() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "PureGym", now: now)
    let machine = try f.gyms.createMachine(at: gym, name: "Bench", now: now)
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "A", now: now)
    try f.splits.addEntry(to: day, exercise: f.bench, machine: machine, now: now)

    try f.database.write { db in
      try Machine.where { $0.id.eq(machine.rawValue) }.delete().execute(db)
    }

    let entries = try f.splits.entries(in: day)
    #expect(entries.count == 1, "retiring a machine deleted the movement from the plan")
    #expect(entries.first?.machineID == nil)
  }

  // MARK: - Whole-plan round trip

  @Test("A dealt plan is written and read back unchanged")
  func planRoundTrip() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench, f.curl]),
      SplitPlanDay(position: 1, name: "Day 2", movements: [f.squat]),
    ])

    try f.splits.replace(split, with: plan, now: now)
    let loaded = try f.splits.plan(for: split)

    #expect(loaded == plan)
  }

  /// Re-dealing replaces the arrangement. The movements are the lifter's either way, so nothing
  /// they logged is at risk -- but the plan must actually be replaced, not appended to.
  @Test("Re-dealing replaces the previous arrangement rather than adding to it")
  func replaceIsNotAppend() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    try f.splits.replace(
      split,
      with: SplitPlan(days: [
        SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench, f.squat, f.curl])
      ]),
      now: now
    )
    try f.splits.replace(
      split,
      with: SplitPlan(days: [
        SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench]),
        SplitPlanDay(position: 1, name: "Day 2", movements: [f.squat]),
        SplitPlanDay(position: 2, name: "Day 3", movements: [f.curl]),
      ]),
      now: now
    )

    let loaded = try f.splits.plan(for: split)
    #expect(loaded.dayCount == 3)
    #expect(loaded.movementCount == 3)
    let rows = try f.database.read { db in try SplitEntry.fetchAll(db) }
    #expect(rows.count == 3, "the previous arrangement's entries survived a replace")
  }

  @Test("An empty plan reads back as no days rather than throwing")
  func emptyPlanRoundTrip() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let loaded = try f.splits.plan(for: split)
    #expect(loaded.dayCount == 0)
    #expect(loaded.movementCount == 0)
  }

  // MARK: - Starting a day

  /// The one path from planning into the app's core loop. Without it the planner is a document.
  @Test("A day becomes today's plan, in order, carrying its machines")
  func dayBecomesAPlan() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "PureGym", now: now)
    let machine = try f.gyms.createMachine(
      at: gym, name: "Hammer Strength Bench", stackIncrementKg: 5, now: now
    )
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    try f.splits.addEntry(to: day, exercise: f.bench, machine: machine, now: now)
    try f.splits.addEntry(to: day, exercise: f.curl, now: now)

    let plan = try f.splits.plannedExercises(for: day)

    #expect(plan.map(\.exerciseID) == [f.bench, f.curl])
    #expect(plan.map(\.exerciseName) == ["Bench Press", "Barbell Curl"])
    #expect(plan[0].machineID == machine)
    #expect(plan[0].machineName == "Hammer Strength Bench")
    // Carried so a progression suggestion cannot propose a step the equipment will not honour.
    #expect(plan[0].machineIncrementKg == 5)
    #expect(plan[1].machineID == nil)
  }

  /// The invariant that makes this path safe. `VolumeStore.plan(for:)` carries a set count because a
  /// past workout has one; a split day does not, and `RepeatableExercise.workingSets` being
  /// non-optional is why this returns `PlannedExercise` directly instead. A number here would be a
  /// prescription entering the logger by the back door.
  @Test("Every movement from a plan has no set count")
  func plansCarryNoSetCounts() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    for exercise in [f.bench, f.squat, f.curl] {
      try f.splits.addEntry(to: day, exercise: exercise, now: now)
    }

    let plan = try f.splits.plannedExercises(for: day)
    #expect(plan.count == 3)
    for movement in plan {
      #expect(movement.plannedSets == nil, "\(movement.exerciseName) arrived with a set count")
    }
  }

  /// Modality has to survive the hop, or a planned pull-up opens as a loaded row demanding a weight
  /// -- a defect the "do it again" path already shipped once.
  @Test("A bodyweight movement stays bodyweight on the way into a session")
  func modalitySurvives() throws {
    let f = try fixture()
    let pullUp = ExerciseID()
    try f.database.write { db in
      try Exercise.insert {
        Exercise.Draft(id: pullUp.rawValue, name: "Pull-Up", modality: "bodyweight")
      }
      .execute(db)
    }
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Pull", now: now)
    try f.splits.addEntry(to: day, exercise: pullUp, now: now)

    let plan = try f.splits.plannedExercises(for: day)
    #expect(plan.first?.modality == .bodyweight)
  }

  @Test("An empty day yields an empty plan rather than throwing")
  func emptyDayYieldsEmptyPlan() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Rest", now: now)
    #expect(try f.splits.plannedExercises(for: day).isEmpty)
  }

  /// Reordering the day reorders the workout. The plan is what the lifter arranged, so the session
  /// must open in that order rather than in insertion order.
  @Test("Moving a movement changes the order the workout opens in")
  func planFollowsTheArrangedOrder() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let bench = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    try f.splits.addEntry(to: day, exercise: f.squat, now: now)
    try f.splits.addEntry(to: day, exercise: f.curl, now: now)

    try f.splits.moveEntry(bench, toDay: day, at: 2)

    let plan = try f.splits.plannedExercises(for: day)
    #expect(plan.map(\.exerciseID) == [f.squat, f.curl, f.bench])
  }

  /// The dealer must be fed the lifter's own movements. Anything else and the plan is recommending
  /// exercises rather than arranging them.
  @Test("The movements offered to the dealer are ones the lifter actually logged")
  func loggedMovementsAreTheInput() throws {
    let f = try fixture()
    let logger = LoggerStore(database: f.database)
    let session = try logger.startSession(at: now)
    _ = try logger.logSet(
      sessionID: session,
      exerciseID: f.bench,
      draft: SetEntryDraft(weightKg: 60, reps: 10),
      at: now
    )

    let movements = try f.splits.loggedMovements()
    #expect(movements == [f.bench])
    // The squat was never logged, so it is not offered.
    #expect(!movements.contains(f.squat))
  }
}
