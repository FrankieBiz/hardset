import Foundation
import Testing

@testable import HardsetCore

@Suite("Comparing a set with the same set last time")
struct SetComparisonTests {
  private func previous(_ kg: Double, _ reps: Int) -> PriorSetRecord {
    PriorSetRecord(weightKg: kg, reps: reps, completedAt: .distantPast)
  }

  private func compare(
    _ kg: Double, _ reps: Int, against old: PriorSetRecord?, floor: Int? = nil
  ) -> SetComparison? {
    SetComparison.compare(weightKg: kg, reps: reps, against: old, repFloor: floor)
  }

  @Test func moreRepsSameLoad() {
    let one = compare(40, 11, against: previous(40, 10))
    #expect(one == .beat(addedKg: 0, addedReps: 1))
    #expect(one?.label(in: .kilograms) == "+1 rep")
    let two = compare(40, 12, against: previous(40, 10))
    #expect(two == .beat(addedKg: 0, addedReps: 2))
    #expect(two?.label(in: .kilograms) == "+2 reps")
  }

  @Test func moreLoadSameReps() {
    let result = compare(42.5, 10, against: previous(40, 10))
    #expect(result == .beat(addedKg: 2.5, addedReps: 0))
    #expect(result?.label(in: .kilograms) == "+2.5 kg")
  }

  @Test func moreOfBoth() {
    let result = compare(42.5, 11, against: previous(40, 10))
    #expect(result == .beat(addedKg: 2.5, addedReps: 1))
    #expect(result?.label(in: .kilograms) == "+2.5 kg · +1 rep")
  }

  @Test func loadJumpWithinRange() {
    let result = compare(42.5, 8, against: previous(40, 12), floor: 8)
    #expect(result == .beat(addedKg: 2.5, addedReps: -4))
    #expect(result?.label(in: .kilograms) == "+2.5 kg")
  }

  @Test func loadJumpBelowFloor() {
    #expect(compare(42.5, 7, against: previous(40, 12), floor: 8) == nil)
  }

  @Test func loadJumpWithoutRange() {
    #expect(compare(42.5, 8, against: previous(40, 12), floor: nil) == nil)
  }

  @Test func matchedWithinTolerance() {
    let result = compare(40.005, 10, against: previous(40, 10))
    #expect(result == .matched)
    #expect(result?.label(in: .kilograms) == "Matched")
  }

  @Test func fewerRepsIsNothing() {
    #expect(compare(40, 9, against: previous(40, 10)) == nil)
    #expect(compare(40, 10, against: nil) == nil)
  }

  @Test func poundsLabel() {
    let result = compare(45.359237, 10, against: previous(40.8233133, 10))
    #expect(result?.label(in: .pounds) == "+10 lb")
  }
}
