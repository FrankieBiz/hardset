import Foundation

/// One completed set, reduced to what progression needs.
public struct ProgressionSample: Hashable, Sendable {
  public let sessionID: SessionID
  public let machineID: MachineID?
  public let weightKg: Double
  public let reps: Int
  public let completedAt: Date
  public let isImported: Bool

  public init(
    sessionID: SessionID,
    machineID: MachineID?,
    weightKg: Double,
    reps: Int,
    completedAt: Date,
    isImported: Bool = false
  ) {
    self.sessionID = sessionID
    self.machineID = machineID
    self.weightKg = weightKg
    self.reps = reps
    self.completedAt = completedAt
    self.isImported = isImported
  }
}

/// One session's best work on one machine.
public struct ProgressionPoint: Hashable, Sendable, Identifiable {
  public let sessionID: SessionID
  public let machineID: MachineID?
  public let date: Date
  /// Always available: the heaviest load moved for at least one rep.
  public let heaviestLoadKg: Double
  /// The best estimate in the session, or `nil` when nothing in it was estimable — a session of
  /// twenty-rep sets produces no estimate, and inventing one would be the ancestor's bug.
  public let bestEstimatedOneRepMaxKg: Double?
  public let workingSets: Int
  /// How far the best estimate can be trusted, from the rep count of the set that produced it:
  /// a single or two to six reps is high, seven to ten moderate, eleven or twelve low. `nil` when
  /// there is no estimate, and when the point was built without saying (previews).
  public let bestEstimateCertainty: Certainty?

  public var id: SessionID { sessionID }

  public init(
    sessionID: SessionID,
    machineID: MachineID?,
    date: Date,
    heaviestLoadKg: Double,
    bestEstimatedOneRepMaxKg: Double?,
    workingSets: Int,
    bestEstimateCertainty: Certainty? = nil
  ) {
    self.sessionID = sessionID
    self.machineID = machineID
    self.date = date
    self.heaviestLoadKg = heaviestLoadKg
    self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
    self.workingSets = workingSets
    self.bestEstimateCertainty = bestEstimatedOneRepMaxKg == nil ? nil : bestEstimateCertainty
  }
}

/// The load history of one exercise on one machine.
///
/// Series are per machine, never merged, because that is the product's actual claim: 80 kg on one
/// brand's leg press is not 80 kg on another's, and a single line through both is a chart that
/// invents progress the user did not make.
public struct ProgressionSeries: Hashable, Sendable, Identifiable {
  public let key: ProgressionKey
  /// Oldest first.
  public let points: [ProgressionPoint]

  public var id: ProgressionKey { key }

  public init(key: ProgressionKey, points: [ProgressionPoint]) {
    self.key = key
    self.points = points
  }

  /// True when no point in the series carries an estimate, so a chart of e1RM would be empty and
  /// the caller should plot load instead.
  public var hasNoEstimates: Bool {
    points.allSatisfy { $0.bestEstimatedOneRepMaxKg == nil }
  }
}

/// A point where the user moved to different equipment.
///
/// The reason this type exists: a lifter who switches from one leg press to another and finds the
/// load dropped 20 kg has not got weaker, and an app that shows a falling line without saying so
/// is actively misleading. The load delta is reported *alongside* the machine change so the two
/// cannot be read separately.
public struct MachineChange: Hashable, Sendable, Identifiable {
  public let date: Date
  public let fromMachineID: MachineID?
  public let toMachineID: MachineID?
  /// Change in heaviest load across the switch. Positive means the new machine's numbers are
  /// higher, which is a fact about the machines and not about the lifter.
  public let heaviestLoadDeltaKg: Double

  public var id: String {
    // A date alone is not unique: two machine changes can share a session start, and duplicate
    // identifiers make a `ForEach` draw one of them.
    let from = fromMachineID?.rawValue.uuidString ?? "none"
    let to = toMachineID?.rawValue.uuidString ?? "none"
    return "\(date.timeIntervalSince1970)-\(from)-\(to)"
  }

  public init(
    date: Date,
    fromMachineID: MachineID?,
    toMachineID: MachineID?,
    heaviestLoadDeltaKg: Double
  ) {
    self.date = date
    self.fromMachineID = fromMachineID
    self.toMachineID = toMachineID
    self.heaviestLoadDeltaKg = heaviestLoadDeltaKg
  }

