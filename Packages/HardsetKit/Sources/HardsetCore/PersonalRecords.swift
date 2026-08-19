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
///    "PR!" on set one of a new movement is noise that devalues every later one.
/// 2. **A record must beat the old one by a real margin** — the greater of 2.5% and one plate
///    increment. Matching last week is not a record, and `>=` was the ancestor's actual bug.
/// 3. **Warm-ups are never records**, however heavy the warm-up happened to be.
/// 4. **Estimated 1RM records require an evaluable estimate on both sides.** A set of 20 reps
///    produces `.unevaluated`, and an unevaluated value cannot beat anything.
/// 5. **Reps-at-load compares only the same load**, to the nearest 0.01 kg, so 100 × 9 beating
///    100 × 8 is a record and 97.5 × 12 is not compared against it.
public enum PersonalRecordDetector {
  /// Minimum relative improvement before a heavier load counts.
  public static let relativeThreshold = 0.025

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
  ///   - increment: The smallest step the equipment actually moves in, so a record on a 5 kg
  ///     stack needs a genuine 5 kg rather than a rounding artefact.
  public static func records(
    for candidate: Candidate,
    history: [PriorSetRecord],
    increment: Double? = nil
  ) -> [PersonalRecord] {
    guard !candidate.isWarmup, candidate.weightKg >= 0, candidate.reps > 0 else { return [] }
    // Rule 1: nothing to beat.
    guard !history.isEmpty else { return [] }

    var records: [PersonalRecord] = []
    let step = increment ?? WeightUnit.kilograms.plateIncrement

    // Heaviest load ever lifted for at least one rep.
    if let heaviest = history.map(\.weightKg).max() {
      let margin = max(heaviest * relativeThreshold, step)
      if candidate.weightKg >= heaviest + margin {
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
    let atSameLoad = history.filter { abs($0.weightKg - candidate.weightKg) < 0.01 }
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
