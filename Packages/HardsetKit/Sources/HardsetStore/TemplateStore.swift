import Foundation
import HardsetCore
import SQLiteData

public nonisolated enum TemplateStoreError: Error, Equatable, Sendable {
  case blankName
  case noExercises
  /// A movement in the plan has no row, so the plan could not be started.
  case unknownExercise
  case notFound
}

/// Saved workouts: plans the lifter starts in one tap.
///
/// A template is a plan and never a record. A session copies what it needs when it starts, so
/// nothing here reads or writes a session's movements, and editing or archiving a plan cannot
/// change what a past workout says it was. The only thing read back from sessions is when a plan
/// was last done.
public nonisolated struct TemplateStore: Sendable {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  /// Live workouts in the lifter's order, with movement and machine names resolved.
  ///
  /// `lastDoneAt` is the start of the latest session started from the plan that counts as done
  /// (`Session.TableColumns.isCounted`): finished, with a working set. An open session does not
  /// count, and neither does one finished with nothing trained, so an accidental Start leaves the
  /// rotation where it was.
  public func loadTemplates() async throws -> [WorkoutTemplate] {
    try Task.checkCancellation()
    let templates = try await database.read { db in
      try Self.readTemplates(in: db)
    }
    try Task.checkCancellation()
    return templates
  }

  /// Saves a plan: its name and place in the rotation, and its movements in the order given.
  ///
  /// One transaction, so a refused plan leaves nothing behind. Movements that stay keep their rows
  /// and are updated in place rather than deleted and re-inserted, which is what a synchronized
  /// table wants. A machine that no longer exists is saved as no machine, which is what deleting
  /// it first would have done.
  public func save(_ template: WorkoutTemplate, now: Date = Date()) async throws {
    let name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw TemplateStoreError.blankName }
    guard !template.exercises.isEmpty else { throw TemplateStoreError.noExercises }
    try Task.checkCancellation()
    try await database.write { db in
      try Self.write(template, named: name, now: now, in: db)
    }
  }

  /// Hides a workout without deleting it, so a session's `templateID` never dangles.
  public func archive(_ id: TemplateID) async throws {
    try Task.checkCancellation()
    try await database.write { db in
      try StoredTemplate.where { $0.id.eq(id.rawValue) && !$0.isArchived }
        .update { $0.isArchived = #bind(true) }
        .execute(db)
      guard db.changesCount == 1 else { throw TemplateStoreError.notFound }
    }
  }

  /// Puts the listed workouts first, in the order given, ahead of any live workout not listed.
  /// A workout whose place does not change is not rewritten.
  public func reorder(_ ids: [TemplateID]) async throws {
    try Task.checkCancellation()
    try await database.write { db in
      let live = try StoredTemplate.where { !$0.isArchived }
        .order { ($0.position, $0.createdAt, $0.id) }
        .fetchAll(db)
      let liveIDs = Set(live.map(\.id))
      var seen = Set<UUID>()
      var order: [UUID] = []
      for id in ids {
        guard liveIDs.contains(id.rawValue) else { throw TemplateStoreError.notFound }
        if seen.insert(id.rawValue).inserted { order.append(id.rawValue) }
      }
      order += live.map(\.id).filter { !seen.contains($0) }
      let current = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0.position) })
      for (position, id) in order.enumerated() where current[id] != position {
        try StoredTemplate.where { $0.id.eq(id) }
          .update { $0.position = #bind(position) }
          .execute(db)
      }
    }
  }

  /// A plan built from a finished workout, to be edited and saved by the caller. Not saved here.
  ///
  /// Movements keep the session's order and machines. `plannedSets` is the number of working sets
  /// logged for the movement, never counting warm-ups, so a plan reproduces the work and not the
  /// warm-up. The rep range is the one the session itself remembered, if any. The plan goes last
  /// in the lifter's rotation.
  public func draft(fromSession id: SessionID, name: String) async throws -> WorkoutTemplate {
    try Task.checkCancellation()
    let draft = try await database.read { db in
      try Self.readDraft(from: id, named: name, in: db)
    }
    try Task.checkCancellation()
    return draft
  }

  /// How this workout has gone: its recent finished sessions, newest first, with the movements
  /// each session actually logged, their working sets and their measured volume.
  ///
  /// Sessions follow the same rule as the rotation (`Session.isCounted`): finished, with at least
  /// one working set. Open sessions, imported sessions (they carry no `templateID`) and another
  /// plan's sessions never appear. A movement comes from the sets themselves, grouped by movement
  /// and machine, so one added or removed mid-workout is still reported from what was logged.
  ///
  /// One read of the page, one count of the whole history, one read of the page's sets, and one
  /// read for the names those sets use. Volume is summed from the fetched rows by `SessionVolume`'s
  /// definition, Σ weight × reps over working sets, because that type is built from live logger
  /// state and cannot take a plain set list.
  public func history(for id: TemplateID, limit: Int = 12) async throws -> TemplateHistory {
    try Task.checkCancellation()
    let history = try await database.read { db in
      try Self.readHistory(for: id, limit: limit, in: db)
    }
    try Task.checkCancellation()
    return history
  }

  /// The most recent session started from this workout that counts as done, if any: finished, with
  /// a working set. It is the "last time" the up-next card compares against, so it follows the same
  /// rule as the rotation.
  ///
  /// Ordered by start time alone, which is the order of the index that finds it. Two sessions of
  /// one workout starting in the same millisecond is not something a lifter can do, so there is no
  /// tie-break to pay a sort for.
  public func lastFinishedSession(for id: TemplateID) async throws -> SessionID? {
    try Task.checkCancellation()
    let session = try await database.read { db in
      try Session
        .where { $0.templateID.eq(id.rawValue) && $0.isCounted }
        .order { $0.startedAt.desc() }
        .limit(1)
        .select(\.id)
        .fetchOne(db)
    }
    return session.map(SessionID.init(rawValue:))
  }

  // MARK: - Reading

  /// A typical straight-sets plan. `save` always writes a count, so this only covers a row from
  /// another writer that left it empty.
  private static let defaultPlannedSets = 3

  private static func readTemplates(in db: Database) throws -> [WorkoutTemplate] {
    let rows = try StoredTemplate.where { !$0.isArchived }
      .order { ($0.position, $0.createdAt, $0.id) }
      .fetchAll(db)
    guard !rows.isEmpty else { return [] }

    let movements = try StoredTemplateExercise
      .where { $0.templateID.in(rows.map(\.id)) }
      .fetchAll(db)
    let names = try exerciseNames(Set(movements.map(\.exerciseID)), in: db)
    let machines = try machineNames(Set(movements.compactMap(\.machineID)), in: db)

    var lastDone: [UUID: Date] = [:]
    let grouped: [(UUID?, Date?)] = try Session
      .where { $0.templateID.isNot(nil) && $0.isCounted }
      .group { $0.templateID }
      .select { ($0.templateID, $0.startedAt.max()) }
      .fetchAll(db)
    for (template, startedAt) in grouped {
      if let template, let startedAt { lastDone[template] = startedAt }
    }

    let byTemplate = Dictionary(grouping: movements, by: \.templateID)
    return rows.map { row in
      let ordered = (byTemplate[row.id] ?? []).sorted {
        ($0.position, $0.createdAt, $0.id.uuidString) < ($1.position, $1.createdAt, $1.id.uuidString)
      }
      return WorkoutTemplate(
        id: TemplateID(rawValue: row.id),
        name: row.name,
        position: row.position,
        exercises: ordered.map { movement in
          TemplateExercise(
            id: movement.id,
            exerciseID: ExerciseID(rawValue: movement.exerciseID),
            exerciseName: names[movement.exerciseID] ?? "Unknown movement",
            machineID: movement.machineID.map(MachineID.init(rawValue:)),
            machineName: movement.machineID.flatMap { machines[$0] },
            plannedSets: movement.plannedSets ?? defaultPlannedSets,
            repRange: repRange(movement.repRangeLower, movement.repRangeUpper),
            restSeconds: movement.restSeconds
          )
        },
        lastDoneAt: lastDone[row.id]
      )
    }
  }

  /// The plan's movement order, by movement and machine. A set whose movement is no longer in the
  /// plan has no place and sorts after the plan by its movement name, rather than being dropped.
  private struct MovementKey: Hashable {
    let exerciseID: UUID
    let machineID: UUID?

    init(exerciseID: UUID, machineID: UUID?) {
      self.exerciseID = exerciseID
      self.machineID = machineID
    }

    /// `"exerciseID|machineID"`, the id a movement's row carries across renders.
    var id: String {
      let exercise = ExerciseID(rawValue: exerciseID).description
      let machine = machineID.map { MachineID(rawValue: $0).description } ?? ""
      return "\(exercise)|\(machine)"
    }
  }

  private static func readHistory(
    for id: TemplateID, limit: Int, in db: Database
  ) throws -> TemplateHistory {
    let pageLimit = max(limit, 0)
    let sessions = try Session
      .where { $0.templateID.eq(id.rawValue) && $0.isCounted }
      .order { ($0.startedAt.desc(), $0.id.desc()) }
      .limit(pageLimit)
      .fetchAll(db)
    let total = try Session
      .where { $0.templateID.eq(id.rawValue) && $0.isCounted }
      .fetchCount(db)
    guard !sessions.isEmpty else {
      return TemplateHistory(sessions: [], totalSessionCount: total, limit: pageLimit)
    }

    let sessionIDs = sessions.map(\.id)
    // The plan's current order, so the sheet lists movements the way the workout does. A set from a
    // movement the plan no longer holds has no rank and falls back to its name below.
    let planRows = try StoredTemplateExercise
      .where { $0.templateID.eq(id.rawValue) }
      .order { ($0.position, $0.createdAt, $0.id) }
      .fetchAll(db)
    var planRank: [MovementKey: Int] = [:]
    for (rank, row) in planRows.enumerated() {
      planRank[MovementKey(exerciseID: row.exerciseID, machineID: row.machineID)] = rank
    }

    // One read for every working set on the page. Warm-ups are excluded here, in SQL, exactly as
    // `SessionVolume` excludes them.
    let sets = try LoggedSet
      .where { $0.sessionID.in(sessionIDs) && !$0.isWarmup }
      .order { ($0.completedAt, $0.setOrdinal, $0.id) }
      .fetchAll(db)

    let exerciseNames = try exerciseNames(Set(sets.map(\.exerciseID)), in: db)
    let machineNames = try machineNames(Set(sets.compactMap(\.machineID)), in: db)
    let setsBySession = Dictionary(grouping: sets, by: \.sessionID)

    let page = sessions.map { session in
      let grouped = Dictionary(
        grouping: setsBySession[session.id] ?? [],
        by: { MovementKey(exerciseID: $0.exerciseID, machineID: $0.machineID) })
      let movements = grouped.map { key, own -> (rank: Int, movement: TemplateHistory.Movement) in
        (
          planRank[key] ?? Int.max,
          TemplateHistory.Movement(
            id: key.id,
            exerciseName: exerciseNames[key.exerciseID] ?? "Unknown movement",
            machineName: key.machineID.flatMap { machineNames[$0] },
            workingSetCount: workingSetCount(of: own),
            volumeKg: workingVolume(of: own)
          )
        )
      }
      .sorted { lhs, rhs in
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if lhs.movement.exerciseName != rhs.movement.exerciseName {
          return lhs.movement.exerciseName < rhs.movement.exerciseName
        }
        return (lhs.movement.machineName ?? "") < (rhs.movement.machineName ?? "")
      }
      .map(\.movement)
      return TemplateHistory.Session(
        id: SessionID(rawValue: session.id),
        // `isCounted` requires a finish time; the start is only a type-level fallback.
        finishedAt: session.finishedAt ?? session.startedAt,
        movements: movements)
    }
    return TemplateHistory(sessions: page, totalSessionCount: total, limit: pageLimit)
  }

  /// Working sets in rows the read already filtered: warm-ups never reach here.
  private static func workingSetCount(of sets: [LoggedSet]) -> Int { sets.count }

  /// Σ weight × reps over those rows, which is `SessionVolume`'s definition. Kept beside the count
  /// so a history row and the session total cannot be summed two different ways.
  private static func workingVolume(of sets: [LoggedSet]) -> Double {
    sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  private static func readDraft(
    from id: SessionID, named name: String, in db: Database
  ) throws -> WorkoutTemplate {
    guard try Session.where({ $0.id.eq(id.rawValue) }).fetchCount(db) == 1 else {
      throw TemplateStoreError.notFound
    }
    let rows = try SessionExercise
      .where { $0.sessionID.eq(id.rawValue) }
      .order { ($0.position, $0.id) }
      .fetchAll(db)
    let names = try exerciseNames(Set(rows.map(\.exerciseID)), in: db)
    let machines = try machineNames(Set(rows.compactMap(\.machineID)), in: db)
    let counts = try workingSetCounts(for: rows, in: db)

    let position = (try StoredTemplate.where { !$0.isArchived }.select(\.position).fetchAll(db).max() ?? -1) + 1
    return WorkoutTemplate(
      name: name,
      position: position,
      exercises: rows.map { row in
        TemplateExercise(
          exerciseID: ExerciseID(rawValue: row.exerciseID),
          exerciseName: names[row.exerciseID] ?? "Unknown movement",
          machineID: row.machineID.map(MachineID.init(rawValue:)),
          machineName: row.machineID.flatMap { machines[$0] },
          plannedSets: counts[row.id] ?? 0,
          repRange: repRange(row.repRangeLower, row.repRangeUpper)
        )
      }
    )
  }

  /// Working sets logged for each plan row of one session, never counting warm-ups, by row id.
  ///
  /// A set counts against the plan row it recorded. A set written before sets recorded their plan
  /// row is matched by movement and machine instead. `rows` are one session's plan rows.
  static func workingSetCounts(for rows: [SessionExercise], in db: Database) throws -> [UUID: Int] {
    guard let sessionID = rows.first?.sessionID else { return [:] }
    let working: [(UUID?, UUID, UUID?)] = try LoggedSet
      .where { $0.sessionID.eq(sessionID) && !$0.isWarmup }
      .select { ($0.sessionExerciseID, $0.exerciseID, $0.machineID) }
      .fetchAll(db)
    var linked: [UUID: Int] = [:]
    var unlinked: [UnlinkedKey: Int] = [:]
    for (link, exercise, machine) in working {
      if let link {
        linked[link, default: 0] += 1
      } else {
        unlinked[UnlinkedKey(exerciseID: exercise, machineID: machine), default: 0] += 1
      }
    }
    return Dictionary(
      uniqueKeysWithValues: rows.map { row in
        (
          row.id,
          linked[row.id]
            ?? unlinked[UnlinkedKey(exerciseID: row.exerciseID, machineID: row.machineID)] ?? 0
        )
      })
  }

  private struct UnlinkedKey: Hashable {
    let exerciseID: UUID
    let machineID: UUID?
  }

  private static func repRange(_ lower: Int?, _ upper: Int?) -> RepRange? {
    guard let lower, let upper else { return nil }
    return RepRange(lower: lower, upper: upper)
  }

  private static func exerciseNames(_ ids: Set<UUID>, in db: Database) throws -> [UUID: String] {
    guard !ids.isEmpty else { return [:] }
    return try Exercise.where { $0.id.in(Array(ids)) }
      .fetchAll(db)
      .reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
  }

  /// "Hammer Strength Leg Press", as the machine picker shows it.
  private static func machineNames(_ ids: Set<UUID>, in db: Database) throws -> [UUID: String] {
    guard !ids.isEmpty else { return [:] }
    return try Machine.where { $0.id.in(Array(ids)) }
      .fetchAll(db)
      .reduce(into: [UUID: String]()) { $0[$1.id] = MachineRecord(row: $1).displayName }
  }

  // MARK: - Writing

  private static func write(
    _ template: WorkoutTemplate, named name: String, now: Date, in db: Database
  ) throws {
    let exerciseIDs = Array(Set(template.exercises.map { $0.exerciseID.rawValue }))
    let known = try Exercise.where { $0.id.in(exerciseIDs) }.select(\.id).fetchAll(db)
    guard Set(known).count == exerciseIDs.count else { throw TemplateStoreError.unknownExercise }
    let machineIDs = Array(Set(template.exercises.compactMap { $0.machineID?.rawValue }))
    let liveMachines =
      machineIDs.isEmpty
      ? Set<UUID>() : Set(try Machine.where { $0.id.in(machineIDs) }.select(\.id).fetchAll(db))

    let id = template.id.rawValue
    let exists = try StoredTemplate.where { $0.id.eq(id) }.fetchCount(db) == 1
    if exists {
      try StoredTemplate.where { $0.id.eq(id) }
        .update {
          $0.name = #bind(name)
          $0.position = #bind(template.position)
        }
        .execute(db)
    } else {
      try StoredTemplate.insert {
        StoredTemplate.Draft(
          id: id, name: name, position: template.position, isArchived: false, createdAt: now)
      }
      .execute(db)
    }

    // A movement id already used by another workout is never taken over: it would move that
    // workout's movement here. The new row gets a fresh identity instead.
    let requested = template.exercises.map(\.id)
    let claimed: [(UUID, UUID)] = try StoredTemplateExercise
      .where { $0.id.in(requested) }
      .select { ($0.id, $0.templateID) }
      .fetchAll(db)
    let owners = Dictionary(uniqueKeysWithValues: claimed)
    let ownRows = try StoredTemplateExercise.where { $0.templateID.eq(id) }.select(\.id).fetchAll(db)
    let kept = Set(requested.filter { owners[$0] == id })
    let stale = ownRows.filter { !kept.contains($0) }
    if !stale.isEmpty {
      try StoredTemplateExercise.where { $0.id.in(stale) }.delete().execute(db)
    }

    for (position, exercise) in template.exercises.enumerated() {
      let machine = (exercise.machineID?.rawValue).flatMap { liveMachines.contains($0) ? $0 : nil }
      if kept.contains(exercise.id) {
        try StoredTemplateExercise.where { $0.id.eq(exercise.id) }
          .update {
            $0.exerciseID = #bind(exercise.exerciseID.rawValue)
            $0.machineID = #bind(machine)
            $0.position = #bind(position)
            $0.plannedSets = #bind(exercise.plannedSets)
            $0.repRangeLower = #bind(exercise.repRange?.lower)
            $0.repRangeUpper = #bind(exercise.repRange?.upper)
            $0.restSeconds = #bind(exercise.restSeconds)
          }
          .execute(db)
      } else {
        try StoredTemplateExercise.insert {
          StoredTemplateExercise.Draft(
            id: owners[exercise.id] == nil ? exercise.id : UUID(),
            templateID: id,
            exerciseID: exercise.exerciseID.rawValue,
            machineID: machine,
            position: position,
            plannedSets: exercise.plannedSets,
            repRangeLower: exercise.repRange?.lower,
            repRangeUpper: exercise.repRange?.upper,
            restSeconds: exercise.restSeconds,
            createdAt: now
          )
        }
        .execute(db)
      }
    }
  }
}
