import Foundation
import Testing

@testable import HardsetCore

/// Reading a weight a person typed, in whatever locale their phone is set to.
@Suite("A typed number is read in the locale it was typed in")
struct TypedNumberTests {
  let french = Locale(identifier: "fr_FR")
  let us = Locale(identifier: "en_US")
  let german = Locale(identifier: "de_DE")

  /// The bug: bodyweight entry used `Double(text)` behind a silent guard, so this typed weight was
  /// discarded with no message at all.
  @Test("A comma decimal is read in a comma locale")
  func commaDecimalInCommaLocale() {
    #expect(TypedNumber.parse("62,5", locale: french) == 62.5)
    #expect(TypedNumber.parse("82,25", locale: german) == 82.25)
  }

  @Test("A point decimal is read in a point locale")
  func pointDecimalInPointLocale() {
    #expect(TypedNumber.parse("62.5", locale: us) == 62.5)
    #expect(TypedNumber.parse("185", locale: us) == 185)
  }

  /// A device set to one locale may be driving a keyboard from another, and both spellings are the
  /// same weight.
  @Test("A point decimal still works in a comma locale, and the reverse")
  func mixedSeparatorsStillWork() {
    #expect(TypedNumber.parse("62.5", locale: french) == 62.5)
    #expect(TypedNumber.parse("62,5", locale: us) == 62.5)
  }

  @Test("Whitespace is tolerated and empty input is not a number")
  func trimmingAndEmpty() {
    #expect(TypedNumber.parse("  82.5 ", locale: us) == 82.5)
    #expect(TypedNumber.parse("", locale: us) == nil)
    #expect(TypedNumber.parse("   ", locale: us) == nil)
  }

  @Test("Text that is not a number is refused rather than coerced")
  func nonNumbersRefused() {
    #expect(TypedNumber.parse("heavy", locale: us) == nil)
    #expect(TypedNumber.parse("-", locale: us) == nil)
    #expect(TypedNumber.parse("kg", locale: us) == nil)
  }

  /// The comma-for-point fallback must not reinterpret a grouped thousand as a decimal.
  @Test("A grouped thousand is not turned into a decimal")
  func groupingIsNotMistakenForADecimal() {
    // In a point locale this is one thousand two hundred and thirty-four, not 1.234.
    #expect(TypedNumber.parse("1,234", locale: us) == 1234)
    // And with both separators present the fallback does not fire at all.
    #expect(TypedNumber.parse("1,234.5", locale: us) == 1234.5)
  }

  @Test("A negative number parses, so callers can reject it themselves")
  func negativesParse() {
    // `parse` reports what was typed; whether a weight may be negative is the caller's rule.
    #expect(TypedNumber.parse("-5", locale: us) == -5)
  }
}
