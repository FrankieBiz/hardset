import Foundation

/// What one movement contributed to a workout, ready to be scored against last time.
public struct ScorecardInput: Hashable, Sendable {
  public let key: ProgressionKey
  public let exerciseName: String
  /// This session's working sets in performed order.
  public let currentSets: [PriorSetRecord]
  /// The most recent earlier session's working sets on this key. Empty means first time.
  public let previousSets: [PriorSetRecord]
  public let repRange: RepRange?
  public let setRecord: Bool
  public let recordKinds: Set<PersonalRecordKind>
  public let estimatesOneRepMax: Bool
  public let assumesAddedLoad: Bool

  public init(
    key: ProgressionKey,
    exerciseName: String,
    currentSets: [PriorSetRecord],
    previousSets: [PriorSetRecord],
    repRange: RepRange? = nil,
    setRecord: Bool = false,
    estimatesOneRepMax: Bool = true,
    assumesAddedLoad: Bool = false,
    recordKinds: Set<PersonalRecordKind> = []
  ) {
    self.key = key
    self.exerciseName = exerciseName
    self.currentSets = currentSets
    self.previousSets = previousSets
    self.repRange = repRange
    self.setRecord = setRecord || !recordKinds.isEmpty
    self.recordKinds = recordKinds
    self.estimatesOneRepMax = estimatesOneRepMax
    self.assumesAddedLoad = assumesAddedLoad
  }
}

/// How a finished workout compares with the last one on the same machines.
///
/// Counted by movement, not by set: five good sets in one movement is one win, and a movement
/// with no previous session on its machine is stated as a first time rather than as progress.
public struct WorkoutScorecard: Hashable, Sendable {
  public let entries: [Entry]
  public let beatenCount: Int
  public let comparedCount: Int
  public let recordMovementCount: Int
  public let biggestGain: Gain?

  public var estimateOnlyRecordMovementCount: Int {
    entries.filter(\.estimateOnlyRecord).count
  }

  public var headline: String {
    guard comparedCount > 0 else { return "First time on every movement" }
    let headline = "Beat last time on \(beatenCount) of \(comparedCount)"
    let estimates = estimateOnlyRecordMovementCount
    guard estimates > 0 else { return headline }
    return headline + " · \(estimates) estimate-only \(estimates == 1 ? "record" : "records")"
  }

  public struct Entry: Hashable, Sendable, Identifiable {
    public let key: ProgressionKey
    public let exerciseName: String
    public let outcome: Outcome
    public let estimateOnlyRecord: Bool
    public var id: ProgressionKey { key }

    public init(key: ProgressionKey, exerciseName: String, outcome: Outcome, estimateOnlyRecord: Bool = false) {
      self.key = key
      self.exerciseName = exerciseName
      self.outcome = outcome
      self.estimateOnlyRecord = estimateOnlyRecord
    }
  }

  public enum Outcome: Hashable, Sendable {
    /// `nil` when the movement set a record but no set beat its partner.
    case beat(SetComparison?)
    case matched
    case notBeaten
    case firstTime
  }

  public struct Gain: Hashable, Sendable {
    public let key: ProgressionKey
    public let exerciseName: String
    /// A fraction, so 0.06 means +6%.
    public let fraction: Double
    public let metric: TrendMetric
    /// How far to trust the figure. An estimated gain is a ratio of two estimates, so it carries the
    /// weaker of their certainties; a gain in the heaviest load is measured, and has none.
    public let certainty: Certainty?
    public let loadAssumption: String?

    public init(
      key: ProgressionKey, exerciseName: String, fraction: Double, metric: TrendMetric,
      certainty: Certainty? = nil, loadAssumption: String? = nil
    ) {
      self.key = key
      self.exerciseName = exerciseName
      self.fraction = fraction
      self.metric = metric
      self.certainty = certainty
      self.loadAssumption = loadAssumption
    }
  }

  public init(
    entries: [Entry],
    beatenCount: Int,
    comparedCount: Int,
    recordMovementCount: Int,
    biggestGain: Gain?
  ) {
    self.entries = entries
    self.beatenCount = beatenCount
    self.comparedCount = comparedCount
    self.recordMovementCount = recordMovementCount
    self.biggestGain = biggestGain
  }

