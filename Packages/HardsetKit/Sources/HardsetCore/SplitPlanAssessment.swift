import Foundation

/// What may honestly be said about an arrangement of movements.
///
/// ## Why this counts movements and not sets
///
/// A plan carries no set counts, by design -- so it has no volume. Every figure here is a count of
/// *movements* or of *days*, which are facts about the partition itself. Running a plan through
/// `VolumeAnalyzer` would require inventing a set count per movement, and a fractional-set figure
/// derived from an invented input is exactly the class of number this app exists not to produce.
/// `MuscleVolumeReport` therefore describes a *logged week*; this describes a *plan*, and the two
/// are deliberately different types with different vocabularies.
///
/// ## The two statements that survive
///
/// `SplitCalibrationProbe` closes off every candidate quality axis: there is no weekly set target
/// for any muscle, raw coverage marks down a well-built PPL and a bro split identically (every
/// conventional split leaves 6-8 muscles at zero, five of them the same five), two legitimate plans
/// differ two-fold in weekly sets, and only 6 of 22 muscles are `.modelled` at all. So this type
/// offers exactly two things:
///
/// 1. **Which muscles nothing credits** -- a fact about a partition, needing no target.
/// 2. **Which of the six modelled muscles this plan credits least** -- comparative and within-plan.
///    The dose-response relationship applies to those six, so the direction is sayable; there is no
///    floor, so no number is.
///
/// It offers no grade, no target, no "too low", and nothing at all about the 16 `counted` muscles
/// beyond credited-versus-not.
public struct SplitPlanAssessment: Hashable, Sendable {
  /// Movements crediting each muscle, across the whole plan. Counts movements, never sets.
  ///
  /// A movement crediting a muscle twice in one week counts twice: that is two movements in the
  /// arrangement, which is what the number describes.
  public let creditingMovements: [MuscleKey: Int]
  /// Distinct days on which at least one movement credits each muscle.
  ///
  /// Reported because it is a fact about the partition. **No claim attaches to it** -- the app has
  /// no registered finding about training frequency, so a UI may show this and may not rank it.
  public let creditingDays: [MuscleKey: Int]
  public let movementCount: Int
  /// Movements the app could not attribute. These make every count above a lower bound.
  public let unattributedMovementCount: Int
  public let dayCount: Int

  public init(
    creditingMovements: [MuscleKey: Int],
    creditingDays: [MuscleKey: Int],
    movementCount: Int,
    unattributedMovementCount: Int,
    dayCount: Int
  ) {
    self.creditingMovements = creditingMovements
    self.creditingDays = creditingDays
    self.movementCount = movementCount
    self.unattributedMovementCount = unattributedMovementCount
    self.dayCount = dayCount
  }

  /// Share of the plan's movements the app could attribute. 1.0 when everything was known.
  public var coverage: Double {
    guard movementCount > 0 else { return 1 }
    return Double(movementCount - unattributedMovementCount) / Double(movementCount)
  }

  /// True when at least one movement could not be attributed, so every count is a floor.
  ///
  /// A UI must say so. "Nothing credits your hamstrings" is a different and much stronger claim
  /// than "nothing the app recognises credits your hamstrings", and only the second is true here.
  public var isLowerBound: Bool { unattributedMovementCount > 0 }

  public func movements(crediting muscle: Muscle) -> Int {
    creditingMovements[MuscleKey(muscle)] ?? 0
  }

  public func days(crediting muscle: Muscle) -> Int {
    creditingDays[MuscleKey(muscle)] ?? 0
  }

  /// Muscles no movement in the plan credits.
  ///
  /// - Parameter excluding: Tokens with no direct movement in the catalogue. Pass
  ///   `ExerciseCatalog.unauthoredDirectTokens` -- reporting a gap the app ships no movement for
  ///   blames the lifter for content debt.
  public func uncreditedMuscles(excluding excluded: Set<Muscle>) -> [Muscle] {
    Muscle.allCases.filter { !excluded.contains($0) && movements(crediting: $0) == 0 }
  }

