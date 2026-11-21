import Foundation
import GRDB
import HardsetCore

/// What Hardset's own exports can put back, and how a file's cells become database values.
///
/// The CSV is one row per logged set, with the set's movement, workout, gym, machine and plan row
/// written out beside it. A file is read into a `HardsetRestorePlan`, and one set of rules decides
/// what a restore may write:
///
/// - It only adds. A row whose id is already here is never changed, never replaced, never removed.
/// - A workout already here is skipped whole, with its sets, so a set the lifter has since
///   corrected away cannot come back from an older file.
/// - Column names come from this table, never from the file, and every value is checked against
///   its column's kind before anything is written.
nonisolated enum RestoreSchema {
  enum Kind: Sendable { case uuid, date, text, json, int, real, bool }

  struct Column: Sendable {
    let name: String
    let kind: Kind
    let nullable: Bool
  }

  struct Table: Sendable {
    let name: String
    let columns: [Column]

    func column(_ name: String) -> Column? { columns.first { $0.name == name } }
  }

  private static func id() -> Column { Column(name: "id", kind: .uuid, nullable: false) }
  private static func uuid(_ name: String, optional: Bool = false) -> Column {
    Column(name: name, kind: .uuid, nullable: optional)
  }
  private static func text(_ name: String, optional: Bool = false) -> Column {
    Column(name: name, kind: .text, nullable: optional)
  }
  private static func date(_ name: String, optional: Bool = false) -> Column {
    Column(name: name, kind: .date, nullable: optional)
  }
  private static func int(_ name: String, optional: Bool = false) -> Column {
    Column(name: name, kind: .int, nullable: optional)
  }
  private static func real(_ name: String, optional: Bool = false) -> Column {
    Column(name: name, kind: .real, nullable: optional)
  }
  private static func bool(_ name: String) -> Column { Column(name: name, kind: .bool, nullable: false) }

  /// In the order rows must be inserted: every table comes after the tables it references.
  ///
  /// These are the tables the lifter's own work lives in. The device-local tables (Health copies,
  /// the rest timer and its journal, the import ledger) describe this phone's state and are not
  /// restored: Health is copied again from Settings, and a rest timer from another day is a
  /// timer that never happened.
  static let tables: [Table] = [
    Table(name: "gyms", columns: [id(), text("name"), bool("isArchived"), date("createdAt")]),
    Table(name: "exercises", columns: [
      id(), text("name"), text("curatedName"), text("catalogSlug", optional: true),
      bool("isCurated"), text("modality"), text("primaryMuscle"),
      Column(name: "secondaryMusclesJSON", kind: .json, nullable: false), text("notes"),
      bool("isArchived"), date("createdAt"),
    ]),
    Table(name: "machines", columns: [
      id(), uuid("gymID"), text("name"), text("brand"), text("loadType"),
      real("stackIncrementKg", optional: true), bool("isArchived"), date("createdAt"),
    ]),
    Table(name: "machineExercises", columns: [
      id(), uuid("machineID"), uuid("exerciseID"), date("createdAt"),
    ]),
    Table(name: "workoutTemplates", columns: [
      id(), text("name"), int("position"), bool("isArchived"), date("createdAt"),
    ]),
    Table(name: "templateExercises", columns: [
      id(), uuid("templateID"), uuid("exerciseID"), uuid("machineID", optional: true),
      int("position"), int("plannedSets", optional: true), int("repRangeLower", optional: true),
      int("repRangeUpper", optional: true), int("restSeconds", optional: true), date("createdAt"),
    ]),
    Table(name: "sessions", columns: [
      id(), uuid("gymID", optional: true), text("title"), text("notes"), date("startedAt"),
      date("finishedAt", optional: true), uuid("templateID", optional: true),
    ]),
    Table(name: "sessionExercises", columns: [
      id(), uuid("sessionID"), uuid("exerciseID"), uuid("machineID", optional: true),
      int("position"), int("plannedSets", optional: true), int("repRangeLower", optional: true),
      int("repRangeUpper", optional: true),
    ]),
    Table(name: "loggedSets", columns: [
      id(), uuid("sessionID"), uuid("exerciseID"), uuid("machineID", optional: true),
      uuid("sessionExerciseID", optional: true), int("setOrdinal"), real("weightKg"), int("reps"),
      real("rpe", optional: true), bool("isWarmup"), date("completedAt"),
    ]),
    Table(name: "bodyweightEntries", columns: [
      id(), real("weightKg"), date("measuredAt"), text("enteredBy"),
    ]),
  ]

  static func table(_ name: String) -> Table? { tables.first { $0.name == name } }

  // MARK: - Cells

  /// A CSV cell read as the kind of column it belongs to, or nil when it cannot be one.
  ///
  /// An empty cell is NULL in a column that allows it, and in a text column that does not, an
  /// empty string: the CSV cannot tell the two apart, and nothing here writes an empty string into
  /// a nullable column.
  static func value(fromCell cell: String, for column: Column, commaDecimals: Bool = false) -> DatabaseValue? {
    if cell.isEmpty {
      if column.nullable { return .null }
      if column.kind == .text { return "".databaseValue }
      return nil
    }
    let trimmed = cell.trimmingCharacters(in: .whitespaces)
    let raw: DatabaseValue
    switch column.kind {
    case .text, .uuid, .date, .json:
      raw = (column.kind == .text || column.kind == .json ? cell : trimmed).databaseValue
    case .int:
      guard let number = Int64(trimmed) else { return nil }
      raw = number.databaseValue
    case .real:
      guard let number = Double(commaDecimals ? trimmed.replacingOccurrences(of: ",", with: ".") : trimmed)
      else { return nil }
      raw = number.databaseValue
    case .bool:
      switch trimmed.lowercased() {
      case "0", "false": raw = Int64(0).databaseValue
      case "1", "true": raw = Int64(1).databaseValue
      default: return nil
      }
    }
    return normalized(raw, for: column)
  }

  /// A value read from a file, in the form the column stores it, or nil when it cannot be stored.
  static func normalized(_ value: DatabaseValue, for column: Column) -> DatabaseValue? {
    switch value.storage {
    case .null:
      return column.nullable ? .null : nil
    case .blob:
      return nil
    case .int64(let number):
      switch column.kind {
      case .int: return value
      case .real: return Double(number).databaseValue
      case .bool: return number == 0 || number == 1 ? value : nil
      default: return nil
      }
    case .double(let number):
      guard number.isFinite else { return nil }
      return column.kind == .real ? value : nil
    case .string(let text):
      switch column.kind {
      case .text: return value
      case .uuid:
        guard let uuid = UUID(uuidString: text) else { return nil }
        return uuid.uuidString.lowercased().databaseValue
      case .date:
        return StoredDate.isStored(text) ? value : nil
      case .json:
        let data = Data(text.utf8)
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) == nil
          ? nil : value
      default: return nil
      }
    }
  }

  /// A value the file has to get right even where the column would accept anything, because a
  /// load or a count outside these is not something Hardset can have recorded.
  static func domainProblem(table: String, row: [String: DatabaseValue]) -> String? {
    func double(_ name: String) -> Double? {
      if case .double(let number) = row[name]?.storage { return number }
      return nil
    }
    func integer(_ name: String) -> Int64? {
      if case .int64(let number) = row[name]?.storage { return number }
      return nil
    }
    switch table {
    case "loggedSets":
      if let weight = double("weightKg"), weight < 0 { return "A load cannot be negative" }
      if let reps = integer("reps"), reps < 0 { return "A rep count cannot be negative" }
      if let rpe = double("rpe"), !(0...10).contains(rpe) { return "RPE must be from 0 to 10" }
    case "machines":
      if let step = double("stackIncrementKg"), step <= 0 { return "A machine's load step must be above zero" }
    case "bodyweightEntries":
      if let weight = double("weightKg"), weight <= 0 { return "A body mass must be above zero" }
    default: break
    }
    return nil
  }
}

