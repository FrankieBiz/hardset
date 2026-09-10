import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// What the lifter authors about a plan, and what must survive the app rearranging it.
///
/// The theme of every test here is the same: a plan holds decisions the lifter made — which machine,
/// how many sets, what the day is called, what order it reads in — and the app may move movements
/// between days without discarding any of them. Re-dealing used to discard most of them silently.
@Suite("A plan keeps what the lifter authored")
struct PlanAuthoringTests {
  private let now = Date(timeIntervalSince1970: 19_000_000)

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
    let exercises: ExerciseStore
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
      exercises: ExerciseStore(database: database),
      bench: bench, squat: squat, curl: curl
    )
  }

  // MARK: - The lifter's own set counts

  @Test("An intended set count is recorded, and absent until the lifter says one")
  func targetSetsRoundTrips() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, now: now)

    // The default is silence. Nothing derives a number from history or supplies one.
    #expect(try f.splits.entries(in: day).first?.targetSets == nil)

    try f.splits.setTargetSets(4, forEntry: entry)
    #expect(try f.splits.entries(in: day).first?.targetSets == 4)
  }

  /// "I have not said" has to stay reachable, or the column stops being optional in practice.
  @Test("An intended set count can be cleared again")
  func targetSetsClears() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    try f.splits.setTargetSets(3, forEntry: entry)

    try f.splits.setTargetSets(nil, forEntry: entry)
    #expect(try f.splits.entries(in: day).first?.targetSets == nil)

    // Zero and negatives are the same statement as "not set", said less clearly.
    try f.splits.setTargetSets(0, forEntry: entry)
    #expect(try f.splits.entries(in: day).first?.targetSets == nil)
    try f.splits.setTargetSets(-2, forEntry: entry)
    #expect(try f.splits.entries(in: day).first?.targetSets == nil)
  }

  @Test("An absurd set count is capped rather than stored")
  func targetSetsCaps() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, now: now)

    try f.splits.setTargetSets(9_999, forEntry: entry)
    #expect(try f.splits.entries(in: day).first?.targetSets == SplitStore.maximumTargetSets)
  }

  /// The hop the column exists for. `PlannedExercise.plannedSets` was already `Int?` and
  /// `sessionExercises.plannedSets` already existed, so the logger opens with the lifter's own count.
  @Test("An intended set count reaches the workout the day starts")
  func targetSetsReachTheSession() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let benched = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.curl, now: now)
    try f.splits.setTargetSets(5, forEntry: benched)

    let plan = try f.splits.plannedExercises(for: day)
    #expect(plan.count == 2)
    #expect(plan[0].plannedSets == 5)
    // Said nothing, so still nothing: the rows come from history, and the app authors no number.
    #expect(plan[1].plannedSets == nil)
  }

  // MARK: - Re-dealing keeps what the lifter authored

  @Test("Re-dealing keeps the machines the lifter named")
  func redealKeepsMachines() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Iron Works", now: now)
    let machine = try f.gyms.createMachine(at: gym, name: "Hammer Bench", now: now)
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, machine: machine, now: now)
    try f.splits.setTargetSets(3, forEntry: entry)

    // Dealt into a different number of days, so every entry row is rewritten.
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench]),
      SplitPlanDay(position: 1, name: "Day 2", movements: []),
    ])
    try f.splits.replace(split, with: plan, now: now)

    let days = try f.splits.days(in: split)
    let carried = try f.splits.entries(in: days[0].id).first
    #expect(carried?.machineID == machine)
    #expect(carried?.targetSets == 3)
  }

  @Test("Re-dealing keeps the names the lifter gave the days")
  func redealKeepsDayNames() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let first = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addDay(to: split, name: "Pull", now: now)
    _ = try f.splits.addEntry(to: first, exercise: f.bench, now: now)

    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench]),
      SplitPlanDay(position: 1, name: "Day 2", movements: [f.squat]),
      SplitPlanDay(position: 2, name: "Day 3", movements: [f.curl]),
    ])
    try f.splits.replace(split, with: plan, now: now)

    // The two the lifter named survive by position; the day that did not exist takes the
    // placeholder, because there is no name of theirs to keep.
    #expect(try f.splits.days(in: split).map(\.name) == ["Push", "Pull", "Day 3"])
  }

  /// Two entries for one movement on two machines must both survive, or a plan that deliberately
  /// repeats a lift loses half of what the lifter said about it.
  @Test("A movement planned twice keeps both of its machines")
  func redealKeepsRepeatedMovements() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Iron Works", now: now)
    let first = try f.gyms.createMachine(at: gym, name: "Hammer Bench", now: now)
    let second = try f.gyms.createMachine(at: gym, name: "Cybex Press", now: now)
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.bench, machine: first, now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.bench, machine: second, now: now)

    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench, f.bench])
    ])
    try f.splits.replace(split, with: plan, now: now)

    let days = try f.splits.days(in: split)
    #expect(try f.splits.entries(in: days[0].id).compactMap(\.machineID) == [first, second])
  }

  @Test("Re-dealing keeps settings on the correct repeated occurrence")
  func redealKeepsAnUnconfiguredOccurrenceAheadOfAConfiguredOne() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "Iron Works", now: now)
    let machine = try f.gyms.createMachine(at: gym, name: "Cybex Press", now: now)
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.bench, machine: machine, now: now)

    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.bench, f.bench])
    ])
    try f.splits.replace(split, with: plan, now: now)

    let entries = try f.splits.entries(in: day)
    #expect(entries.map(\.machineID) == [nil, machine])
  }

  // MARK: - Day order

  /// Day order is the order the plan reads in, and the tie-break `SplitRotation` uses. Days could be
  /// added, renamed and deleted, and never moved.
  @Test("A day can be moved within its plan")
  func daysReorder() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let push = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addDay(to: split, name: "Pull", now: now)
    _ = try f.splits.addDay(to: split, name: "Legs", now: now)

    try f.splits.moveDay(push, to: 2)
    #expect(try f.splits.days(in: split).map(\.name) == ["Pull", "Legs", "Push"])

    try f.splits.moveDay(push, to: 0)
    #expect(try f.splits.days(in: split).map(\.name) == ["Push", "Pull", "Legs"])
  }

  @Test("Moving a day leaves positions dense and clamps an out-of-range target")
  func dayPositionsStayDense() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let push = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addDay(to: split, name: "Pull", now: now)

    try f.splits.moveDay(push, to: 99)
    let days = try f.splits.days(in: split)
    #expect(days.map(\.name) == ["Pull", "Push"])
    #expect(days.map(\.position) == [0, 1])

    try f.splits.moveDay(push, to: -5)
    #expect(try f.splits.days(in: split).map(\.name) == ["Push", "Pull"])
  }

  @Test("Moving a day never touches another plan")
  func movingADayIsScopedToItsPlan() throws {
    let f = try fixture()
    let mine = try f.splits.createSplit(name: "Mine", now: now)
    let other = try f.splits.createSplit(name: "Other", now: now)
    let a = try f.splits.addDay(to: mine, name: "A", now: now)
    _ = try f.splits.addDay(to: mine, name: "B", now: now)
    _ = try f.splits.addDay(to: other, name: "X", now: now)
    _ = try f.splits.addDay(to: other, name: "Y", now: now)

    try f.splits.moveDay(a, to: 1)
    #expect(try f.splits.days(in: mine).map(\.name) == ["B", "A"])
    #expect(try f.splits.days(in: other).map(\.name) == ["X", "Y"])
  }

  // MARK: - Movements the lifter retired

  /// Marked, never removed. Archiving is a soft delete, so nothing takes the movement out of the
  /// plan — but the picker stops offering it, so the plan has to be able to say so.
  @Test("A retired movement is reported without being removed from the plan")
  func retiredMovementsAreReported() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "Week", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.curl, now: now)

    #expect(try f.splits.retiredMovements(in: day).isEmpty)

    try f.exercises.setArchived(true, for: f.curl)

    #expect(try f.splits.retiredMovements(in: day) == [f.curl])
    // Still in the plan, and still startable. The app reports; it does not edit.
    #expect(try f.splits.entries(in: day).count == 2)
    #expect(try f.splits.plannedExercises(for: day).count == 2)
  }

  /// A retired movement still has a name, and the plan must use it.
  ///
  /// `selectableExercises()` excludes archived rows, so a planner building its rows only from that
  /// list rendered a retired movement as "Unknown movement / Not attributed" — a movement the lifter
  /// named, reported as though the app had never heard of it. Found by archiving one and looking.
  @Test("A retired movement can still be named by id")
  func retiredMovementsCanStillBeNamed() throws {
    let f = try fixture()
    let catalog = CatalogSeeder(database: f.database)
    try f.exercises.setArchived(true, for: f.curl)

    let selectable = try catalog.selectableExercises().map(\.id)
    #expect(!selectable.contains(f.curl))

    // Looked up by id, which does not filter on archived.
    let named = try catalog.entries(for: [f.bench, f.curl])
    #expect(named.count == 2)
    #expect(named.first { $0.id == f.curl }?.name == "Barbell Curl")
  }
}