  /// Among the six muscles the dose-response model covers, the ones this plan credits with the
  /// fewest movements. Empty when the plan credits none of them at all.
  ///
  /// **This is a comparison, not a deficiency.** There is no target to be under. What makes it
  /// sayable is that these six are the tokens where the literature supports a direction at all --
  /// more sets tended to produce more growth, with diminishing returns -- so "this is the least of
  /// them in your plan" is a statement a lifter can act on without the app inventing a number.
  ///
  /// Modelled muscles credited by nothing are excluded: they belong in `uncreditedMuscles`, and
  /// reporting them twice would double-count one gap as two findings.
  public var leastCreditedModelledMuscles: [Muscle] {
    let credited = Muscle.allCases.filter { $0.tier == .modelled && movements(crediting: $0) > 0 }
    guard let fewest = credited.map({ movements(crediting: $0) }).min() else { return [] }
    return credited.filter { movements(crediting: $0) == fewest }
  }

  /// The disclosure text for anything derived from a plan, per App Review guideline 1.4.1.
  public static let source = EvidenceSource(
    id: "hardset-split-plan-v1",
    title: "What a plan can tell you",
    methodology: """
      A plan in Hardset is an arrangement of movements you already train, so the app reports what \
      that arrangement covers and what it leaves out. It counts movements and days, never sets: a \
      plan does not record how many sets you will do, and a set figure derived from a guess would \
      not be a measurement. No plan is graded or scored. No weekly set target exists for any \
      muscle, so the app cannot tell you a plan is short of one.
      """,
    citation: """
      Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. Sports Med 2025. \
      DOI 10.1007/s40279-025-02344-w, PMID 41343037.
      """,
    validRange: """
      Six muscles -- chest, front delts, biceps, triceps, quadriceps, hamstrings -- match sites \
      measured in that corpus, and only for those can the app say a direction. For the other \
      sixteen it reports whether a movement credits them and nothing more.
      """
  )
}

extension SplitPlan {
  /// What can be said about this arrangement.
  public func assessed(with attribution: AttributionIndex) -> SplitPlanAssessment {
    var movementsPerMuscle: [MuscleKey: Int] = [:]
    var daysPerMuscle: [MuscleKey: Int] = [:]
    var movementCount = 0
    var unattributed = 0

    for day in days {
      var seenToday: Set<MuscleKey> = []
      for movement in day.movements {
        movementCount += 1
        let contributions = (attribution.contributions(for: movement) ?? [])
          .filter { $0.setWeight > 0 }
        guard !contributions.isEmpty else {
          unattributed += 1
          continue
        }
        // A movement crediting the same muscle through two contributions still credits it once.
        for key in Set(contributions.map(\.key)) {
          movementsPerMuscle[key, default: 0] += 1
          seenToday.insert(key)
        }
      }
      for key in seenToday {
        daysPerMuscle[key, default: 0] += 1
      }
    }

    return SplitPlanAssessment(
      creditingMovements: movementsPerMuscle,
      creditingDays: daysPerMuscle,
      movementCount: movementCount,
      unattributedMovementCount: unattributed,
      dayCount: days.count
    )
  }
}

extension SplitPlanDay {
  /// Muscle groups this day's movements credit, most-credited first, for a descriptive subtitle.
  ///
  /// Describes what is on the day; it does not label the day as a training style. "Legs · Back" is a
  /// readback of the lifter's own choices, whereas calling it "Pull" would assert the app picked a
  /// split archetype for them.
  ///
  /// ## Ranked by credit, not by how many movements touch a group
  ///
  /// Counting movements-per-group weights a bench press's triceps exactly as much as its chest, and
  /// on a real dealt day that produced "Arms · Legs · Shoulders" for a day of rows, bench, leg press
  /// and leg curls -- omitting chest and back entirely and leading with the least important thing
  /// there. Found by looking at the screen; no test would have called it wrong.
  ///
  /// So the sort key is summed `setWeight`, which makes a direct credit outrank an indirect one.
  /// Note this deliberately does NOT follow `MuscleVolumeReport.setsTouchingGroup`'s
  /// count-once-never-sum rule. That rule exists because summing a group's members inflates a
  /// *displayed volume total* -- a bench press would be counted three times in "upper body". Nothing
  /// here is displayed as a quantity: it is a sort key for three words, so the double-counting that
  /// rule prevents has no number to distort.
  public func dominantGroups(with attribution: AttributionIndex) -> [MuscleGroup] {
    var credit: [MuscleGroup: Double] = [:]
    for movement in movements {
      let contributions = (attribution.contributions(for: movement) ?? [])
        .filter { $0.setWeight > 0 }
      for contribution in contributions {
        guard let group = contribution.key.group else { continue }
        credit[group, default: 0] += contribution.setWeight
      }
    }
    return credit
      .sorted {
        $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
      }
      .map(\.key)
  }
}
