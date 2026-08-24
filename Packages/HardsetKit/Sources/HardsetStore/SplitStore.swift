import Foundation
import HardsetCore
import SQLiteData

/// A plan, as the UI sees it.
public nonisolated struct SplitRecord: Hashable, Sendable, Identifiable {
  public let id: SplitID
  public let name: String
  public let createdAt: Date

  init(row: Split) {
    self.id = SplitID(rawValue: row.id)
    self.name = row.name
    self.createdAt = row.createdAt
  }
}

/// One day of a plan.
public nonisolated struct SplitDayRecord: Hashable, Sendable, Identifiable {
  public let id: SplitDayID
  public let splitID: SplitID
  public let name: String
  /// The ordering. Never derived from `name` -- two days may legitimately share one.
  public let position: Int

  init(row: SplitDay) {
    self.id = SplitDayID(rawValue: row.id)
    self.splitID = SplitID(rawValue: row.splitID)
    self.name = row.name
    self.position = row.position
  }
}

/// One movement on one day.
///
/// Carries no set count, and that is the design rather than an omission: the app has no weekly set
/// target for any muscle, so a number here would be invented. See `docs/SPLITS-spec.md`.
public nonisolated struct SplitEntryRecord: Hashable, Sendable, Identifiable {
  public let id: SplitEntryID
  public let dayID: SplitDayID
  public let exerciseID: ExerciseID
  /// The machine this movement is planned on, when the lifter has said which.
  public let machineID: MachineID?
  public let position: Int

  init(row: SplitEntry) {
    self.id = SplitEntryID(rawValue: row.id)
    self.dayID = SplitDayID(rawValue: row.splitDayID)
    self.exerciseID = ExerciseID(rawValue: row.exerciseID)
    self.machineID = row.machineID.map(MachineID.init(rawValue:))
    self.position = row.position
  }
}

