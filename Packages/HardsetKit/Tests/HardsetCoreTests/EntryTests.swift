import Foundation
import Testing

@testable import HardsetCore

@Suite("Keypad entry cannot invent a value")
struct NumericEntryBufferTests {
  /// The defect this type exists to prevent: `Double(text) ?? 0` turning an untouched field
  /// into a 0 kg set.
  @Test("An empty buffer has no value, not zero")
  func emptyIsNil() {
    let buffer = NumericEntryBuffer()
    #expect(buffer.value == nil)
    #expect(buffer.isEmpty)
    #expect(buffer.displayText.isEmpty)
  }

  @Test("A nil prefill yields an empty buffer rather than 0")
  func nilPrefillIsEmpty() {
    #expect(NumericEntryBuffer(value: nil).value == nil)
  }

  /// Zero is a real entry — bodyweight work — and must survive as zero.
  @Test("A typed zero is a value")
  func typedZeroIsAValue() {
    var buffer = NumericEntryBuffer()
    buffer.append(digit: 0)
    #expect(buffer.value == 0)
    #expect(!buffer.isEmpty)
  }

  @Test("A whole prefill shows without a trailing .0")
  func wholePrefillIsTidy() {
    #expect(NumericEntryBuffer(value: 60).displayText == "60")
    #expect(NumericEntryBuffer(value: 62.5).displayText == "62.5")
  }

  @Test("Reps buffers refuse a decimal point entirely")
  func repsRefuseDecimal() {
    var buffer = NumericEntryBuffer(value: nil, allowsDecimal: false)
    buffer.append(digit: 8)
    buffer.appendDecimalSeparator()
    buffer.append(digit: 5)
    #expect(buffer.displayText == "85")
  }

  @Test("A leading decimal point becomes 0.")
  func leadingSeparatorIsExplicit() {
    var buffer = NumericEntryBuffer()
    buffer.appendDecimalSeparator()
    #expect(buffer.displayText == "0.")
    // "0." alone is not yet a number.
    buffer.append(digit: 5)
    #expect(buffer.value == 0.5)
  }

  @Test("Only one decimal point is accepted")
  func singleSeparator() {
    var buffer = NumericEntryBuffer()
    buffer.append(digit: 6)
    buffer.appendDecimalSeparator()
    buffer.appendDecimalSeparator()
    buffer.append(digit: 5)
    #expect(buffer.displayText == "6.5")
  }

  @Test("A second leading zero is ignored")
  func noDoubleLeadingZero() {
    var buffer = NumericEntryBuffer()
    buffer.append(digit: 0)
    buffer.append(digit: 0)
    #expect(buffer.displayText == "0")
    buffer.append(digit: 7)
    #expect(buffer.displayText == "7")
  }

  @Test("Digit limits are enforced")
  func digitLimits() {
    var buffer = NumericEntryBuffer(maximumIntegerDigits: 3, maximumFractionDigits: 1)
    for _ in 0..<6 { buffer.append(digit: 9) }
    #expect(buffer.displayText == "999")
    buffer.appendDecimalSeparator()
    buffer.append(digit: 5)
    buffer.append(digit: 5)
    #expect(buffer.displayText == "999.5")
  }

  @Test("Deleting back to empty returns to no value, not zero")
  func deleteToEmpty() {
    var buffer = NumericEntryBuffer(value: 60)
    buffer.deleteBackward()
    buffer.deleteBackward()
    #expect(buffer.isEmpty)
    #expect(buffer.value == nil)
    // Deleting past empty is a no-op rather than a crash.
    buffer.deleteBackward()
    #expect(buffer.value == nil)
  }

  @Test("Clearing discards the prefill")
  func clearing() {
    var buffer = NumericEntryBuffer(value: 100)
    buffer.clear()
    #expect(buffer.value == nil)
  }
}

@Suite("Kilograms are canonical and conversion round-trips")
struct WeightUnitTests {
  @Test("Kilograms convert to themselves")
  func kilogramsAreIdentity() {
    #expect(WeightUnit.kilograms.fromKilograms(100) == 100)
    #expect(WeightUnit.kilograms.toKilograms(100) == 100)
  }

  @Test("The pound is exactly 0.45359237 kg")
  func poundDefinition() {
    #expect(abs(WeightUnit.pounds.toKilograms(1) - 0.45359237) < 1e-12)
    #expect(abs(WeightUnit.pounds.fromKilograms(0.45359237) - 1) < 1e-12)
  }

  /// A display/store round trip must not drift, or a user on pounds watches their logged
  /// weights wander after a few edits.
  @Test("Display and storage round-trip without drift", arguments: [0.0, 2.5, 60.0, 137.5, 250.0])
  func roundTrip(kilograms: Double) {
    for unit in WeightUnit.allCases {
      let displayed = unit.fromKilograms(kilograms)
      #expect(abs(unit.toKilograms(displayed) - kilograms) < 1e-9)
    }
  }

  @Test("Rounding snaps to the plate step")
  func rounding() {
    #expect(WeightUnit.kilograms.roundedToIncrement(61.3) == 62.5)
    #expect(WeightUnit.kilograms.roundedToIncrement(61.0) == 60.0)
    #expect(WeightUnit.pounds.roundedToIncrement(137) == 135)
    // A machine with a coarser stack overrides the default.
    #expect(WeightUnit.kilograms.roundedToIncrement(61.3, increment: 5) == 60)
    // A nonsense increment is ignored rather than dividing by zero.
    #expect(WeightUnit.kilograms.roundedToIncrement(61.3, increment: 0) == 61.3)
  }
}
