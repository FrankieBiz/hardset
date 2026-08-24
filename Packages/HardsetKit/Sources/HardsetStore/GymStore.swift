import Foundation
import HardsetCore
import SQLiteData

/// A gym, as the UI sees it.
public nonisolated struct GymRecord: Hashable, Sendable, Identifiable {
  public let id: GymID
  public let name: String

  init(row: Gym) {
    self.id = GymID(rawValue: row.id)
    self.name = row.name
  }
}

/// A machine, as the UI sees it.
public nonisolated struct MachineRecord: Hashable, Sendable, Identifiable {
  public let id: MachineID
  public let gymID: GymID
  public let name: String
  public let brand: String
  /// The smallest step this stack actually moves in, when known. Drives honest progression: a
  /// suggestion of +2.5 kg on a stack that moves in 5 kg jumps is a lie about the equipment.
  public let stackIncrementKg: Double?

  init(row: Machine) {
    self.id = MachineID(rawValue: row.id)
    self.gymID = GymID(rawValue: row.gymID)
    self.name = row.name
    self.brand = row.brand
    self.stackIncrementKg = row.stackIncrementKg
  }

  /// "Hammer Strength Leg Press", or just the name when the brand is unknown. The brand is the
  /// whole point of tracking machines separately, so it leads when it exists.
  public var displayName: String {
    brand.isEmpty ? name : "\(brand) \(name)"
  }
}

