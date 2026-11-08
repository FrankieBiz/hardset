import Foundation
import GRDB
import HardsetCore
import SQLiteData
import Testing
@testable import HardsetStore

@Suite("Explicit machine load steps")
struct MachineIncrementTests {
  @Test("Persisted load steps reach new and recovered workouts without changing saved sets")
  @MainActor
  func lifecycle() throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let gyms = GymStore(database: db), logger = LoggerStore(database: db)
    let gym = try gyms.createGym(name: "Gym")
    let machine = try gyms.createMachine(at: gym, name: "Sled")
    let exercise = ExerciseID()
    try db.write { try Exercise.insert { Exercise.Draft(id: exercise.rawValue, name: "Press") }.execute($0) }
    try gyms.setStackIncrement(2.5, for: machine, at: gym)
    let live = try SessionCoordinator.start(store: logger, gymID: gym,
      plan: [.init(exerciseID: exercise, machineID: machine, exerciseName: "Press")])
    let state = live.exercises[0]
    live.exercises[0].slots[0].draft = .init(weightKg: 80, reps: 8)
    #expect(live.logSet(slotID: state.slots[0].id, inExercise: state.id))
    try gyms.setStackIncrement(5, for: machine, at: gym)
    live.exercises[0].updateMachineIncrement(5)
    #expect(live.exercises[0].slots[0].draft.weightKg == 80)
    #expect(try logger.sets(in: live.sessionID).first?.weightKg == 80)
    let recovered = try #require(try SessionCoordinator.resume(store: logger))
    #expect(recovered.exercises[0].machineIncrementKg == 5)
    #expect(recovered.exercises[0].slots[0].draft.weightKg == 80)
    try gyms.setStackIncrement(nil, for: machine, at: gym)
    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == nil)
  }

  @Test("Invalid increments and the wrong gym leave the machine unchanged")
  func rejection() throws {
    let db = try DatabaseQueue()
    try HardsetMigrations.migrator().migrate(db)
    let gyms = GymStore(database: db)
    let gym = try gyms.createGym(name: "Gym")
    let other = try gyms.createGym(name: "Other")
    let machine = try gyms.createMachine(at: gym, name: "Sled", stackIncrementKg: 5)
    for increment in [Double.nan, .infinity, -2.5, 0] {
      #expect(throws: MachineProfileError.invalidIncrement) { try gyms.setStackIncrement(increment, for: machine, at: gym) }
    }
    #expect(throws: MachineProfileError.machineUnavailable) { try gyms.setStackIncrement(10, for: machine, at: other) }
    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == 5)
  }
}
