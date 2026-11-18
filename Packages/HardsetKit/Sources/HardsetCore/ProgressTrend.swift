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
  /// Non-nil means the movement is stalled, and the number is the trailing run of sessions
  /// without a record.
  public let stalledSessions: Int?
  public let latestDate: Date

  public var id: ProgressionKey { key }

  public init(
    key: ProgressionKey,
    metric: TrendMetric,
    sparkline: [Double],
    sixWeekChange: Double?,
    sessionCount: Int,
    stalledSessions: Int?,
    latestDate: Date
  ) {
    self.key = key
    self.metric = metric
    self.sparkline = sparkline
    self.sixWeekChange = sixWeekChange
    self.sessionCount = sessionCount
    self.stalledSessions = stalledSessions
    self.latestDate = latestDate
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

    let points: [(date: Date, value: Double)] = sessions.compactMap { session in
      guard let value = value(of: metric, in: session.samples) else { return nil }
      return (session.date, value)
    }
    guard let latest = points.last else { return nil }

    let change: Double?
    let windowStart = latestSession.date.addingTimeInterval(-49 * day)
    let windowEnd = latestSession.date.addingTimeInterval(-35 * day)
    let base = points
      .filter { $0.date >= windowStart && $0.date <= windowEnd }
      .map(\.value)
      .max()
    if let base, base > 0 {
      change = latest.value / base - 1
    } else {
      change = nil
    }

    let recordSessions = recordSessionIDs(
      samples: samples,
      incrementKg: incrementKg,
      estimatesOneRepMax: estimatesOneRepMax,
      lastSessions: sessions.count - 1
    )
    var stalled: Int?
    if sessions.count >= minimumSessionsForStall {
      var run = 0
      for session in sessions.dropFirst().reversed() {
        if recordSessions.contains(session.id) { break }
        run += 1
      }
      stalled = run >= stallRun ? run : nil
    }

    return MovementTrend(
      key: key,
      metric: metric,
      sparkline: Array(points.suffix(12)).map(\.value),
      sixWeekChange: change,
      sessionCount: sessions.count,
      stalledSessions: stalled,
      latestDate: latestSession.date
    )
  }

  /// The sessions that set at least one record, with history always including every earlier set.
  ///
  /// The first session only builds history: with nothing before it, an ordinary ramp would look
  /// like a run of records. `lastSessions` limits which sessions are tested, not what they are
  /// tested against.
  public static func recordSessionIDs(
    samples: [ProgressionSample],
    incrementKg: Double?,
    estimatesOneRepMax: Bool,
    lastSessions: Int? = nil
  ) -> Set<SessionID> {
    let sessions = sessions(from: samples)
    guard sessions.count > 1 else { return [] }

    var records = Set<SessionID>()
    var history: [PriorSetRecord] = []
    let firstTested = max(1, sessions.count - (lastSessions ?? sessions.count))

    for (index, session) in sessions.enumerated() {
      var sessionHistory = history
      for sample in session.samples.sorted(by: { $0.completedAt < $1.completedAt }) {
        if index >= firstTested {
          let found = PersonalRecordDetector.records(
            for: .init(weightKg: sample.weightKg, reps: sample.reps),
            history: sessionHistory,
            increment: incrementKg,
            estimatesOneRepMax: estimatesOneRepMax
          )
          if !found.isEmpty { records.insert(session.id) }
        }
        sessionHistory.append(
          PriorSetRecord(weightKg: sample.weightKg, reps: sample.reps, completedAt: sample.completedAt)
        )
      }
      history = sessionHistory
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
    samples
      .compactMap { StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps).value }
      .max()
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
