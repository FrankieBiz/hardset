import Foundation
import Testing

@testable import HardsetCore

/// What one press of plus or minus is allowed to do.
@Suite("A load steps by something the gym can actually produce")
struct PlateMathTests {
  @Test("The default step is stated in the unit on screen, not converted into it")
  func defaultsAreNative() {
    // 2.5 kg and 5 lb, because those are the plates that exist. Converting either into the other
    // gives 5.51 lb or 2.27 kg, which no gym can load.
    #expect(PlateMath.step(modality: .barbell, machineIncrementKg: nil, unit: .kilograms) == 2.5)
    #expect(PlateMath.step(modality: .barbell, machineIncrementKg: nil, unit: .pounds) == 5)
  }

  @Test("Dumbbells step by their ladder and added bodyweight steps finer")
  func modalityChangesTheStep() {
    #expect(PlateMath.step(modality: .dumbbell, machineIncrementKg: nil, unit: .kilograms) == 2)
    #expect(PlateMath.step(modality: .bodyweight, machineIncrementKg: nil, unit: .kilograms) == 1.25)
    #expect(PlateMath.step(modality: .bodyweight, machineIncrementKg: nil, unit: .pounds) == 2.5)
  }

  @Test("An unknown modality still gets a usable step")
  func unknownModalityHasAStep() {
    #expect(PlateMath.step(modality: nil, machineIncrementKg: nil, unit: .kilograms) == 2.5)
    #expect(PlateMath.step(modality: nil, machineIncrementKg: nil, unit: .pounds) == 5)
  }

  /// The one figure here that is a fact rather than a convention.
  @Test("A recorded machine increment beats every default")
  func machineIncrementWins() {
    #expect(PlateMath.step(modality: .machine, machineIncrementKg: 5, unit: .kilograms) == 5)
    // 5 kg read in pounds is 11.023. Rounded to display precision so the step a control is labelled
    // with is exactly the step it applies -- three presses have to equal three times the label.
    #expect(PlateMath.step(modality: .machine, machineIncrementKg: 5, unit: .pounds) == 11)
  }

  /// The step a lifter is told about and the step they get must be the same number.
  @Test("Pressing three times moves exactly three times the stated step")
  func pressesMatchTheStatedStep() {
    for unit in WeightUnit.allCases {
      for increment in [5.0, 2.5, 7.5] {
        let step = PlateMath.step(modality: .machine, machineIncrementKg: increment, unit: unit)
        var value: Double? = 100
        for _ in 0..<3 { value = PlateMath.stepped(value, by: 1, step: step) }
        #expect(value == 100 + 3 * step, "unit \(unit), increment \(increment)")
      }
    }
  }

  /// A default step is exact by construction and must survive untouched.
  @Test("A 1.25 kg step is not rounded away")
  func fineDefaultStepSurvives() {
    let step = PlateMath.step(modality: .bodyweight, machineIncrementKg: nil, unit: .kilograms)
    #expect(step == 1.25)
    // And four presses land on a real plate total rather than drifting off the grid.
    #expect(PlateMath.stepped(0, by: 4, step: step) == 5)
  }

  @Test("A nonsensical machine increment falls back rather than freezing the control")
  func zeroIncrementFallsBack() {
    #expect(PlateMath.step(modality: .machine, machineIncrementKg: 0, unit: .kilograms) == 2.5)
    #expect(PlateMath.step(modality: .machine, machineIncrementKg: -5, unit: .kilograms) == 2.5)
  }

  @Test("A press moves the value by exactly one step")
  func pressMovesOneStep() {
    #expect(PlateMath.stepped(82.5, by: 1, step: 2.5) == 85)
    #expect(PlateMath.stepped(85, by: -1, step: 2.5) == 82.5)
    #expect(PlateMath.stepped(185, by: 2, step: 5) == 195)
  }

  /// Starting a bench press at 2.5 kg because the lifter pressed plus would be an invention.
  @Test("An empty field steps to nothing")
  func emptyStaysEmpty() {
    #expect(PlateMath.stepped(nil, by: 1, step: 2.5) == nil)
    #expect(PlateMath.stepped(nil, by: -1, step: 2.5) == nil)
  }

  @Test("A load cannot be stepped below zero")
  func clampedAtZero() {
    #expect(PlateMath.stepped(2, by: -1, step: 2.5) == 0)
    #expect(PlateMath.stepped(0, by: -1, step: 2.5) == 0)
    // Zero is a real value for a bodyweight movement: the set is the body.
    #expect(PlateMath.stepped(0, by: 1, step: 1.25) == 1.25)
  }

  /// Without rounding, repeated presses accumulate binary dust and a field reading 85 reads
  /// 84.99999999999999.
  @Test("Twenty presses up and twenty down return to the start exactly")
  func repeatedPressesDoNotDrift() {
    var value: Double? = 60
    for _ in 0..<20 { value = PlateMath.stepped(value, by: 1, step: 2.5) }
    for _ in 0..<20 { value = PlateMath.stepped(value, by: -1, step: 2.5) }
    #expect(value == 60)
  }

  @Test("A converted machine step does not drift either")
  func convertedStepDoesNotDrift() {
    let step = PlateMath.step(modality: .machine, machineIncrementKg: 2.5, unit: .pounds)
    var value: Double? = 100
    for _ in 0..<10 { value = PlateMath.stepped(value, by: 1, step: step) }
    // Ten presses of a rounded step land on exactly ten times that step above the start.
    #expect(value == 100 + 10 * step)
  }

  @Test("A zero step cannot move the value")
  func zeroStepDoesNothing() {
    #expect(PlateMath.stepped(85, by: 1, step: 0) == nil)
  }
}
