import Foundation

/// Reading a number a person typed on a system keyboard.
///
/// The logger itself never needs this: it uses `NumericPad`, which keeps the typed characters and
/// the stored value separate on purpose, so the display separator and the canonical "." cannot get
/// confused. Anywhere the *system* decimal pad is used, though, the separator is whatever the device
/// is set to, and `Double("62,5")` is nil in every locale on earth.
///
/// That is not a hypothetical. Bodyweight entry read its field with `Double(text)` behind a `guard`
/// that returned silently: a lifter in France or Germany typed a fractional weight, tapped Save, and
/// had nothing recorded and nothing said.
public nonisolated enum TypedNumber {
  /// Parses what a person typed, or `nil` if it is not a number.
  ///
  /// Tries the locale's own format first, then the canonical form, then a comma-for-point swap --
  /// because a device set to one locale may well be driving a keyboard from another, and both
  /// spellings mean the same weight.
  ///
  /// - Parameter locale: Injectable so the behaviour can be tested somewhere other than whatever
  ///   locale the test machine happens to have.
  public static func parse(_ text: String, locale: Locale = .current) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = locale
    if let number = formatter.number(from: trimmed) { return number.doubleValue }

    if let plain = Double(trimmed) { return plain }
    // Only when there is exactly one comma and no point, so "1,234" in a locale that groups with
    // commas is not silently turned into 1.234.
    guard trimmed.filter({ $0 == "," }).count == 1, !trimmed.contains(".") else { return nil }
    return Double(trimmed.replacingOccurrences(of: ",", with: "."))
  }
}