/// The text the database writes for an instant, `2026-11-01 10:00:00.000` in UTC, fraction
/// optional. Rows are ordered and indexed on this text, so a date in any other form would sort
/// wrongly rather than fail; only this form is accepted.
///
/// Read by hand rather than with a formatter: a restore checks one of these per set, and building
/// formatters per cell would cost more than the rest of the import together.
nonisolated enum StoredDate {
  static func isStored(_ text: String) -> Bool { date(text) != nil }

  static func date(_ text: String) -> Date? {
    let bytes = Array(text.utf8)
    guard bytes.count >= 19, bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x20,
      bytes[13] == 0x3A, bytes[16] == 0x3A
    else { return nil }
    func digits(_ range: Range<Int>) -> Int? {
      var value = 0
      for index in range {
        guard (0x30...0x39).contains(bytes[index]) else { return nil }
        value = value * 10 + Int(bytes[index] - 0x30)
      }
      return value
    }
    guard let year = digits(0..<4), let month = digits(5..<7), let day = digits(8..<10),
      let hour = digits(11..<13), let minute = digits(14..<16), let second = digits(17..<19),
      (1...12).contains(month), hour < 24, minute < 60, second < 60
    else { return nil }
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    let monthLengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...monthLengths[month - 1]).contains(day) else { return nil }
    var fraction = 0.0
    if bytes.count > 19 {
      guard bytes[19] == 0x2E, bytes.count >= 21, bytes.count <= 29,
        let digitsAfterPoint = digits(20..<bytes.count)
      else { return nil }
      fraction = Double(digitsAfterPoint) / pow(10, Double(bytes.count - 20))
    }
    // Days since 1970-01-01 in the proleptic Gregorian calendar.
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = shiftedYear / 400
    let yearOfEra = shiftedYear - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    let days = era * 146_097 + dayOfEra - 719_468
    let seconds = Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second)
    return Date(timeIntervalSince1970: seconds + fraction)
  }
}

