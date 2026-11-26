import Foundation

/// What the log holds for one machine: the facts a lifter needs to know whether they have
/// actually used the equipment they pay for.
///
/// Every number comes from working sets whose own `machineID` names this machine. A set with no
/// machine counts for no machine, because a lifter can switch machines mid-exercise and only the
/// set's own reference says where the work happened. Warm-ups are not work in this sense: they are
/// filtered out before counting, not subtracted afterwards.
public struct MachineUsage: Hashable, Sendable {
  /// Sessions holding at least one working set on this machine.
  public let sessionCount: Int
  /// Working sets, warm-ups excluded.
  public let workingSetCount: Int
  /// The heaviest working set's load, in canonical kilograms. Nil only when there are no working
  /// sets, which is why a usage with no sets has no entry at all.
  public let heaviestLoadKg: Double?
  /// The newest working set's `completedAt`, so a workout that began before midnight and finished
  /// after it is dated by the work and not by the session's start.
  public let lastUsedAt: Date?

  public init(
    sessionCount: Int, workingSetCount: Int, heaviestLoadKg: Double?, lastUsedAt: Date?
  ) {
    self.sessionCount = sessionCount
    self.workingSetCount = workingSetCount
    self.heaviestLoadKg = heaviestLoadKg
    self.lastUsedAt = lastUsedAt
  }

  /// True exactly when no working set has ever named this machine.
  public var isNeverUsed: Bool { workingSetCount == 0 }
}

/// The words the gym list uses for a machine's log.
///
/// The numbers are facts about the log, never advice about training: no target, no best, no
/// verdict. "Heaviest" is what the log holds, not a personal record, and there is deliberately no
/// way to ask this copy for a recommendation.
public enum MachineUsageCopy {
  /// "Last used 6 Nov · 14 sessions · 312 working sets · heaviest 80 kg".
  ///
  /// Returns `neverUsed` when `workingSets == 0`, so no caller can compose "0 sessions" even by
  /// passing a date and a count. A nil date or heaviest load only drops its own fragment; the
  /// separator never trails.
  public static func summary(
    lastUsed: String?, sessions: Int, workingSets: Int, heaviest: String?
  ) -> String {
    guard workingSets > 0 else { return neverUsed }
    var fragments: [String] = []
    if let lastUsed { fragments.append("Last used \(lastUsed)") }
    fragments.append(sessions == 1 ? "1 session" : "\(sessions) sessions")
    fragments.append(workingSets == 1 ? "1 working set" : "\(workingSets) working sets")
    if let heaviest { fragments.append("heaviest \(heaviest)") }
    return fragments.joined(separator: " · ")
  }

  public static let neverUsed = "No working sets logged on this machine"

  /// Why the count on screen can be smaller than the history the lifter remembers.
  ///
  /// Imported sets count when the file named a machine this database knows, so the blanket claim
  /// that imports carry no machine would be false for a Hardset-to-Hardset restore. Free weights
  /// genuinely carry none, and a set without a machine cannot be attributed to one.
  public static let importsAndFreeWeights =
    "Imported history counts only where the file named a machine this app knows. Free-weight sets "
    + "carry no machine, so they are not counted here."
}
