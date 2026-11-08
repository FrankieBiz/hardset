import Foundation

/// RFC 4180 fields, including escaped quotes, embedded newlines and empty trailing cells.
/// Syntax errors stop an import before any durable rows are created.
public enum CSVDocument {
  public static func decode(_ text: String) throws -> [[String]] {
    let characters = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    let delimiter = separator(in: characters)
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var closed = false
    var index = characters.startIndex
    while index < characters.endIndex {
      let character = characters[index]
      if quoted {
        if character == "\"" {
          if characters.index(after: index) < characters.endIndex, characters[characters.index(after: index)] == "\"" {
            field.append("\""); index = characters.index(after: index)
          } else { quoted = false; closed = true }
        } else { field.append(character) }
      } else if character == "," || character == ";" {
        // The separator is decided from the header, outside quoted fields.
        if character == delimiter {
          row.append(field); field = ""; closed = false
        } else {
          guard !closed else { throw CSVError.malformed(row: rows.count + 1) }
          field.append(character)
        }
      } else if character == "\n" || character == "\r" || character == "\r\n" {
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        row = []; field = ""; closed = false
        if character == "\r", characters.index(after: index) < characters.endIndex, characters[characters.index(after: index)] == "\n" { index = characters.index(after: index) }
      } else if character == "\"" {
        guard field.isEmpty, !closed else { throw CSVError.malformed(row: rows.count + 1) }
        quoted = true
      } else {
        guard !closed else { throw CSVError.malformed(row: rows.count + 1) }
        field.append(character)
      }
      index = characters.index(after: index)
    }
    guard !quoted else { throw CSVError.malformed(row: rows.count + 1) }
    if !field.isEmpty || !row.isEmpty || closed { row.append(field); rows.append(row) }
    return rows
  }

  private static func separator(in characters: String) -> Character {
    var quoted = false
    for character in characters {
      if character == "\"" { quoted.toggle() }
      if !quoted {
        if character == ";" { return ";" }
        if character == "," { return "," }
        if character == "\n" || character == "\r" || character == "\r\n" { break }
      }
    }
    return ","
  }

  public static func encode(_ rows: [[String]]) -> String {
    rows.map { row in
      row.map { field in
        if field.contains(where: { ",;\"\r\n".contains($0) }) {
          return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
      }.joined(separator: ",")
    }.joined(separator: "\r\n") + "\r\n"
  }
}

public enum CSVError: Error, Equatable, Sendable {
  case malformed(row: Int)
}
