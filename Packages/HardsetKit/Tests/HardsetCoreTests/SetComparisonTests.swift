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

  @Test func spokenLabelsNameWhatGrew() {
    #expect(SetComparison.beat(addedKg: 0, addedReps: 1).spokenLabel(in: .kilograms)
      == "plus 1 rep on last time")
    #expect(SetComparison.beat(addedKg: 0, addedReps: 2).spokenLabel(in: .kilograms)
      == "plus 2 reps on last time")
    #expect(SetComparison.beat(addedKg: 2.5, addedReps: 0).spokenLabel(in: .kilograms)
      == "plus 2.5 kg on last time")
    #expect(SetComparison.beat(addedKg: 2.5, addedReps: 1).spokenLabel(in: .kilograms)
      == "plus 2.5 kg and 1 rep on last time")
    // A load jump that cost reps names the load only, as the visible mark does.
    #expect(SetComparison.beat(addedKg: 2.5, addedReps: -4).spokenLabel(in: .kilograms)
      == "plus 2.5 kg on last time")
    #expect(SetComparison.matched.spokenLabel(in: .kilograms) == "matched last time")
  }

  @Test func spokenLabelInPounds() {
    #expect(SetComparison.beat(addedKg: 4.5359237, addedReps: 0).spokenLabel(in: .pounds)
      == "plus 10 lb on last time")
  }

  /// A typed load is a fact, so a difference between two typed loads keeps the precision they were
  /// typed with. Only an estimate is rounded to a plate.
  @Test func addedLoadKeepsTheTypedPrecision() {
    let posix = Locale(identifier: "en_US_POSIX")
    #expect(SetComparison.beat(addedKg: 1.25, addedReps: 0).label(in: .kilograms, locale: posix) == "+1.25 kg")
    #expect(SetComparison.beat(addedKg: 3.75, addedReps: 0).label(in: .kilograms, locale: posix) == "+3.75 kg")
    // 1.25 lb per side: a 2.5 lb microplate pair, stored as kilograms, still reads 2.5 lb.
    #expect(SetComparison.beat(addedKg: 2.5 * 0.45359237, addedReps: 0).label(in: .pounds, locale: posix)
      == "+2.5 lb")
    #expect(SetComparison.beat(addedKg: 1.25, addedReps: 1).spokenLabel(in: .kilograms, locale: posix)
      == "plus 1.25 kg and 1 rep on last time")
  }

  /// Weights within the detector's tolerance are the same weight, so a hair of float noise on the
  /// load cannot turn fewer reps into a win.
  @Test func aLoadWithinToleranceIsNotALoadJump() {
    let previous = PriorSetRecord(weightKg: 40, reps: 10, completedAt: .distantPast)

    // Typed as 88.2 lb: 40.0068 kg, which is the same load to the detector.
    #expect(SetComparison.compare(weightKg: 40.0068, reps: 9, against: previous, repFloor: 8) == nil)
    #expect(SetComparison.compare(weightKg: 40.0068, reps: 10, against: previous, repFloor: 8) == .matched)
    // A real jump still counts, and so does the same sub-tolerance load with more reps.
    #expect(SetComparison.compare(weightKg: 42.5, reps: 8, against: previous, repFloor: 8)
      == .beat(addedKg: 2.5, addedReps: -2))
    #expect(SetComparison.compare(weightKg: 40.0068, reps: 11, against: previous, repFloor: 8)
      == .beat(addedKg: 0, addedReps: 1))
  }
}
