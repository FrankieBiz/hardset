import Foundation
import GRDB
import HardsetCore

nonisolated extension DataTransferStore {
  /// Puts a Hardset export back, in one transaction, adding only what is missing.
  ///
  /// - A row whose id is already here is left exactly as it is. Nothing is replaced: the tables'
  ///   primary keys say `ON CONFLICT REPLACE`, so every insert here says `OR ABORT` instead, and a
  ///   row that collides with a different one stops the whole restore.
  /// - A workout already here is skipped with its sets and plan rows, so a set the lifter has since
  ///   corrected away cannot be put back by an older file. Saved workouts are treated the same way.
  /// - The workouts it adds are recorded in the import ledger, so "Undo last import" removes
  ///   exactly them. The movements, gyms and machines it had to create stay, as they do after any
  ///   import.
  func commitRestore(_ restore: WorkoutImportPreview.Restore, file: Data) async throws -> WorkoutImportResult {
    try Task.checkCancellation()
    let digest = SHA256Digest.hex(of: file)
    let byteCount = file.count
    return try await database.write { db in
      do {
        return try Self.applyRestore(restore.plan, digest: digest, byteCount: byteCount, in: db)
      } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
        throw WorkoutImportError.unreadable(
          "The rows in this file do not fit together (\(error.message ?? "a constraint failed"))")
      }
    }
  }

  /// How many of the file's workouts are already here, read before committing so the preview can
  /// say so.
  func alreadyRestoredWorkoutCount(in restore: WorkoutImportPreview.Restore) async throws -> Int {
    try Task.checkCancellation()
    return try await database.read { db in
      let existing = Set(try String.fetchAll(db, sql: "SELECT id FROM sessions"))
      return restore.plan.rows("sessions").filter {
        HardsetRestorePlan.id(of: $0).map(existing.contains) == true
      }.count
    }
  }

  private static func applyRestore(
    _ plan: HardsetRestorePlan, digest: String, byteCount: Int, in db: Database
  ) throws -> WorkoutImportResult {
    // A gym an earlier CSV could only name is the live gym of that name if there is one.
    var matchedGyms: [String: String] = [:]
    for gym in plan.rows("gyms") {
      guard let id = HardsetRestorePlan.id(of: gym), plan.gymsToMatchByName.contains(id),
        let name = HardsetRestorePlan.string(gym, "name")
      else { continue }
      if let live = try String.fetchOne(db, sql: """
        SELECT id FROM gyms WHERE isArchived = 0 AND lower(trim(name)) = lower(trim(?))
        ORDER BY createdAt, id LIMIT 1
        """, arguments: [name]) {
        matchedGyms[id] = live
      }
    }

    let hereAlready = Dictionary(uniqueKeysWithValues: try ["sessions", "workoutTemplates"].map {
      ($0, Set(try String.fetchAll(db, sql: "SELECT id FROM \"\($0)\"")))
    })
    var addedSessions: Set<String> = []
    var addedTemplates: Set<String> = []
    var undo = ImportRows()
    var importedSets = 0
    var skippedWorkouts = 0
    var addedBodyweight = 0
    var addedGyms = 0
    var addedMachines = 0
    var addedMovements = 0

    for table in RestoreSchema.tables {
      // Sets and plan rows can be numerous, and are only ever added under a workout that was
      // added, so they are not looked up one by one.
      let present: Set<String>
      if ["loggedSets", "sessionExercises", "templateExercises"].contains(table.name) {
        present = []
      } else if let known = hereAlready[table.name] {
        present = known
      } else {
        present = Set(try String.fetchAll(db, sql: "SELECT id FROM \"\(table.name)\""))
      }
      for original in plan.rows(table.name) {
        guard let id = HardsetRestorePlan.id(of: original) else { continue }
        var row = original
        switch table.name {
        case "sessions":
          if present.contains(id) { skippedWorkouts += 1; continue }
          addedSessions.insert(id)
        case "sessionExercises", "loggedSets":
          guard let session = HardsetRestorePlan.string(row, "sessionID"),
            addedSessions.contains(session) else { continue }
        case "workoutTemplates":
          if present.contains(id) { continue }
          addedTemplates.insert(id)
        case "templateExercises":
          guard let template = HardsetRestorePlan.string(row, "templateID"),
            addedTemplates.contains(template) else { continue }
        default:
          if present.contains(id) || matchedGyms[id] != nil { continue }
        }
        if table.name == "sessions" || table.name == "machines",
          let gym = HardsetRestorePlan.string(row, "gymID"), let live = matchedGyms[gym] {
          row["gymID"] = live.databaseValue
        }
        // A block that moved to another machine keeps that machine on its plan row, which no
        // set may have used, so the file may not describe it. Without it the row is kept, with no
        // machine, rather than failing a restore over a pointer no logged set depends on.
        if table.name == "sessionExercises", let machine = HardsetRestorePlan.string(row, "machineID"),
          try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM machines WHERE id = ?)", arguments: [machine]) != true
        {
          row["machineID"] = .null
        }
        try insert(row, into: table.name, in: db)
        switch table.name {
        case "sessionExercises":
          if let uuid = UUID(uuidString: id) { undo.plans.append(uuid) }
        case "loggedSets":
          if let uuid = UUID(uuidString: id) { undo.sets.append(uuid) }
          importedSets += 1
        case "sessions":
          if let uuid = UUID(uuidString: id) { undo.sessions.append(uuid) }
        case "bodyweightEntries":
          addedBodyweight += 1
        case "gyms":
          addedGyms += 1
        case "machines":
          addedMachines += 1
        case "exercises":
          addedMovements += 1
        default: break
        }
      }
    }
    if !undo.sessions.isEmpty, !undo.sets.isEmpty {
      try Self.recordImport(digest: digest, byteCount: byteCount, undo: undo, in: db)
    }
    return WorkoutImportResult(
      importedWorkouts: addedSessions.count, importedSets: importedSets,
      skippedWorkouts: skippedWorkouts, restoredSavedWorkouts: addedTemplates.count,
      restoredBodyweightEntries: addedBodyweight,
      leftOutUnfinishedWorkouts: plan.unfinishedWorkouts, restoredGyms: addedGyms,
      restoredMachines: addedMachines, restoredMovements: addedMovements)
  }

  /// Column names are this module's own, from `RestoreSchema`; only values come from the file.
  private static func insert(_ row: HardsetRestorePlan.Row, into table: String, in db: Database) throws {
    let columns = row.keys.sorted()
    let names = columns.map { "\"\($0)\"" }.joined(separator: ", ")
    let marks = Array(repeating: "?", count: columns.count).joined(separator: ", ")
    let sql = "INSERT OR ABORT INTO \"\(table)\" (\(names)) VALUES (\(marks))"
    let values: [(any DatabaseValueConvertible)?] = columns.map { row[$0] ?? .null }
    let statement = try db.cachedStatement(sql: sql)
    try statement.execute(arguments: StatementArguments(values))
    guard db.changesCount == 1 else {
      throw WorkoutImportError.unreadable("A row in \(table) was not written")
    }
  }
}
