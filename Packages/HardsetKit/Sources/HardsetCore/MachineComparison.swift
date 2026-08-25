import Foundation

/// What you press on one machine, next to what you press on the others.
///
/// The question the app is built to answer and had no screen for: "I press a different weight on
/// one chest press than on another — what do I do on each?" The per-machine history was always
/// tracked and always correct; it was only ever *drawn*, as one line per machine inside a chart the
/// lifter had to find their way into. This states it.
///
/// Read-only and derived entirely from series that already exist. Nothing here re-reads the
/// database and nothing here merges two machines — the whole point is the difference between them.
public struct MachineComparisonRow: Hashable, Sendable, Identifiable {
  public let key: ProgressionKey
  /// The heaviest load moved on this machine, ever. Always available.
  public let heaviestLoadKg: Double
  /// The best estimate on this machine, or `nil` when nothing logged on it was estimable. A
  /// machine only ever used for twenty-rep sets has no estimate, and inventing one would be the
  /// ancestor's bug.
  public let bestEstimatedOneRepMaxKg: Double?
  public let lastTrained: Date
  public let sessionCount: Int
  /// Heaviest load minus the reference machine's, or `nil` on the reference row itself.
  ///
  /// A difference between two machines, never a change in strength. `MachineComparison.explanation`
  /// is the only sanctioned way to put it into words.
  public let heaviestLoadDeltaKg: Double?

  public var id: ProgressionKey { key }

  public init(
    key: ProgressionKey,
    heaviestLoadKg: Double,
    bestEstimatedOneRepMaxKg: Double?,
    lastTrained: Date,
    sessionCount: Int,
    heaviestLoadDeltaKg: Double?
  ) {
    self.key = key
    self.heaviestLoadKg = heaviestLoadKg
    self.bestEstimatedOneRepMaxKg = bestEstimatedOneRepMaxKg
    self.lastTrained = lastTrained
    self.sessionCount = sessionCount
    self.heaviestLoadDeltaKg = heaviestLoadDeltaKg
  }

  /// The machine every other row is measured against.
  public var isReference: Bool { heaviestLoadDeltaKg == nil }
}

public enum MachineComparison {
  /// One row per machine, the one you use most first.
  ///
  /// # Why "most used" is the reference
  ///
  /// Some machine has to be the baseline for a delta to mean anything, and the honest choice is the
  /// one the lifter has the most sessions on: it is the number they actually know. Picking the
  /// strongest would flatter, picking the newest would move the baseline every time they tried
  /// something once, and picking the heaviest would make every other row negative by construction.
  /// Ties break on most recently trained, so the reference is stable rather than dependent on the
  /// order series arrive in.
  ///
  /// # What the delta is not
  ///
  /// It is never progress. Two machines' loads differ because of leverage, cam shape, carriage
  /// weight and setup, and a lifter reading -20 kg as having got weaker is exactly the misreading
  /// `MachineChange` exists to prevent. Render it through `explanation(forDeltaKg:)`.
  public static func rows(from series: [ProgressionSeries]) -> [MachineComparisonRow] {
    var summaries: [(key: ProgressionKey, heaviest: Double, estimate: Double?, last: Date, sessions: Int)] = []

    for entry in series {
      guard !entry.points.isEmpty else { continue }
      var heaviest = 0.0
      var estimate: Double?
      var last = Date.distantPast
      for point in entry.points {
        heaviest = max(heaviest, point.heaviestLoadKg)
        if let candidate = point.bestEstimatedOneRepMaxKg {
          estimate = max(estimate ?? candidate, candidate)
        }
        last = max(last, point.date)
      }
      summaries.append((entry.key, heaviest, estimate, last, entry.points.count))
    }
    guard !summaries.isEmpty else { return [] }

    var reference = summaries[0]
    for summary in summaries.dropFirst() {
      if summary.sessions > reference.sessions
        || (summary.sessions == reference.sessions && summary.last > reference.last)
      {
        reference = summary
      }
    }

    var ordered: [(key: ProgressionKey, heaviest: Double, estimate: Double?, last: Date, sessions: Int)] = []
    ordered.append(reference)
    // Everything else by most recently trained, so the machine they were on last week reads before
    // one they tried once a year ago.
    var rest: [(key: ProgressionKey, heaviest: Double, estimate: Double?, last: Date, sessions: Int)] = []
    for summary in summaries where summary.key != reference.key {
      rest.append(summary)
    }
    rest.sort { $0.last > $1.last }
    ordered.append(contentsOf: rest)

    var result: [MachineComparisonRow] = []
    for summary in ordered {
      result.append(
        MachineComparisonRow(
          key: summary.key,
          heaviestLoadKg: summary.heaviest,
          bestEstimatedOneRepMaxKg: summary.estimate,
          lastTrained: summary.last,
          sessionCount: summary.sessions,
          heaviestLoadDeltaKg: summary.key == reference.key
            ? nil
            : summary.heaviest - reference.heaviest
        )
      )
    }
    return result
  }

  /// The sentence a delta must be shown with.
  ///
  /// Deliberately parallel to `MachineChange.explanation`, and for the same reason: across two
  /// machines a load difference is neither progress nor regression, and any wording that leaves
  /// room for that reading is wrong. Says "on this one" rather than naming a direction of travel.
  /// - Parameters:
  ///   - delta: the difference, already converted to the unit being displayed.
  ///   - unitAbbreviation: passed in rather than hardcoded, because the caller converts. An earlier
  ///     version wrote "kg" here and the view repaired it with a string replacement on the finished
  ///     sentence -- which works until the wording changes and then silently tells a lifter reading
  ///     in pounds that they pressed "20 kg more".
  public static func explanation(
    forDelta delta: Double,
    unitAbbreviation: String,
    machineName: String
  ) -> String {
    let magnitude = abs(delta)
    guard magnitude > 0 else {
      return "The same load as on \(machineName). That is a coincidence, not a comparison."
    }
    let direction = delta > 0 ? "more" : "less"
    return
      "\(MachineChange.format(magnitude)) \(unitAbbreviation) \(direction) than on \(machineName) "
      + "\u{2014} a difference between the machines rather than a change in strength."
  }
}
