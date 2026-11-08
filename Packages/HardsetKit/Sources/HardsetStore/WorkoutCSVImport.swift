import Foundation
import HardsetCore

/// Import preview owns parsed facts. Missing equipment never acquires a machine identity.
public nonisolated struct WorkoutImportPreview: Sendable {
  public let source: String
  public let sessions: [Workout]
  public let originalCSV: String
  public var setCount: Int { sessions.reduce(0) { $0 + $1.sets.count } }

  public struct Workout: Sendable {
    public let title: String
    public let startedAt: Date
    public let finishedAt: Date
    public var sets: [Set]
  }

  public struct Set: Sendable {
    public let exercise: String
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let rpe: Double?
    public let notes: String
  }
}

public nonisolated enum WorkoutCSVImport {
  /// Strong's unitless Weight column uses an explicit user-selected unit. Never infer it
  /// from load magnitude. Hevy's weight_kg/weight_lbs headers and Weight Unit take priority.
  public static func preview(
    _ text: String, strongUnit: WeightUnit, timeZone: TimeZone = .current
  ) throws -> WorkoutImportPreview {
    let rows = try CSVDocument.decode(text)
    guard let first = rows.first, rows.count > 1 else { throw WorkoutImportError.empty }
    let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    guard Set(headers).count == headers.count else { throw WorkoutImportError.headers }
    let hevy = headers.contains("exercise_title")
    guard headers.contains(hevy ? "start_time" : "date"),
      headers.contains(hevy ? "exercise_title" : "exercise name"), headers.contains("reps")
    else { throw WorkoutImportError.headers }
    func value(_ row: [String], _ names: String...) -> String {
      for name in names {
        if let index = headers.firstIndex(of: name), row.indices.contains(index) { return row[index] }
      }
      return ""
    }
    var sessions: [WorkoutImportPreview.Workout] = []
    var indexes: [String: Int] = [:]
    for (offset, row) in rows.dropFirst().enumerated() {
      let line = offset + 2
      guard row.count == headers.count else { throw WorkoutImportError.row(line, "Column count differs from the header") }
      let startText = value(row, hevy ? "start_time" : "date")
      guard let start = date(startText, timeZone: timeZone) else {
        throw WorkoutImportError.row(line, "Unrecognized start date")
      }
      let end: Date
      if hevy {
        guard let parsed = date(value(row, "end_time"), timeZone: timeZone), parsed >= start else {
          throw WorkoutImportError.row(line, "Missing or invalid end date")
        }
        end = parsed
      } else {
        guard let duration = duration(value(row, "duration", "workout duration")) else {
          throw WorkoutImportError.row(line, "Missing or invalid workout duration")
        }
        end = start.addingTimeInterval(duration)
      }
      guard end.timeIntervalSince1970.isFinite, end <= Date.distantFuture else {
        throw WorkoutImportError.row(line, "Workout end date is outside the supported calendar range")
      }
      let exercise = value(row, hevy ? "exercise_title" : "exercise name").trimmingCharacters(in: .whitespacesAndNewlines)
      let rawWeight = value(row, "weight_kg", "weight_lbs", "weight")
      guard !exercise.isEmpty, let weight = Double(rawWeight), weight.isFinite, weight >= 0,
        let reps = Int(value(row, "reps")), (1...999).contains(reps), weight <= 10000
      else { throw WorkoutImportError.row(line, "Supported sets need an explicit load from 0 to 10,000 and 1 to 999 reps") }
      let unit: WeightUnit
      if headers.contains("weight_kg") { unit = .kilograms }
      else if headers.contains("weight_lbs") { unit = .pounds }
      else {
        let recorded = value(row, "weight unit").lowercased()
        switch recorded {
        case "kg", "kgs", "kilograms": unit = .kilograms
        case "lb", "lbs", "pounds": unit = .pounds
        case "": unit = strongUnit
        default: throw WorkoutImportError.row(line, "Unrecognized weight unit")
        }
      }
      let rpeText = value(row, "rpe")
      let rpe = Double(rpeText)
      guard rpeText.isEmpty || (rpe.map { $0.isFinite && (0...10).contains($0) } == true) else {
        throw WorkoutImportError.row(line, "Invalid RPE")
      }
      let title = value(row, "title", "workout name")
      let key = startText + "\u{0}" + title
      let set = WorkoutImportPreview.Set(exercise: exercise, weightKg: unit.toKilograms(weight),
        reps: reps, isWarmup: value(row, "set_type", "set order").lowercased() == "warmup"
          || value(row, "set order").uppercased() == "W", rpe: rpe,
        notes: value(row, "exercise_notes", "notes"))
      if let index = indexes[key] {
        guard sessions[index].finishedAt == end else { throw WorkoutImportError.row(line, "Conflicting workout end dates") }
        sessions[index].sets.append(set)
      } else {
        indexes[key] = sessions.count
        sessions.append(.init(title: title, startedAt: start, finishedAt: end, sets: [set]))
      }
    }
    return .init(source: hevy ? "Hevy" : "Strong", sessions: sessions, originalCSV: text)
  }

  private static func date(_ text: String, timeZone: TimeZone) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let result = iso.date(from: text) { return result }
    iso.formatOptions = [.withInternetDateTime]
    if let result = iso.date(from: text) { return result }
    for format in ["yyyy-MM-dd HH:mm:ss", "dd MMM yyyy, HH:mm", "d MMM yyyy, HH:mm", "yyyy-MM-dd'T'HH:mm:ss"] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = timeZone
      formatter.dateFormat = format
      formatter.isLenient = false
      if let result = formatter.date(from: text) { return result }
    }
    return nil
  }

  private static func duration(_ text: String) -> TimeInterval? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let seconds = Double(text), seconds.isFinite, seconds >= 0 { return seconds }
    let parts = text.split(separator: ":").compactMap { Double($0) }
    if parts.count == 3, parts.allSatisfy({ $0.isFinite && $0 >= 0 }), parts[1] < 60, parts[2] < 60 {
      return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
    var total = 0.0
    var remaining = text[...]
    for (suffix, multiplier) in [("h", 3600.0), ("m", 60.0), ("s", 1.0)] {
      if let index = remaining.firstIndex(of: Character(suffix)) {
        guard let number = Double(remaining[..<index].trimmingCharacters(in: .whitespaces)),
          number.isFinite, number >= 0 else { return nil }
        total += number * multiplier
        remaining = remaining[remaining.index(after: index)...]
      }
    }
    return remaining.trimmingCharacters(in: .whitespaces).isEmpty && !text.isEmpty && total.isFinite ? total : nil
  }
}

public nonisolated enum WorkoutImportError: Error, Equatable, Sendable, LocalizedError {
  case empty
  case headers
  case row(Int, String)
  case alreadyImported
  public var errorDescription: String? {
    switch self {
    case .empty: "The CSV contains no sets."
    case .headers: "Use an English Strong or Hevy CSV export with its original header."
    case .row(let row, let reason): "Row \(row): \(reason). No workouts were imported."
    case .alreadyImported: "This exact CSV has already been imported on this device."
    }
  }
}
