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
  public func createMachine(
    at gymID: GymID,
    name: String,
    brand: String = "",
    stackIncrementKg: Double? = nil,
    now: Date = Date()
  ) throws -> MachineID {
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