  /// The sentence the chart must show. Deliberately refuses to characterise the change as progress
  /// or regression, because across a machine switch it is neither.
  ///
  /// Stated in kilograms, the canonical unit. Screens use `explanation(in:)` with the lifter's own
  /// unit, so the sentence agrees with the chart it sits under.
  public var explanation: String { explanation(in: .kilograms) }

  /// The same sentence, with the load difference converted to `unit` and rounded to a tenth.
  public func explanation(in unit: WeightUnit) -> String {
    let direction = heaviestLoadDeltaKg >= 0 ? "higher" : "lower"
    // Rounded before the zero check, so a difference too small to show is stated as a match
    // rather than printed as "0 kg higher".
    let shown = (unit.fromKilograms(abs(heaviestLoadDeltaKg)) * 10).rounded() / 10
    guard shown > 0 else {
      return "You changed machines here. The load happened to match, which is a coincidence, not a comparison."
    }
    return "You changed machines here. The load is \(Self.format(shown)) \(unit.abbreviation) \(direction), which is a difference between the machines rather than a change in strength."
  }

  static func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
  }
}

/// Builds per-machine load history from logged sets.
public enum ProgressionAnalyzer {
  /// One series per machine, each point a session's best work.
  ///
  /// Warm-ups must be excluded by the caller — they are excluded in SQL upstream, so a warm-up
  /// reaching here is a bug rather than something to filter defensively and hide.
  ///
  /// `estimatesOneRepMax` is `false` for movements whose logged load is not the load moved, such
  /// as bodyweight work (`ExerciseModality.estimatesOneRepMax`); no point then carries an estimate.
  public static func series(
    from samples: [ProgressionSample], exerciseID: ExerciseID, estimatesOneRepMax: Bool = true
  ) -> [ProgressionSeries] {
    // Group by machine, then by session within it.
    var byMachine: [ProgressionKey: [SessionID: [ProgressionSample]]] = [:]
    for sample in samples {
      let key = ProgressionKey(exerciseID: exerciseID, machineID: sample.machineID, isImported: sample.isImported)
      byMachine[key, default: [:]][sample.sessionID, default: []].append(sample)
    }

    return byMachine
      .map { key, sessions in
        let points = sessions
          .map { sessionID, samples in
            point(
              sessionID: sessionID, machineID: key.machineID, samples: samples,
              estimatesOneRepMax: estimatesOneRepMax
            )
          }
          .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.sessionID.rawValue.uuidString < $1.sessionID.rawValue.uuidString
          }
        return ProgressionSeries(
          key: key,
          points: points
        )
      }
      // Most-trained machine first: that is the one the user means by "my leg press".
      .sorted { lhs, rhs in
        if lhs.points.count != rhs.points.count { return lhs.points.count > rhs.points.count }
        let left = lhs.points.last?.date ?? .distantPast
        let right = rhs.points.last?.date ?? .distantPast
        if left != right { return left > right }
        if lhs.key.isImported != rhs.key.isImported { return !lhs.key.isImported }
        return (lhs.key.machineID?.rawValue.uuidString ?? "")
          < (rhs.key.machineID?.rawValue.uuidString ?? "")
      }
  }

  private static func point(
    sessionID: SessionID, machineID: MachineID?, samples: [ProgressionSample],
    estimatesOneRepMax: Bool
  ) -> ProgressionPoint {
    let heaviest = samples.map(\.weightKg).max() ?? 0
    // Only estimable sets contribute. A session of high-rep work yields no estimate at all rather
    // than an extrapolated one.
    let estimable = estimatesOneRepMax ? samples : []
    // Equal estimates keep the same better-supported claim as trends and receipt gains.
    let best = StrengthMath.bestSupportedEstimate(estimable.map {
      StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps)
    })
    return ProgressionPoint(
      sessionID: sessionID,
      machineID: machineID,
      date: samples.map(\.completedAt).min() ?? .distantPast,
      heaviestLoadKg: heaviest,
      bestEstimatedOneRepMaxKg: best?.value,
      workingSets: samples.count,
      bestEstimateCertainty: best?.certainty
    )
  }

  /// The certainty to state beside an estimate chart: the weakest of each line's latest estimate,
  /// because those are the figures the legend reads out. `.unevaluated` when no line has one.
  ///
  /// A point that does not say how certain its estimate is counts as low. Certainty is never
  /// assumed upward.
  public static func estimateCertainty(latestOf series: [[ProgressionPoint]]) -> Certainty {
    let latest = series.compactMap { points in
      points.filter { $0.bestEstimatedOneRepMaxKg != nil }.max {
        if $0.date != $1.date { return $0.date < $1.date }
        return $0.sessionID.rawValue.uuidString < $1.sessionID.rawValue.uuidString
      }
    }
    guard !latest.isEmpty else { return .unevaluated }
    return Certainty.combine(latest.map { $0.bestEstimateCertainty ?? .low })
  }

  /// True when there are points and every one of them recorded no added load: bodyweight work,
  /// where a load line would be a flat line at zero that says nothing.
  public static func hasNoAddedLoad(_ series: [[ProgressionPoint]]) -> Bool {
    let points = series.flatMap { $0 }
    return !points.isEmpty && points.allSatisfy { $0.heaviestLoadKg <= 0 }
  }

  /// Points where the machine changed between consecutive sessions or stints, in chronological order.
  ///
  /// Computed across the whole exercise rather than within a series, because a machine change is
  /// by definition a move between series and would be invisible inside either one.
  public static func machineChanges(from samples: [ProgressionSample]) -> [MachineChange] {
    struct SessionMachineKey: Hashable {
      let sessionID: SessionID
      let machineID: MachineID?
    }

    // One entry per session-machine pair: which machine, and the heaviest load on that specific
    // machine. The session id is kept so equal timestamps still order deterministically.
    var perSessionMachine:
      [SessionMachineKey: (sessionID: SessionID, date: Date, machineID: MachineID?, heaviest: Double)] = [:]
    for sample in samples where !sample.isImported {
      let key = SessionMachineKey(sessionID: sample.sessionID, machineID: sample.machineID)
      if let existing = perSessionMachine[key] {
        perSessionMachine[key] = (
          sample.sessionID,
          min(existing.date, sample.completedAt),
          sample.machineID,
          max(existing.heaviest, sample.weightKg)
        )
      } else {
        perSessionMachine[key] = (
          sample.sessionID, sample.completedAt, sample.machineID, sample.weightKg
        )
      }
    }

    // A total order, not just by date: `values` comes from a dictionary, whose iteration order is
    // randomized per process, so equal timestamps would otherwise reorder between launches.
    let ordered = perSessionMachine.values.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.sessionID != $1.sessionID {
        return $0.sessionID.rawValue.uuidString < $1.sessionID.rawValue.uuidString
      }
      return ($0.machineID?.rawValue.uuidString ?? "") < ($1.machineID?.rawValue.uuidString ?? "")
    }
    guard ordered.count > 1 else { return [] }

    var changes: [MachineChange] = []
    for (previous, current) in zip(ordered, ordered.dropFirst()) where previous.machineID != current.machineID {
      changes.append(
        MachineChange(
          date: current.date,
          fromMachineID: previous.machineID,
          toMachineID: current.machineID,
          heaviestLoadDeltaKg: current.heaviest - previous.heaviest
        )
      )
    }
    return changes
  }

  public static let source = EvidenceSource(
    id: "hardset-progression-v1",
    title: "Load history",
    methodology: """
      Each point is your best work in one session on one specific machine: the heaviest load you \
      moved, and where the rep counts allow it, the best estimated one-rep max. Sessions on \
      different machines are drawn as separate lines and never merged, because the same number on \
      different equipment is not the same effort. Sets with no machine recorded form their own line. \
      Imported history is labelled as imported with no machine recorded and stays separate from native history.
      """,
    citation: nil,
    validRange: """
      An estimated one-rep max is only shown for sets of twelve reps or fewer; above that no \
      estimate is produced. Its certainty follows the reps behind it: a single or two to six reps \
      is high, seven to ten moderate, eleven or twelve low. A change in load across a machine \
      switch is a difference between machines, not a change in strength, and is labelled as such.
      """
  )
}
