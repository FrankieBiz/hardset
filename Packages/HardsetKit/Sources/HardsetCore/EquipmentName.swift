import Foundation

/// The one rule for a gym or machine name the lifter typed.
public enum EquipmentName {
  /// The name as it will be stored: spaces at either end removed, runs of spaces inside it
  /// collapsed to one, and nil when nothing is left. A blank name would put an empty row in every
  /// picker, with nothing to tell it apart.
  public static func normalized(_ raw: String) -> String? {
    let words = raw.split(whereSeparator: \.isWhitespace)
    return words.isEmpty ? nil : words.joined(separator: " ")
  }
}
