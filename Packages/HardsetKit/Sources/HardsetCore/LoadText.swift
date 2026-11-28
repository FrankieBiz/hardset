import Foundation

/// How a load is written out, so one set reads as the same number on every screen and in every
/// shared message.
///
/// Two kinds of number, two rules. An *entered* load is a fact the lifter typed, so it is never
/// rounded to a plate, but it is written with at most one decimal in the unit it is shown in. The
/// keypad accepts two decimals and storage keeps the exact kilograms, yet a conversion invents
/// digits nobody typed: 80 kg is 176.37 lb, and a hundredth of a pound is precision no one
/// entered and no plate can load. A lifter who types 100.25 lb will see 100.3, and the stored
/// value is still exact. An *estimate* is arithmetic on those facts, so it goes through
/// `StrengthMath.displayRounded` and never shows two decimals: ten-gram precision on an estimate
/// reads as a measurement.
public enum LoadText {
  /// An entered load in `unit`, with at most one fraction digit and none when it is whole.
  public static func entered(_ kilograms: Double, in unit: WeightUnit, locale: Locale = .current)
    -> String
  {
    // Settle the binary noise of the conversion first, so a typed 100.25 lb, which converts to
    // kilograms and back as 100.24999999999999, rounds half up to 100.3 and not down to 100.2.
    let settled = (unit.fromKilograms(kilograms) * 1_000_000).rounded() / 1_000_000
    let displayed = (settled * 10).rounded(.toNearestOrAwayFromZero) / 10
    return displayed.formatted(
      .number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
  }

  /// A load or a step the lifter acts on, with up to two fraction digits and none when they are
  /// zero: the "+1.25 kg" a set row says it beat last time by, the load a target asks for next, and
  /// the margin a record needed. These are plates to load and thresholds to clear, so rounding them
  /// would claim a load that cannot be loaded or a margin smaller than the rule applied; `entered`
  /// is for what was logged, and shows less.
  public static func exact(_ kilograms: Double, in unit: WeightUnit, locale: Locale = .current)
    -> String
  {
    unit.fromKilograms(kilograms)
      .formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
  }

  /// An estimated load in `unit`, rounded to 0.5 kg or 1 lb.
  public static func estimate(_ kilograms: Double, in unit: WeightUnit, locale: Locale = .current)
    -> String
  {
    StrengthMath.displayRounded(kilograms, in: unit)
      .formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
  }
}