/// Gyms and their machines.
///
/// This exists because without it the machine-level tracking the app is built around is
/// unreachable: the schema, the progression engine and the chart all key on a machine, but a user
/// with no way to create one logs every set with `machineID == nil` and the whole differentiator
/// is dead code.
public nonisolated struct GymStore {
  private let database: any DatabaseWriter

  public init(database: any DatabaseWriter) {
    self.database = database
  }

  // MARK: - Gyms

  public func gyms() throws -> [GymRecord] {
    try database.read { db in
      try Gym.where { !$0.isArchived }.order { $0.name }.fetchAll(db).map(GymRecord.init(row:))
    }
  }

  @discardableResult
  public func createGym(name: String, now: Date = Date()) throws -> GymID {
    let id = GymID()
    try database.write { db in
      try Gym.insert {
        Gym.Draft(id: id.rawValue, name: name, isArchived: false, createdAt: now)
      }
      .execute(db)
    }
    return id
  }

  /// Archives rather than deletes. Logged sets reference machines at this gym, and a hard delete
  /// would either orphan them or cascade away real training history.
  /// Renames a gym.
  ///
  /// The right fix for a typo, and distinct from archiving. Every session, machine and set is keyed
  /// to the id, so a rename preserves all of it while archiving would strand it.
  public func renameGym(_ id: GymID, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try database.write { db in
      try Gym.where { $0.id.eq(id.rawValue) }.update { $0.name = #bind(trimmed) }.execute(db)
    }
  }

  /// Records the smallest step a stack actually moves in, or clears it.
  ///
  /// `nil` means unknown, and unknown is a real answer: an invented increment would licence
  /// progression suggestions the equipment cannot honour, which is the reason machine creation
  /// leaves it unset. What was missing was any way to supply it afterwards.
  public func setStackIncrement(_ increment: Double?, for machineID: MachineID) throws {
    // A non-positive step is not a step. Stored as unknown rather than as zero, which would make
    // every suggestion land on the same load forever.
    let sanitised = increment.flatMap { $0 > 0 ? $0 : nil }
    try database.write { db in
      try Machine
        .where { $0.id.eq(machineID.rawValue) }
        .update { $0.stackIncrementKg = #bind(sanitised) }
        .execute(db)
    }
  }

  /// Renames a machine.
  ///
  /// Machines are named at the rack, in a hurry, one-handed -- so typos are likely and this is the
  /// repair for them. Load history is keyed to the machine id, so the chart keeps every point and
  /// only the label changes. Archiving a mistyped machine and making a new one would split one
  /// piece of equipment's history into two series, which is precisely what this app refuses to do.
  public func renameMachine(_ id: MachineID, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try database.write { db in
      try Machine.where { $0.id.eq(id.rawValue) }.update { $0.name = #bind(trimmed) }.execute(db)
    }
  }

  public func archiveGym(_ id: GymID) throws {
    try database.write { db in
      try Gym.where { $0.id.eq(id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }
  }

  // MARK: - Machines

  public func machines(at gymID: GymID) throws -> [MachineRecord] {
    try database.read { db in
      try Machine
        .where { $0.gymID.eq(gymID.rawValue) }
        .where { !$0.isArchived }
        .order { $0.name }
        .fetchAll(db)
        .map(MachineRecord.init(row:))
    }
  }

  @discardableResult
  /// - Parameter forExercise: The movement this machine was named for, when there is one.
  ///   Recorded in `machineExercises`, which existed in the schema and was registered for sync
  ///   from the first migration but had **never been written to**. It is what lets the app know a
  ///   gym has equipment for a movement *before* a set has been logged on it -- machines here are
  ///   almost always named from inside an exercise's picker, so the association is free at the
  ///   moment of creation and unrecoverable later without guessing.
  /// Movements this gym is known to have equipment for.
  ///
  /// Two sources, unioned: machines named for a movement (`machineExercises`), and movements
  /// actually logged on a machine at this gym. The second is the stronger signal and the first is
  /// what makes the list useful on a gym's first visit.
  ///
  /// This is relevance, never a prescription. It answers "what can I do here", which the app knows,
  /// and not "what should I do", which it does not.
  public func exercisesWithEquipment(at gymID: GymID) throws -> Set<ExerciseID> {
    try database.read { db in
      let machineIDs = try Machine
        .where { $0.gymID.eq(gymID.rawValue) && !$0.isArchived }
        .fetchAll(db)
        .map(\.id)
      guard !machineIDs.isEmpty else { return [] }

      var result = Set<ExerciseID>()
      for row in try MachineExercise.where({ $0.machineID.in(machineIDs) }).fetchAll(db) {
        result.insert(ExerciseID(rawValue: row.exerciseID))
      }
      // `machineID` is optional on a set, so membership is tested in Swift rather than in the
      // predicate. This runs when the picker opens, not per render, and only over sets that
      // recorded a machine at all.
      let atThisGym = Set(machineIDs)
      for row in try LoggedSet.where({ $0.machineID.isNot(nil) }).fetchAll(db) {
        guard let machine = row.machineID, atThisGym.contains(machine) else { continue }
        result.insert(ExerciseID(rawValue: row.exerciseID))
      }
      return result
    }
  }

  /// Movements logged most recently, newest first, de-duplicated.
  ///
  /// The cheapest useful ordering there is: what someone trains is overwhelmingly what they trained
  /// last week. No modelling, no inference -- just their own history, read back.
  public func recentlyLoggedExercises(limit: Int = 8) throws -> [ExerciseID] {
    try database.read { db in
      let rows = try LoggedSet
        .order { $0.completedAt.desc() }
        .limit(limit * 12)
        .fetchAll(db)
      var seen = Set<UUID>()
      var ordered: [ExerciseID] = []
      for row in rows where !seen.contains(row.exerciseID) {
        seen.insert(row.exerciseID)
        ordered.append(ExerciseID(rawValue: row.exerciseID))
        if ordered.count == limit { break }
      }
      return ordered
    }
  }

  public func createMachine(
    at gymID: GymID,
    name: String,
    brand: String = "",
    stackIncrementKg: Double? = nil,
    forExercise exerciseID: ExerciseID? = nil,
    now: Date = Date()
  ) throws -> MachineID {
    let id = MachineID()
    try database.write { db in
      try Machine.insert {
        Machine.Draft(
          id: id.rawValue, gymID: gymID.rawValue, name: name, brand: brand,
          stackIncrementKg: stackIncrementKg,
          isArchived: false, createdAt: now
        )
      }
      .execute(db)

      if let exerciseID {
        try MachineExercise.insert {
          MachineExercise.Draft(
            id: UUID(), machineID: id.rawValue, exerciseID: exerciseID.rawValue, createdAt: now
          )
        }
        .execute(db)
      }
    }
    return id
  }

  public func archiveMachine(_ id: MachineID) throws {
    try database.write { db in
      try Machine.where { $0.id.eq(id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }
  }

  /// Machines this exercise has actually been performed on at this gym, most recent first.
  ///
  /// This is the list the set row should offer, not every machine in the building. Recency is the
  /// right order because the machine you used last time is overwhelmingly the one you are standing
  /// at now — and it means the common case costs zero thought.
  public func recentMachines(
    for exerciseID: ExerciseID, at gymID: GymID? = nil, limit: Int = 5
  ) throws -> [MachineRecord] {
    try database.read { db in
      let sets = try LoggedSet
        .where { $0.exerciseID.eq(exerciseID.rawValue) }
        .where { $0.machineID.isNot(nil) }
        .order { $0.completedAt.desc() }
        .limit(200)
        .fetchAll(db)

      var seen: [UUID] = []
      for set in sets {
        guard let machineID = set.machineID, !seen.contains(machineID) else { continue }
        seen.append(machineID)
        if seen.count >= limit * 2 { break }
      }
      guard !seen.isEmpty else { return [] }

      let rows = try Machine
        .where { $0.id.in(seen) }
        .where { !$0.isArchived }
        .fetchAll(db)
      let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

      return seen
        .compactMap { byID[$0] }
        .filter { gymID == nil || $0.gymID == gymID?.rawValue }
        .prefix(limit)
        .map(MachineRecord.init(row:))
    }
  }
}

extension GymStore {
  /// The gym of the most recent session that recorded one.
  ///
  /// Used to preselect where the next workout is, because a lifter trains at the same place most
  /// of the time and being asked every session is the kind of friction that makes people stop
  /// recording the machine at all. Learned from what was logged rather than stored as a
  /// preference, so there is no setting to go stale.
  public func lastUsedGym() throws -> GymID? {
    try database.read { db in
      let row = try Session
        .where { $0.gymID.isNot(nil) }
        .order { $0.startedAt.desc() }
        .fetchOne(db)
      guard let raw = row?.gymID else { return nil }
      // Archived gyms are not offered: the equipment list would be empty.
      let live = try Gym.where { $0.id.eq(raw) }.where { !$0.isArchived }.fetchOne(db)
      return live.map { GymID(rawValue: $0.id) }
    }
  }
}
