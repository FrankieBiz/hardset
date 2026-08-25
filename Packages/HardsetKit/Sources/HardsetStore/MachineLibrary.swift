import Foundation
import HardsetCore
import SQLiteData

/// One machine, with everything a review screen needs to say about it.
///
/// A read model, assembled in one pass rather than by a screen asking four questions per row. The
/// ancestor app rendered a list and resolved each row's detail lazily, which is how a list of
/// twenty machines becomes eighty queries.
public nonisolated struct MachineLibraryEntry: Hashable, Sendable, Identifiable {
  public let id: MachineID
  public let name: String
  /// The smallest step this stack actually moves in, when the lifter has said. `nil` is not a
  /// missing value to fill in with a guess: an invented increment licences progression advice the
  /// equipment cannot honour.
  public let stackIncrementKg: Double?
  public let isArchived: Bool
  /// Movements this machine is recorded as the equipment for, by name, alphabetically.
  public let linkedExerciseNames: [String]
  /// When a set was last logged on it. `nil` for a machine named but never used — which is a real
  /// state worth showing, not an error.
  public let lastUsed: Date?
  /// The heaviest working set ever logged on it, and the reps at that load.
  ///
  /// Warm-ups and drops are excluded, the same exclusion the progression chart makes: neither is a
  /// heaviest load, and a drop set's reduced weight is not a lighter attempt at the same thing.
  public let heaviestKg: Double?
  public let heaviestReps: Int?
  public let workingSetCount: Int

  public init(
    id: MachineID,
    name: String,
    stackIncrementKg: Double?,
    isArchived: Bool,
    linkedExerciseNames: [String],
    lastUsed: Date?,
    heaviestKg: Double?,
    heaviestReps: Int?,
    workingSetCount: Int
  ) {
    self.id = id
    self.name = name
    self.stackIncrementKg = stackIncrementKg
    self.isArchived = isArchived
    self.linkedExerciseNames = linkedExerciseNames
    self.lastUsed = lastUsed
    self.heaviestKg = heaviestKg
    self.heaviestReps = heaviestReps
    self.workingSetCount = workingSetCount
  }

  /// A machine that has never been trained on. Named at the rack and then never used, or created
  /// by a typo — the two cases the library exists to let a lifter find and tidy.
  public var isUnused: Bool { workingSetCount == 0 && lastUsed == nil }
}

/// The heaviest working set on one machine.
///
/// A named struct rather than a `(kg: Double, reps: Int)` tuple in a dictionary, so the tie-break
/// rule has somewhere to live and gets read as a rule rather than as a comparison inlined twice.
///
/// `nonisolated` is load-bearing, not decoration: this module defaults declarations to `@MainActor`
/// (see the note on `machineLibrary`), and without it `beats` is main-actor-isolated -- which the
/// compiler will tell you about only once the surrounding extension is itself `nonisolated`.
private nonisolated struct BestSet {
  let kg: Double
  let reps: Int

  /// Ties on load break on reps: the same weight for more reps is the better set, and reporting
  /// the first-seen one would make the figure depend on row order.
  func beats(_ other: BestSet) -> Bool {
    kg > other.kg || (kg == other.kg && reps > other.reps)
  }
}

