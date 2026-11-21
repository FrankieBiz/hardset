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
  /// Saved workouts a restore from Hardset's own JSON added. Zero for every other import.
  public let restoredSavedWorkouts: Int
  /// Body mass entries a restore from Hardset's own JSON added. Zero for every other import.
  public let restoredBodyweightEntries: Int
  /// Workouts in a Hardset export with no finish time, which a restore leaves out.
  public let leftOutUnfinishedWorkouts: Int

  public init(
    importedWorkouts: Int, importedSets: Int, skippedWorkouts: Int,
    restoredSavedWorkouts: Int = 0, restoredBodyweightEntries: Int = 0,
    leftOutUnfinishedWorkouts: Int = 0
  ) {
    self.importedWorkouts = importedWorkouts
    self.importedSets = importedSets
    self.skippedWorkouts = skippedWorkouts
    self.restoredSavedWorkouts = restoredSavedWorkouts
    self.restoredBodyweightEntries = restoredBodyweightEntries
    self.leftOutUnfinishedWorkouts = leftOutUnfinishedWorkouts
  }
}

/// The exact surviving rows the next undo would remove, captured for confirmation.
public nonisolated struct WorkoutImportUndo: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let sessionCount: Int
  public let setCount: Int

  public var confirmationMessage: String {
    "Delete \(sessionCount) \(sessionCount == 1 ? "session" : "sessions") and "
      + "\(setCount) \(setCount == 1 ? "set" : "sets") from the last import? "
      + "Imported movements stay in Library. This cannot be undone."
  }
}

public nonisolated enum WorkoutImportUndoError: Error, LocalizedError, Equatable {
  case changed, containsLaterChanges, unidentified

  public var errorDescription: String? {
    switch self {
    case .changed:
      "The last import changed. Review the current session and set counts before undoing."
    case .containsLaterChanges:
      "Undo is unavailable because these imported workouts contain later additions or moved rows. No training data was removed."
    case .unidentified:
      "This import cannot be undone because its exact rows are unavailable. No training data was removed."
    }
  }
}

