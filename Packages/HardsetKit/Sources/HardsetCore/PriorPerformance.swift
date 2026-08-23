import Foundation

/// A set the user completed previously, as loaded once at session start.
public struct PriorSetRecord: Hashable, Sendable, Codable {
  public let weightKg: Double
  public let reps: Int
  public let completedAt: Date

  public init(weightKg: Double, reps: Int, completedAt: Date) {
    self.weightKg = weightKg
    self.reps = reps
    self.completedAt = completedAt
  }
}

/// Everything the logger needs to know about one exercise-on-one-machine's history.
public struct PriorPerformance: Hashable, Sendable, Codable {
  public let key: ProgressionKey
  /// Most recent session's sets, in performed order.
  public let lastSets: [PriorSetRecord]
  public let heaviestSet: PriorSetRecord?

  public init(key: ProgressionKey, lastSets: [PriorSetRecord], heaviestSet: PriorSetRecord?) {
    self.key = key
    self.lastSets = lastSets
    self.heaviestSet = heaviestSet
  }

  /// What to pre-fill the nth set row with, as a real value.
  public func suggestion(forSetIndex index: Int) -> PriorSetRecord? {
    if lastSets.indices.contains(index) { return lastSets[index] }
    return lastSets.last
  }
}

/// Invariant: the logger performs zero database work per render.
///
/// Prior performance for every exercise in the session is read once, up front, into this
/// immutable value. The reference app instead ran an unbounded `FetchDescriptor` inside a
/// `ForEach` body, issuing roughly thirty queries a second while the user scrolled.
///
/// Being a `Sendable` value type with no database handle, it is structurally incapable of
/// querying anything -- the mistake cannot recur without changing this type.
public struct PriorPerformanceSnapshot: Hashable, Sendable {
  private let byKey: [ProgressionKey: PriorPerformance]
  /// When the snapshot was taken, so staleness is visible rather than assumed.
  public let capturedAt: Date

  public init(entries: [ProgressionKey: PriorPerformance], capturedAt: Date) {
    self.byKey = entries
    self.capturedAt = capturedAt
  }

  public static func empty(capturedAt: Date) -> PriorPerformanceSnapshot {
    PriorPerformanceSnapshot(entries: [:], capturedAt: capturedAt)
  }

  public func prior(for key: ProgressionKey) -> PriorPerformance? { byKey[key] }

  /// Falls back to the same exercise on a different machine, flagged as an assumption so
  /// the UI can say the number came from other equipment.
  public func priorAllowingOtherMachines(
    for key: ProgressionKey
  ) -> (performance: PriorPerformance, wasOtherMachine: Bool)? {
    if let exact = byKey[key] { return (exact, false) }
    guard key.machineID != nil else { return nil }
    let sameExercise = byKey.values
      .filter { $0.key.exerciseID == key.exerciseID }
      .sorted { ($0.heaviestSet?.completedAt ?? .distantPast) > ($1.heaviestSet?.completedAt ?? .distantPast) }
    guard let nearest = sameExercise.first else { return nil }
    return (nearest, true)
  }

  public var count: Int { byKey.count }
}

/// A set row being filled in.
///
/// `weightKg` and `reps` are optional and start non-nil only when a real suggestion was
/// applied. The reference app showed the previous set's numbers as `TextField`
/// *placeholder* text, which looks identical to a filled field but reads back as empty --
/// so an untouched row logged 0 kg and silently zeroed the session's volume. Here an
/// untouched row is not loggable at all.
public struct SetEntryDraft: Hashable, Sendable {
  public var weightKg: Double?
  public var reps: Int?
  /// How hard the set was, on the 1-10 RPE scale, when the lifter chose to record it.
  ///
  /// Optional and **never required to log**: a set with no RPE is a complete set. The column has
  /// existed since the first migration and nothing ever wrote to it, which for an app aimed at
  /// people who read the training literature is a strange omission -- proximity to failure is the
  /// variable they actually manipulate.
  ///
  /// The app records it and does not prescribe it. There is no target RPE, no warning for being
  /// too far from failure, and no inference drawn from it, because none of that is established.
  public var rpe: Double?
  /// What history suggested, retained so the UI can show "same as last time" affordances.
  public let suggestion: PriorSetRecord?

  /// Seeds the draft with the suggestion as an actual value, not a placeholder.
  public init(suggestion: PriorSetRecord?) {
    self.suggestion = suggestion
    self.weightKg = suggestion?.weightKg
    self.reps = suggestion?.reps
    // Deliberately not carried forward from history. Last week's effort is not this week's, and
    // prefilling it would put a number the lifter did not feel into their own record.
    self.rpe = nil
  }

  public init(
    weightKg: Double?, reps: Int?, rpe: Double? = nil, suggestion: PriorSetRecord? = nil
  ) {
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.suggestion = suggestion
  }

  /// True only when both fields hold a real, usable value. Bind the log control's
  /// enabled state to this so an untouched row can never be written.
  ///
  /// RPE is not part of this. Requiring it would make an optional field mandatory by the back door.
  public var isLoggable: Bool { resolved() != nil }

  /// A recorded RPE, if it is one the scale actually has.
  ///
  /// Clamped rather than trusted: the scale runs 1 to 10 in half points, and a value outside that
  /// is an input error rather than a very hard set.
  public var validatedRPE: Double? {
    guard let rpe, rpe >= 1, rpe <= 10 else { return nil }
    return (rpe * 2).rounded() / 2
  }

  /// The values to persist, or `nil` if this row is not complete.
  /// Zero reps is not a logged set, and negative load is not a load.
  public func resolved() -> (weightKg: Double, reps: Int)? {
    guard let weightKg, let reps, reps > 0, weightKg >= 0 else { return nil }
    return (weightKg, reps)
  }
}