nonisolated extension GymStore {
  /// Every machine at a gym, with its detail, for the review screen.
  ///
  /// # Why archived machines are included
  ///
  /// Archiving is reversible here and deleting is impossible: sets logged against a machine keep
  /// their reference, and invariant #10 forbids merging two machines' history, so a hard delete
  /// would orphan a real series. A library that hid archived rows would make archiving a one-way
  /// door with no undo -- which is exactly how a mistyped duplicate becomes permanent.
  ///
  /// # Everything in this file must say `nonisolated`
  ///
  /// `HardsetStore` is built with `.defaultIsolation(MainActor.self)`, so **any declaration here
  /// that omits `nonisolated` silently becomes `@MainActor`** -- which is why every store type in
  /// this module spells it out. An extension that forgets it compiles without a word of complaint
  /// and then traps at run time the moment one of its closures runs off the main actor: SIGTRAP,
  /// no message, apparently *on entry to the function* so nothing logged inside it ever prints and
  /// the failure reads as if the call site were at fault.
  ///
  /// It cost hours here. `filter`, `sorted` and any other closure handed to the stdlib are the
  /// triggers; `map(\.someKeyPath)` and plain `for` loops are not, because a key path carries no
  /// isolation and a loop body is not a closure. Rewriting the closures as loops made the symptom
  /// go away while leaving the real defect -- a store that claims to be callable from any context
  /// and is not -- fully in place.
  ///
  /// - Parameter includeArchived: `false` gives the same set `machines(at:)` does.
  public func machineLibrary(
    at gymID: GymID,
    includeArchived: Bool = true
  ) throws -> [MachineLibraryEntry] {
    let allMachines: [Machine] = try database.read { db in
      try Machine.where { $0.gymID.eq(gymID.rawValue) }.order { $0.name }.fetchAll(db)
    }
    let machines = allMachines.filter { includeArchived || !$0.isArchived }
    guard !machines.isEmpty else { return [] }
    let ids = machines.map(\.id)

    let links: [MachineExercise] = try database.read { db in
      try MachineExercise.where { $0.machineID.in(ids) }.fetchAll(db)
    }
    var exerciseIDsByMachine: [UUID: [UUID]] = [:]
    for link in links {
      exerciseIDsByMachine[link.machineID, default: []].append(link.exerciseID)
    }

    var linkedExerciseIDs: Set<UUID> = []
    for list in exerciseIDsByMachine.values {
      for id in list { linkedExerciseIDs.insert(id) }
    }
    var namesByExercise: [UUID: String] = [:]
    if !linkedExerciseIDs.isEmpty {
      let wanted = Array(linkedExerciseIDs)
      let named: [Exercise] = try database.read { db in
        try Exercise.where { $0.id.in(wanted) }.fetchAll(db)
      }
      for row in named { namesByExercise[row.id] = row.name }
    }

    // One pass over every set that recorded a machine. `machineID` is optional, so membership is
    // tested in Swift rather than in the predicate -- the same reason `exercisesWithEquipment`
    // does it this way.
    let sets: [LoggedSet] = try database.read { db in
      try LoggedSet.where { $0.machineID.isNot(nil) }.fetchAll(db)
    }

    let owned = Set(ids)
    var lastUsed: [UUID: Date] = [:]
    var heaviest: [UUID: BestSet] = [:]
    var counts: [UUID: Int] = [:]

    for set in sets {
      guard let machineID = set.machineID, owned.contains(machineID) else { continue }
      // `lastUsed` counts any set, warm-up included: the question it answers is "when was I last
      // at this machine", and a warm-up means you were there.
      if set.completedAt > (lastUsed[machineID] ?? .distantPast) {
        lastUsed[machineID] = set.completedAt
      }
      guard !set.isWarmup, !set.isDropSet else { continue }
      counts[machineID, default: 0] += 1
      let candidate = BestSet(kg: set.weightKg, reps: set.reps)
      if let best = heaviest[machineID] {
        if candidate.beats(best) { heaviest[machineID] = candidate }
      } else {
        heaviest[machineID] = candidate
      }
    }

    var entries: [MachineLibraryEntry] = []
    for machine in machines {
      var linkedNames: [String] = []
      for exerciseID in exerciseIDsByMachine[machine.id] ?? [] {
        if let name = namesByExercise[exerciseID] { linkedNames.append(name) }
      }
      entries.append(
        MachineLibraryEntry(
          id: MachineID(rawValue: machine.id),
          name: machine.name,
          stackIncrementKg: machine.stackIncrementKg,
          isArchived: machine.isArchived,
          linkedExerciseNames: linkedNames.sorted(),
          lastUsed: lastUsed[machine.id],
          heaviestKg: heaviest[machine.id]?.kg,
          heaviestReps: heaviest[machine.id]?.reps,
          workingSetCount: counts[machine.id] ?? 0
        )
      )
    }
    return entries
  }

  /// Puts a machine away, or brings it back.
  ///
  /// The counterpart `archiveMachine` never had. Without it, archiving from a review screen is a
  /// one-way door: a lifter who archives the wrong row cannot restore it, and because invariant #10
  /// forbids merging machines there is no second path to the history that row owns. The audit that
  /// preceded this feature named the missing unarchive as the reason a mistyped duplicate is
  /// permanent, and it was right.
  public func setMachineArchived(_ archived: Bool, for id: MachineID) throws {
    try database.write { db in
      try Machine
        .where { $0.id.eq(id.rawValue) }
        .update { $0.isArchived = #bind(archived) }
        .execute(db)
    }
  }
}

/// A machine name the lifter has used before, offered when naming a new one.
///
/// Carries *where* the name is already in use, because that decides what selecting it means and
/// what has to be said about it. A name already at this gym must select that machine; a name from
/// another gym must create a new one, and must say so.
public nonisolated struct MachineNameSuggestion: Hashable, Sendable, Identifiable {
  public let name: String
  /// The machine at **this** gym already carrying this name, when there is one.
  ///
  /// Non-nil means selecting this suggestion must resolve to that machine rather than insert a
  /// second row. Minting a second `MachineID` for one physical machine is unrecoverable: invariant
  /// #10 forbids merging two machines' history, so the sets would be split across two series
  /// forever with no way to rejoin them.
  public let existingHere: MachineID?
  /// Other gyms where a machine of this name exists, for the disclosure line.
  public let otherGymNames: [String]

  public var id: String { name }

  public init(name: String, existingHere: MachineID?, otherGymNames: [String]) {
    self.name = name
    self.existingHere = existingHere
    self.otherGymNames = otherGymNames
  }
}

nonisolated extension GymStore {
  /// Compares machine names the way a lifter means them: case- and spacing-insensitively.
  ///
  /// "hammer  leg press" and "Hammer Leg Press" are one machine to the person standing at it, and
  /// treating them as two is how a typo becomes a permanent second history.
  static func normalized(_ name: String) -> String {
    name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
  }

  /// A machine already at this gym under this name, if there is one.
  ///
  /// The partition is the whole point. Matching across gyms would be the merge invariant #10
  /// forbids; matching *within* one gym is the opposite -- it stops a second row being created for
  /// a machine that is already there.
  public func existingMachine(named name: String, at gymID: GymID) throws -> MachineID? {
    let wanted = Self.normalized(name)
    guard !wanted.isEmpty else { return nil }
    let rows: [Machine] = try database.read { db in
      try Machine.where { $0.gymID.eq(gymID.rawValue) }.fetchAll(db)
    }
    for row in rows where !row.isArchived && Self.normalized(row.name) == wanted {
      return MachineID(rawValue: row.id)
    }
    return nil
  }

  /// Every machine name the lifter has used anywhere, for autocomplete.
  ///
  /// Offered because the alternative is retyping "Hammer Strength Iso-Lateral Row" at the second
  /// gym and getting it slightly wrong, which silently creates a third machine with a third empty
  /// history. Ordered with the names already at this gym first, since selecting one of those is
  /// the only case that resolves rather than creates.
  public func machineNameSuggestions(at gymID: GymID) throws -> [MachineNameSuggestion] {
    // Ordered in SQL so the suggestion list has a stable base before it is partitioned below.
    let machines: [Machine] = try database.read { db in
      try Machine.order { $0.name }.fetchAll(db)
    }
    let gyms: [Gym] = try database.read { db in
      try Gym.order { $0.name }.fetchAll(db)
    }
    var gymNames: [UUID: String] = [:]
    for gym in gyms { gymNames[gym.id] = gym.name }

    var here: [String: MachineID] = [:]
    var elsewhere: [String: [String]] = [:]
    var display: [String: String] = [:]

    for machine in machines where !machine.isArchived {
      let key = Self.normalized(machine.name)
      guard !key.isEmpty else { continue }
      // First spelling seen wins as the label, so the offered text is one the lifter actually
      // typed rather than a normalised reconstruction of it.
      if display[key] == nil { display[key] = machine.name }
      if machine.gymID == gymID.rawValue {
        if here[key] == nil { here[key] = MachineID(rawValue: machine.id) }
      } else if let gymName = gymNames[machine.gymID] {
        if !(elsewhere[key] ?? []).contains(gymName) {
          elsewhere[key, default: []].append(gymName)
        }
      }
    }

    var suggestions: [MachineNameSuggestion] = []
    for (key, name) in display {
      suggestions.append(
        MachineNameSuggestion(
          name: name,
          existingHere: here[key],
          otherGymNames: (elsewhere[key] ?? []).sorted()
        )
      )
    }
    // Names already here first, then alphabetically. Deterministic, because a dictionary's order
    // is not, and a suggestion list that reshuffles between presentations is unusable.
    return suggestions.sorted { lhs, rhs in
      let lhsIsHere = lhs.existingHere != nil
      let rhsIsHere = rhs.existingHere != nil
      if lhsIsHere != rhsIsHere { return lhsIsHere }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  /// Resolves a typed machine name to a machine at this gym, creating one only if needed.
  ///
  /// The safe replacement for calling `createMachine` straight from a name field. Autocomplete
  /// makes a collision *likely* rather than rare -- the lifter is being shown names to pick -- and
  /// an unconditional insert would answer "that one" with a brand-new machine holding no history.
  ///
  /// Never matches across gyms. Two Nautilus chest presses in two buildings are two machines with
  /// two histories, which is invariant #10 and is not negotiable.
  ///
  /// - Returns: the machine, and whether it had to be created.
  @discardableResult
  public func resolveMachine(
    at gymID: GymID,
    named name: String,
    stackIncrementKg: Double? = nil,
    forExercise exerciseID: ExerciseID? = nil,
    now: Date = Date()
  ) throws -> (id: MachineID, created: Bool) {
    if let existing = try existingMachine(named: name, at: gymID) {
      // Still record what it is equipment for. The association is free at this moment and
      // unrecoverable later, and `linkMachine` is idempotent.
      if let exerciseID {
        try linkMachine(existing, toExercise: exerciseID, now: now)
      }
      return (existing, false)
    }
    let created = try createMachine(
      at: gymID,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      stackIncrementKg: stackIncrementKg,
      forExercise: exerciseID,
      now: now
    )
    return (created, true)
  }
}
