import Foundation

/// One way of writing a load, everywhere the logger shows one.
///
/// Up to two decimals with trailing zeros trimmed: the precision the keypad accepts and seeds,
/// so a kilogram load shown in pounds reads "220.46" in the field, under "Last time", on the
/// machine chip and on the step buttons alike. Three roundings on one card made one load look like
/// two different numbers. Display only; the draft stays canonical kilograms.
///
/// Written with the locale's decimal separator, as the keypad's separator key is labelled, and
/// without grouping, as the keypad types it: "82,5" on a comma-locale phone, and "1002.5" rather
/// than "1,002.5" for a load typed as 1002.5.
enum LoadFigure {
  static func text(_ value: Double, locale: Locale = .current) -> String {
    guard value.isFinite else { return "—" }
    return value.formatted(
      .number.precision(.fractionLength(0...2)).grouping(.never).locale(locale)
    )
  }

  /// Keypad text, which is always stored with ".", written with the locale's separator.
  static func typed(_ text: String, locale: Locale = .current) -> String {
    let separator = locale.decimalSeparator ?? "."
    return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
  }
}

/// Column widths shared by `SetRowView` and the column header `ExerciseSectionView` draws above
/// the rows, so the header's labels sit exactly over the values they name.
///
/// Sized for the narrowest supported phone. The row's fixed parts are the 28 pt ordinal, the 60 pt
/// last-time column, the 56 pt log control and three 8 pt gaps, 168 pt; a 375 pt screen leaves it
/// 343 pt inside the session's page margins, and the remaining 175 pt is the weight, the multiply
/// sign and the reps, which share it, the sign taking its own width and each figure half the rest.
enum SetRowMetrics {
  static let ordinalWidth: CGFloat = 28
  static let previousWidth: CGFloat = 60
  /// The multiply sign's column, and the gap the column header leaves between the unit and "Reps"
  /// so each label sits over its figures.
  static let multiplyWidth: CGFloat = 24
}