  public static func make(_ inputs: [ScorecardInput]) -> WorkoutScorecard {
    var entries: [Entry] = []
    var beaten = 0
    var compared = 0
    var recordMovements = 0
    var gains: [Gain] = []

    for input in inputs {
      guard !input.currentSets.isEmpty else { continue }
      if input.setRecord { recordMovements += 1 }

      guard !input.previousSets.isEmpty else {
        entries.append(Entry(key: input.key, exerciseName: input.exerciseName, outcome: .firstTime))
        continue
      }
      compared += 1

      var comparisons: [SetComparison] = []
      for index in 0..<min(input.currentSets.count, input.previousSets.count) {
        if let comparison = SetComparison.compare(
          weightKg: input.currentSets[index].weightKg,
          reps: input.currentSets[index].reps,
          against: input.previousSets[index],
          repFloor: input.repRange?.lower
        ) {
          comparisons.append(comparison)
        }
      }

      var beats: [SetComparison] = []
      for comparison in comparisons {
        if case .beat = comparison { beats.append(comparison) }
      }
      let best = beats.max { lhs, rhs in
        guard case let .beat(leftKg, leftReps) = lhs,
          case let .beat(rightKg, rightReps) = rhs
        else { return false }
        return leftKg == rightKg ? leftReps < rightReps : leftKg < rightKg
      }

      let outcome: Outcome
      if best != nil || input.setRecord {
        outcome = .beat(best)
        beaten += 1
      } else if comparisons.contains(.matched) {
        outcome = .matched
      } else {
        outcome = .notBeaten
      }
      entries.append(Entry(key: input.key, exerciseName: input.exerciseName, outcome: outcome,
        estimateOnlyRecord: input.recordKinds == [.estimatedOneRepMax]))

      if let gain = gain(for: input) { gains.append(gain) }
    }

    // Keep added-load ratios in their own comparison group. Preserve the existing ranking of
    // known-load metrics; unknown-load gains are a fallback, grouped by added load or reps.
    let knownGains = gains.filter { $0.loadAssumption == nil }
    let addedMetric: TrendMetric = gains.contains { $0.metric == .addedLoad } ? .addedLoad : .repsAtTopLoad
    let comparableGains = knownGains.isEmpty ? gains.filter { $0.metric == addedMetric } : knownGains
    return WorkoutScorecard(
      entries: entries,
      beatenCount: beaten,
      comparedCount: compared,
      recordMovementCount: recordMovements,
      biggestGain: comparableGains.max { $0.fraction < $1.fraction }
    )
  }

  private static func gain(for input: ScorecardInput) -> Gain? {
    let currentHeaviest = input.currentSets.map(\.weightKg).max() ?? 0
    let previousHeaviest = input.previousSets.map(\.weightKg).max() ?? 0

    let metric: TrendMetric
    let current: Double
    let previous: Double
    var certainty: Certainty?
    if input.estimatesOneRepMax, !input.assumesAddedLoad,
      let currentEstimate = bestEstimate(input.currentSets),
      let previousEstimate = bestEstimate(input.previousSets),
      let currentValue = currentEstimate.value,
      let previousValue = previousEstimate.value,
      previousValue > 0
    {
      metric = .estimatedMax
      current = currentValue
      previous = previousValue
      certainty = Certainty.combine([currentEstimate.certainty, previousEstimate.certainty])
    } else if input.assumesAddedLoad, currentHeaviest == 0, previousHeaviest == 0 {
      metric = .repsAtTopLoad
      current = Double(input.currentSets.map(\.reps).max() ?? 0)
      previous = Double(input.previousSets.map(\.reps).max() ?? 0)
      guard previous > 0 else { return nil }
      certainty = .low
    } else {
      // A load percentage requires a nonzero baseline.
      guard previousHeaviest > 0 else { return nil }
      metric = input.assumesAddedLoad ? .addedLoad : .heaviestLoad
      certainty = input.assumesAddedLoad ? .low : nil
      current = currentHeaviest
      previous = previousHeaviest
    }

    let fraction = current / previous - 1
    guard fraction > 0 else { return nil }
    return Gain(
      key: input.key, exerciseName: input.exerciseName, fraction: fraction, metric: metric,
      certainty: certainty,
      loadAssumption: input.assumesAddedLoad ? ExerciseModality.unknownLoadAssumption : nil
    )
  }

  /// The best estimate among the sets, with its certainty: the figure and the trust in it come from
  /// the same set.
  private static func bestEstimate(_ sets: [PriorSetRecord]) -> Claim<Double>? {
    StrengthMath.bestSupportedEstimate(sets.map {
      StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps)
    })
  }
}
