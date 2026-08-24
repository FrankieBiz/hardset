import Foundation

/// One completed set, reduced to what progression needs.
public struct ProgressionSample: Hashable, Sendable {
  public let sessionID: SessionID
  public let machineID: MachineID?
  public let weightKg: Double
  public let reps: Int
  public let completedAt: Date

  public init(
    sessionID: SessionID,
    machineID: MachineID?,
    weightKg: Double,
    reps: Int,
    completedAt: Date
  ) {
    self.sessionID = sessionID
    self.machineID = machineID
    self.weightKg = weightKg
    self.reps = reps
    self.completedAt = completedAt
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

  public var id: SessionID { sessionID }

  public init(
    sessionID: SessionID,
    machineID: MachineID?,
    date: Date,
    heaviestLoadKg: Double,
    bestEstimatedOneRepMaxKg: Double?,
    workingSets: Int
  ) {
    self.sessionID = sessionID
    self.machineID = machineID
    self.date = date
    self.heaviestLoadKg = heaviestLoadKg
    self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
    self.workingSets = workingSets
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

  public var id: Date { date }

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
  public var explanation: String {
    let direction = heaviestLoadDeltaKg >= 0 ? "higher" : "lower"
    let magnitude = abs(heaviestLoadDeltaKg)
    guard magnitude > 0 else {
      return "You changed machines here. The load happened to match, which is a coincidence, not a comparison."
    }
    return "You changed machines here. The load is \(Self.format(magnitude)) kg \(direction), which is a difference between the machines rather than a change in strength."
  }

  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}

/// Builds per-machine load history from logged sets.
public enum ProgressionAnalyzer {
  /// One series per machine, each point a session's best work.
  ///
  /// Warm-ups must be excluded by the caller — they are excluded in SQL upstream, so a warm-up
  /// reaching here is a bug rather than something to filter defensively and hide.
  public static func series(from samples: [ProgressionSample], exerciseID: ExerciseID)
    -> [ProgressionSeries]
  {
    // Group by machine, then by session within it.
    var byMachine: [MachineID?: [SessionID: [ProgressionSample]]] = [:]
    for sample in samples {
      byMachine[sample.machineID, default: [:]][sample.sessionID, default: []].append(sample)
    }

    return byMachine
      .map { machineID, sessions in
        let points = sessions
          .map { sessionID, samples in point(sessionID: sessionID, machineID: machineID, samples: samples) }
          .sorted { $0.date < $1.date }
        return ProgressionSeries(
          key: ProgressionKey(exerciseID: exerciseID, machineID: machineID),
          points: points
        )
      }
      // Most-trained machine first: that is the one the user means by "my leg press".
      .sorted { lhs, rhs in
        if lhs.points.count != rhs.points.count { return lhs.points.count > rhs.points.count }
        return (lhs.points.last?.date ?? .distantPast) > (rhs.points.last?.date ?? .distantPast)
      }
  }

  private static func point(
    sessionID: SessionID, machineID: MachineID?, samples: [ProgressionSample]
  ) -> ProgressionPoint {
    let heaviest = samples.map(\.weightKg).max() ?? 0
    // Only estimable sets contribute. A session of high-rep work yields no estimate at all rather
    // than an extrapolated one.
    let estimates = samples.compactMap {
      StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps).value
    }
    return ProgressionPoint(
      sessionID: sessionID,
      machineID: machineID,
      date: samples.map(\.completedAt).min() ?? .distantPast,
      heaviestLoadKg: heaviest,
      bestEstimatedOneRepMaxKg: estimates.max(),
      workingSets: samples.count
    )
  }

  /// Points where the machine changed between consecutive sessions, in chronological order.
  ///
  /// Computed across the whole exercise rather than within a series, because a machine change is
  /// by definition a move between series and would be invisible inside either one.
  public static func machineChanges(from samples: [ProgressionSample]) -> [MachineChange] {
    // One entry per consecutive run of the same session-and-machine, not one per session.
    //
    // Keying on the session alone kept whichever machine was seen first and took the heaviest load
    // across all of them, so a lifter who moved equipment mid-exercise had that session attributed
    // to one machine while carrying a load set on the other. The delta against the next session was
    // then a comparison between two different machines reported as one -- precisely the merge this
    // per-machine design exists to refuse, in the code whose job is to annotate machine changes. A
    // move made inside one session was also invisible, because the session collapsed to one entry.
    //
    // A run ends when the machine changes *or* the session does. Ending it on the session boundary
    // too is what keeps the delta meaningful: it compares the last session on the old machine
    // against the first on the new one, rather than against a maximum accumulated over months.
    //
    // Grouped by walking logging order rather than by collecting into a dictionary and re-sorting.
    // Two blocks can share a timestamp, and sorting on date alone left their relative order to the
    // dictionary's -- so whether a move was detected at all depended on hash ordering. Decorating
    // with the input index makes the order total.
    struct Run {
      let sessionID: SessionID
      let machineID: MachineID?
      let date: Date
      var heaviest: Double
    }
    let ordered = samples
      .enumerated()
      .sorted { ($0.element.completedAt, $0.offset) < ($1.element.completedAt, $1.offset) }
      .map(\.element)
      .reduce(into: [Run]()) { runs, sample in
        if let last = runs.last,
          last.sessionID == sample.sessionID,
          last.machineID == sample.machineID
        {
          runs[runs.count - 1].heaviest = max(last.heaviest, sample.weightKg)
        } else {
          runs.append(
            Run(
              sessionID: sample.sessionID,
              machineID: sample.machineID,
              date: sample.completedAt,
              heaviest: sample.weightKg
            )
          )
        }
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
      different equipment is not the same effort.
      """,
    citation: nil,
    validRange: """
      An estimated one-rep max is only shown for sets of twelve reps or fewer; above that no \
      estimate is produced. A change in load across a machine switch is a difference between \
      machines, not a change in strength, and is labelled as such.
      """
  )
}
