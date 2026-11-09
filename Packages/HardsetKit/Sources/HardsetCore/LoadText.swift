import Foundation

/// How a load is written out, so one set reads as the same number on every screen and in every
/// shared message.
///
/// Two kinds of number, two rules. An *entered* load is a fact the lifter typed, so it keeps the
/// precision the keypad accepts (two decimals) and is never rounded to a plate. An *estimate* is
/// arithmetic on those facts, so it goes through `StrengthMath.displayRounded` and never shows two
/// decimals: ten-gram precision on an estimate reads as a measurement.
public enum LoadText {
  /// An entered load in `unit`, with up to two fraction digits and none when they are zero.
  public static func entered(_ kilograms: Double, in unit: WeightUnit, locale: Locale = .current)
    -> String
  {
    unit.fromKilograms(kilograms)
      .formatted(.number.precision(.fractionLength(0...2)).locale(locale))
  }

  /// An estimated load in `unit`, rounded to 0.5 kg or 1 lb.
  public static func estimate(_ kilograms: Double, in unit: WeightUnit, locale: Locale = .current)
    -> String
  {
    StrengthMath.displayRounded(kilograms, in: unit)
      .formatted(.number.precision(.fractionLength(0...1)).locale(locale))
  }
}
