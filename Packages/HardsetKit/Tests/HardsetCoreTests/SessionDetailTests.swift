import Foundation
import Testing

@testable import HardsetCore

@Suite("A past workout groups by movement and machine, and never merges two machines")
struct SessionDetailTests {
  private let start = Date(timeIntervalSince1970: 44_000_000)
  private let press = ExerciseID()
  private let curl = ExerciseID()
  private let hammer = MachineID()
  private let cybex = MachineID()

  private func entry(
    _ exercise: ExerciseID, _ name: String, _ machine: MachineID?, _ machineName: String?,
    _ weight: Double, at minute: Double, ordinal: Int = 0
  ) -> SessionDetail.Entry {
    SessionDetail.Entry(
      line: SessionDetail.SetLine(setID: SetID(), weightKg: weight, reps: 8, isWarmup: false, records: []),
      exerciseID: exercise, exerciseName: name, machineID: machine, machineName: machineName,
      completedAt: start.addingTimeInterval(minute * 60), setOrdinal: ordinal)
  }

  @Test("A movement on two machines is two blocks, in the order they were first used")
  func twoMachinesTwoBlocks() {
    let blocks = SessionDetail.blocks(from: [
      entry(press, "Leg Press", cybex, "Cybex", 90, at: 20),
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 1),
      entry(press, "Leg Press", hammer, "Hammer", 105, at: 4),
    ])
    #expect(blocks.map(\.machineName) == ["Hammer", "Cybex"])
    #expect(blocks[0].sets.map(\.weightKg) == [100, 105])
    #expect(blocks[1].sets.map(\.weightKg) == [90])
  }

  @Test("Coming back to a machine later adds to its block")
  func returningJoinsBlock() {
    let blocks = SessionDetail.blocks(from: [
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 1),
      entry(curl, "Curl", nil, nil, 20, at: 10),
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 30),
    ])
    #expect(blocks.map(\.exerciseName) == ["Leg Press", "Curl"])
    #expect(blocks[0].sets.count == 2)
    #expect(blocks[1].machineName == nil)
  }

  @Test("Sets logged in the same instant keep their ordinal order")
  func sameInstant() {
    let blocks = SessionDetail.blocks(from: [
      entry(press, "Leg Press", hammer, "Hammer", 110, at: 1, ordinal: 1),
      entry(press, "Leg Press", hammer, "Hammer", 100, at: 1, ordinal: 0),
    ])
    #expect(blocks[0].sets.map(\.weightKg) == [100, 110])
  }
}
