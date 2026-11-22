import Foundation

/// What a movement's trend line plots.
public enum TrendMetric: String, Hashable, Sendable {
  /// The best evaluable Epley estimate in each session.
  case estimatedMax
  /// The heaviest load in each session, used when no estimate is possible.
  case heaviestLoad
  /// Logged added load when the movement's modality is unknown. Never ranked with estimated max.
  case addedLoad
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
  /// Non-nil means none of the movement's last `ProgressTrendAnalyzer.stallRun` sessions set a
  /// record, and the number is that count. It is never a longer run, because only those sessions
  /// are checked. The screen says exactly that, "No record in 3 sessions", and not that the lifter
  /// has stalled.
  public let stalledSessions: Int?
  public let latestDate: Date
  /// The date of the movement's first session, so a row with no six-week change can say how much
  /// history it does have. Nil when the caller does not know it.
  public let firstDate: Date?
  /// How far to trust the displayed estimate/change. A six-week ratio carries the weaker of
  /// its two estimates, using the same combination rule as the scorecard. Without a comparison
  /// window this is the latest estimate's certainty. Unknown-modality metrics are low; other
  /// observed metrics have none.
  public let certainty: Certainty?
  public let loadAssumption: String?

  public var id: ProgressionKey { key }

  public init(
    key: ProgressionKey,
    metric: TrendMetric,
    sparkline: [Double],
    sixWeekChange: Double?,
    sessionCount: Int,
    stalledSessions: Int?,
    latestDate: Date,
    firstDate: Date? = nil,
    certainty: Certainty? = nil,
    loadAssumption: String? = nil
  ) {
    self.key = key
    self.metric = metric
    self.sparkline = sparkline
    self.sixWeekChange = sixWeekChange
    self.sessionCount = sessionCount
    self.stalledSessions = stalledSessions
    self.latestDate = latestDate
    self.firstDate = firstDate
    self.certainty = certainty
    self.loadAssumption = loadAssumption
  }
}

/// Builds movement trends, the sessions that set records, and the no-record-in-recent-sessions flag.
public enum ProgressTrendAnalyzer {
  public static let stallRun = 3
  public static let minimumSessionsForStall = 4

  /// How many days before the latest session an earlier one may sit and still be what a six-week
  /// change is read against: five to seven weeks. The change is computed from this band and the
  /// copy that explains a missing change is written from it, so neither can drift from the other.
  public static let comparisonBandDays: ClosedRange<Int> = 35...49

  private static let day: TimeInterval = 86_400

  /// Nil when there are no samples.
  public static func trend(
    key: ProgressionKey,
    samples: [ProgressionSample],
    incrementKg: Double?,
    estimatesOneRepMax: Bool,
    assumesAddedLoad: Bool = false
  ) -> MovementTrend? {
    let sessions = sessions(from: samples)
    guard let latestSession = sessions.last else { return nil }

    let metric: TrendMetric
    if assumesAddedLoad {
      metric = latestSession.samples.contains { $0.weightKg > 0 } ? .addedLoad : .repsAtTopLoad
    } else if !estimatesOneRepMax {
      metric = .repsAtTopLoad
    } else if bestEstimate(in: latestSession.samples) != nil {
      metric = .estimatedMax
    } else {
      metric = .heaviestLoad
    }

    let points: [(date: Date, value: Double, topLoad: Double, certainty: Certainty?)] = sessions.compactMap { session in
      guard let value = value(of: metric, in: session.samples) else { return nil }
      return (session.date, value, session.samples.map(\.weightKg).max() ?? 0,
        metric == .estimatedMax ? bestEstimateClaim(in: session.samples)?.certainty : nil)
    }
    guard let latest = points.last else { return nil }

    let change: Double?
    let windowStart = latestSession.date.addingTimeInterval(-Double(comparisonBandDays.upperBound) * day)
    let windowEnd = latestSession.date.addingTimeInterval(-Double(comparisonBandDays.lowerBound) * day)
    let base = points
      .filter { $0.date >= windowStart && $0.date <= windowEnd }
      // Reps at the top load are only a fair comparison at the same top load: ten bodyweight
      // pull-ups against five with 20 kg added is not an improvement of 100%, it is a different
      // exercise's number. Other metrics are loads or estimates, which compare across sessions.
      .filter {
        metric != .repsAtTopLoad
          || abs($0.topLoad - latest.topLoad) < PersonalRecordDetector.loadMatchingTolerance
      }
      .max {
        if $0.value != $1.value { return $0.value < $1.value }
        return ($0.certainty ?? .unevaluated) < ($1.certainty ?? .unevaluated)
      }
    if let base, base.value > 0 {
      change = latest.value / base.value - 1
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
        estimatesOneRepMax: estimatesOneRepMax && !assumesAddedLoad,
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
      firstDate: sessions.first?.date,
      certainty: assumesAddedLoad ? .low : metric == .estimatedMax
        ? Certainty.combine([latest.certainty, change == nil ? nil : base?.certainty].compactMap { $0 })
        : nil,
      loadAssumption: assumesAddedLoad ? ExerciseModality.unknownLoadAssumption : nil
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

  /// The ranking is deliberately one metric: percentages of load and reps cannot be ordered
  /// alongside percentages of estimated max. Other metrics remain visible in body-part sections.
  public static let mostImprovedMetric: TrendMetric = .estimatedMax

  /// The positive six-week gains within one metric, best-supported first.
  ///
  /// Ordered by how sure the estimate is, then by whether the movement has gone without a record,
  /// then by the size of the gain. A bigger percentage from a weaker estimate does not outrank a
  /// smaller one from a better one, and a movement with no record in its last sessions ranks after
  /// one of the same confidence that has one, so the strip never leads with a Low-confidence
  /// movement that is also flagged "No record in 3 sessions" while a better-supported gain sits
  /// below it. `ProgressCopy.mostImprovedOrdering` says so on screen.
  public static func mostImproved(
    _ trends: [MovementTrend], metric: TrendMetric = mostImprovedMetric, limit: Int = 3
  ) -> [MovementTrend] {
    guard metric == .estimatedMax || metric == .addedLoad else { return [] }
    return trends
      .filter { $0.metric == metric && ($0.sixWeekChange ?? 0) > 0 }
      .sorted { lhs, rhs in
        let leftCertainty = lhs.certainty ?? .unevaluated
        let rightCertainty = rhs.certainty ?? .unevaluated
        if leftCertainty != rightCertainty { return leftCertainty > rightCertainty }
        let leftStalled = lhs.stalledSessions != nil
        let rightStalled = rhs.stalledSessions != nil
        if leftStalled != rightStalled { return !leftStalled }
        let left = lhs.sixWeekChange ?? 0
        let right = rhs.sixWeekChange ?? 0
        if left != right { return left > right }
        if lhs.latestDate != rhs.latestDate { return lhs.latestDate > rhs.latestDate }
        if lhs.key.exerciseID != rhs.key.exerciseID {
          return lhs.key.exerciseID.rawValue.uuidString < rhs.key.exerciseID.rawValue.uuidString
        }
        if lhs.key.machineID != rhs.key.machineID {
          return (lhs.key.machineID?.rawValue.uuidString ?? "") < (rhs.key.machineID?.rawValue.uuidString ?? "")
        }
        return !lhs.key.isImported && rhs.key.isImported
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
    StrengthMath.bestSupportedEstimate(samples.map {
      StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps)
    })
  }

  private static func value(of metric: TrendMetric, in samples: [ProgressionSample]) -> Double? {
    switch metric {
    case .estimatedMax:
      return bestEstimate(in: samples)
    case .heaviestLoad, .addedLoad:
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
