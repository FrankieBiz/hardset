import Foundation

/// What a movement's trend line plots.
public enum TrendMetric: String, Hashable, Sendable {
  /// The best evaluable Epley estimate in each session.
  case estimatedMax
  /// The heaviest load in each session, used when no estimate is possible.
  case heaviestLoad
  /// The most reps at the session's heaviest load, used for bodyweight work.
  case repsAtTopLoad
}

/// One movement-on-one-machine's recent trajectory.
public struct MovementTrend: Hashable, Sendable, Identifiable {
  public let key: ProgressionKey
  public let metric: TrendMetric
  /// Oldest first, at most twelve values, in kilograms or reps according to `metric`.
  public let sparkline: [Double]
  /// A fraction, so 0.08 means +8%. Nil when the six-week window has no session.
  public let sixWeekChange: Double?
  public let sessionCount: Int
  /// Non-nil means the movement is stalled: none of its last `ProgressTrendAnalyzer.stallRun`
  /// sessions set a record, and the number is that count. It is never a longer run, because only
  /// those sessions are checked.
  public let stalledSessions: Int?
  public let latestDate: Date
  /// How far to trust the latest estimate, from the reps behind it, so the figure and its badge can
  /// sit together. Only an estimate has one: nil for a heaviest-load or bodyweight trend.
  public let certainty: Certainty?

  public var id: ProgressionKey { key }

  public init(
    key: ProgressionKey,
    metric: TrendMetric,
    sparkline: [Double],
    sixWeekChange: Double?,
    sessionCount: Int,
    stalledSessions: Int?,
    latestDate: Date,
    certainty: Certainty? = nil
  ) {
    self.key = key
    self.metric = metric
    self.sparkline = sparkline
    self.sixWeekChange = sixWeekChange
    self.sessionCount = sessionCount
    self.stalledSessions = stalledSessions
    self.latestDate = latestDate
    self.certainty = certainty
  }
}

/// Builds movement trends, the sessions that set records, and the stalled flag.
public enum ProgressTrendAnalyzer {
  public static let stallRun = 3
  public static let minimumSessionsForStall = 4

  private static let day: TimeInterval = 86_400

  /// Nil when there are no samples.
  public static func trend(
    key: ProgressionKey,
    samples: [ProgressionSample],
    incrementKg: Double?,
    estimatesOneRepMax: Bool
  ) -> MovementTrend? {
    let sessions = sessions(from: samples)
    guard let latestSession = sessions.last else { return nil }

    let metric: TrendMetric
    if !estimatesOneRepMax {
      metric = .repsAtTopLoad
    } else if bestEstimate(in: latestSession.samples) != nil {
      metric = .estimatedMax
    } else {
      metric = .heaviestLoad
    }

    let points: [(date: Date, value: Double, topLoad: Double)] = sessions.compactMap { session in
      guard let value = value(of: metric, in: session.samples) else { return nil }
      return (session.date, value, session.samples.map(\.weightKg).max() ?? 0)
    }
    guard let latest = points.last else { return nil }

    let change: Double?
    let windowStart = latestSession.date.addingTimeInterval(-49 * day)
    let windowEnd = latestSession.date.addingTimeInterval(-35 * day)
    let base = points
      .filter { $0.date >= windowStart && $0.date <= windowEnd }
      // Reps at the top load are only a fair comparison at the same top load: ten bodyweight
      // pull-ups against five with 20 kg added is not an improvement of 100%, it is a different
      // exercise's number. Other metrics are loads or estimates, which compare across sessions.
      .filter {
        metric != .repsAtTopLoad
          || abs($0.topLoad - latest.topLoad) < PersonalRecordDetector.loadMatchingTolerance
      }
      .map(\.value)
      .max()
    if let base, base > 0 {
      change = latest.value / base - 1
    } else {
      change = nil
    }

    // Only the last `stallRun` sessions decide a stall, so only they are replayed through the
    // detector, each set against everything before it. Replaying the whole history made opening
    // the progress board grow with the square of a movement's set count.
    var stalled: Int?
    if sessions.count >= minimumSessionsForStall {
      let recordSessions = recordSessionIDs(
        samples: samples,
        incrementKg: incrementKg,
        estimatesOneRepMax: estimatesOneRepMax,
        lastSessions: stallRun
      )
      let setARecord = sessions.suffix(stallRun).contains { recordSessions.contains($0.id) }
      stalled = setARecord ? nil : stallRun
    }

    return MovementTrend(
      key: key,
      metric: metric,
      sparkline: Array(points.suffix(12)).map(\.value),
      sixWeekChange: change,
      sessionCount: sessions.count,
      stalledSessions: stalled,
      latestDate: latestSession.date,
      certainty: metric == .estimatedMax ? bestEstimateClaim(in: latestSession.samples)?.certainty : nil
    )
  }

