import Foundation
import Testing

@testable import HardsetCore

@Suite("Double-progression targets")
struct OverloadTargetTests {
  let r = RepRange(lower: 8, upper: 12)!

  private func set(_ kg: Double, _ reps: Int) -> PriorSetRecord {
    PriorSetRecord(weightKg: kg, reps: reps, completedAt: .distantPast)
  }

  private func targets(
    _ last: [PriorSetRecord], count: Int, increment: Double? = 2.5,
    unit: WeightUnit = .kilograms, addsLoad: Bool = true
  ) -> [SetTarget?] {
    OverloadTarget.targets(
      lastSets: last, range: r, setCount: count, incrementKg: increment,
      unit: unit, addsLoad: addsLoad
    )
  }

  @Test func belowTopAddsOneRepPerSet() {
    let result = targets([set(40, 10), set(40, 9), set(40, 8)], count: 3)
    #expect(result.map { $0?.weightKg } == [40, 40, 40])
    #expect(result.map { $0?.reps } == [11, 10, 9])
    #expect(result.allSatisfy { $0?.rule == .addRep })
  }

  @Test func allAtTopAddsTheMachineStep() {
    let result = targets([set(40, 12), set(40, 12), set(40, 12)], count: 3)
    #expect(result.allSatisfy { $0?.weightKg == 42.5 })
    #expect(result.allSatisfy { $0?.reps == 8 })
    #expect(result.allSatisfy { $0?.rule == .addLoad(stepKg: 2.5, isAssumedStep: false) })
  }

  @Test func unknownStepUsesOnePlateInTheLiftersUnit() {
    let pounds = targets([set(40, 12), set(40, 12)], count: 2, increment: nil, unit: .pounds)
    #expect(pounds.allSatisfy { abs(($0?.weightKg ?? 0) - (40 + 2.26796185)) < 1e-6 })
    #expect(pounds.allSatisfy {
      if case .addLoad(_, true) = $0?.rule { return true }
      return false
    })

    let kilograms = targets([set(40, 12), set(40, 12)], count: 2, increment: nil, unit: .kilograms)
    #expect(kilograms.allSatisfy { $0?.weightKg == 42.5 })
  }

  @Test func aSetAlreadyAtTopHolds() {
    let result = targets([set(40, 12), set(40, 11)], count: 2)
    #expect(result[0]?.weightKg == 40)
    #expect(result[0]?.reps == 12)
    #expect(result[0]?.rule == .holdTop)
    #expect(result[1]?.weightKg == 40)
    #expect(result[1]?.reps == 12)
    #expect(result[1]?.rule == .addRep)
  }

  @Test func mixedLoadsAtTopDoNotAddLoad() {
    let result = targets([set(40, 12), set(37.5, 12)], count: 2)
    #expect(result[0]?.weightKg == 40)
    #expect(result[0]?.reps == 12)
    #expect(result[0]?.rule == .holdTop)
    #expect(result[1]?.weightKg == 37.5)
    #expect(result[1]?.reps == 12)
    #expect(result[1]?.rule == .holdTop)
  }

  @Test func noHistoryMeansNoTargets() {
    #expect(targets([], count: 3) == [nil, nil, nil])
  }

  @Test func extraRowsReuseTheLastSet() {
    let result = targets([set(40, 10), set(40, 9), set(40, 8)], count: 4)
    #expect(result[3]?.weightKg == 40)
    #expect(result[3]?.reps == 9)
    #expect(result[3]?.rule == .addRep)
  }

  @Test func bodyweightOnlyAddsRepsUncapped() {
    let result = targets([set(0, 12), set(0, 12)], count: 2, addsLoad: false)
    #expect(result[0]?.weightKg == 0)
    #expect(result[0]?.reps == 13)
    #expect(result[0]?.rule == .addRep)
    #expect(result[1]?.weightKg == 0)
    #expect(result[1]?.reps == 13)
    #expect(result[1]?.rule == .addRep)
  }

  @Test func explanationsAreFixedCopy() {
    #expect(SetTarget(weightKg: 40, reps: 11, rule: .addRep).explanation == "One more rep than last time")
    #expect(SetTarget(weightKg: 40, reps: 12, rule: .holdTop).explanation == "Top of your range; hold it")
    #expect(
      SetTarget(weightKg: 42.5, reps: 8, rule: .addLoad(stepKg: 2.5, isAssumedStep: false)).explanation
        == "Every set hit the top of your range: add one step"
    )
    #expect(
      SetTarget(weightKg: 42.27, reps: 8, rule: .addLoad(stepKg: 2.26796185, isAssumedStep: true)).explanation
        == "Every set hit the top of your range: add one plate (assumed step)"
    )
  }

  @Test func targetsAreSpokenAsWhatToAim() {
    #expect(SetTarget(weightKg: 40, reps: 11, rule: .addRep).spokenLabel(in: .kilograms)
      == "target 11 reps")
    #expect(SetTarget(weightKg: 40, reps: 12, rule: .holdTop).spokenLabel(in: .kilograms)
      == "target 12 reps")
    #expect(SetTarget(weightKg: 40, reps: 1, rule: .addRep).spokenLabel(in: .kilograms)
      == "target 1 rep")
    // When the load itself is the news, it is said.
    #expect(
      SetTarget(weightKg: 42.5, reps: 8, rule: .addLoad(stepKg: 2.5, isAssumedStep: false))
        .spokenLabel(in: .kilograms) == "target 42.5 kg for 8 reps")
    #expect(
      SetTarget(weightKg: 43.09, reps: 8, rule: .addLoad(stepKg: 2.27, isAssumedStep: true))
        .spokenLabel(in: .pounds) == "target 95 lb for 8 reps")
  }

  @Test func spokenTargetKeepsTheTypedPrecision() {
    let posix = Locale(identifier: "en_US_POSIX")
    #expect(
      SetTarget(weightKg: 43.75, reps: 8, rule: .addLoad(stepKg: 1.25, isAssumedStep: false))
        .spokenLabel(in: .kilograms, locale: posix) == "target 43.75 kg for 8 reps")
    // 92.5 lb is a plate pair, not 93.
    #expect(
      SetTarget(weightKg: 92.5 * 0.45359237, reps: 8, rule: .addLoad(stepKg: 1.13, isAssumedStep: false))
        .spokenLabel(in: .pounds, locale: posix) == "target 92.5 lb for 8 reps")
  }
}
