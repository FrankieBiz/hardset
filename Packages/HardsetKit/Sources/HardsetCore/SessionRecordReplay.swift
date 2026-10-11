import Foundation

/// Re-judges a session's sets for records after the fact, by the same rules as the moment.
///
/// `SessionCoordinator.logSet` reads history *before* each write and judges the set against it
/// (`DECISIONS.md` §12). Replaying a session's sets in order against the history that preceded
/// it gives the same verdicts. A summary, a resumed workout and a corrected set can then all be
/// judged from storage, and none of them trusts what a screen happened to remember.
public enum SessionRecordReplay {
  public struct Entry: Hashable, Sendable {
    public let setID: SetID
    public let key: ProgressionKey
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool
    public let completedAt: Date

    public init(
      setID: SetID, key: ProgressionKey, weightKg: Double, reps: Int, isWarmup: Bool,
      completedAt: Date
    ) {
      self.setID = setID
      self.key = key
      self.weightKg = weightKg
      self.reps = reps
      self.isWarmup = isWarmup
      self.completedAt = completedAt
    }
  }

  /// - Parameters:
  ///   - session: This session's sets, in the order they were performed.
  ///   - priorHistory: Working sets from before this session, per exercise and machine.
  ///   - increments: Stack increments for the machines involved.
  /// - Returns: The records each set earned. Sets that earned none are absent.
  public static func records(
    session: [Entry],
    priorHistory: [ProgressionKey: [PriorSetRecord]],
    increments: [MachineID: Double]
  ) -> [SetID: [PersonalRecord]] {
    var history = priorHistory
    var result: [SetID: [PersonalRecord]] = [:]
    for entry in session {
      let found = PersonalRecordDetector.records(
        for: .init(weightKg: entry.weightKg, reps: entry.reps, isWarmup: entry.isWarmup),
        history: history[entry.key] ?? [],
        increment: entry.key.machineID.flatMap { increments[$0] }
      )
      if !found.isEmpty { result[entry.setID] = found }
      // Warm-ups are not benchmarks, exactly as `completedSets(for:)` excludes them in SQL.
      if !entry.isWarmup {
        history[entry.key, default: []].append(
          PriorSetRecord(weightKg: entry.weightKg, reps: entry.reps, completedAt: entry.completedAt)
        )
      }
    }
    return result
  }
}
