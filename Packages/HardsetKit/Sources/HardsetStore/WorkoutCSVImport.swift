import Foundation
import HardsetCore

/// Import preview owns parsed facts. Missing equipment never acquires a machine identity.
public nonisolated struct WorkoutImportPreview: Sendable {
  public let source: String
  public let sessions: [Workout]
  public let interpretation: String
  public let originalCSV: String
  /// Rows recognised as something other than a loaded strength set, left out rather than given an
  /// invented load or rep count. Empty unless the preview was built with
  /// `skippingUnsupportedRows`.
  public let skipped: [SkippedRow]
  public var setCount: Int { sessions.reduce(0) { $0 + $1.sets.count } }

  /// A file row that will not be imported, and why.
  public struct SkippedRow: Sendable, Equatable {
    /// The row's line in the file, counting the header as line 1.
    public let line: Int
    public let reason: Reason

    public init(line: Int, reason: Reason) {
      self.line = line
      self.reason = reason
    }

    public enum Reason: Sendable, Equatable {
      /// No rep count, or zero reps: a timed set (a plank), a distance set (a run) or an empty row.
      case noReps
      /// Reps but a blank load: an unweighted set the exporting app recorded without a weight.
      case noLoad
    }
  }

  public struct Workout: Sendable {
    public let title: String
    public let startedAt: Date
    public let finishedAt: Date
    public var sets: [Set]
    /// The start exactly as the file wrote it. A date without an offset means a different instant
    /// in each time zone, so a later import compares this text, read in the zone an earlier
    /// import used, rather than trusting today's zone.
    let startText: String
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
  ///
  /// - Parameter skippingUnsupportedRows: When `false`, any row without an explicit load and rep
  ///   count fails the whole preview. When `true`, rows with no reps (timed, distance or zero-rep
  ///   sets) or a blank load (unweighted sets) are listed in `skipped` and left out, because one
  ///   plank in years of history should not block the rest. Malformed rows -- a bad date, unit or
  ///   column count, a negative or non-finite number -- still fail the whole preview either way.
  public static func preview(
    _ text: String, strongUnit: WeightUnit, timeZone: TimeZone = .current,
    skippingUnsupportedRows: Bool = false
  ) throws -> WorkoutImportPreview {
    let rows = try CSVDocument.decode(text)
    guard let first = rows.first, rows.count > 1 else { throw WorkoutImportError.empty }
    // A semicolon-separated file comes from a comma-decimal locale, where "82,5" is 82.5. In a
    // comma-separated file the same cell can only have been quoted text, so it stays invalid.
    let commaDecimals = CSVDocument.separator(of: text) == ";"
    func number(_ text: String) -> Double? {
      Double(commaDecimals ? text.replacingOccurrences(of: ",", with: ".") : text)
    }
    var skipped: [WorkoutImportPreview.SkippedRow] = []
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
    var dates = DateParser(timeZone: timeZone)
    for (offset, row) in rows.dropFirst().enumerated() {
      let line = offset + 2
      guard row.count == headers.count else { throw WorkoutImportError.row(line, "Column count differs from the header") }
      let startText = value(row, hevy ? "start_time" : "date")
      guard let start = dates.date(startText) else {
        throw WorkoutImportError.row(line, "Unrecognized start date")
      }
      let end: Date
      if hevy {
        guard let parsed = dates.date(value(row, "end_time")), parsed >= start else {
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
      if skippingUnsupportedRows {
        // Recognised non-strength or unloaded rows. Neither a load nor a rep count is invented
        // for them; anything else malformed still falls through to the error below.
        let rawReps = value(row, "reps").trimmingCharacters(in: .whitespaces)
        if rawReps.isEmpty || Int(rawReps) == 0 {
          skipped.append(.init(line: line, reason: .noReps))
          continue
        }
        if rawWeight.trimmingCharacters(in: .whitespaces).isEmpty {
          skipped.append(.init(line: line, reason: .noLoad))
          continue
        }
      }
      guard !exercise.isEmpty, let weight = number(rawWeight), weight.isFinite, weight >= 0,
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
      let rpe = number(rpeText)
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
        sessions.append(.init(
          title: title, startedAt: start, finishedAt: end, sets: [set], startText: startText))
      }
    }
    guard !sessions.isEmpty else {
      throw skipped.isEmpty ? WorkoutImportError.empty : WorkoutImportError.noSupportedSets(skipped: skipped.count)
    }
    return .init(source: hevy ? "Hevy" : "Strong", sessions: sessions,
      interpretation: "Unitless Strong loads interpreted as \(strongUnit.abbreviation). \(zoneNote)\(timeZone.identifier).",
      originalCSV: text, skipped: skipped)
  }

  /// Precedes the time-zone identifier in every preview's interpretation, which `commit` writes
  /// into each imported session's notes. A later import reads the zone back from there.
  static let zoneNote = "Dates without an offset interpreted in "

  /// The zone an imported session's notes say its dates were read in, if they say.
  static func interpretedTimeZone(inNotes notes: String) -> TimeZone? {
    guard let marker = notes.range(of: zoneNote) else { return nil }
    let rest = notes[marker.upperBound...]
    let identifier = rest.prefix { $0 != "." && !$0.isWhitespace }
    return TimeZone(identifier: String(identifier))
  }

  /// Parses export dates with formatters built once, not once per cell per format: ICU setup per
  /// formatter made a multi-year export take tens of seconds. The format that matched last is
  /// tried first, since every row of a file uses the same one.
  ///
  /// A date without an offset is a wall-clock time in `timeZone`. Its text is validated strictly
  /// in GMT, where no wall time is skipped, and then placed in `timeZone` by the calendar. A wall
  /// time inside a spring-forward gap therefore resolves to the adjacent valid instant instead of
  /// failing the whole file, while a date such as 30 February is still refused.
  nonisolated struct DateParser {
    private static let wallClockFormats = [
      "yyyy-MM-dd HH:mm:ss", "dd MMM yyyy, HH:mm", "d MMM yyyy, HH:mm", "yyyy-MM-dd'T'HH:mm:ss",
    ]
    private let fractionalISO: ISO8601DateFormatter
    private let iso: ISO8601DateFormatter
    private let wallClock: [DateFormatter]
    private let gmtCalendar: Calendar
    private let localCalendar: Calendar
    private var lastMatch = 0
    private var parsed: [String: Date] = [:]

    init(timeZone: TimeZone) {
      fractionalISO = ISO8601DateFormatter()
      fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime]
      let gmt = TimeZone(secondsFromGMT: 0)!
      var gmtCalendar = Calendar(identifier: .gregorian)
      gmtCalendar.timeZone = gmt
      self.gmtCalendar = gmtCalendar
      var localCalendar = Calendar(identifier: .gregorian)
      localCalendar.timeZone = timeZone
      self.localCalendar = localCalendar
      wallClock = Self.wallClockFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = gmtCalendar
        formatter.timeZone = gmt
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
      }
    }

    mutating func date(_ text: String) -> Date? {
      // Every set row of a workout repeats its dates, so most cells were read already.
      if let known = parsed[text] { return known }
      guard let result = parse(text) else { return nil }
      parsed[text] = result
      return result
    }

    private mutating func parse(_ text: String) -> Date? {
      // An internet date-time always separates date and time with "T", so the common Strong and
      // Hevy texts skip two failing ISO attempts per cell.
      if text.contains(where: { $0 == "T" || $0 == "t" }),
        let result = fractionalISO.date(from: text) ?? iso.date(from: text)
      {
        return result
      }
      let order = [lastMatch] + wallClock.indices.filter { $0 != lastMatch }
      for index in order {
        guard let gmtWallClock = wallClock[index].date(from: text) else { continue }
        lastMatch = index
        let parts = gmtCalendar.dateComponents(
          [.era, .year, .month, .day, .hour, .minute, .second], from: gmtWallClock)
        return localCalendar.date(from: parts)
      }
      return nil
    }
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
  /// Every row was a timed, distance or unloaded set, so there is nothing to import.
  case noSupportedSets(skipped: Int)
  public var errorDescription: String? {
    switch self {
    case .empty: "The CSV contains no sets."
    case .headers: "Use an English Strong or Hevy CSV export with its original header."
    case .row(let row, let reason): "Row \(row): \(reason). No workouts were imported."
    case .alreadyImported: "This exact CSV has already been imported on this device."
    case .noSupportedSets(let skipped):
      "None of the \(skipped) rows is a set with a recorded load and reps. Timed, distance and "
        + "unweighted sets are not imported, so nothing was imported."
    }
  }
}
