import Foundation

/// The three distinct things people mean by "PR", kept separate rather than merged into one
/// celebration.
///
/// The reference app compared only estimated one-rep max and fired whenever the new value was
/// `>=` the old, so a repeat of last week's set announced a record. Collapsing three different
/// achievements into one number also means a genuine rep PR at a lighter load reads as nothing.
public enum PersonalRecordKind: String, Sendable, Hashable, CaseIterable, Codable {
  /// The most weight ever moved for at least one rep.
  case heaviestLoad
  /// The most reps ever performed at this exact load.
  case repsAtLoad
  /// The best estimated one-rep max. Only ever claimed when the estimate is evaluable.
  case estimatedOneRepMax

  public var label: String {
    switch self {
    case .heaviestLoad: "Heaviest weight"
    case .repsAtLoad: "Most reps at this weight"
    case .estimatedOneRepMax: "Best estimated 1RM"
    }
  }
}

/// A record the app is willing to announce.
public struct PersonalRecord: Sendable, Hashable, Identifiable {
  public let kind: PersonalRecordKind
  public let weightKg: Double
  public let reps: Int
  /// What was beaten. Stated so the claim is checkable rather than asserted.
  public let previousWeightKg: Double?
  public let previousReps: Int?

  public var id: PersonalRecordKind { kind }

  public init(
    kind: PersonalRecordKind,
    weightKg: Double,
    reps: Int,
    previousWeightKg: Double? = nil,
    previousReps: Int? = nil
  ) {
    self.kind = kind
    self.weightKg = weightKg
    self.reps = reps
    self.previousWeightKg = previousWeightKg
    self.previousReps = previousReps
  }
}

/// Decides whether a completed set beat anything, conservatively.
///
/// Five rules, each of which is a way the reference app announced records that were not records:
///
/// 1. **Never on the first ever set for a lift.** With no history there is nothing to beat, and
///    "PR!" on set one of a new movement is noise that devalues every later one. The stores
///    extend this to the whole first session on a lift: until a working set exists from an
///    earlier session they pass no history, so an ordinary ramp is not a run of records.
/// 2. **A record must beat the old one by a real margin** — the greater of 2.5% and one plate
///    increment (the equipment's own step, or one 5 lb plate when it is unknown). Matching last
///    week is not a record, and `>=` was the ancestor's actual bug.
/// 3. **Warm-ups are never records**, however heavy the warm-up happened to be.
/// 4. **Estimated 1RM records require an evaluable estimate on both sides.** A set of 20 reps
///    produces `.unevaluated`, and an unevaluated value cannot beat anything. Bodyweight work,
///    whose logged load is added load only, has no evaluable estimate at all.
/// 5. **Reps-at-load compares only the same load**, to the nearest 0.01 kg, so 100 × 9 beating
///    100 × 8 is a record and 97.5 × 12 is not compared against it.
public enum PersonalRecordDetector {
  /// Minimum relative improvement before a heavier load counts.
  public static let relativeThreshold = 0.025
  /// Matching tolerance shared with the Store's indexed comparison selection.
  public static let loadMatchingTolerance = 0.01
  /// The plate step assumed when the equipment's own step is unknown: one 5 lb plate, 2.268 kg.
  ///
  /// It is the smaller of the two real plate steps, so both a 2.5 kg and a 5 lb jump count while
  /// sub-plate noise does not. It is unit-neutral on purpose: a receipt's records must not change
  /// when the display unit does.
  public static let defaultIncrementKg = WeightUnit.pounds.toKilograms(WeightUnit.pounds.plateIncrement)

  /// A completed set being tested.
  public struct Candidate: Sendable, Hashable {
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool

    public init(weightKg: Double, reps: Int, isWarmup: Bool = false) {
      self.weightKg = weightKg
      self.reps = reps
      self.isWarmup = isWarmup
    }
  }

  /// Records set by `candidate`, given everything previously logged for that lift.
  ///
  /// - Parameters:
  ///   - history: Every previously completed working set for the same exercise-and-machine.
  ///     Warm-ups should not be included; they are not records and not benchmarks.
  ///     A compact selection is equivalent when it preserves the all-time heaviest
  ///     set, best reps at the candidate load, and best evaluable load at each rep
  ///     count. An arbitrary recent sample cannot justify an all-time claim.
  ///   - increment: The smallest step the equipment actually moves in, so a record on a 5 kg
  ///     stack needs a genuine 5 kg rather than a rounding artefact.
  ///   - estimatesOneRepMax: `false` for movements whose load is not the load moved, such as
  ///     bodyweight work (`ExerciseModality.estimatesOneRepMax`). No estimated-1RM record is
  ///     claimed for them; heaviest-load and reps-at-load records still are.
  public static func records(
    for candidate: Candidate,
    history: [PriorSetRecord],
    increment: Double? = nil,
    estimatesOneRepMax: Bool = true
  ) -> [PersonalRecord] {
    guard !candidate.isWarmup, candidate.weightKg >= 0, candidate.reps > 0 else { return [] }
    // Rule 1: nothing to beat.
    guard !history.isEmpty else { return [] }

    var records: [PersonalRecord] = []
    let step = increment ?? defaultIncrementKg

    // Heaviest load ever lifted for at least one rep.
    if let heaviest = history.map(\.weightKg).max() {
      let margin = max(heaviest * relativeThreshold, step)
      // The tolerance lets a typed 165 lb equal 160 lb plus a 5 lb step, which differ in the
      // last floating-point bit, while sub-plate noise still falls far short.
      if candidate.weightKg + loadMatchingTolerance >= heaviest + margin {
        records.append(
          PersonalRecord(
            kind: .heaviestLoad,
            weightKg: candidate.weightKg,
            reps: candidate.reps,
            previousWeightKg: heaviest
          )
        )
      }
    }

    // Most reps at this exact load.
    let atSameLoad = history.filter { abs($0.weightKg - candidate.weightKg) < loadMatchingTolerance }
    if let bestReps = atSameLoad.map(\.reps).max(), candidate.reps > bestReps {
      records.append(
        PersonalRecord(
          kind: .repsAtLoad,
          weightKg: candidate.weightKg,
          reps: candidate.reps,
          previousWeightKg: candidate.weightKg,
          previousReps: bestReps
        )
      )
    }

    // Best estimated one-rep max — only when both sides are evaluable.
    guard estimatesOneRepMax else { return records }
    let candidateEstimate = StrengthMath.estimatedOneRepMax(
      weightKg: candidate.weightKg, reps: candidate.reps
    )
    if let newEstimate = candidateEstimate.value {
      let previousEstimates = history.compactMap {
        StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps).value
      }
      if let bestPrevious = previousEstimates.max(),
        newEstimate >= bestPrevious * (1 + relativeThreshold)
      {
        records.append(
          PersonalRecord(
            kind: .estimatedOneRepMax,
            weightKg: candidate.weightKg,
            reps: candidate.reps,
            previousWeightKg: bestPrevious
          )
        )
      }
    }

    return records
  }
}