/// Plans: named arrangements of movements the lifter already trains.
///
/// The store persists and reshapes a partition. It does not decide one -- `SplitDealer` does that,
/// as a pure function -- and it does not evaluate one. There is deliberately no method here that
/// returns a quality figure for a plan, because no such figure is computable: see
/// `SplitCalibrationProbe` and DECISIONS #19.
public nonisolated struct SplitStore {
  private let database: any DatabaseWriter
  /// Used to record a machine in the gym's library when a plan names one. Held rather than
  /// constructed per call so the association has exactly one implementation.
  private let gyms: GymStore

  public init(database: any DatabaseWriter) {
    self.database = database
    self.gyms = GymStore(database: database)
  }

  // MARK: - Plans

  public func splits() throws -> [SplitRecord] {
    try database.read { db in
      try Split
        .where { !$0.isArchived }
        .order { $0.createdAt.desc() }
        .fetchAll(db)
        .map(SplitRecord.init(row:))
    }
  }

  public func split(_ id: SplitID) throws -> SplitRecord? {
    try database.read { db in
      try Split.where { $0.id.eq(id.rawValue) }.fetchOne(db).map(SplitRecord.init(row:))
    }
  }

  @discardableResult
  public func createSplit(name: String, now: Date = Date()) throws -> SplitID {
    let id = SplitID()
    try database.write { db in
      try Split.insert {
        Split.Draft(id: id.rawValue, name: name, isArchived: false, createdAt: now)
      }
      .execute(db)
    }
    return id
  }

  public func renameSplit(_ id: SplitID, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try database.write { db in
      try Split.where { $0.id.eq(id.rawValue) }.update { $0.name = #bind(trimmed) }.execute(db)
    }
  }

  /// Archives rather than deletes, so a plan can be put away and brought back.
  ///
  /// Nothing references a split the way a logged set references an exercise, so a hard delete would
  /// be safe -- but a plan is something a lifter built, and "undo" is cheaper than "retype it".
  public func archiveSplit(_ id: SplitID) throws {
    try database.write { db in
      try Split.where { $0.id.eq(id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }
  }

  public func unarchiveSplit(_ id: SplitID) throws {
    try database.write { db in
      try Split.where { $0.id.eq(id.rawValue) }.update { $0.isArchived = #bind(false) }.execute(db)
    }
  }

  // MARK: - Days

  public func days(in splitID: SplitID) throws -> [SplitDayRecord] {
    try database.read { db in
      try SplitDay
        .where { $0.splitID.eq(splitID.rawValue) }
        .order { $0.position }
        .fetchAll(db)
        .map(SplitDayRecord.init(row:))
    }
  }

  /// Appends a day at the end of the week.
  @discardableResult
  public func addDay(to splitID: SplitID, name: String, now: Date = Date()) throws -> SplitDayID {
    let id = SplitDayID()
    try database.write { db in
      let next = try SplitDay.nextPosition(splitID: splitID.rawValue, in: db)
      try SplitDay.insert {
        SplitDay.Draft(
          id: id.rawValue, splitID: splitID.rawValue, name: name, position: next, createdAt: now
        )
      }
      .execute(db)
    }
    return id
  }

  public func renameDay(_ id: SplitDayID, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try database.write { db in
      try SplitDay.where { $0.id.eq(id.rawValue) }.update { $0.name = #bind(trimmed) }.execute(db)
    }
  }

  /// Removes a day and everything planned on it.
  ///
  /// A hard delete, unlike a logged set: nothing here is a record of training that happened, so
  /// there is no history to lose. Remaining days are re-numbered so positions stay contiguous --
  /// a gap would be invisible until something rendered "Day 1, Day 3".
  public func deleteDay(_ id: SplitDayID) throws {
    try database.write { db in
      guard let day = try SplitDay.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else { return }
      try SplitDay.where { $0.id.eq(id.rawValue) }.delete().execute(db)
      try SplitDay.compactPositions(splitID: day.splitID, in: db)
    }
  }

  // MARK: - Entries

  public func entries(in dayID: SplitDayID) throws -> [SplitEntryRecord] {
    try database.read { db in
      try SplitEntry
        .where { $0.splitDayID.eq(dayID.rawValue) }
        .order { $0.position }
        .fetchAll(db)
        .map(SplitEntryRecord.init(row:))
    }
  }

  /// Plans a movement onto a day, and -- when a machine is named -- adds that machine to the gym's
  /// library for this movement.
  ///
  /// The library write is the point of naming a machine here at all. `machineExercises` is what
  /// `GymStore.exercisesWithEquipment(at:)` reads to know a gym has equipment for a movement before
  /// anything has been logged on it, so planning a split is the earliest moment that association
  /// can be recorded -- and, as `createMachine`'s own note says, it is unrecoverable later without
  /// guessing.
  @discardableResult
  public func addEntry(
    to dayID: SplitDayID,
    exercise exerciseID: ExerciseID,
    machine machineID: MachineID? = nil,
    now: Date = Date()
  ) throws -> SplitEntryID {
    let id = SplitEntryID()
    try database.write { db in
      let next = try SplitEntry.nextPosition(dayID: dayID.rawValue, in: db)
      try SplitEntry.insert {
        SplitEntry.Draft(
          id: id.rawValue,
          splitDayID: dayID.rawValue,
          exerciseID: exerciseID.rawValue,
          machineID: machineID?.rawValue,
          position: next,
          createdAt: now
        )
      }
      .execute(db)
    }
    // A separate write, deliberately: the entry is the thing the lifter asked for, and a failure to
    // record the library association must not lose it.
    if let machineID {
      try gyms.linkMachine(machineID, toExercise: exerciseID, now: now)
    }
    return id
  }

  /// Names the machine for a movement already on a day, adding it to the library too.
  public func setMachine(
    _ machineID: MachineID?,
    forEntry id: SplitEntryID,
    now: Date = Date()
  ) throws {
    let entry = try database.write { db -> SplitEntry? in
      try SplitEntry
        .where { $0.id.eq(id.rawValue) }
        .update { $0.machineID = #bind(machineID?.rawValue) }
        .execute(db)
      return try SplitEntry.where { $0.id.eq(id.rawValue) }.fetchOne(db)
    }
    if let machineID, let entry {
      try gyms.linkMachine(machineID, toExercise: ExerciseID(rawValue: entry.exerciseID), now: now)
    }
  }

  public func removeEntry(_ id: SplitEntryID) throws {
    try database.write { db in
      guard let entry = try SplitEntry.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else { return }
      try SplitEntry.where { $0.id.eq(id.rawValue) }.delete().execute(db)
      try SplitEntry.compactPositions(dayID: entry.splitDayID, in: db)
    }
  }

  /// Moves a movement to another day, or to another slot on its own day.
  ///
  /// This is what a lifter dragging a row is doing, and it is the whole interaction the feature
  /// exists for: the dealer's arrangement is a starting point, not a verdict.
  ///
  /// - Parameter position: Where in the destination day it lands. Clamped into range, and appended
  ///   when nil.
  public func moveEntry(
    _ id: SplitEntryID,
    toDay dayID: SplitDayID,
    at position: Int? = nil
  ) throws {
    try database.write { db in
      guard let entry = try SplitEntry.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else { return }
      let origin = entry.splitDayID

      // Take it out of the destination's numbering first so a same-day move does not count itself.
      var destination = try SplitEntry.ordered(dayID: dayID.rawValue, in: db)
        .filter { $0.id != entry.id }
      let target = min(max(0, position ?? destination.count), destination.count)
      destination.insert(entry, at: target)

      for (index, row) in destination.enumerated() {
        try SplitEntry
          .where { $0.id.eq(row.id) }
          .update {
            $0.splitDayID = #bind(dayID.rawValue)
            $0.position = #bind(index)
          }
          .execute(db)
      }

      if origin != dayID.rawValue {
        try SplitEntry.compactPositions(dayID: origin, in: db)
      }
    }
  }

  // MARK: - Whole-plan reads and writes

  /// Loads a plan into the pure type the dealer and the assessment work in.
  ///
  /// Two queries, not one per day: a plan is opened as a whole and this must not become the logger's
  /// per-render querying in another costume.
  public func plan(for splitID: SplitID) throws -> SplitPlan {
    try database.read { db in
      let days = try SplitDay
        .where { $0.splitID.eq(splitID.rawValue) }
        .order { $0.position }
        .fetchAll(db)
      let dayIDs = days.map(\.id)
      let entries =
        dayIDs.isEmpty
        ? []
        : try SplitEntry.where { $0.splitDayID.in(dayIDs) }.order { $0.position }.fetchAll(db)

      var byDay: [UUID: [SplitEntry]] = [:]
      for entry in entries {
        byDay[entry.splitDayID, default: []].append(entry)
      }

      return SplitPlan(
        days: days.enumerated().map { index, day in
          SplitPlanDay(
            position: index,
            name: day.name,
            movements: (byDay[day.id] ?? []).map { ExerciseID(rawValue: $0.exerciseID) }
          )
        }
      )
    }
  }

  /// Replaces a split's days and entries with a dealt plan.
  ///
  /// Destructive by design: this is "re-deal my week", and the arrangement it replaces is not
  /// training history. Nothing logged references a split, so no record of work is at risk.
  ///
  /// Machine assignments do not survive a re-deal, because the plan type does not carry them -- the
  /// dealer works in movements. Re-naming machines afterwards is the lifter's, and the library
  /// associations already written are not removed by this.
  public func replace(_ splitID: SplitID, with plan: SplitPlan, now: Date = Date()) throws {
    try database.write { db in
      // Entries cascade with their days.
      try SplitDay.where { $0.splitID.eq(splitID.rawValue) }.delete().execute(db)

      for day in plan.days {
        let dayID = UUID()
        try SplitDay.insert {
          SplitDay.Draft(
            id: dayID, splitID: splitID.rawValue, name: day.name, position: day.position,
            createdAt: now
          )
        }
        .execute(db)

        for (index, movement) in day.movements.enumerated() {
          try SplitEntry.insert {
            SplitEntry.Draft(
              id: UUID(),
              splitDayID: dayID,
              exerciseID: movement.rawValue,
              machineID: nil,
              position: index,
              createdAt: now
            )
          }
          .execute(db)
        }
      }
    }
  }

  /// A day of a plan, as today's workout.
  ///
  /// This is what makes a plan more than a readback: it is the one path from planning into the
  /// app's core loop. Without it the planner is a document.
  ///
  /// **Every `plannedSets` is nil, and that is the design.** `VolumeStore.plan(for:)` -- the
  /// "do it again" path -- carries a set count because a past workout genuinely has one: it counts
  /// the sets that were logged. A split day genuinely does not, and `RepeatableExercise` cannot
  /// express that, because its `workingSets` is non-optional. Routing through that type would have
  /// forced a number to be invented here, which is the exact thing this whole feature refuses. So
  /// this returns `PlannedExercise` directly, where `plannedSets` is `Int?` and nil means what it
  /// says.
  ///
  /// Machine, name and modality are carried per movement -- modality because without it a planned
  /// pull-up opens as a loaded row demanding a weight, which is a defect the repeat path already
  /// shipped once.
  public func plannedExercises(for dayID: SplitDayID) throws -> [PlannedExercise] {
    try database.read { db in
      let entries = try SplitEntry.ordered(dayID: dayID.rawValue, in: db)
      guard !entries.isEmpty else { return [] }

      let exercises = try Exercise.where { $0.id.in(entries.map(\.exerciseID)) }.fetchAll(db)
      let exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

      let machineIDs = entries.compactMap(\.machineID)
      let machines =
        machineIDs.isEmpty ? [] : try Machine.where { $0.id.in(machineIDs) }.fetchAll(db)
      let machinesByID = Dictionary(machines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

      return entries.compactMap { entry in
        // A movement whose exercise row has gone is skipped rather than started as "Unknown". The
        // foreign key is CASCADE, so this should be unreachable; silently inventing a name for it
        // would not be.
        guard let exercise = exercisesByID[entry.exerciseID] else { return nil }
        let machine = entry.machineID.flatMap { machinesByID[$0] }
        return PlannedExercise(
          exerciseID: ExerciseID(rawValue: entry.exerciseID),
          machineID: machine.map { MachineID(rawValue: $0.id) },
          exerciseName: exercise.name,
          modality: ExerciseModality(rawValue: exercise.modality),
          machineName: machine?.name,
          machineIncrementKg: machine?.stackIncrementKg,
          // Nil, always. See the note above.
          plannedSets: nil
        )
      }
    }
  }

  /// Every distinct movement the lifter has actually logged, newest first.
  ///
  /// The input the dealer is meant to be given: their own movements, not a catalogue. A plan built
  /// from anything else would be recommending movements rather than arranging them.
  public func loggedMovements(limit: Int = 40) throws -> [ExerciseID] {
    try gyms.recentlyLoggedExercises(limit: limit)
  }
}

// MARK: - Position arithmetic
//
// Extracted as `static func`s taking `db` for the reason recorded in `MachineExercise.existing`: a
// nested StructuredQueries closure inside `database.write { db in ... }` binds `$0` to the outer
// `db` and produces a misleading diagnostic.

extension SplitDay {
  nonisolated static func nextPosition(splitID: UUID, in db: Database) throws -> Int {
    let existing = try SplitDay.where { $0.splitID.eq(splitID) }.fetchAll(db)
    return (existing.map(\.position).max() ?? -1) + 1
  }

  /// Renumbers a split's days to 0..<n in their current order, closing any gap.
  nonisolated static func compactPositions(splitID: UUID, in db: Database) throws {
    let remaining = try SplitDay.where { $0.splitID.eq(splitID) }.order { $0.position }.fetchAll(db)
    for (index, row) in remaining.enumerated() where row.position != index {
      try SplitDay.where { $0.id.eq(row.id) }.update { $0.position = #bind(index) }.execute(db)
    }
  }
}

extension SplitEntry {
  nonisolated static func ordered(dayID: UUID, in db: Database) throws -> [SplitEntry] {
    try SplitEntry.where { $0.splitDayID.eq(dayID) }.order { $0.position }.fetchAll(db)
  }

  nonisolated static func nextPosition(dayID: UUID, in db: Database) throws -> Int {
    let existing = try SplitEntry.where { $0.splitDayID.eq(dayID) }.fetchAll(db)
    return (existing.map(\.position).max() ?? -1) + 1
  }

  nonisolated static func compactPositions(dayID: UUID, in db: Database) throws {
    let remaining = try SplitEntry.ordered(dayID: dayID, in: db)
    for (index, row) in remaining.enumerated() where row.position != index {
      try SplitEntry.where { $0.id.eq(row.id) }.update { $0.position = #bind(index) }.execute(db)
    }
  }
}
