import Foundation

/// What the session actually contains, counted from written sets only.
///
/// This is the number the whole product is judged on, so it lives here and is tested rather
/// than being computed inline in a view. Three rules, each of which is a way the figure could
/// be quietly inflated:
///
/// 1. **Only logged sets count.** A row the user typed into but never logged is not training.
/// 2. **Warm-ups are excluded from working-set counts and volume.** They are real work but they
///    are not the prescription, and counting them makes every session look bigger than it was.
///    Drop sets are excluded from the *count* but not from tonnage: the chain counts as the one
///    set it continues, while every rep it moved is still real. See
///    `SetCounting.dropSetConvention`.
/// 3. **An unresolvable draft contributes nothing** rather than being coerced to zero — a row
///    cannot be logged without a resolvable draft anyway, so this is belt-and-braces against a
///    future path that bypasses `LoggerStore`.
public struct SessionVolume: Hashable, Sendable {
  /// Logged, non-warm-up sets.
  public let workingSets: Int
  /// Logged warm-up sets, reported separately rather than folded in.
  public let warmupSets: Int
  /// Logged drops, reported separately for the same reason warm-ups are: they are real work that
  /// the set count deliberately does not include, and a figure that vanishes is a figure that
  /// looks like a bug.
  public let dropSets: Int
  /// Σ (weight × reps) over logged working sets **and drops**, in canonical kilograms.
  public let volumeKg: Double
  /// Σ reps over logged working sets and drops.
  public let reps: Int

  public init(
    workingSets: Int, warmupSets: Int, volumeKg: Double, reps: Int, dropSets: Int = 0
  ) {
    self.workingSets = workingSets
    self.warmupSets = warmupSets
    self.dropSets = dropSets
    self.volumeKg = volumeKg
    self.reps = reps
  }

  public init(exercises: [ExerciseLogState]) {
    var workingSets = 0
    var warmupSets = 0
    var dropSets = 0
    var volumeKg = 0.0
    var reps = 0

    for exercise in exercises {
      for slot in exercise.slots where slot.isLogged {
        guard let resolved = slot.draft.resolved() else { continue }
        switch slot.kind {
        case .warmup:
          warmupSets += 1
        case .working, .drop:
          // A drop adds tonnage and reps but not a set. Tonnage is arithmetic over what was
          // actually lifted, so it counts in full; the set count is a convention, and the
          // convention counts a chain once. See `SetCounting.dropSetConvention`.
          if slot.kind.countsAsWorkingSet { workingSets += 1 } else { dropSets += 1 }
          volumeKg += resolved.weightKg * Double(resolved.reps)
          reps += resolved.reps
        }
      }
    }

    self.init(
      workingSets: workingSets, warmupSets: warmupSets, volumeKg: volumeKg, reps: reps,
      dropSets: dropSets
    )
  }

  public var isEmpty: Bool { workingSets == 0 && warmupSets == 0 && dropSets == 0 }
}

extension Duration {
  /// `m:ss`, or `h:mm:ss` past an hour. Used for rest countdowns and session length.
  ///
  /// Negative durations render as `0:00` rather than as a minus sign: a rest timer that has
  /// elapsed is finished, not owed.
  public var clockString: String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }
}
