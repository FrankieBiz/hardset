import Foundation
import GRDB
import HardsetCore

/// Hardset's own CSV: what it writes, and how it reads it back.
///
/// One row per logged set. The first 19 columns are the original export, in their original order
/// and with their original meaning, so a file written by an earlier build still reads and a
/// spreadsheet built on those columns still works. Everything after them was added so that the
/// workout, its movements, its gym and machines, and the plan row each set was logged against can
/// all be put back, not only the sets: a movement's muscles and equipment, a gym and machine's
/// identity, a machine's load step, and the order and rep range of each block.
///
/// The same header list drives the export's SQL and this reader, and `RestoreCSVTests` checks it
/// against every column of the tables it restores, so a column added to one of those tables
/// cannot be left out of the file unnoticed.
nonisolated enum RestoreCSV {
  struct Header: Sendable {
    let name: String
    /// The expression the export selects it with, over the aliases in `query`.
    let sql: String
  }

  /// The first 19 are the original export. The rest were added after it, in this order.
  static let columns: [Header] = [
    Header(name: "id", sql: "l.id"),
    Header(name: "sessionID", sql: "l.sessionID"),
    Header(name: "exerciseID", sql: "l.exerciseID"),
    Header(name: "machineID", sql: "l.machineID"),
    Header(name: "sessionExerciseID", sql: "l.sessionExerciseID"),
    Header(name: "setOrdinal", sql: "l.setOrdinal"),
    Header(name: "weightKg", sql: "l.weightKg"),
    Header(name: "reps", sql: "l.reps"),
    Header(name: "rpe", sql: "l.rpe"),
    Header(name: "isWarmup", sql: "l.isWarmup"),
    Header(name: "completedAt", sql: "l.completedAt"),
    Header(name: "exerciseName", sql: "e.name"),
    Header(name: "workoutTitle", sql: "s.title"),
    Header(name: "workoutStart", sql: "s.startedAt"),
    Header(name: "workoutEnd", sql: "s.finishedAt"),
    Header(name: "workoutNotes", sql: "s.notes"),
    Header(name: "machineName", sql: "m.name"),
    Header(name: "machineBrand", sql: "m.brand"),
    Header(name: "gymName", sql: "g.name"),
    // Added: the workout's gym and saved-workout identity.
    Header(name: "workoutGymID", sql: "s.gymID"),
    Header(name: "workoutTemplateID", sql: "s.templateID"),
    Header(name: "gymIsArchived", sql: "g.isArchived"),
    Header(name: "gymCreatedAt", sql: "g.createdAt"),
    // Added: the machine's own identity, and the gym it belongs to.
    Header(name: "machineGymID", sql: "m.gymID"),
    Header(name: "machineGymName", sql: "mg.name"),
    Header(name: "machineGymIsArchived", sql: "mg.isArchived"),
    Header(name: "machineGymCreatedAt", sql: "mg.createdAt"),
    Header(name: "machineLoadType", sql: "m.loadType"),
    Header(name: "machineStackIncrementKg", sql: "m.stackIncrementKg"),
    Header(name: "machineIsArchived", sql: "m.isArchived"),
    Header(name: "machineCreatedAt", sql: "m.createdAt"),
    // Added: the movement's muscles, equipment and provenance.
    Header(name: "exerciseCuratedName", sql: "e.curatedName"),
    Header(name: "exerciseSlug", sql: "e.catalogSlug"),
    Header(name: "exerciseIsCurated", sql: "e.isCurated"),
    Header(name: "exerciseModality", sql: "e.modality"),
    Header(name: "exercisePrimaryMuscle", sql: "e.primaryMuscle"),
    Header(name: "exerciseSecondaryMuscles", sql: "e.secondaryMusclesJSON"),
    Header(name: "exerciseNotes", sql: "e.notes"),
    Header(name: "exerciseIsArchived", sql: "e.isArchived"),
    Header(name: "exerciseCreatedAt", sql: "e.createdAt"),
    // Added: the plan row (a block of one movement in one workout) the set was logged against.
    Header(name: "planMachineID", sql: "p.machineID"),
    Header(name: "planPosition", sql: "p.position"),
    Header(name: "planPlannedSets", sql: "p.plannedSets"),
    Header(name: "planRepRangeLower", sql: "p.repRangeLower"),
    Header(name: "planRepRangeUpper", sql: "p.repRangeUpper"),
  ]

  /// How many columns the first export wrote.
  static let originalColumnCount = 19

  static var query: String {
    "SELECT " + columns.map { "\($0.sql) AS \"\($0.name)\"" }.joined(separator: ", ") + """

      FROM loggedSets l
      LEFT JOIN exercises e ON e.id = l.exerciseID
      LEFT JOIN sessions s ON s.id = l.sessionID
      LEFT JOIN machines m ON m.id = l.machineID
      LEFT JOIN gyms g ON g.id = s.gymID
      LEFT JOIN gyms mg ON mg.id = m.gymID
      LEFT JOIN sessionExercises p ON p.id = l.sessionExerciseID
      ORDER BY s.startedAt, s.id, l.completedAt, l.setOrdinal, l.id
      """
  }

  /// One table row a CSV row describes, and which cell holds each of its columns.
  struct Entity: Sendable {
    let label: String
    let table: String
    let fields: [(column: String, header: String)]
  }

  static let exerciseEntity = Entity(label: "Movement", table: "exercises", fields: [
    ("id", "exerciseID"), ("name", "exerciseName"), ("curatedName", "exerciseCuratedName"),
    ("catalogSlug", "exerciseSlug"), ("isCurated", "exerciseIsCurated"),
    ("modality", "exerciseModality"), ("primaryMuscle", "exercisePrimaryMuscle"),
    ("secondaryMusclesJSON", "exerciseSecondaryMuscles"), ("notes", "exerciseNotes"),
    ("isArchived", "exerciseIsArchived"), ("createdAt", "exerciseCreatedAt"),
  ])
  static let workoutGymEntity = Entity(label: "Gym", table: "gyms", fields: [
    ("id", "workoutGymID"), ("name", "gymName"), ("isArchived", "gymIsArchived"),
    ("createdAt", "gymCreatedAt"),
  ])
  static let machineGymEntity = Entity(label: "Gym", table: "gyms", fields: [
    ("id", "machineGymID"), ("name", "machineGymName"), ("isArchived", "machineGymIsArchived"),
    ("createdAt", "machineGymCreatedAt"),
  ])
  static let machineEntity = Entity(label: "Machine", table: "machines", fields: [
    ("id", "machineID"), ("gymID", "machineGymID"), ("name", "machineName"),
    ("brand", "machineBrand"), ("loadType", "machineLoadType"),
    ("stackIncrementKg", "machineStackIncrementKg"), ("isArchived", "machineIsArchived"),
    ("createdAt", "machineCreatedAt"),
  ])
  static let sessionEntity = Entity(label: "Workout", table: "sessions", fields: [
    ("id", "sessionID"), ("gymID", "workoutGymID"), ("title", "workoutTitle"),
    ("notes", "workoutNotes"), ("startedAt", "workoutStart"), ("finishedAt", "workoutEnd"),
    ("templateID", "workoutTemplateID"),
  ])
  static let planEntity = Entity(label: "Plan row", table: "sessionExercises", fields: [
    ("id", "sessionExerciseID"), ("sessionID", "sessionID"), ("exerciseID", "exerciseID"),
    ("machineID", "planMachineID"), ("position", "planPosition"),
    ("plannedSets", "planPlannedSets"), ("repRangeLower", "planRepRangeLower"),
    ("repRangeUpper", "planRepRangeUpper"),
  ])
  static let setEntity = Entity(label: "Set", table: "loggedSets", fields: [
    ("id", "id"), ("sessionID", "sessionID"), ("exerciseID", "exerciseID"),
    ("machineID", "machineID"), ("sessionExerciseID", "sessionExerciseID"),
    ("setOrdinal", "setOrdinal"), ("weightKg", "weightKg"), ("reps", "reps"),
    ("rpe", "rpe"), ("isWarmup", "isWarmup"), ("completedAt", "completedAt"),
  ])

  static let entities = [
    exerciseEntity, workoutGymEntity, machineGymEntity, machineEntity, sessionEntity, planEntity,
    setEntity,
  ]

  /// Columns without which a file is not one of Hardset's.
  private static let required = [
    "id", "sessionid", "exerciseid", "setordinal", "weightkg", "reps", "iswarmup", "completedat",
    "workoutstart", "workoutend",
  ]

  /// `headers` are trimmed and lowercased, as `WorkoutCSVImport` reads them.
  static func isOwnExport(headers: [String]) -> Bool {
    required.allSatisfy(headers.contains)
  }

  static let interpretation =
    "A Hardset export. Weights are stored in kilograms and dates are exact, so the unit above "
    + "and this device's time zone change nothing in it."

  static func preview(
    rows: [[String]], headers: [String], commaDecimals: Bool, text: String
  ) throws -> WorkoutImportPreview {
    try read(rows: rows, headers: headers, commaDecimals: commaDecimals)
      .preview(source: text, interpretation: interpretation)
  }

  /// Reads the whole file before anything is written. Any cell that is not a valid value for its
  /// column, a movement, gym, machine or workout described two different ways, or a workout that
  /// ends before it starts stops the import with the line it is on.
  ///
  /// A file from an earlier build has only the first 19 columns. It names gyms but does not
  /// identify them, so each name stands for one gym, matched to a gym of that name already here
  /// when the file is committed. Its machines are placed in the gym of the first workout that used
  /// them, its plan rows are ordered as they first appear, and its movements are whatever the file
  /// names, with no muscles recorded, which the Library flags as needing a body part.
  static func read(rows: [[String]], headers: [String], commaDecimals: Bool) throws -> HardsetRestorePlan {
    var position: [String: Int] = [:]
    for header in columns {
      if let found = headers.firstIndex(of: header.name.lowercased()) { position[header.name] = found }
    }
    let earlier = position["workoutGymID"] == nil
    var result = HardsetRestorePlan(layout: earlier ? .earlierCSV : .csv)

    var unfinished: Set<String> = []
    var gymsByName: [String: String] = [:]
    var gymOfMachine: [String: String] = [:]
    var planPosition: [String: Int64] = [:]
    var plansInSession: [String: Int64] = [:]
    var instants: [String: Date] = [:]
    // An earlier file does not say when a movement or machine was made; its first workout does.
    var firstUsed: [String: String] = [:]
    // An earlier file does not say which machine a block is on now. Its sets do: the latest one's,
    // since a block that moved machines keeps the machine it moved to. Decided up front so every
    // row of the block describes it the same way.
    var latestMachineOfBlock: [String: String] = [:]
    if earlier, let planColumn = position["sessionExerciseID"], let machineColumn = position["machineID"] {
      for cells in rows.dropFirst() where cells.count == headers.count {
        let block = cells[planColumn].trimmingCharacters(in: .whitespaces)
        guard !block.isEmpty, let uuid = UUID(uuidString: block) else { continue }
        let machine = cells[machineColumn].trimmingCharacters(in: .whitespaces)
        latestMachineOfBlock[uuid.uuidString.lowercased()] = UUID(uuidString: machine)?.uuidString.lowercased()
      }
    }

    func gym(named name: String, since createdAt: String) -> String {
      if let known = gymsByName[name] { return known }
      let id = UUID().uuidString.lowercased()
      gymsByName[name] = id
      result.gymsToMatchByName.insert(id)
      _ = result.tables["gyms", default: .init()].add([
        "id": id.databaseValue, "name": name.databaseValue, "isArchived": Int64(0).databaseValue,
        "createdAt": createdAt.databaseValue,
      ])
      return id
    }

    for (offset, cells) in rows.dropFirst().enumerated() {
      let line = offset + 2
      guard cells.count == headers.count else {
        throw WorkoutImportError.row(line, "Column count differs from the header")
      }
      func cell(_ header: String) -> String? { position[header].map { cells[$0] } }
      func build(_ entity: Entity) throws -> HardsetRestorePlan.Row {
        var row: HardsetRestorePlan.Row = [:]
        let table = RestoreSchema.table(entity.table)
        for (column, header) in entity.fields {
          guard let raw = cell(header) else { continue }
          guard let spec = table?.column(column),
            let value = RestoreSchema.value(fromCell: raw, for: spec, commaDecimals: commaDecimals)
          else { throw WorkoutImportError.row(line, "\(header) holds a value Hardset cannot read") }
          row[column] = value
        }
        if let problem = RestoreSchema.domainProblem(table: entity.table, row: row) {
          throw WorkoutImportError.row(line, problem)
        }
        return row
      }
      func add(_ row: HardsetRestorePlan.Row, as entity: Entity) throws {
        guard let id = HardsetRestorePlan.id(of: row) else {
          throw WorkoutImportError.row(line, "\(entity.label) has no id")
        }
        guard result.tables[entity.table, default: .init()].add(row) else {
          throw WorkoutImportError.row(
            line, "\(entity.label) \(id) is described two different ways in this file")
        }
      }

      var sessionRow = try build(sessionEntity)
      guard let sessionID = HardsetRestorePlan.id(of: sessionRow),
        let startText = HardsetRestorePlan.string(sessionRow, "startedAt")
      else { throw WorkoutImportError.row(line, "The workout has no id or start") }
      // An open workout is the one the app offers to resume; it is counted and left out.
      guard let endText = HardsetRestorePlan.string(sessionRow, "finishedAt") else {
        unfinished.insert(sessionID)
        continue
      }
      guard let start = instants[startText] ?? StoredDate.date(startText),
        let end = instants[endText] ?? StoredDate.date(endText), end >= start
      else { throw WorkoutImportError.row(line, "The workout ends before it starts") }
      instants[startText] = start
      instants[endText] = end

      var workoutGym: String?
      if earlier {
        let name = (cell("gymName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
          workoutGym = gym(named: name, since: startText)
          sessionRow["gymID"] = workoutGym?.databaseValue
        }
      } else if let id = HardsetRestorePlan.string(sessionRow, "gymID") {
        workoutGym = id
        try add(try build(workoutGymEntity), as: workoutGymEntity)
      }
      try add(sessionRow, as: sessionEntity)

      var exerciseRow = try build(exerciseEntity)
      if earlier {
        guard let name = HardsetRestorePlan.string(exerciseRow, "name"),
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw WorkoutImportError.row(line, "The movement has no name") }
        if let id = HardsetRestorePlan.id(of: exerciseRow) {
          exerciseRow["createdAt"] = firstUsed["exercise " + id, default: startText].databaseValue
          firstUsed["exercise " + id] = firstUsed["exercise " + id] ?? startText
        }
      }
      try add(exerciseRow, as: exerciseEntity)

      var machineID: String?
      if let raw = cell("machineID"), !raw.isEmpty {
        var machineRow = try build(machineEntity)
        guard let id = HardsetRestorePlan.id(of: machineRow) else {
          throw WorkoutImportError.row(line, "The machine has no id")
        }
        machineID = id
        if earlier {
          let owner = gymOfMachine[id] ?? workoutGym ?? gym(named: "Gym not recorded", since: startText)
          gymOfMachine[id] = owner
          machineRow["gymID"] = owner.databaseValue
          machineRow["createdAt"] = firstUsed["machine " + id, default: startText].databaseValue
          firstUsed["machine " + id] = firstUsed["machine " + id] ?? startText
        } else {
          guard HardsetRestorePlan.string(machineRow, "gymID") != nil else {
            throw WorkoutImportError.row(line, "The machine has no gym")
          }
          try add(try build(machineGymEntity), as: machineGymEntity)
        }
        try add(machineRow, as: machineEntity)
      }

      if let raw = cell("sessionExerciseID"), !raw.isEmpty {
        var planRow = try build(planEntity)
        if earlier, let id = HardsetRestorePlan.id(of: planRow) {
          if planPosition[id] == nil {
            planPosition[id] = plansInSession[sessionID, default: 0]
            plansInSession[sessionID, default: 0] += 1
          }
          planRow["position"] = planPosition[id]?.databaseValue
          planRow["machineID"] = latestMachineOfBlock[id]?.databaseValue ?? .null
        }
        try add(planRow, as: planEntity)
      }

      try add(try build(setEntity), as: setEntity)
    }
    result.unfinishedWorkouts = unfinished.count
    guard !result.rows("loggedSets").isEmpty || !unfinished.isEmpty else {
      throw WorkoutImportError.empty
    }
    return result
  }
}