/// A file's rows, read, checked and held until the lifter decides. Nothing here has touched the
/// database; `DataTransferStore.restore` writes it in one transaction.
nonisolated struct HardsetRestorePlan: Sendable {
  typealias Row = [String: DatabaseValue]

  /// One row per id, in the order the file first described it.
  struct Rows: Sendable {
    private(set) var order: [Row] = []
    private var index: [String: Int] = [:]

    var count: Int { order.count }

    /// Returns false when this id was described differently before.
    mutating func add(_ row: Row) -> Bool {
      guard let id = HardsetRestorePlan.id(of: row) else { return false }
      if let existing = index[id] { return order[existing] == row }
      index[id] = order.count
      order.append(row)
      return true
    }
  }

  var layout: WorkoutImportPreview.Restore.Layout
  var tables: [String: Rows] = [:]
  /// Gyms an earlier CSV named but could not identify. They are matched to a gym of the same name
  /// already here, or created, when the file is committed.
  var gymsToMatchByName: Set<String> = []
  /// Workouts in the file with no finish time. A restore leaves them out: an open workout is the
  /// one the app offers to resume, and a restored one would compete with the lifter's own.
  var unfinishedWorkouts = 0

  func rows(_ table: String) -> [Row] { tables[table]?.order ?? [] }

  static func id(of row: Row) -> String? {
    if case .string(let id) = row["id"]?.storage { return id }
    return nil
  }

  static func string(_ row: Row, _ column: String) -> String? {
    if case .string(let text) = row[column]?.storage { return text }
    return nil
  }

  var savedWorkouts: Int { rows("workoutTemplates").count }
  var bodyweightEntries: Int { rows("bodyweightEntries").count }

  /// The workouts the file would add, as the import preview card shows them.
  func previewWorkouts() -> [WorkoutImportPreview.Workout] {
    let names = Dictionary(
      rows("exercises").compactMap { row in
        Self.id(of: row).flatMap { id in Self.string(row, "name").map { (id, $0) } }
      }, uniquingKeysWith: { first, _ in first })
    var setsBySession: [String: [Row]] = [:]
    for set in rows("loggedSets") {
      if let session = Self.string(set, "sessionID") { setsBySession[session, default: []].append(set) }
    }
    return rows("sessions").compactMap { session -> WorkoutImportPreview.Workout? in
      guard let id = Self.id(of: session), let startText = Self.string(session, "startedAt"),
        let endText = Self.string(session, "finishedAt"),
        let start = StoredDate.date(startText), let end = StoredDate.date(endText)
      else { return nil }
      let sets = (setsBySession[id] ?? []).sorted {
        (Self.string($0, "completedAt") ?? "", Self.integer($0, "setOrdinal"))
          < (Self.string($1, "completedAt") ?? "", Self.integer($1, "setOrdinal"))
      }.map { set -> WorkoutImportPreview.Set in
        WorkoutImportPreview.Set(
          exercise: Self.string(set, "exerciseID").flatMap { names[$0] } ?? "Movement",
          weightKg: Self.double(set, "weightKg"), reps: Int(Self.integer(set, "reps")),
          isWarmup: Self.integer(set, "isWarmup") == 1,
          rpe: { if case .double(let rpe) = set["rpe"]?.storage { return rpe } else { return nil } }(),
          notes: "")
      }
      return WorkoutImportPreview.Workout(
        title: Self.string(session, "title") ?? "", startedAt: start, finishedAt: end, sets: sets,
        startText: startText)
    }
  }

  private static func integer(_ row: Row, _ column: String) -> Int64 {
    if case .int64(let number) = row[column]?.storage { return number }
    return 0
  }

  private static func double(_ row: Row, _ column: String) -> Double {
    if case .double(let number) = row[column]?.storage { return number }
    return 0
  }

  /// The import preview for this plan, which `commit` recognises by its `restore` payload.
  func preview(source text: String, interpretation: String) throws -> WorkoutImportPreview {
    let workouts = previewWorkouts()
    guard !workouts.isEmpty else {
      throw unfinishedWorkouts > 0
        ? WorkoutImportError.unreadable(
          "Every workout in this file was unfinished, and an unfinished workout is not restored. Finish it in Hardset and export again")
        : WorkoutImportError.empty
    }
    return WorkoutImportPreview(
      source: "Hardset", sessions: workouts, interpretation: interpretation, originalCSV: text,
      skipped: [], restore: .init(
        layout: layout, savedWorkouts: savedWorkouts, bodyweightEntries: bodyweightEntries,
        unfinishedWorkouts: unfinishedWorkouts, plan: self))
  }
}
