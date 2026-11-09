import Foundation
import GRDB
import HardsetCore
import SQLiteData

/// What one committed import wrote, and what it left out as already imported.
public nonisolated struct WorkoutImportResult: Sendable, Equatable {
  public let importedWorkouts: Int
  public let importedSets: Int
  /// Workouts in the file already imported from the same app's earlier export.
  public let skippedWorkouts: Int

  public init(importedWorkouts: Int, importedSets: Int, skippedWorkouts: Int) {
    self.importedWorkouts = importedWorkouts
    self.importedSets = importedSets
    self.skippedWorkouts = skippedWorkouts
  }
}

/// Free, complete exports and atomic migration of a validated external workout file.
/// No live database connection or lazy row escapes a read snapshot.
public nonisolated struct DataTransferStore: Sendable {
  private let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  public enum Format: String, CaseIterable, Sendable {
    case csv, json, sqlite

    /// How the format is written in prose: "SQLite", not "SQLITE".
    public var displayName: String {
      switch self {
      case .csv: "CSV"
      case .json: "JSON"
      case .sqlite: "SQLite"
      }
    }
  }

  /// Every export gets its own directory, so overlapping shares cannot replace each other's file.
  /// SQLite uses the online backup API, including committed WAL pages. It never copies a live file.
  ///
  /// The file is named for the local day it was made, `Hardset-2026-11-09.csv`, so exports saved
  /// side by side in Files can be told apart without opening them.
  public func export(
    _ format: Format, directory: URL, madeAt: Date = Date(), timeZone: TimeZone = .current
  ) async throws -> URL {
    try Task.checkCancellation()
    let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = folder.appendingPathComponent(
      "\(Self.fileStem(madeAt: madeAt, timeZone: timeZone)).\(format.rawValue)")
    do {
      switch format {
      case .csv:
        let data = try await database.read { db in try Self.csv(in: db) }
        try data.write(to: destination, options: .atomic)
      case .json:
        let data = try await database.read { db in try Self.json(in: db) }
        try data.write(to: destination, options: .atomic)
      case .sqlite:
        // The source read suspends; backup itself runs on its database queue.
        let output = try DatabaseQueue(path: destination.path)
        try await database.read { source in
          try output.writeWithoutTransaction { target in try source.backup(to: target) }
        }
        try output.close()
      }
      try Task.checkCancellation()
      return destination
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }

  private static func fileStem(madeAt: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return "Hardset-\(formatter.string(from: madeAt))"
  }

  /// Imports the previewed sets and returns how many were written.
  ///
  /// Workouts already imported from the same app are skipped; `commit(_:)` reports how many.
  public func importWorkouts(_ preview: WorkoutImportPreview) async throws -> Int {
    try await commit(preview).importedSets
  }

  /// How many of the previewed workouts are already in Hardset from an earlier import of the
  /// same app's export, and would be skipped. Read before committing, so the preview can say so.
  public func alreadyImportedWorkoutCount(in preview: WorkoutImportPreview) async throws -> Int {
    try Task.checkCancellation()
    return try await database.read { db in
      var count = 0
      for workout in preview.sessions where try Self.isAlreadyImported(workout, from: preview.source, in: db) {
        count += 1
      }
      return count
    }
  }

  /// Preview construction is public only through the parser, so callers cannot forge a
  /// validated workout or substitute file contents between validation and persistence.
  ///
  /// Strong and Hevy export the whole history every time, so a later export repeats every
  /// workout an earlier one carried. A workout is skipped when an imported session from the same
  /// app already has its start and title; a native session at the same moment is the lifter's own
  /// and never counts. The exact-file refusal still applies on top. A file that adds nothing is not
  /// retained as an import.
  public func commit(_ preview: WorkoutImportPreview) async throws -> WorkoutImportResult {
    try Task.checkCancellation()
    return try await database.write { db in
      if try Row.fetchOne(db, sql: "SELECT id FROM deviceImportBatches WHERE sourceCSV = ?",
        arguments: [preview.originalCSV]) != nil { throw WorkoutImportError.alreadyImported }
      // Use separate movements for unverified imported equipment. An imported nil machine
      // must never seed the native movement's free-weight or machine benchmark series.
      var exercises: [String: UUID] = [:]
      var importedWorkouts = 0
      var importedSets = 0
      var skippedWorkouts = 0
      for workout in preview.sessions {
        if try Self.isAlreadyImported(workout, from: preview.source, in: db) {
          skippedWorkouts += 1
          continue
        }
        importedWorkouts += 1
        importedSets += workout.sets.count
        let session = UUID()
        try Session.insert {
          Session.Draft(id: session, title: workout.title,
            notes: "Imported from \(preview.source) • Unevaluated Machine. \(preview.interpretation)",
            startedAt: workout.startedAt, finishedAt: workout.finishedAt)
        }.execute(db)
        var plans: [String: UUID] = [:]
        for (ordinal, set) in workout.sets.enumerated() {
          let exercise: UUID
          let importedName = "\(set.exercise) (Imported • \(preview.source))"
          if let existing = exercises[set.exercise] { exercise = existing }
          else if let earlier = try Self.importedExercise(named: importedName, in: db) {
            // An earlier import's movement of the same name, so a later export's sets continue
            // that series instead of splitting it across two identically named movements.
            exercise = earlier
            exercises[set.exercise] = exercise
          } else {
            exercise = UUID()
            exercises[set.exercise] = exercise
            try Exercise.insert {
              Exercise.Draft(id: exercise, name: importedName,
                notes: "Imported • Unevaluated Machine. \(set.notes)", createdAt: workout.startedAt)
            }.execute(db)
          }
          let plan: UUID
          if let existing = plans[set.exercise] { plan = existing }
          else {
            plan = UUID()
            plans[set.exercise] = plan
            try SessionExercise.insert {
              SessionExercise.Draft(id: plan, sessionID: session, exerciseID: exercise,
                position: plans.count - 1)
            }.execute(db)
          }
          try LoggedSet.insert {
            LoggedSet.Draft(id: UUID(), sessionID: session, exerciseID: exercise,
              sessionExerciseID: plan, setOrdinal: ordinal, weightKg: set.weightKg,
              reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup,
              // The CSV does not record set completion instants. Preserve the workout start
              // as a grouping timestamp and disclose that limitation in the session's notes.
              completedAt: workout.startedAt)
          }.execute(db)
        }
        try db.execute(sql: "UPDATE sessions SET notes = notes || ? WHERE id = ?",
          arguments: [". Set timestamps are unavailable; grouped at workout start.", session.uuidString.lowercased()])
      }
      if importedWorkouts > 0 {
        try db.execute(sql: "INSERT INTO deviceImportBatches(id, sourceCSV) VALUES (?, ?)",
          arguments: [UUID().uuidString.lowercased(), preview.originalCSV])
      }
      return WorkoutImportResult(
        importedWorkouts: importedWorkouts, importedSets: importedSets, skippedWorkouts: skippedWorkouts)
    }
  }

  /// A live movement an earlier import created under this exact name, if any.
  private static func importedExercise(named name: String, in db: Database) throws -> UUID? {
    try Exercise
      .where { $0.name.eq(name) && $0.notes.like("Imported • %") && !$0.isArchived }
      .order { ($0.createdAt, $0.id) }
      .fetchOne(db)?
      .id
  }

  /// An imported session from the same app with the same start and title. Imported sessions are
  /// the only ones whose notes begin "Imported from <app> ", which `commit` writes.
  private static func isAlreadyImported(
    _ workout: WorkoutImportPreview.Workout, from source: String, in db: Database
  ) throws -> Bool {
    let startedAt = workout.startedAt
    let title = workout.title
    return try Session
      .where { $0.startedAt.eq(startedAt) && $0.title.eq(title) && $0.notes.like("Imported from \(source) %") }
      .fetchCount(db) > 0
  }

  private static func csv(in db: Database) throws -> Data {
    let rows = try Row.fetchAll(db, sql: """
      SELECT l.*, e.name AS exerciseName, s.title AS workoutTitle,
        s.startedAt AS workoutStart, s.finishedAt AS workoutEnd, s.notes AS workoutNotes,
        m.name AS machineName, m.brand AS machineBrand, g.name AS gymName
      FROM loggedSets l
      LEFT JOIN exercises e ON e.id = l.exerciseID
      LEFT JOIN sessions s ON s.id = l.sessionID
      LEFT JOIN machines m ON m.id = l.machineID
      LEFT JOIN gyms g ON g.id = s.gymID
      ORDER BY s.startedAt, s.id, l.setOrdinal, l.completedAt, l.id
      """)
    let columns = ["id", "sessionID", "exerciseID", "machineID", "sessionExerciseID",
      "setOrdinal", "weightKg", "reps", "rpe", "isWarmup", "completedAt", "exerciseName",
      "workoutTitle", "workoutStart", "workoutEnd", "workoutNotes", "machineName", "machineBrand", "gymName"]
    let fields = rows.map { row in columns.map { string(row[$0] as DatabaseValue) } }
    return Data(CSVDocument.encode([columns] + fields).utf8)
  }

  private static func json(in db: Database) throws -> Data {
    let names = HardsetMigrations.syncedTableNames + HardsetMigrations.deferredSyncTableNames
      + HardsetMigrations.deviceLocalTableNames
    var tables: [String: [[String: Any]]] = [:]
    for name in names {
      tables[name] = try Row.fetchAll(db, sql: "SELECT * FROM \"\(name)\" ORDER BY id").map { row in
        Dictionary(uniqueKeysWithValues: row.columnNames.map { column -> (String, Any) in
          let value: DatabaseValue = row[column]
          switch value.storage {
          case .null: return (column, NSNull())
          case .int64(let number): return (column, number)
          case .double(let number): return (column, number)
          case .string(let text): return (column, text)
          case .blob(let bytes): return (column, ["base64": bytes.base64EncodedString()])
          }
        })
      }
    }
    return try JSONSerialization.data(withJSONObject: ["format": "Hardset", "version": 1,
      "weightUnit": "kg", "tables": tables], options: [.prettyPrinted, .sortedKeys])
  }

  private static func string(_ value: DatabaseValue) -> String {
    switch value.storage {
    case .null: ""
    case .int64(let number): String(number)
    case .double(let number): String(number)
    case .string(let text): text
    case .blob(let bytes): bytes.base64EncodedString()
    }
  }
}
