import Foundation
import Testing

@testable import HardsetCore

/// The keypad's quick steps are the machine's real increment where one is recorded, and 2.5 and 5
/// where it is not. A step to a load the equipment cannot hold is a small lie in the lifter's own
/// log, and the row's −/+ already refuse it by using the machine's increment.
@Suite("Keypad quick steps")
struct QuickStepsTests {
  @Test("With no increment recorded the pad offers 2.5 and 5, in whatever unit it shows")
  func fallback() {
    for unit in WeightUnit.allCases {
      #expect(QuickSteps.weight(machineIncrementKg: nil, unit: unit) == [-5, -2.5, 2.5, 5])
      #expect(!QuickSteps.usesMachineStep(machineIncrementKg: nil, unit: unit))
    }
  }

  @Test("A recorded increment is the step, and its double is the larger one")
  func machineStepInKilograms() {
    #expect(QuickSteps.weight(machineIncrementKg: 5, unit: .kilograms) == [-10, -5, 5, 10])
    #expect(QuickSteps.weight(machineIncrementKg: 4.5, unit: .kilograms) == [-9, -4.5, 4.5, 9])
    #expect(QuickSteps.usesMachineStep(machineIncrementKg: 4.5, unit: .kilograms))
  }

  /// A pin stack that moves ten pounds is 4.5359237 kg in storage; read in pounds the step is ten
  /// pounds, not 9.999999999999998 and not a number the display cannot show.
  @Test("A pound lifter sees the machine's step in pounds, rounded to what the display can show")
  func machineStepInPounds() {
    let tenPounds = 10 * 0.45359237
    #expect(QuickSteps.weight(machineIncrementKg: tenPounds, unit: .pounds) == [-20, -10, 10, 20])
    // A step recorded in kilograms is read as pounds: 2.5 kg is 5.51 lb, to the pad's two places.
    #expect(QuickSteps.weight(machineIncrementKg: 2.5, unit: .pounds) == [-11.02, -5.51, 5.51, 11.02])
  }

  @Test("An increment that is not a usable step is none: the fallback, not a zero step")
  func unusableIncrementIsNone() {
    for bad in [0, -2.5, .nan, .infinity, -.infinity] as [Double] {
      #expect(QuickSteps.weight(machineIncrementKg: bad, unit: .kilograms) == [-5, -2.5, 2.5, 5], "\(bad)")
      #expect(!QuickSteps.usesMachineStep(machineIncrementKg: bad, unit: .kilograms), "\(bad)")
    }
    // So small in pounds that it rounds to nothing at two places.
    #expect(!QuickSteps.usesMachineStep(machineIncrementKg: 0.0001, unit: .kilograms))
  }

  @Test("Every offer is four distinct steps, ordered, and none is zero")
  func shape() {
    for increment in [nil, 1.25, 2.5, 4.5, 5, 7.5, 10] as [Double?] {
      for unit in WeightUnit.allCases {
        let steps = QuickSteps.weight(machineIncrementKg: increment, unit: unit)
        #expect(steps.count == 4)
        #expect(steps == steps.sorted())
        #expect(Set(steps).count == 4)
        #expect(!steps.contains(0))
        #expect(steps[0] == -steps[3] && steps[1] == -steps[2])
      }
    }
  }

  @Test("Reps move by one or two, never by a machine's step")
  func repsAreNotMachineSteps() {
    #expect(QuickSteps.reps == [-1, 1, 2])
  }

  /// The pad applies a step to what the lifter typed. A step from a machine of 4.5 kg applied twice
  /// from 100 kg gives 109 kg, a load the stack can hold, where a fixed 5 would have given 110.
  @Test("Applied through the entry buffer, a machine's steps land on loads it can hold")
  func appliedToTheBuffer() {
    var buffer = NumericEntryBuffer(value: 100, maximumIntegerDigits: 4, maximumFractionDigits: 2)
    let steps = QuickSteps.weight(machineIncrementKg: 4.5, unit: .kilograms)
    buffer.adjust(by: steps[2])
    buffer.adjust(by: steps[2])
    #expect(buffer.value == 109)
    buffer.adjust(by: steps[1])
    #expect(buffer.value == 104.5)
  }
}