  /// The sessions that set at least one record, with history always including every earlier set.
  ///
  /// The first session only builds history: with nothing before it, an ordinary ramp would look
  /// like a run of records. `lastSessions` limits which sessions are tested, not what they are
  /// tested against.
  ///
  /// Incremental all-time landmarks preserve every comparison the detector needs, so every
  /// record mark can be replayed without rescanning or re-estimating the whole history per set.
  /// `lastSessions` still bounds the stall check's work without truncating its benchmarks.
  public static func recordSessionIDs(
    samples: [ProgressionSample],
    incrementKg: Double?,
    estimatesOneRepMax: Bool,
    lastSessions: Int? = nil
  ) -> Set<SessionID> {
    let sessions = sessions(from: samples)
    guard sessions.count > 1 else { return [] }

    var records = Set<SessionID>()
    var history = RecordReplayIndex(samples: samples)
    let firstTested = max(1, sessions.count - (lastSessions ?? sessions.count))

    for (index, session) in sessions.enumerated() {
      for sample in session.samples.sorted(by: { $0.completedAt < $1.completedAt }) {
        if index >= firstTested {
          let found = PersonalRecordDetector.records(
            for: .init(weightKg: sample.weightKg, reps: sample.reps),
            history: history.comparisons(for: sample),
            increment: incrementKg,
            estimatesOneRepMax: estimatesOneRepMax
          )
          if !found.isEmpty { records.insert(session.id) }
        }
        history.append(sample)
      }
    }
    return records
  }

  /// The three largest positive six-week gains, largest first.
  public static func mostImproved(_ trends: [MovementTrend], limit: Int = 3) -> [MovementTrend] {
    trends
      .filter { ($0.sixWeekChange ?? 0) > 0 }
      .sorted { lhs, rhs in
        let left = lhs.sixWeekChange ?? 0
        let right = rhs.sixWeekChange ?? 0
        if left != right { return left > right }
        return lhs.latestDate > rhs.latestDate
      }
      .prefix(limit)
      .map { $0 }
  }

  // MARK: - Session reduction

  private struct Session {
    let id: SessionID
    let date: Date
    let samples: [ProgressionSample]
  }

  private static func sessions(from samples: [ProgressionSample]) -> [Session] {
    var grouped: [SessionID: [ProgressionSample]] = [:]
    for sample in samples {
      grouped[sample.sessionID, default: []].append(sample)
    }
    return grouped.map { id, sets in
      Session(
        id: id,
        date: sets.map(\.completedAt).min() ?? .distantPast,
        samples: sets
      )
    }
    .sorted { lhs, rhs in
      if lhs.date != rhs.date { return lhs.date < rhs.date }
      return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
  }

  private static func bestEstimate(in samples: [ProgressionSample]) -> Double? {
    bestEstimateClaim(in: samples)?.value
  }

  /// The session's best estimate with its certainty, so the figure and the trust in it come from
  /// the same set.
  private static func bestEstimateClaim(in samples: [ProgressionSample]) -> Claim<Double>? {
    samples
      .map { StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }
      .filter { $0.value != nil }
      .max { ($0.value ?? 0) < ($1.value ?? 0) }
  }

  private static func value(of metric: TrendMetric, in samples: [ProgressionSample]) -> Double? {
    switch metric {
    case .estimatedMax:
      return bestEstimate(in: samples)
    case .heaviestLoad:
      return samples.map(\.weightKg).max()
    case .repsAtTopLoad:
      guard let heaviest = samples.map(\.weightKg).max() else { return nil }
      return samples
        .filter { abs($0.weightKg - heaviest) < PersonalRecordDetector.loadMatchingTolerance }
        .map { Double($0.reps) }
        .max()
    }
  }
}
