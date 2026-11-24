import Foundation
import GRDB
import HardsetCore

/// Hardset's own JSON export, read back.
///
/// The file is every table, so unlike the CSV it also carries saved workouts, body mass, workouts
/// with no sets, and the exact rows and identities the database held. It goes through the same
/// `HardsetRestorePlan` as the CSV and is written by the same rules: rows are only added, never
/// changed, and a workout already here is skipped whole.
///
/// Only files this version fully understands are read. A file written by a newer Hardset, a table
/// this version does not know, or a column it does not know is refused whole, because restoring
/// around data it cannot read would look like a complete restore and not be one.
nonisolated enum RestoreJSON {
  /// Device-local tables: this phone's retained device samples, rest timer and journal, and import
  /// ledger. They are in the file for inspection and are not restored.
  private static let deviceTables: Set<String> = Set(HardsetMigrations.deviceLocalTableNames)

  static func looksLikeJSON(_ text: String) -> Bool {
    for character in text {
      if character == "\u{FEFF}" || character.isWhitespace { continue }
      return character == "{"
    }
    return false
  }

  static let interpretation =
    "A Hardset export. Weights are stored in kilograms and dates are exact, so the unit above "
    + "and this device's time zone change nothing in it."

  private struct Envelope: Decodable {
    let format: String?
    let version: Int?
    let weightUnit: String?
    let tables: [String: [[String: Cell]]]?
  }

  private enum Cell: Decodable {
    case null, int(Int64), double(Double), string(String), unsupported

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() { self = .null }
      else if let number = try? container.decode(Int64.self) { self = .int(number) }
      else if let number = try? container.decode(Double.self) { self = .double(number) }
      else if let text = try? container.decode(String.self) { self = .string(text) }
      else { self = .unsupported }
    }

    var value: DatabaseValue? {
      switch self {
      case .null: .null
      case .int(let number): number.databaseValue
      case .double(let number): number.databaseValue
      case .string(let text): text.databaseValue
      case .unsupported: nil
      }
    }
  }

  static func preview(_ text: String) throws -> WorkoutImportPreview {
    try read(text).preview(source: text, interpretation: interpretation)
  }

  static func read(_ text: String) throws -> HardsetRestorePlan {
    let envelope: Envelope
    do {
      envelope = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8))
    } catch {
      throw WorkoutImportError.unreadable("This file is not a Hardset export")
    }
    guard envelope.format == "Hardset", let tables = envelope.tables else {
      throw WorkoutImportError.unreadable("This file is not a Hardset export")
    }
    guard envelope.version == 1 else {
      throw WorkoutImportError.unreadable(
        "This export was made by a different version of Hardset than this one can read")
    }
    guard envelope.weightUnit == "kg" else {
      throw WorkoutImportError.unreadable("This export does not say its weights are in kilograms")
    }
    let known = Set(RestoreSchema.tables.map(\.name))
    if let unknown = tables.keys.sorted().first(where: { !known.contains($0) && !deviceTables.contains($0) }) {
      throw WorkoutImportError.unreadable(
        "This export has a table, \(unknown), that this version of Hardset does not know how to restore")
    }

    var result = HardsetRestorePlan(layout: .json)
    var unfinished: Set<String> = []
    var instants: [String: Date] = [:]
    for table in RestoreSchema.tables {
      for (position, object) in (tables[table.name] ?? []).enumerated() {
        var row: HardsetRestorePlan.Row = [:]
        for (key, cell) in object {
          guard let column = table.column(key) else {
            throw WorkoutImportError.unreadable(
              "\(table.name) has a column, \(key), that this version of Hardset does not know")
          }
          guard let raw = cell.value, let value = RestoreSchema.normalized(raw, for: column) else {
            throw WorkoutImportError.unreadable(
              "\(table.name) entry \(position + 1) holds a value Hardset cannot read in \(key)")
          }
          row[key] = value
        }
        guard let id = HardsetRestorePlan.id(of: row) else {
          throw WorkoutImportError.unreadable("\(table.name) entry \(position + 1) has no id")
        }
        if let problem = RestoreSchema.domainProblem(table: table.name, row: row) {
          throw WorkoutImportError.unreadable("\(table.name) entry \(position + 1): \(problem)")
        }
        if table.name == "sessions" {
          guard let startText = HardsetRestorePlan.string(row, "startedAt") else {
            throw WorkoutImportError.unreadable("A workout has no start")
          }
          guard let endText = HardsetRestorePlan.string(row, "finishedAt") else {
            unfinished.insert(id)
            continue
          }
          guard let start = instants[startText] ?? StoredDate.date(startText),
            let end = instants[endText] ?? StoredDate.date(endText), end >= start
          else { throw WorkoutImportError.unreadable("A workout ends before it starts") }
          instants[startText] = start
          instants[endText] = end
        } else if table.name == "sessionExercises" || table.name == "loggedSets",
          let session = HardsetRestorePlan.string(row, "sessionID"), unfinished.contains(session)
        {
          continue
        }
        guard result.tables[table.name, default: .init()].add(row) else {
          throw WorkoutImportError.unreadable(
            "\(table.name) entry \(position + 1), \(id), is described two different ways in this file")
        }
      }
    }
    result.unfinishedWorkouts = unfinished.count
    return result
  }
}
