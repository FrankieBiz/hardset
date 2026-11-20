import Foundation

/// Incremental landmarks for the record detector, never a recent-history cutoff. Each candidate
/// gets the all-time load, its best reps at the same load, the heaviest load at enough reps, and
/// the best evaluable estimate. The detector remains the sole owner of record rules and margins.
struct RecordReplayIndex {
  private let weights: [Double]
  private let repCounts: [Int]
  private let weightPositions: [Double: Int]
  private let repPositions: [Int: Int]
  private var repsAtWeight: MaximumTree
  private var loadAtReps: MaximumTree
  private var heaviest: PriorSetRecord?
  private var bestEstimate: (value: Double, set: PriorSetRecord)?

  init(samples: [ProgressionSample]) {
    weights = Set(samples.map(\.weightKg)).sorted()
    repCounts = Set(samples.map(\.reps)).sorted()
    weightPositions = Dictionary(uniqueKeysWithValues: weights.enumerated().map { ($0.element, $0.offset) })
    repPositions = Dictionary(uniqueKeysWithValues: repCounts.enumerated().map { ($0.element, $0.offset) })
    repsAtWeight = MaximumTree(count: weights.count, metric: .reps)
    loadAtReps = MaximumTree(count: repCounts.count, metric: .load)
  }

  func comparisons(for sample: ProgressionSample) -> [PriorSetRecord] {
    let tolerance = PersonalRecordDetector.loadMatchingTolerance
    // Compare the differences themselves, exactly like the detector's strict abs tolerance;
    // rounded bucket keys would miss loads straddling a bucket boundary.
    let lower = boundary(weights) { $0 - sample.weightKg > -tolerance }
    let upper = boundary(weights) { $0 - sample.weightKg >= tolerance }
    let repStart = boundary(repCounts) { $0 >= sample.reps }
    return [heaviest, repsAtWeight.maximum(in: lower..<upper),
      loadAtReps.maximum(in: repStart..<repCounts.count), bestEstimate?.set].compactMap { $0 }
  }

  mutating func append(_ sample: ProgressionSample) {
    let set = PriorSetRecord(weightKg: sample.weightKg, reps: sample.reps, completedAt: sample.completedAt)
    if sample.weightKg > (heaviest?.weightKg ?? -.infinity) { heaviest = set }
    if let value = StrengthMath.estimatedOneRepMax(weightKg: sample.weightKg, reps: sample.reps).value,
      value > (bestEstimate?.value ?? -.infinity)
    { bestEstimate = (value, set) }
    if let position = weightPositions[sample.weightKg] { repsAtWeight.insert(set, at: position) }
    if let position = repPositions[sample.reps] { loadAtReps.insert(set, at: position) }
  }

  private func boundary<Value>(_ values: [Value], where predicate: (Value) -> Bool) -> Int {
    var lower = 0
    var upper = values.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if predicate(values[middle]) { upper = middle } else { lower = middle + 1 }
    }
    return lower
  }

  /// A range maximum with logarithmic reads and writes, over coordinates fixed before replay.
  /// Storage grows with distinct loads/rep counts, and no set is re-estimated on every later set.
  private struct MaximumTree {
    enum Metric { case reps, load }
    let metric: Metric
    let offset: Int
    var nodes: [PriorSetRecord?]

    init(count: Int, metric: Metric) {
      self.metric = metric
      var size = 1
      while size < count { size *= 2 }
      offset = size
      nodes = Array(repeating: nil, count: size * 2)
    }

    mutating func insert(_ set: PriorSetRecord, at position: Int) {
      var index = offset + position
      nodes[index] = best(nodes[index], set)
      while index > 1 {
        index /= 2
        nodes[index] = best(nodes[index * 2], nodes[index * 2 + 1])
      }
    }

    func maximum(in range: Range<Int>) -> PriorSetRecord? {
      var lower = range.lowerBound + offset
      var upper = range.upperBound + offset
      var result: PriorSetRecord?
      while lower < upper {
        if lower % 2 == 1 { result = best(result, nodes[lower]); lower += 1 }
        if upper % 2 == 1 { upper -= 1; result = best(result, nodes[upper]) }
        lower /= 2
        upper /= 2
      }
      return result
    }

    private func best(_ lhs: PriorSetRecord?, _ rhs: PriorSetRecord?) -> PriorSetRecord? {
      guard let lhs else { return rhs }
      guard let rhs else { return lhs }
      switch metric {
      case .reps: return lhs.reps >= rhs.reps ? lhs : rhs
      case .load:
        return (lhs.weightKg, lhs.reps) >= (rhs.weightKg, rhs.reps) ? lhs : rhs
      }
    }
  }
}
