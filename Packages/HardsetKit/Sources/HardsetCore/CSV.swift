import Foundation

/// Comma-separated output, escaped correctly.
///
/// Its own type, and unit-tested, because CSV escaping is the kind of thing that looks trivial and
/// then loses somebody's data: a machine called `Hammer Strength, row 2` or an exercise note
/// containing a quote silently shifts every later column, and the file still opens without
/// complaint. A user who exports their training history and gets a subtly wrong file is worse off
/// than one who cannot export at all, because they will not find out for months.
///
/// Foundation-only and free of any database handle, like everything else in this module.
public enum CSV {
  /// One row, terminated with CRLF.
  ///
  /// RFC 4180 specifies CRLF, and it is what Excel expects; Numbers and every command-line tool
  /// accept it too.
  public static func row(_ fields: [String]) -> String {
    fields.map(escape).joined(separator: ",") + "\r\n"
  }

  /// Quotes a field only when it needs it, doubling any quotes inside.
  ///
  /// A leading or trailing space is also quoted: unquoted, some readers strip it, which would
  /// silently rename a gym.
  public static func escape(_ field: String) -> String {
    // Scalars, not Characters. In Swift `"\r\n"` is a single grapheme cluster, so
    // `field.contains("\n")` is **false** for a field containing a CRLF -- which is exactly the
    // text a lifter produces by pasting a note in from somewhere else. That field would have gone
    // out unquoted, ending the row early and shifting every column after it, in a file that still
    // opens without complaint. Scalar membership sees both halves.
    let breaking: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]
    let needsQuoting =
      field.unicodeScalars.contains(where: breaking.contains)
      || field.hasPrefix(" ") || field.hasSuffix(" ")
    guard needsQuoting else { return field }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  /// A number as a plain decimal, never in scientific notation and never localised.
  ///
  /// `String(describing:)` on a `Double` produces `1e-05` for small values and a locale-dependent
  /// separator through some formatters — either of which turns a weight column into text on
  /// import. Trailing `.0` is dropped so 80 kg exports as `80`, not `80.0`.
  public static func number(_ value: Double) -> String {
    guard value.isFinite else { return "" }
    if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
    return String(format: "%.4f", value)
      .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
  }

  /// Timestamps as ISO 8601 with the offset, so a reader can tell when a set was actually
  /// performed rather than guessing a zone.
  public static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
