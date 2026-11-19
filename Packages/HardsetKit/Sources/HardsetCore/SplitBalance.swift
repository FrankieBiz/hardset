import Foundation

/// Planned sets across one full rotation of the saved workouts, with the gaps named.
///
/// This is the same fractional counting as logged volume, pointed at a plan instead of history.
/// It deliberately carries no target bands and makes no judgement: one rotation is not a week.
public struct SplitBalance: Hashable, Sendable {
  public let report: MuscleVolumeReport
  /// Muscle groups with no planned sets other than the neck, in `MuscleGroup.allCases` order.
  public let emptyGroups: [MuscleGroup]

  public init(report: MuscleVolumeReport, emptyGroups: [MuscleGroup]) {
    self.report = report
    self.emptyGroups = emptyGroups
  }

  /// One line per body group, for the editor to draw.
  public struct Row: Hashable, Sendable, Identifiable {
    public let group: MuscleGroup
    public let title: String
    /// "12 sets touch it", or "Nothing planned".
    public let line: String
    public let isEmpty: Bool
    public var id: MuscleGroup { group }
  }

  /// Every body group in order, each saying how many planned sets touch it or that nothing is
  /// planned for it. The neck is left out unless something is planned for it: it is rarely trained,
  /// and an empty neck is not a gap worth pointing at. A count of sets, never a total of a group's
  /// muscles, as everywhere else, and no target or judgement.
  public var rows: [Row] {
    MuscleGroup.allCases.compactMap { group in
      if let sets = report.setsTouchingGroup[group] {
        return Row(
          group: group, title: Self.title(for: group),
          line: sets == 1 ? "1 set touches it" : "\(sets) sets touch it", isEmpty: false)
      }
      guard group != .neck else { return nil }
      return Row(
        group: group, title: Self.title(for: group), line: "Nothing planned", isEmpty: true)
    }
  }

  /// Said when planned sets sit on movements with no muscles recorded, because those count toward no
  /// group and would otherwise quietly make every line above a floor.
  public var unattributedNote: String? {
    let sets = report.unattributedHardSets
    guard sets > 0 else { return nil }
    if sets == 1 {
      return "1 planned set is on a movement with no muscles recorded, so it counts toward none."
    }
    return "\(sets) planned sets are on movements with no muscles recorded, so they count toward none."
  }

  private static func title(for group: MuscleGroup) -> String {
    switch group {
    case .chest: "Chest"
    case .shoulders: "Shoulders"
    case .back: "Back"
    case .arms: "Arms"
    case .core: "Core"
    case .neck: "Neck"
    case .legs: "Legs"
    case .glutes: "Glutes"
    }
  }
}

/// Counts a rotation's planned sets through the existing volume analyser.
public enum SplitBalanceAnalyzer {
  /// Each template exercise contributes `plannedSets` working sets. Warm-ups are never planned
  /// here, so every set is a hard set.
  public static func balance(
    templates: [WorkoutTemplate],
    attribution: AttributionIndex
  ) -> SplitBalance {
    var sets: [CountableSet] = []
    for template in templates {
      for exercise in template.exercises {
        for _ in 0..<exercise.plannedSets {
          sets.append(CountableSet(exerciseID: exercise.exerciseID, isWarmup: false))
        }
      }
    }

    let report = VolumeAnalyzer.report(sets: sets, attribution: attribution)
    let empty = MuscleGroup.allCases.filter { group in
      group != .neck && report.setsTouchingGroup[group] == nil
    }
    return SplitBalance(report: report, emptyGroups: empty)
  }
}
