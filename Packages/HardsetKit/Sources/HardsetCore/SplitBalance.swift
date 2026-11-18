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
