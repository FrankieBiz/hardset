import Foundation
import Testing

@testable import HardsetCore

@Suite("Weights render in the lifter's unit, and only in it")
struct WeightFormatterTests {
  let posix = Locale(identifier: "en_US_POSIX")
  let german = Locale(identifier: "de_DE")

  @Test("Kilograms render as logged, trailing zeros trimmed")
  func kilograms() {
    let f = WeightFormatter(unit: .kilograms, locale: posix)
    #expect(f.load(kilograms: 60) == "60 kg")
    #expect(f.load(kilograms: 62.5) == "62.5 kg")
    #expect(f.load(kilograms: 61.25) == "61.25 kg")
    #expect(f.number(kilograms: 60) == "60")
  }

  @Test("Pounds are converted, and 'kg' never appears")
  func pounds() {
    let f = WeightFormatter(unit: .pounds, locale: posix)
    // 135 lb typed, stored as kilograms, read back: exactly 135.
    #expect(f.load(kilograms: WeightUnit.pounds.toKilograms(135)) == "135 lb")
    #expect(f.load(kilograms: 60) == "132.28 lb")
    #expect(!f.load(kilograms: 60).contains("kg"))
  }

  @Test("The locale's decimal separator is used")
  func localeSeparator() {
    let f = WeightFormatter(unit: .kilograms, locale: german)
    #expect(f.load(kilograms: 62.5) == "62,5 kg")
  }

  @Test("Large loads are not grouped, matching what the keypad accepts")
  func noGrouping() {
    let f = WeightFormatter(unit: .pounds, locale: posix)
    #expect(f.number(kilograms: WeightUnit.pounds.toKilograms(1100)) == "1100")
  }

  @Test("Estimates round to display precision and say they are estimates")
  func estimates() {
    #expect(WeightFormatter(unit: .kilograms, locale: posix).estimate(kilograms: 80.26) == "about 80.5 kg")
    #expect(WeightFormatter(unit: .pounds, locale: posix).estimate(kilograms: 80) == "about 176 lb")
  }

  @Test("VoiceOver hears the unit's name, not its abbreviation")
  func spoken() {
    #expect(WeightFormatter(unit: .kilograms, locale: posix).spoken(kilograms: 62.5) == "62.5 kilograms")
    #expect(WeightFormatter(unit: .kilograms, locale: posix).spoken(kilograms: 1) == "1 kilogram")
    #expect(WeightFormatter(unit: .pounds, locale: posix).spoken(kilograms: WeightUnit.pounds.toKilograms(1)) == "1 pound")
  }
}

@Suite("Counts agree with their nouns")
struct CountTextTests {
  @Test("Sets", arguments: [(0, "0 sets"), (1, "1 set"), (2, "2 sets")])
  func sets(count: Int, expected: String) { #expect(CountText.sets(count) == expected) }

  @Test("Reps", arguments: [(1, "1 rep"), (8, "8 reps")])
  func reps(count: Int, expected: String) { #expect(CountText.reps(count) == expected) }
}

@Suite("A report states the most any of its figures can claim")
struct HighestCertaintyTests {
  @Test("An empty report claims nothing")
  func emptyClaimsNothing() {
    let report = MuscleVolumeReport(
      fractionalSets: [:], hardSets: 0, unattributedHardSets: 0, setsTouchingGroup: [:])
    #expect(report.highestCertainty == nil)
  }

  @Test("Only counted muscles: low, never the old hardcoded moderate")
  func countedIsLow() {
    let counted = Muscle.allCases.first { $0.tier != .modelled }!
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(counted): 6], hardSets: 6, unattributedHardSets: 0,
      setsTouchingGroup: [:])
    #expect(report.highestCertainty == .low)
  }

  @Test("A modelled muscle in range lifts the ceiling to moderate, never high")
  func modelledIsModerate() {
    let modelled = Muscle.allCases.first { $0.tier == .modelled }!
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(modelled): 10], hardSets: 10, unattributedHardSets: 0,
      setsTouchingGroup: [:])
    #expect(report.highestCertainty == .moderate)
  }
}
