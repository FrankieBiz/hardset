import Foundation
import GRDB
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
  /// Working sets the lifter intends here, or nil when they have not said.
  ///
  /// Never authored by the app. nil is a real answer and the default, which is what keeps this a
  /// record of intent rather than a prescription.
  public let targetSets: Int?

  init(row: SplitEntry) {
    self.id = SplitEntryID(rawValue: row.id)
    self.dayID = SplitDayID(rawValue: row.splitDayID)
    self.exerciseID = ExerciseID(rawValue: row.exerciseID)
    self.machineID = row.machineID.map(MachineID.init(rawValue:))
    self.position = row.position
    self.targetSets = row.targetSets
  }
}

/// Plans: named arrangements of movements the lifter already trains.
///
/// The store persists and reshapes a partition. It does not decide one -- `SplitDealer` does that,
/// as a pure function -- and it does not evaluate one. There is deliberately no method here that
/// returns a quality figure for a plan, because no such figure is computable: see
/// `SplitCalibrationProbe` and DECISIONS #19.
public nonisolated struct SplitStore: Sendable {
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
    return try database.read { db in
      try Split
        .where { !$0.isArchived }
        .order { $0.createdAt.desc() }
        .fetchAll(db)
        .map(SplitRecord.init(row:))
    }
  }

  /// Plans that have been put away, newest first.
  ///
  /// This exists so `isArchived` is a round trip rather than a one-way door. A soft delete with no
  /// restore path is worse than a hard one: the rows keep syncing to iCloud while the lifter has
  /// been told the plan is gone, and "archived" becomes a word for "invisible forever".
  public func archivedSplits() throws -> [SplitRecord] {
    try database.read { db in
      try Split
        .where { $0.isArchived }
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
  /// Moves a day to a new position within its plan.
  ///
  /// Day order is not decoration. It is the order the lifter reads their own plan in, and it is the
  /// tie-break `SplitRotation.longestSinceTrained` uses when two days are equally overdue -- so a
  /// plan whose days cannot be reordered has an arrangement the lifter cannot correct. Days could be
  /// added, renamed and deleted, and never moved.
  ///
  /// Renumbers the whole plan to 0..<n, the same shape as `compactPositions`, so positions stay
  /// dense and no gap accumulates.
  public func moveDay(_ id: SplitDayID, to position: Int) throws {
    try database.write { db in
      guard let day = try SplitDay.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else { return }
      var ordered = try SplitDay.where { $0.splitID.eq(day.splitID) }
        .order { $0.position }
        .fetchAll(db)
      ordered.removeAll { $0.id == day.id }
      let target = min(max(0, position), ordered.count)
      ordered.insert(day, at: target)

      for (index, row) in ordered.enumerated() where row.position != index {
        try SplitDay.where { $0.id.eq(row.id) }.update { $0.position = #bind(index) }.execute(db)
      }
    }
  }

  public func deleteDay(_ id: SplitDayID) throws {
    try database.write { db in
      guard let day = try SplitDay.where({ $0.id.eq(id.rawValue) }).fetchOne(db) else { return }
      try SplitDay.where { $0.id.eq(id.rawValue) }.delete().execute(db)
      try SplitDay.compactPositions(splitID: day.splitID, in: db)
    }
  }

  // MARK: - Entries

  /// Which of a day's planned movements have been retired.
  ///
  /// A movement the lifter archived stays in their plan: `splitEntries.exerciseID` cascades only on
  /// delete, and archiving is a soft delete, so nothing removes it. That is the right default -- the
  /// plan is theirs and the app must not edit it. But the picker stops offering an archived movement
  /// while the plan goes on starting it, so the plan has to be able to *say* so.
  ///
  /// Returned as a set rather than filtered out, deliberately. Dropping the row would be the app
  /// quietly editing a plan; marking it lets the lifter decide.
  public func retiredMovements(in dayID: SplitDayID) throws -> Set<ExerciseID> {
    try database.read { db in
      let entries = try SplitEntry.ordered(dayID: dayID.rawValue, in: db)
      guard !entries.isEmpty else { return [] }
      let archived = try Exercise
        .where { $0.id.in(entries.map(\.exerciseID)) && $0.isArchived }
        .fetchAll(db)
      return Set(archived.map { ExerciseID(rawValue: $0.id) })
    }
  }

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

  /// Swaps which movement a planned slot holds, keeping the slot.
  ///
  /// Remove-and-re-add was the only way to do this, and it is not the same operation: it appends at
  /// the bottom of the day and drops the intended sets, so correcting a movement cost the lifter the
  /// two things they had authored about that slot. Position and `targetSets` are statements about
  /// the slot and survive.
  ///
  /// The machine does not, and that asymmetry is the point. A machine is bound to the movement
  /// pressed on it -- 80 kg on a Hammer Strength leg press is a different series from 80 kg on a
  /// Cybex, which is the whole of differentiator #2 -- so carrying the binding across a swap would
  /// have the app assert a machine attribution for a movement nobody said was performed on it.
  /// Cleared, and visibly: the row loses its machine line and offers "Add machine" again.
  public func setExercise(_ exerciseID: ExerciseID, forEntry id: SplitEntryID) throws {
    let cleared: UUID? = nil
    try database.write { db in
      guard try SplitEntry.where({ $0.id.eq(id.rawValue) }).fetchOne(db) != nil else { return }
      try SplitEntry
        .where { $0.id.eq(id.rawValue) }
        .update {
          $0.exerciseID = #bind(exerciseID.rawValue)
          $0.machineID = #bind(cleared)
        }
        .execute(db)
    }
  }

  /// Records how many working sets the lifter intends on one planned movement.
  ///
  /// `nil` clears it, and clearing is a first-class outcome: "I have not said" must stay reachable,
  /// or the column stops being optional in practice. Non-positive values clear too, because zero
  /// intended sets is the same statement as removing the movement, said less clearly.
  ///
  /// Capped at `Self.maximumTargetSets`. Not a training claim -- a stepper cannot reach it and
  /// nothing in the app compares the number to anything. It exists so a corrupt or fuzzed value
  /// cannot make the logger open thousands of rows.
  public func setTargetSets(_ sets: Int?, forEntry id: SplitEntryID) throws {
    let requested = sets ?? 0
    let resolved: Int? = requested > 0 ? min(requested, Self.maximumTargetSets) : nil
    try database.write { db in
      try SplitEntry
        .where { $0.id.eq(id.rawValue) }
        .update { $0.targetSets = #bind(resolved) }
        .execute(db)
    }
  }

  /// The most sets a plan entry may intend. A guard against absurd input, not a recommendation.
  public static let maximumTargetSets = 20

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

  /// Replaces a plan's arrangement, **carrying forward what the lifter authored**.
  ///
  /// Re-dealing rearranges movements. It is not a reset, and it used to behave like one: this method
  /// wrote `machineID: nil` for every entry and took its day names from the dealer, so one tap of
  /// "Deal" silently discarded every machine the lifter had named and renamed "Push / Pull / Legs"
  /// back to "Day 1 / Day 2 / Day 3". Machine assignments are the app's whole differentiator and
  /// there is no undo, so losing them to a rearrangement is data loss.
  ///
  /// Two things are therefore preserved across the replacement:
  ///
  /// - **Machines and intended set counts, by movement.** A movement keeps what the lifter said
  ///   about it wherever it lands. Where the same movement appears more than once, these are reused
  ///   in the order they were found, so a plan with two entries for one movement on two machines
  ///   keeps both.
  /// - **Day names, by position.** Day *n* keeps day *n*'s name. Dealing into more days than
  ///   existed gives the new days the dealer's placeholder; dealing into fewer drops the tail's
  ///   names with the days themselves.
  /// - **Day identity, by position.** Day *n* keeps day *n*'s row, so `sessions.splitDayID` still
  ///   points at it. This used to delete every day and insert fresh `UUID()`s, and because that
  ///   column is `ON DELETE SET NULL`, one tap of "Deal" permanently unlinked every workout ever
  ///   started from the plan -- the rotation line went back to "Not trained yet" for a plan trained
  ///   all year, and no undo could bring it back. Carrying identity by position is the same rule as
  ///   carrying the name by position, and for the same reason: a re-deal is a rearrangement, not a
  ///   reset.
  public func replace(_ splitID: SplitID, with plan: SplitPlan, now: Date = Date()) throws {
    try database.write { db in
      let previousDays = try SplitDay.where { $0.splitID.eq(splitID.rawValue) }
        .order { $0.position }
        .fetchAll(db)

      // What the lifter authored per movement, queued so repeats keep their own.
      var authoredQueue: [UUID: [AuthoredEntry]] = [:]
      for day in previousDays {
        for entry in try SplitEntry.ordered(dayID: day.id, in: db) {
          authoredQueue[entry.exerciseID, default: []]
            .append(AuthoredEntry(machineID: entry.machineID, targetSets: entry.targetSets))
        }
      }

      var reusedDayIDs: Set<UUID> = []

      for day in plan.days {
        // `position` indexes the previous arrangement, which is why this is not simply
        // `previousDays.first`. The guard against a repeated position is not theoretical tidiness:
        // reusing one row twice would insert two days with the same primary key and fail the whole
        // write, losing the deal rather than one day's history.
        var reusable: SplitDay?
        if day.position >= 0, day.position < previousDays.count {
          let candidate = previousDays[day.position]
          if !reusedDayIDs.contains(candidate.id) { reusable = candidate }
        }
        let dayID: UUID

        if let reusable {
          dayID = reusable.id
          reusedDayIDs.insert(dayID)
          // The lifter's own name wins over the dealer's placeholder.
          let name = reusable.name.isEmpty ? day.name : reusable.name
          try SplitDay.where { $0.id.eq(reusable.id) }
            .update {
              $0.name = #bind(name)
              $0.position = #bind(day.position)
            }
            .execute(db)
          // The day is no longer deleted, so the cascade that used to clear its movements no longer
          // fires and this has to do it.
          try SplitEntry.where { $0.splitDayID.eq(dayID) }.delete().execute(db)
        } else {
          dayID = UUID()
          try SplitDay.insert {
            SplitDay.Draft(
              id: dayID, splitID: splitID.rawValue, name: day.name, position: day.position,
              createdAt: now
            )
          }
          .execute(db)
        }

        for (index, movement) in day.movements.enumerated() {
          var authored: AuthoredEntry?
          if var queued = authoredQueue[movement.rawValue], !queued.isEmpty {
            authored = queued.removeFirst()
            authoredQueue[movement.rawValue] = queued
          }
          try SplitEntry.insert {
            SplitEntry.Draft(
              id: UUID(),
              splitDayID: dayID,
              exerciseID: movement.rawValue,
              machineID: authored?.machineID,
              position: index,
              targetSets: authored?.targetSets,
              createdAt: now
            )
          }
          .execute(db)
        }
      }

      // Only the tail the deal has no room for. These are genuinely gone -- their movements cascade
      // and any session started from them is unlinked, which is DECISION #41's rule for deleting a
      // day and the one case where a deal really does reshape the plan.
      for day in previousDays where !reusedDayIDs.contains(day.id) {
        try SplitDay.where { $0.id.eq(day.id) }.delete().execute(db)
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
  /// - Parameter gymID: Where this workout is happening. **Load-bearing**: a machine belongs to one
  ///   gym, so a plan's machine is only the right machine if the lifter is at that gym.
  ///
  ///   A plan has no gym of its own, and it should not need one — a lifter who trains the same
  ///   arrangement at two gyms should not be forced to keep two plans. So the machine is reconciled
  ///   here, at the one moment the gym is known:
  ///
  ///   - Same gym: kept.
  ///   - Different gym, and a machine of the same name exists here: resolved to *that* machine, via
  ///     `existingMachine(named:at:)`. Nothing is created and no history is merged — invariant #10
  ///     and DECISION #39 both hold, because resolution is scoped to this gym and matches by name
  ///     the way the lifter means it.
  ///   - Different gym, no counterpart here: dropped. The row opens unbound and the lifter picks,
  ///     which is what the logger's own gym-scoped picker would have made them do anyway.
  ///   - No gym at all: dropped, because a session with no gym can only ever log `machineID == nil`,
  ///     and the logger will not offer a machine picker either.
  ///
  ///   Without this, starting a plan built at one gym while standing in another opened every row
  ///   bound to the *other* gym's machine and showed its load history as though it were the
  ///   equipment in front of you — silently writing sets into a machine series the lifter never
  ///   touched. Proven on device before it was fixed. The logger's picker has always been gym-scoped
  ///   (`canPickMachines` requires a gym); the plan was the one path around it.
  public func plannedExercises(
    for dayID: SplitDayID, at gymID: GymID? = nil
  ) throws -> [PlannedExercise] {
    try database.read { db in
      let entries = try SplitEntry.ordered(dayID: dayID.rawValue, in: db)
      guard !entries.isEmpty else { return [] }

      let exercises = try Exercise.where { $0.id.in(entries.map(\.exerciseID)) }.fetchAll(db)
      let exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

      let machineIDs = entries.compactMap(\.machineID)
      let machines =
        machineIDs.isEmpty ? [] : try Machine.where { $0.id.in(machineIDs) }.fetchAll(db)
      let machinesByID = Dictionary(machines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

      // Read here rather than through `GymStore`: a nested `database.read` on the same queue would
      // deadlock, so the counterpart lookup has to share this transaction.
      var counterpartByName: [String: Machine] = [:]
      if let gymID {
        let here = try Machine.where { $0.gymID.eq(gymID.rawValue) }.fetchAll(db)
        for machine in here where !machine.isArchived {
          // First writer wins, matching `existingMachine(named:at:)`, which returns the first
          // unarchived row it finds under the name.
          let key = GymStore.normalized(machine.name)
          if counterpartByName[key] == nil { counterpartByName[key] = machine }
        }
      }

      return entries.compactMap { entry in
        // A movement whose exercise row has gone is skipped rather than started as "Unknown". The
        // foreign key is CASCADE, so this should be unreachable; silently inventing a name for it
        // would not be.
        guard let exercise = exercisesByID[entry.exerciseID] else { return nil }
        let planned = entry.machineID.flatMap { machinesByID[$0] }
        let machine = Self.machine(planned, usableAt: gymID, counterparts: counterpartByName)
        return PlannedExercise(
          exerciseID: ExerciseID(rawValue: entry.exerciseID),
          machineID: machine.map { MachineID(rawValue: $0.id) },
          exerciseName: exercise.name,
          modality: ExerciseModality(rawValue: exercise.modality),
          machineName: machine?.name,
          machineIncrementKg: machine?.stackIncrementKg,
          // The lifter's own intended set count, or nil when they have not said one.
          //
          // This is the hop the `targetSets` column exists for, and it needed no new machinery:
          // `PlannedExercise.plannedSets` was already `Int?` and `sessionExercises.plannedSets`
          // already existed, so a day the lifter has given set counts now opens with that many
          // rows. Where they have said nothing this stays nil and the rows come from their history,
          // exactly as before -- which is why the app never ends up authoring a number.
          plannedSets: entry.targetSets
        )
      }
    }
  }

  /// Whether any live plan has a day with a movement on it.
  ///
  /// Answers one question for the start screen: is there a plan to point at? Deliberately a boolean
  /// rather than the days themselves, because *which* plan is selected is `SplitPlannerScreen`'s
  /// state and copying that choice into a second screen is how two screens come to disagree.
  public func hasStartableDay() throws -> Bool {
    try database.read { db in
      let plans = try Split.where { !$0.isArchived }.fetchAll(db)
      guard !plans.isEmpty else { return false }
      let days = try SplitDay.where { $0.splitID.in(plans.map(\.id)) }.fetchAll(db)
      guard !days.isEmpty else { return false }
      // An empty day cannot be started, so a plan of empty days is not something to point at.
      return try SplitEntry.where { $0.splitDayID.in(days.map(\.id)) }.fetchOne(db) != nil
    }
  }

  // MARK: - Rotation

  /// When each day of a plan was last trained, for the days that ever have been.
  ///
  /// Read from `sessions.splitDayID`, which is written when a day is started as a workout — so this
  /// is a record of what happened, not a match of a session's contents back onto a plan. A day the
  /// lifter has never started is absent from the dictionary rather than carrying a placeholder
  /// date, because "never" and "a long time ago" are different answers and the UI says so.
  ///
  /// Only finished sessions count. An open one is already on screen as the live workout, and a
  /// session that was started and discarded is not training that happened.
  ///
  /// Keyed by `startedAt` rather than `finishedAt`: a workout belongs to the day it was performed,
  /// and a session finished after midnight was still trained the evening before.
  public func lastTrainedByDay(in splitID: SplitID) throws -> [SplitDayID: Date] {
    try database.read { db in
      let days = try SplitDay.where { $0.splitID.eq(splitID.rawValue) }.fetchAll(db)
      // Spelled `[UUID?]` because `splitDayID` is nullable, and `in` requires both sides to agree.
      let dayIDs: [UUID?] = days.map(\.id)
      guard !dayIDs.isEmpty else { return [:] }

      // Typed query rather than raw SQL with a bound identifier. The column is TEXT and the exact
      // spelling SQLiteData writes a UUID in is its business, not this file's -- a literal in the
      // wrong case would match nothing and report "never trained" for a day trained yesterday,
      // which is the silent-wrong-number failure this app exists to not have.
      let sessions = try Session
        .where { $0.splitDayID.in(dayIDs) && $0.finishedAt.isNot(nil) }
        .fetchAll(db)

      // A plain loop, not `reduce`: the max is per key, and the loop says so in one pass.
      var latest: [SplitDayID: Date] = [:]
      for session in sessions {
        guard let rawDayID = session.splitDayID else { continue }
        let dayID = SplitDayID(rawValue: rawDayID)
        if let seen = latest[dayID], seen >= session.startedAt { continue }
        latest[dayID] = session.startedAt
      }
      return latest
    }
  }

  /// Which machine a planned movement should open on at `gymID`, if any.
  ///
  /// Extracted so the rule lives in exactly one place: the reconciliation is the whole reason
  /// `plannedExercises` takes a gym, and a second copy of it would be a second chance to get it
  /// wrong. See that method's documentation for why each branch is what it is.
  static func machine(
    _ planned: Machine?, usableAt gymID: GymID?, counterparts: [String: Machine]
  ) -> Machine? {
    guard let planned else { return nil }
    guard let gymID else { return nil }
    if planned.gymID == gymID.rawValue { return planned }
    return counterparts[GymStore.normalized(planned.name)]
  }

  /// Every distinct movement in a completed workout, newest first.
  ///
  /// An open workout is not training history yet: its rows can be corrected, removed, or be part
  /// of a workout the lifter abandons. The first-plan builder deliberately uses only finished
  /// sessions so it reflects an established routine rather than whatever happens to be on screen.
  public func completedWorkoutMovements(limit: Int = 40) throws -> [ExerciseID] {
    guard limit > 0 else { return [] }
    return try database.read { db in
      let ids = try UUID.fetchAll(
        db,
        sql: """
          SELECT loggedSets.exerciseID
          FROM loggedSets
          JOIN sessions ON sessions.id = loggedSets.sessionID
          WHERE sessions.finishedAt IS NOT NULL
          GROUP BY loggedSets.exerciseID
          ORDER BY MAX(loggedSets.completedAt) DESC
          LIMIT ?
          """,
        arguments: [limit]
      )
      return ids.map(ExerciseID.init(rawValue:))
    }
  }

  /// Recent logged movements for picker relevance. Unlike the first-plan builder, this is allowed
  /// to include an open workout because it helps the lifter continue the session currently underway.
  public func loggedMovements(limit: Int = 40) throws -> [ExerciseID] {
    try gyms.recentlyLoggedExercises(limit: limit)
  }
}

/// What the lifter authored about one planned movement, carried across a re-deal.
///
/// A pair rather than two parallel dictionaries: both belong to the same entry, and splitting them
/// is how a movement ends up keeping its machine and losing its set count.
private nonisolated struct AuthoredEntry {
  let machineID: UUID?
  let targetSets: Int?
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
