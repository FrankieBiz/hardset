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
public nonisolated struct GymStore: Sendable {
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
  public func archiveGym(_ id: GymID) throws {
    try database.write { db in
      try Gym.where { $0.id.eq(id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }
  }

  /// Corrects a live gym's name in place. The identity is unchanged, so every session and set
  /// that names this gym follows the new name.
  public func renameGym(_ id: GymID, to name: String) throws {
    let trimmed = try Self.validName(name)
    try database.write { db in
      try Gym.where { $0.id.eq(id.rawValue) && !$0.isArchived }
        .update { $0.name = #bind(trimmed) }.execute(db)
      guard db.changesCount == 1 else { throw EquipmentNameError.unavailable }
    }
  }

  private static func validName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw EquipmentNameError.blank }
    return trimmed
  }

  /// Every live gym with its live machines, by name, from one read. For managing what was
  /// added, not for choosing: the pickers stay recency-first.
  public func inventory() async throws -> [GymInventory] {
    try Task.checkCancellation()
    return try await database.read { db in
      let gyms = try Gym.where { !$0.isArchived }.order { ($0.name, $0.id) }.fetchAll(db)
      let machines = try Machine.where { !$0.isArchived }.order { ($0.name, $0.brand, $0.id) }.fetchAll(db)
      let byGym = Dictionary(grouping: machines, by: \.gymID)
      return gyms.map { gym in
        GymInventory(gym: GymRecord(row: gym), machines: (byGym[gym.id] ?? []).map(MachineRecord.init(row:)))
      }
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
  public func createMachine(
    at gymID: GymID,
    name: String,
    brand: String = "",
    stackIncrementKg: Double? = nil,
    now: Date = Date()
  ) throws -> MachineID {
    try Self.validateIncrement(stackIncrementKg)
    let id = MachineID()
    try database.write { db in
      try Machine.insert {
        Machine.Draft(
          id: id.rawValue, gymID: gymID.rawValue, name: name, brand: brand,
          loadType: "unknown", stackIncrementKg: stackIncrementKg,
          isArchived: false, createdAt: now
        )
      }
      .execute(db)
    }
    return id
  }

  /// Validate and persist before any logger state adopts the equipment constraint.
  public func setStackIncrement(_ incrementKg: Double?, for id: MachineID, at gymID: GymID) throws {
    try Self.validateIncrement(incrementKg)
    try database.write { db in
      try Machine.where { $0.id.eq(id.rawValue) && $0.gymID.eq(gymID.rawValue) && !$0.isArchived }
        .update { $0.stackIncrementKg = #bind(incrementKg) }.execute(db)
      guard db.changesCount == 1 else { throw MachineProfileError.machineUnavailable }
    }
  }

  private static func validateIncrement(_ increment: Double?) throws {
    if let increment, !increment.isFinite || increment <= 0 { throw MachineProfileError.invalidIncrement }
  }

  public func archiveMachine(_ id: MachineID) throws {
    try database.write { db in
      try Machine.where { $0.id.eq(id.rawValue) }.update { $0.isArchived = #bind(true) }.execute(db)
    }
  }

  /// Corrects a live machine's name and brand in place. A blank brand is allowed, since many
  /// machines have none; a blank name is not.
  public func renameMachine(_ id: MachineID, name: String, brand: String) throws {
    let trimmedName = try Self.validName(name)
    let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
    try database.write { db in
      try Machine.where { $0.id.eq(id.rawValue) && !$0.isArchived }
        .update {
          $0.name = #bind(trimmedName)
          $0.brand = #bind(trimmedBrand)
        }
        .execute(db)
      guard db.changesCount == 1 else { throw EquipmentNameError.unavailable }
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
  public nonisolated func lastUsedGym() throws -> GymID? {
    try database.read { db in
      try Self.readLastUsedGym(in: db)
    }
  }

  /// Options and preselection from one database snapshot.
  public nonisolated func selection() throws -> GymSelection {
    try database.read { db in try Self.readSelection(in: db) }
  }

  public nonisolated func loadSelection() async throws -> GymSelection {
    try Task.checkCancellation()
    return try await database.read { db in try Self.readSelection(in: db) }
  }

  private nonisolated static func readSelection(in db: Database) throws -> GymSelection {
    let options = try Gym.where { !$0.isArchived }.order { $0.name }.fetchAll(db).map(GymRecord.init(row:))
    return GymSelection(options: options, lastUsed: try readLastUsedGym(in: db))
  }

  private nonisolated static func readLastUsedGym(in db: Database) throws -> GymID? {
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

public nonisolated struct GymSelection: Hashable, Sendable {
  public let options: [GymRecord]
  public let lastUsed: GymID?
}

public nonisolated enum MachineProfileError: Error, Equatable, Sendable {
  case invalidIncrement, machineUnavailable
}

/// A live gym and the live machines added at it.
public nonisolated struct GymInventory: Hashable, Sendable, Identifiable {
  public let gym: GymRecord
  public let machines: [MachineRecord]
  public var id: GymID { gym.id }
}

/// Why a gym or machine could not be renamed.
public nonisolated enum EquipmentNameError: Error, Equatable, Sendable {
  /// The name was empty once spaces were trimmed.
  case blank
  /// No live gym or machine has this identity: it was archived, or never existed.
  case unavailable
}
