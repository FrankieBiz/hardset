import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing

@testable import HardsetStore

/// Changing which movement a planned slot holds, without losing the slot.
///
/// Remove-and-re-add was the only route, and it is a different operation: it appends at the bottom
/// of the day and forgets the intended sets. Correcting a movement therefore cost the lifter the two
/// things they had authored about that slot, which is why this exists.
@Suite("A planned slot can change its movement and keep its place")
struct SplitEntrySwapTests {
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

  @Test("Swapping keeps the slot's position rather than appending a new one")
  func swapKeepsPosition() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "PPL", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    let middle = try f.splits.addEntry(to: day, exercise: f.squat, now: now)
    _ = try f.splits.addEntry(to: day, exercise: f.curl, now: now)

    try f.splits.setExercise(f.bench, forEntry: middle)

    let entries = try f.splits.entries(in: day)
    #expect(entries.map(\.position) == [0, 1, 2])
    // Still the second row, and still the same entry -- not a removal plus an append.
    #expect(entries[1].id == middle)
    #expect(entries[1].exerciseID == f.bench)
    #expect(entries.count == 3)
  }

  @Test("Swapping keeps the sets the lifter said they intend")
  func swapKeepsTargetSets() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "PPL", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, now: now)
    try f.splits.setTargetSets(4, forEntry: entry)

    try f.splits.setExercise(f.squat, forEntry: entry)

    let swapped = try #require(try f.splits.entries(in: day).first)
    #expect(swapped.exerciseID == f.squat)
    // The intended sets are a statement about the slot, not about the movement that was in it.
    #expect(swapped.targetSets == 4)
  }

  @Test("Swapping clears the machine, because the binding was about the old movement")
  func swapClearsMachine() throws {
    let f = try fixture()
    let gym = try f.gyms.createGym(name: "PureGym Holloway", now: now)
    let machine = try f.gyms.resolveMachine(at: gym, named: "Hammer Strength", forExercise: f.bench)
    let split = try f.splits.createSplit(name: "PPL", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, machine: machine.id, now: now)
    #expect(try f.splits.entries(in: day).first?.machineID == machine.id)

    try f.splits.setExercise(f.squat, forEntry: entry)

    // Load history is keyed to exercise x machine. Carrying the binding across would have the app
    // assert that a back squat is performed on the machine someone benched on.
    #expect(try f.splits.entries(in: day).first?.machineID == nil)
  }

  @Test("Swapping an entry that is not there changes nothing")
  func swapOfMissingEntryIsNoop() throws {
    let f = try fixture()
    let split = try f.splits.createSplit(name: "PPL", now: now)
    let day = try f.splits.addDay(to: split, name: "Push", now: now)
    let entry = try f.splits.addEntry(to: day, exercise: f.bench, now: now)

    try f.splits.setExercise(f.squat, forEntry: SplitEntryID())

    let entries = try f.splits.entries(in: day)
    #expect(entries.map(\.id) == [entry])
    #expect(entries.first?.exerciseID == f.bench)
  }
}