/// Free exports and atomic migration of a validated external workout file.
/// No live database connection or lazy row escapes a read snapshot.
///
/// JSON and SQLite are complete snapshots of every table, including device-local ones. CSV is one
/// row per logged set with the set's workout, movement, gym, machine and plan row written beside
/// it; see `RestoreCSV` for exactly what it carries. The CSV and the JSON can be read back by
/// `commit` (see `DataTransferStore+Restore.swift`); the SQLite copy cannot.
public nonisolated struct DataTransferStore: Sendable {
  let database: any DatabaseWriter
  public init(database: any DatabaseWriter) { self.database = database }

  struct ImportRows: Codable {
    var sessions: [UUID] = []
    var plans: [UUID] = []
    var sets: [UUID] = []
  }

  /// Nil for a database containing only imports made before the precise ledger shipped.
  public func lastImportUndo() async throws -> WorkoutImportUndo? {
    try await database.read { db in try Self.undoPreview(in: db)?.preview }
  }

  /// Revalidates both the confirmed counts and every owned identity in the delete transaction.
  /// A later import or a later addition to its workouts requires a fresh decision, never a cascade
  /// that silently removes work the import did not create.
  public func undoLastImport(_ confirmed: WorkoutImportUndo) async throws {
    try Task.checkCancellation()
    try await database.write { db in
      guard let current = try Self.undoPreview(in: db), current.preview == confirmed else {
        throw WorkoutImportUndoError.changed
      }
      let sessionIDs = try Self.jsonIDs(current.rows.sessions)
      try db.execute(sql: "DELETE FROM sessions WHERE id IN (SELECT value FROM json_each(?))",
        arguments: [sessionIDs])
      guard db.changesCount == confirmed.sessionCount else { throw WorkoutImportUndoError.changed }
      try db.execute(sql: "DELETE FROM deviceImportBatches WHERE id = ?",
        arguments: [confirmed.id.uuidString.lowercased()])
      guard db.changesCount == 1 else { throw WorkoutImportUndoError.changed }
    }
  }

  private static func jsonIDs(_ ids: [UUID]) throws -> String {
    String(decoding: try JSONEncoder().encode(ids.map { $0.uuidString.lowercased() }), as: UTF8.self)
  }

  private static func hasSurvivingRows(_ rows: ImportRows, in db: Database) throws -> Bool {
    for (table, ids) in [("sessions", rows.sessions), ("sessionExercises", rows.plans), ("loggedSets", rows.sets)] {
      if try Bool.fetchOne(db,
        sql: "SELECT EXISTS (SELECT 1 FROM \(table) WHERE id IN (SELECT value FROM json_each(?)))",
        arguments: [try jsonIDs(ids)]) == true { return true }
    }
    return false
  }

  /// A digest, not the file: re-exports repeat the whole history, so copies added up.
  static func recordImport(digest: String, byteCount: Int, undo: ImportRows, in db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO deviceImportBatches(id, sourceCSV, sourceDigest, byteCount, undoRows, undoOrder)
        VALUES (?, '', ?, ?, ?, (SELECT coalesce(max(undoOrder), 0) + 1 FROM deviceImportBatches))
        """,
      arguments: [UUID().uuidString.lowercased(), digest, byteCount,
        String(decoding: try JSONEncoder().encode(undo), as: UTF8.self)])
  }

  private static func undoPreview(in db: Database) throws -> (preview: WorkoutImportUndo, rows: ImportRows)? {
    guard let batch = try Row.fetchOne(db, sql: """
      SELECT id, undoRows FROM deviceImportBatches
      WHERE undoOrder IS NOT NULL ORDER BY undoOrder DESC LIMIT 1
      """) else { return nil }
    guard let id = UUID(uuidString: batch["id"]), let json: String = batch["undoRows"],
      let rows = try? JSONDecoder().decode(ImportRows.self, from: Data(json.utf8)),
      !rows.sessions.isEmpty, !rows.sets.isEmpty,
      Set(rows.sessions).count == rows.sessions.count,
      Set(rows.plans).count == rows.plans.count, Set(rows.sets).count == rows.sets.count
    else { throw WorkoutImportUndoError.unidentified }
    let sessionIDs = try jsonIDs(rows.sessions)
    let setIDs = try jsonIDs(rows.sets)
    let planIDs = try jsonIDs(rows.plans)
    let sessions = try String.fetchAll(db,
      sql: "SELECT id FROM sessions WHERE id IN (SELECT value FROM json_each(?))", arguments: [sessionIDs])
    let sets = try Row.fetchAll(db, sql: """
      SELECT id, sessionID FROM loggedSets WHERE id IN (SELECT value FROM json_each(?))
      """, arguments: [setIDs])
    let plans = try Row.fetchAll(db, sql: """
      SELECT id, sessionID FROM sessionExercises WHERE id IN (SELECT value FROM json_each(?))
      """, arguments: [planIDs])
    let ownedSessions = Set(rows.sessions.map { $0.uuidString.lowercased() })
    let ownedSets = Set(rows.sets.map { $0.uuidString.lowercased() })
    let ownedPlans = Set(rows.plans.map { $0.uuidString.lowercased() })
    let sessionSets = try String.fetchAll(db, sql: """
      SELECT id FROM loggedSets WHERE sessionID IN (SELECT value FROM json_each(?))
      """, arguments: [sessionIDs])
    let sessionPlans = try String.fetchAll(db, sql: """
      SELECT id FROM sessionExercises WHERE sessionID IN (SELECT value FROM json_each(?))
      """, arguments: [sessionIDs])
    guard sets.allSatisfy({ ownedSessions.contains($0["sessionID"] as String) }),
      plans.allSatisfy({ ownedSessions.contains($0["sessionID"] as String) }),
      Set(sessionSets).isSubset(of: ownedSets), Set(sessionPlans).isSubset(of: ownedPlans)
    else { throw WorkoutImportUndoError.containsLaterChanges }
    return (WorkoutImportUndo(id: id, sessionCount: sessions.count, setCount: sets.count), rows)
  }

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

    /// Whether Hardset can read a file of this format back in. Every line of copy that says what a
    /// format is for is written from this, and `ExportFormatPurposeTests` proves it against the
    /// importer, so the app cannot promise a restore it cannot do.
    public var restoresIntoHardset: Bool {
      switch self {
      case .csv: true
      case .json, .sqlite: false
      }
    }

    /// What the format is for, said beside its export button.
    public var purpose: String {
      switch self {
      case .csv:
        "Every finished workout, set by set, with the movements, gyms and machines it used. "
          + "Hardset can read this file back in, so this is the one to keep. It leaves out saved "
          + "workouts and body mass, and a workout still open when you export."
      case .json:
        "Every table, for inspecting your data or keeping a full copy. Hardset can't read it back in."
      case .sqlite:
        "The database itself, for inspecting your data or keeping a full copy. Hardset can't read it back in."
      }
    }

    /// What to say once the file is made.
    public func readyMessage(fileName: String) -> String {
      restoresIntoHardset
        ? "\(fileName) is ready. Save it somewhere off this iPhone. To restore, choose it under "
          + "Restore or bring in workouts."
        : "\(fileName) is ready. It is a copy to keep and inspect; Hardset can't restore from it. "
          + "Export a CSV to keep a copy you can restore."
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
    Self.removeStaleExports(in: directory, now: Date())
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

  /// How long an earlier export's folder is kept, so a share sheet still reading it is not cut off.
  static let staleExportAge: TimeInterval = 3600

  /// Best-effort removal of folders earlier exports made in `directory`: only UUID-named folders,
  /// which is how `export` names them, and only once older than `staleExportAge`. Each SQLite
  /// export is a whole copy of the database, so they must not pile up. Failure removes nothing
  /// more and never blocks the new export.
  private static func removeStaleExports(in directory: URL, now: Date) {
    let manager = FileManager.default
    guard let entries = try? manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])
    else { return }
    for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
      guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
        values.isDirectory == true, let modified = values.contentModificationDate,
        now.timeIntervalSince(modified) > staleExportAge
      else { continue }
      try? manager.removeItem(at: entry)
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
    if let restore = preview.restore { return try await alreadyRestoredWorkoutCount(in: restore) }
    return try await database.read { db in
      var count = 0
      var zones = EarlierZones()
      for workout in preview.sessions
      where try Self.isAlreadyImported(workout, from: preview.source, zones: &zones, in: db) {
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
    // The file is recognised by its SHA-256 digest and length; only those are kept.
    let file = Data(preview.originalCSV.utf8)
    // Hardset's own export is put back by id, not converted, so it never takes the path below.
    if let restore = preview.restore { return try await commitRestore(restore, file: file) }
    let digest = SHA256Digest.hex(of: file)
    let byteCount = file.count
    return try await database.write { db in
      // The exact file was imported before. Refuse only while its workouts are all still here:
      // after the lifter deletes them in History to correct an import, the same file must be
      // importable again, so the stale record of that import is dropped instead.
      let earlierBatches = try Row.fetchAll(db,
        sql: "SELECT id, undoRows FROM deviceImportBatches WHERE sourceDigest = ? AND byteCount = ?",
        arguments: [digest, byteCount])
      if !earlierBatches.isEmpty {
        var zones = EarlierZones()
        if try preview.sessions.allSatisfy({
          try Self.isAlreadyImported($0, from: preview.source, zones: &zones, in: db)
        }) {
          throw WorkoutImportError.alreadyImported
        }
        for batch in earlierBatches {
          if let json: String = batch["undoRows"] {
            // A partial reimport must retain the earlier batch's surviving row identities.
            // A damaged precise ledger is retained too; guessing that it is empty loses evidence.
            guard let rows = try? JSONDecoder().decode(ImportRows.self, from: Data(json.utf8)) else { continue }
            if try Self.hasSurvivingRows(rows, in: db) { continue }
          }
          try db.execute(sql: "DELETE FROM deviceImportBatches WHERE id = ?",
            arguments: [batch["id"] as String])
        }
      }
      // Match movement identity only. Session provenance keeps unknown imported equipment apart
      // from native benchmarks and charts, even for a movement whose native machine is nil.
      let candidates = try Exercise.where { !$0.isArchived }.order { $0.id }.fetchAll(db).sorted {
        if $0.isCurated != $1.isCurated { return $0.isCurated }
        return ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
      }
      var exercises: [String: UUID] = [:]
      var importedWorkouts = 0
      var importedSets = 0
      var undoRows = ImportRows()
      var skippedWorkouts = 0
      var zones = EarlierZones()
      for workout in preview.sessions {
        if try Self.isAlreadyImported(workout, from: preview.source, zones: &zones, in: db) {
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
        undoRows.sessions.append(session)
        var plans: [UUID: UUID] = [:]
        for (ordinal, set) in workout.sets.enumerated() {
          let exercise: UUID
          let importedName = "\(set.exercise) (Imported • \(preview.source))"
          let normalized = CatalogSeeder.normalized(set.exercise)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
          if let existing = exercises[normalized] { exercise = existing }
          else if let matched = candidates.first(where: {
            !$0.notes.hasPrefix(CatalogSeeder.importedNotesPrefix)
              && CatalogSeeder.isSameName($0.name, normalized)
          }) {
            exercise = matched.id
            exercises[normalized] = exercise
          } else if let earlier = candidates.first(where: {
            $0.notes.hasPrefix(CatalogSeeder.importedNotesPrefix)
              && CatalogSeeder.isSameName($0.name, CatalogSeeder.normalized(importedName))
          }) {
            // An earlier import's movement of the same name, so a later export's sets continue
            // that series instead of splitting it across two identically named movements.
            exercise = earlier.id
            exercises[normalized] = exercise
          } else {
            exercise = UUID()
            exercises[normalized] = exercise
            try Exercise.insert {
              Exercise.Draft(id: exercise, name: importedName,
                notes: "Imported • Unevaluated Machine. \(set.notes)", createdAt: workout.startedAt)
            }.execute(db)
          }
          let plan: UUID
          if let existing = plans[exercise] { plan = existing }
          else {
            plan = UUID()
            plans[exercise] = plan
            try SessionExercise.insert {
              SessionExercise.Draft(id: plan, sessionID: session, exerciseID: exercise,
                position: plans.count - 1)
            }.execute(db)
            undoRows.plans.append(plan)
          }
          let setID = UUID()
          try LoggedSet.insert {
            LoggedSet.Draft(id: setID, sessionID: session, exerciseID: exercise,
              sessionExerciseID: plan, setOrdinal: ordinal, weightKg: set.weightKg,
              reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup,
              // The CSV does not record set completion instants. Preserve the workout start
              // as a grouping timestamp and disclose that limitation in the session's notes.
              completedAt: workout.startedAt)
          }.execute(db)
          undoRows.sets.append(setID)
        }
        // Matching an existing movement must neither overwrite its notes nor discard the CSV's.
        // Exports repeat an exercise note on every set, so retain each distinct note once per
        // movement in this workout's own notes, inside the same atomic import transaction.
        var seenNotes: [String: Set<String>] = [:]
        let noteLines = workout.sets.compactMap { set -> String? in
          guard !set.notes.isEmpty,
            seenNotes[set.exercise, default: []].insert(set.notes).inserted else { return nil }
          return "\(set.exercise): \(set.notes)"
        }
        let noteSuffix = ". Set timestamps are unavailable; grouped at workout start."
          + (noteLines.isEmpty ? "" : "\n\n" + noteLines.joined(separator: "\n"))
        try db.execute(sql: "UPDATE sessions SET notes = notes || ? WHERE id = ?",
          arguments: [noteSuffix, session.uuidString.lowercased()])
      }
      if importedWorkouts > 0 {
        try Self.recordImport(digest: digest, byteCount: byteCount, undo: undoRows, in: db)
      }
      return WorkoutImportResult(
        importedWorkouts: importedWorkouts, importedSets: importedSets, skippedWorkouts: skippedWorkouts)
    }
  }

  /// An imported session from the same app with the same start and title. Imported sessions are
  /// the only ones whose notes begin "Imported from <app> ", which `commit` writes.
  ///
  /// "The same start" is decided in the zone the earlier import used, which its notes record. A
  /// date without an offset is a wall-clock time, so after the phone changes zone the same text
  /// parses to a different instant; comparing instants alone would import every workout again.
  /// A start read as the same instant also matches, which covers dates with an offset and an
  /// exporting app that rewrote its wall-clock text for the new zone.
  private static func isAlreadyImported(
    _ workout: WorkoutImportPreview.Workout, from source: String, zones: inout EarlierZones,
    in db: Database
  ) throws -> Bool {
    let startedAt = workout.startedAt
    let title = workout.title
    // Zone offsets span UTC-12 to UTC+14, so a reinterpreted start lies within this window.
    let earliest = startedAt.addingTimeInterval(-27 * 3600)
    let latest = startedAt.addingTimeInterval(27 * 3600)
    let candidates = try Session
      .where { $0.startedAt >= earliest && $0.startedAt <= latest }
      .where { $0.title.eq(title) && $0.notes.like("Imported from \(source) %") }
      .select { ($0.startedAt, $0.notes) }
      .fetchAll(db)
    for candidate in candidates {
      if candidate.0 == startedAt { return true }
      guard let zone = WorkoutCSVImport.interpretedTimeZone(inNotes: candidate.1) else { continue }
      if zones.date(workout.startText, in: zone) == candidate.0 { return true }
    }
    return false
  }

  /// Date parsers for the zones earlier imports were read in, built once per check rather than
  /// once per workout, since building formatters is the expensive part of parsing.
  nonisolated struct EarlierZones {
    private var parsers: [String: WorkoutCSVImport.DateParser] = [:]

    mutating func date(_ text: String, in zone: TimeZone) -> Date? {
      parsers[zone.identifier, default: WorkoutCSVImport.DateParser(timeZone: zone)].date(text)
    }
  }

  private static func csv(in db: Database) throws -> Data {
    let rows = try Row.fetchAll(db, sql: RestoreCSV.query)
    let names = RestoreCSV.columns.map(\.name)
    let fields = rows.map { row in names.map { string(row[$0] as DatabaseValue) } }
    return Data(CSVDocument.encode([names] + fields).utf8)
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
