import Foundation

/// One day of a plan: an ordered list of movements, and nothing else.
///
/// No set counts. A split is a partition of movements the lifter already trains, and the app has no
/// weekly set target for any muscle to derive one from -- see `VolumeAnalyzer.weeklyTarget`, which
/// is `.unevaluated` for all 22 tokens. The storage layer omits the column for the same reason.
public struct SplitPlanDay: Hashable, Sendable {
  /// Position in the week. The only ordering there is -- two days may share a name.
  public let position: Int
  /// The lifter's, and editable. The dealer supplies "Day 1"-style placeholders rather than
  /// "Push" or "Upper", because naming a day after a training style asserts the app chose one.
  public let name: String
  public let movements: [ExerciseID]

  public init(position: Int, name: String, movements: [ExerciseID]) {
    self.position = position
    self.name = name
    self.movements = movements
  }

  public var isEmpty: Bool { movements.isEmpty }
}

/// An arrangement of movements across days. A partition, not a prescription.
public struct SplitPlan: Hashable, Sendable {
  public let days: [SplitPlanDay]

  public init(days: [SplitPlanDay]) {
    self.days = days
  }

  public var dayCount: Int { days.count }
  public var movementCount: Int { days.reduce(0) { $0 + $1.movements.count } }
  /// Every movement in the plan, in day then position order.
  public var allMovements: [ExerciseID] { days.flatMap(\.movements) }
}

// MARK: - Dealing

/// Deals movements across days.
///
/// Pure, Foundation-only, and holds no database handle -- the same rule as
/// `PriorPerformanceSnapshot`, and for the same reason: a type that cannot reach the database cannot
/// query it per render.
///
/// ## What this is allowed to be
///
/// This is arithmetic over movements the lifter authored, not a program generator. It decides *which
/// day* each of their movements lands on and nothing else. It does not choose movements, does not
/// choose set counts, and does not evaluate the result -- there is no target to evaluate against
/// (`VolumeAnalyzer.weeklyTarget` is `.unevaluated` for every muscle) and no coverage figure that
/// distinguishes a good plan from a bad one (`SplitCalibrationProbe` shows every conventional split
/// leaves 6-8 muscles at zero, five of them the same five).
///
/// **Deliberately absent:** any rule about which muscles may share a day, or may not appear on
/// consecutive days. That is a recovery claim and the app has no such finding.
public enum SplitDealer {
  /// Spreads `movements` across `dayCount` days, balancing each muscle's credit between days.
  ///
  /// Greedy and largest-first: the movements crediting the most muscle go down first, each onto
  /// whichever day currently owes the least for *that movement's own* muscles. Not optimal --
  /// multi-dimensional partitioning is NP-hard and a better answer would be indistinguishable to a
  /// lifter -- but deterministic, which matters more: re-dealing the same input twice must not
  /// reshuffle someone's plan.
  ///
  /// - Parameters:
  ///   - movements: The lifter's own movements. Duplicates are preserved; the caller decides
  ///     whether the same movement twice in a week is meaningful.
  ///   - dayCount: How many days the lifter asked for. Clamped to at least 1, because a plan with
  ///     no days is not a thing a caller can mean. More days than movements is legitimate and
  ///     yields empty days rather than fewer days.
  ///   - attribution: What each movement trains. Movements missing from it are dealt last, round
  ///     robin -- crediting nothing, they cannot be balanced, and pretending otherwise would let a
  ///     plan of unrecognised movements look evenly spread.
  ///   - dayName: Placeholder names, by zero-based index. Injected so the UI layer can localise
  ///     without this module importing a string catalogue.
  public static func deal(
    movements: [ExerciseID],
    across dayCount: Int,
    attribution: AttributionIndex,
    dayName: (Int) -> String = { "Day \($0 + 1)" }
  ) -> SplitPlan {
    let days = max(1, dayCount)

    // Credited contributions only. Stabilisers carry weight 0 -- grip on a deadlift is not trained
    // forearm work -- so including them would let a movement look balanced against muscles it
    // never credits.
    var credited: [(id: ExerciseID, contributions: [MuscleContribution], load: Double)] = []
    var unattributed: [ExerciseID] = []

    for id in movements {
      let contributions = (attribution.contributions(for: id) ?? []).filter { $0.setWeight > 0 }
      if contributions.isEmpty {
        unattributed.append(id)
      } else {
        credited.append(
          (id, contributions, contributions.reduce(0) { $0 + $1.setWeight })
        )
      }
    }

    // Largest first, then by id. The tiebreak is what makes this deterministic; without it two
    // equal-weight movements order by whatever the caller happened to pass.
    credited.sort {
      $0.load != $1.load ? $0.load > $1.load : $0.id.description < $1.id.description
    }

    var buckets: [[ExerciseID]] = Array(repeating: [], count: days)
    var load: [[MuscleKey: Double]] = Array(repeating: [:], count: days)

    for movement in credited {
      // Cost of adding this movement to a day: how much that day already owes for the muscles this
      // movement credits, weighted by how much of each it adds. Weighting is what stops a
      // chest-dominant movement landing on the chest-heavy day merely because its minor muscles are
      // quiet there.
      var best = 0
      var bestCost = Double.infinity
      for day in 0..<days {
        var cost = 0.0
        for contribution in movement.contributions {
          cost += contribution.setWeight * (load[day][contribution.key] ?? 0)
        }
        let isBetter =
          cost < bestCost
          || (cost == bestCost && buckets[day].count < buckets[best].count)
        if isBetter {
          best = day
          bestCost = cost
        }
      }
      buckets[best].append(movement.id)
      for contribution in movement.contributions {
        load[best][contribution.key, default: 0] += contribution.setWeight
      }
    }

    // Round robin from the least-populated day, so unrecognised movements do not all pile onto
    // day 1 when nothing else has been placed.
    for (offset, id) in unattributed.enumerated() {
      let day =
        days == 1
        ? 0
        : buckets.indices.min {
          buckets[$0].count != buckets[$1].count
            ? buckets[$0].count < buckets[$1].count : $0 < $1
        } ?? (offset % days)
      buckets[day].append(id)
    }

    return SplitPlan(
      days: buckets.enumerated().map { index, movements in
        SplitPlanDay(position: index, name: dayName(index), movements: movements)
      }
    )
  }
}
