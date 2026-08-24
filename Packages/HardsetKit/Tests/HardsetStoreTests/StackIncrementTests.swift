import Foundation
import GRDB
import HardsetCore
import Testing

@testable import HardsetStore

/// `machines.stackIncrementKg` had readers everywhere and no writer any UI could reach: machines
/// were created with the step deliberately unknown and there was no second chance to supply it. So
/// the column was always nil, its "5 kg steps" label never appeared, and the keypad's +/- could
/// never use the equipment's real step.
@Suite("A machine's stack step can be recorded and corrected")
struct StackIncrementTests {
  private func fixture() throws -> (any DatabaseWriter, GymStore) {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    let queue = try DatabaseQueue(configuration: configuration)
    try HardsetMigrations.migrator().migrate(queue)
    return (queue, GymStore(database: queue))
  }

  @Test("A step written on a machine reads back")
  func stepRoundTrips() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Leg Press")

    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == nil)
    try gyms.setStackIncrement(5, for: machine)
    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == 5)
  }

  /// Unknown is a real answer. A guessed step licences suggestions the equipment cannot hit.
  @Test("Clearing the step restores unknown rather than zero")
  func clearingRestoresUnknown() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Leg Press")
    try gyms.setStackIncrement(5, for: machine)

    try gyms.setStackIncrement(nil, for: machine)
    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == nil)
  }

  /// Zero would make every suggestion land on the same load forever.
  @Test("A non-positive step is stored as unknown, not as zero")
  func nonPositiveIsUnknown() throws {
    let (_, gyms) = try fixture()
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Leg Press")

    try gyms.setStackIncrement(0, for: machine)
    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == nil)
    try gyms.setStackIncrement(-5, for: machine)
    #expect(try gyms.machines(at: gym).first?.stackIncrementKg == nil)
  }

  /// The whole point: the increment has to reach the code that resolves a suggestion's step.
  @Test("A recorded step reaches the progression path")
  func stepReachesProgression() throws {
    let (db, gyms) = try fixture()
    let logger = LoggerStore(database: db)
    let gym = try gyms.createGym(name: "Iron Works")
    let machine = try gyms.createMachine(at: gym, name: "Leg Press")
    try gyms.setStackIncrement(5, for: machine)

    #expect(try logger.machineIncrements(for: [machine])[machine] == 5)
    // And it is what `PlateMath` then offers as the keypad step, rather than the barbell default.
    let step = PlateMath.step(
      modality: .machine,
      machineIncrementKg: try logger.machineIncrements(for: [machine])[machine],
      unit: .kilograms
    )
    #expect(step == 5)
  }
}
