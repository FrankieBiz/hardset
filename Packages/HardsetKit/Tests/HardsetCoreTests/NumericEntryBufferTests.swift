import Testing

@testable import HardsetCore

/// A prefill must arrive at the precision the row can display.
@Suite("Seeded prefills are rounded for display")
struct NumericEntryBufferSeedTests {
  @Test("A converted kilogram value is not shown at full double precision")
  func convertedValueIsRounded() {
    // 60 kg in pounds, which is what the set row seeds when the user reads imperial.
    let pounds = WeightUnit.pounds.fromKilograms(60)
    let buffer = NumericEntryBuffer(value: pounds, maximumFractionDigits: 2)
    // Was "132.277357310926 53", wrapping across four lines of the row.
    #expect(buffer.displayText == "132.28")
  }

  @Test("A whole number keeps no trailing decimal")
  func wholeNumbersStayWhole() {
    #expect(NumericEntryBuffer(value: 60, maximumFractionDigits: 2).displayText == "60")
    #expect(NumericEntryBuffer(value: 2.50, maximumFractionDigits: 2).displayText == "2.5")
  }

  @Test("A reps buffer rounds to a whole number")
  func repsAreWhole() {
    let buffer = NumericEntryBuffer(
      value: 9.6, allowsDecimal: false, maximumFractionDigits: 0
    )
    #expect(buffer.displayText == "10")
  }

  @Test("An empty prefill stays empty rather than becoming zero")
  func nilStaysEmpty() {
    let buffer = NumericEntryBuffer(value: nil)
    #expect(buffer.displayText.isEmpty)
    #expect(buffer.value == nil)
  }

  /// A prefill has to be a load someone can actually put on a bar.
  ///
  /// 84 kg read back in pounds is 185.188…, and seeding the raw conversion put "185.19" in the field
  /// while the same row printed "Last time 185.2 lb" two inches to the left. The rounding belongs to
  /// the conversion, not to the field: the field still accepts two decimals, because 62.75 kg is a
  /// real load for anyone with micro-plates.
  @Test("A converted prefill seeds a loadable number, not a raw conversion")
  func convertedPrefillIsLoadable() {
    let seeded = WeightUnit.pounds.displayValue(fromKilograms: 84)
    #expect(NumericEntryBuffer(value: seeded, maximumFractionDigits: 2).displayText == "185.2")

    // A value that is exact in the display unit keeps no decimal point at all.
    let exact = WeightUnit.pounds.displayValue(fromKilograms: WeightUnit.pounds.toKilograms(185))
    #expect(NumericEntryBuffer(value: exact, maximumFractionDigits: 2).displayText == "185")

    // And the field itself still holds finer entry than the app ever produces.
    #expect(NumericEntryBuffer(value: 62.75, maximumFractionDigits: 2).displayText == "62.75")
  }
}
