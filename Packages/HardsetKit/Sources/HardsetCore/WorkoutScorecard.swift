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
  public let estimatesOneRepMax: Bool

  public init(
    key: ProgressionKey,
    exerciseName: String,
    currentSets: [PriorSetRecord],
    previousSets: [PriorSetRecord],
    repRange: RepRange? = nil,
    setRecord: Bool = false,
    estimatesOneRepMax: Bool = true
  ) {
    self.key = key
    self.exerciseName = exerciseName
    self.currentSets = currentSets
    self.previousSets = previousSets
    self.repRange = repRange
    self.setRecord = setRecord
    self.estimatesOneRepMax = estimatesOneRepMax
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

  public var headline: String {
    guard comparedCount > 0 else { return "First time on every movement" }
    return "Beat last time on \(beatenCount) of \(comparedCount)"
  }

  public struct Entry: Hashable, Sendable, Identifiable {
    public let key: ProgressionKey
    public let exerciseName: String
    public let outcome: Outcome
    public var id: ProgressionKey { key }

    public init(key: ProgressionKey, exerciseName: String, outcome: Outcome) {
      self.key = key
      self.exerciseName = exerciseName
      self.outcome = outcome
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

    public init(
      key: ProgressionKey, exerciseName: String, fraction: Double, metric: TrendMetric,
      certainty: Certainty? = nil
    ) {
      self.key = key
      self.exerciseName = exerciseName
      self.fraction = fraction
      self.metric = metric
      self.certainty = certainty
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
    var biggestGain: Gain?

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
      entries.append(Entry(key: input.key, exerciseName: input.exerciseName, outcome: outcome))

      if let gain = gain(for: input),
        biggestGain == nil || gain.fraction > biggestGain!.fraction
      {
        biggestGain = gain
      }
    }

    return WorkoutScorecard(
      entries: entries,
      beatenCount: beaten,
      comparedCount: compared,
      recordMovementCount: recordMovements,
      biggestGain: biggestGain
    )
  }

  private static func gain(for input: ScorecardInput) -> Gain? {
    let currentHeaviest = input.currentSets.map(\.weightKg).max() ?? 0
    let previousHeaviest = input.previousSets.map(\.weightKg).max() ?? 0

    let metric: TrendMetric
    let current: Double
    let previous: Double
    var certainty: Certainty?
    if input.estimatesOneRepMax,
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
    } else {
      // A bodyweight movement has no heaviest load to compare.
      guard previousHeaviest > 0 else { return nil }
      metric = .heaviestLoad
      current = currentHeaviest
      previous = previousHeaviest
    }

    let fraction = current / previous - 1
    guard fraction > 0 else { return nil }
    return Gain(
      key: input.key, exerciseName: input.exerciseName, fraction: fraction, metric: metric,
      certainty: certainty
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
