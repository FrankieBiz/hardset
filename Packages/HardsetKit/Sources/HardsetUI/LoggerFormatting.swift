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
/// Sized for the narrowest supported phone. With the 56 pt log control and four 8 pt gaps the row
/// needs 292 pt; a 375 pt screen leaves it 319 pt inside the session's margins, the card's padding
/// and the row's inset, and the slack goes to the two entry fields.
enum SetRowMetrics {
  static let ordinalWidth: CGFloat = 28
  static let previousWidth: CGFloat = 60
  static let weightMinWidth: CGFloat = 64
  static let repsMinWidth: CGFloat = 52
}
