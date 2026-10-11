import Foundation

/// The one way a weight becomes text.
///
/// Six local `format(_:)` helpers had grown across the UI, and every one hard-coded "kg", so a
/// lifter who chose pounds still read kilograms in the PR banner, the machine picker and the
/// machine-change note. Conversion stays in `WeightUnit`; this owns only presentation.
public struct WeightFormatter: Hashable, Sendable {
  public let unit: WeightUnit
  public let locale: Locale

  public init(unit: WeightUnit, locale: Locale = .current) {
    self.unit = unit
    self.locale = locale
  }

  /// A logged or typed load: "62.5 kg". Up to two decimals, so 61.25 kg reads as entered.
  public func load(kilograms: Double) -> String {
    "\(number(kilograms: kilograms)) \(unit.abbreviation)"
  }

  /// The number alone, for fields that draw the unit separately.
  public func number(kilograms: Double) -> String {
    Self.text(unit.fromKilograms(kilograms), fractionDigits: 2, locale: locale)
  }

  /// A sum of loads, such as a session's or a period's volume: "20723 lb". A whole number, because
  /// two decimals on a total implies a precision nobody reads or trusts. Halves round up.
  public func total(kilograms: Double) -> String {
    let rounded = unit.fromKilograms(kilograms).rounded()
    return "\(Self.text(rounded, fractionDigits: 0, locale: locale)) \(unit.abbreviation)"
  }

  /// A derived load: "about 80.5 kg". Rounded to display precision, because an estimate shown to
  /// 10 g reads as a measurement (guideline 1.4.1).
  public func estimate(kilograms: Double) -> String {
    let rounded = StrengthMath.displayRounded(kilograms, in: unit)
    return "about \(Self.text(rounded, fractionDigits: 1, locale: locale)) \(unit.abbreviation)"
  }

  /// A total for VoiceOver: "20723 pounds". Whole, as `total(kilograms:)` is.
  public func spokenTotal(kilograms: Double) -> String {
    let rounded = unit.fromKilograms(kilograms).rounded()
    return spoken(kilograms: unit.toKilograms(rounded))
  }

  /// For VoiceOver: "62.5 kilograms".
  public func spoken(kilograms: Double) -> String {
    let value = unit.fromKilograms(kilograms)
    let isOne = (value * 100).rounded() == 100
    let name: String
    switch unit {
    case .kilograms: name = isOne ? "kilogram" : "kilograms"
    case .pounds: name = isOne ? "pound" : "pounds"
    }
    return "\(Self.text(value, fractionDigits: 2, locale: locale)) \(name)"
  }

  static func text(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
    value.formatted(
      .number
        .precision(.fractionLength(0...fractionDigits))
        .grouping(.never)
        .locale(locale)
    )
  }
}

/// Counts with the noun agreeing. "1 sets" reached the history screen.
public enum CountText {
  public static func sets(_ count: Int) -> String { count == 1 ? "1 set" : "\(count) sets" }
  public static func reps(_ count: Int) -> String { count == 1 ? "1 rep" : "\(count) reps" }
}
