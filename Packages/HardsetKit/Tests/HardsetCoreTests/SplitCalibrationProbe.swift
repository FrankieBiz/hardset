import Foundation
import Testing

@testable import HardsetCore

/// Where real splits actually land on Hardset's own attribution and dose-response model.
///
/// These are the numbers any argument about a plan-quality rating has to survive, so they are pinned
/// rather than left to be re-derived by hand. If the catalogue's attribution changes, the reasoning
/// that rests on them is stale and this suite says so.
///
/// The headline facts, all computed here:
/// - Only 6 of 22 muscles are `.modelled`. Every other row in a volume report is `unevaluated`, so a
///   whole-body "volume grade" would be two-thirds unevaluated territory.
/// - **Every** conventional split leaves 6-8 muscles at zero credit, and five are common to all of
///   them: forearms, abs, obliques, neck, hip abductors. So raw coverage cannot be a quality signal
///   -- it would mark down every real plan for not training necks.
/// - A deliberately lopsided plan is distinguished not by any volume figure but by leaving 18
///   muscles at zero.
@Suite("Where real splits land")
struct SplitCalibrationProbe {
  /// One training week: exercise slug and its working sets, grouped by day.
  typealias Week = [[(String, Int)]]

  private func entry(_ slug: String) -> CatalogEntry? {
    ExerciseCatalog.v1.first { $0.slug == slug }?.catalogEntry
  }

  private func report(_ week: Week) -> MuscleVolumeReport {
    var sets: [CountableSet] = []
    var entries: [CatalogEntry] = []
    for day in week {
      for (slug, count) in day {
        guard let e = entry(slug) else {
          Issue.record("catalogue has no slug '\(slug)' -- this fixture is stale")
          continue
        }
        entries.append(e)
        for _ in 0..<count { sets.append(CountableSet(exerciseID: e.id, isWarmup: false)) }
      }
    }
    return VolumeAnalyzer.report(sets: sets, attribution: AttributionIndex(entries: entries))
  }

  // MARK: - Fixtures

  /// A conventional 6-day push/pull/legs at three sets an exercise.
  private let ppl: Week = [
    [("barbell-bench-press", 3), ("incline-dumbbell-press", 3), ("overhead-press", 3),
     ("lateral-raise", 3), ("cable-triceps-pushdown", 3)],
    [("lat-pulldown", 3), ("barbell-row", 3), ("seated-cable-row", 3),
     ("barbell-curl", 3), ("face-pull", 3)],
    [("barbell-back-squat", 3), ("romanian-deadlift", 3), ("leg-press", 3),
     ("seated-leg-curl", 3), ("standing-calf-raise", 3)],
    [("incline-barbell-bench-press", 3), ("dumbbell-bench-press", 3),
     ("seated-dumbbell-press", 3), ("cable-lateral-raise", 3), ("skull-crusher", 3)],
    [("pull-up", 3), ("chest-supported-row", 3), ("straight-arm-pulldown", 3),
     ("hammer-curl", 3), ("reverse-pec-deck", 3)],
    [("barbell-front-squat", 3), ("lying-leg-curl", 3), ("hack-squat", 3),
     ("hip-thrust", 3), ("seated-calf-raise", 3)],
  ]

  /// The classic one-muscle-a-day bro split. Legitimate, popular, and low on hamstrings.
  private let bro: Week = [
    [("barbell-bench-press", 4), ("incline-dumbbell-press", 4), ("pec-deck", 3), ("cable-fly", 3)],
    [("lat-pulldown", 4), ("barbell-row", 4), ("seated-cable-row", 3), ("straight-arm-pulldown", 3)],
    [("overhead-press", 4), ("lateral-raise", 4), ("reverse-pec-deck", 3), ("shrug", 3)],
    [("barbell-curl", 4), ("hammer-curl", 3), ("cable-triceps-pushdown", 4), ("skull-crusher", 3)],
    [("barbell-back-squat", 4), ("leg-press", 4), ("seated-leg-curl", 3), ("standing-calf-raise", 3)],
  ]

  /// Three-day full body: half the weekly sets of the PPL and a perfectly reasonable plan.
  private let fullBody: Week = [
    [("barbell-back-squat", 3), ("barbell-bench-press", 3), ("barbell-row", 3),
     ("romanian-deadlift", 3), ("overhead-press", 2)],
    [("leg-press", 3), ("incline-dumbbell-press", 3), ("lat-pulldown", 3),
     ("seated-leg-curl", 3), ("lateral-raise", 2)],
    [("barbell-front-squat", 3), ("dip", 3), ("pull-up", 3), ("hip-thrust", 3), ("barbell-curl", 2)],
  ]

  /// All pressing, no pulling, no legs. The plan a rating exists to catch.
  private let lopsided: Week = [
    [("barbell-bench-press", 5), ("incline-barbell-bench-press", 5), ("dumbbell-bench-press", 4)],
    [("overhead-press", 5), ("lateral-raise", 5), ("cable-triceps-pushdown", 5)],
    [("chest-press-machine", 5), ("pec-deck", 5), ("dip", 4)],
  ]

  // MARK: - The facts a rating argument rests on

  /// Two-thirds of the vocabulary cannot be graded against the dose-response model at all.
  @Test("Only six muscles are modelled; the rest are unevaluated")
  func modelledCoverageIsNarrow() {
    let modelled = Muscle.allCases.filter { $0.tier == .modelled }
    #expect(modelled.count == 6)
    #expect(Set(modelled) == [.chest, .frontDelts, .biceps, .triceps, .quadriceps, .hamstrings])

    // And the model refuses to place a counted muscle even when the sets are there.
    #expect(VolumeAnalyzer.doseResponse(fractionalSets: 12, for: .lats).value == nil)
    #expect(VolumeAnalyzer.doseResponse(fractionalSets: 12, for: .chest).value != nil)
  }

  /// The reason raw coverage cannot be a quality signal: every real plan fails it identically.
  @Test("Every conventional split leaves the same handful of muscles at zero")
  func realPlansAlwaysHaveZeros() {
    let plans = [("ppl", ppl), ("bro", bro), ("fullBody", fullBody)]
    let zeroSets = plans.map { Set(report($0.1).untrainedMuscles(excluding: [])) }

    for (index, plan) in plans.enumerated() {
      // Six to eight, never zero. A completeness score marks down all three equally.
      let count = zeroSets[index].count
      #expect(count >= 6 && count <= 8, "\(plan.0) had \(count) untrained muscles")
    }

    // What all three miss, computed rather than assumed: the muscles a hypertrophy split does not
    // give dedicated sets to. Note `traps` is absent -- the bro split shrugs -- which is exactly the
    // kind of detail that makes a hand-written completeness rule wrong.
    let universal = zeroSets.reduce(zeroSets[0]) { $0.intersection($1) }
    #expect(universal == [.forearms, .abs, .obliques, .neck, .hipAbductors])
  }

  /// Volume on the modelled muscles is where the evidence actually applies, and conventional plans
  /// sit inside the studied range there.
  @Test("A conventional PPL puts every modelled muscle inside the studied range")
  func pplSitsInsideTheStudiedRange() {
    let r = report(ppl)
    for muscle in Muscle.allCases where muscle.tier == .modelled {
      let sets = r.sets(for: muscle)
      #expect(sets > 0, "\(muscle) got no credit in a conventional PPL")
      let dose = try! #require(VolumeAnalyzer.doseResponse(fractionalSets: sets, for: muscle).value)
      #expect(!dose.isBeyondStudiedRange, "\(muscle) at \(sets) sets is past the studied range")
    }
    #expect(r.hardSets == 90)
    #expect(r.unattributedHardSets == 0)
  }

  /// Two legitimate plans differing two-fold in weekly sets. Any formula that treats total volume as
  /// a quality axis has to call one of these worse than the other, and neither is.
  @Test("Legitimate splits differ roughly two-fold in weekly sets")
  func legitimatePlansDifferWidelyInVolume() {
    #expect(report(ppl).hardSets == 90)
    #expect(report(fullBody).hardSets == 42)
  }

  /// The one place the evidence does bite on a popular plan: a bro split's hamstrings.
  @Test("A bro split is low on hamstrings, and hamstrings is a modelled muscle")
  func broSplitIsLowOnHamstrings() {
    let r = report(bro)
    let hams = r.sets(for: .hamstrings)
    #expect(hams > 0)
    #expect(hams <= 4, "expected the bro split's hamstrings to be low, got \(hams)")
    // Chest, by contrast, is well inside the range -- so this is a distribution finding, not a
    // volume-total finding.
    #expect(r.sets(for: .chest) >= 12)
  }

  /// What actually distinguishes a bad plan: not a volume number, but eighteen muscles at zero.
  @Test("A lopsided plan is distinguished by its zeros, not by its volume")
  func lopsidedPlanIsDistinguishedByZeros() {
    let r = report(lopsided)
    let zeros = r.untrainedMuscles(excluding: [])
    #expect(zeros.count == 18)
    #expect(zeros.contains(.lats))
    #expect(zeros.contains(.quadriceps))
    #expect(zeros.contains(.hamstrings))

    // Its total volume is unremarkable -- comparable to the full-body plan nobody would criticise.
    #expect(r.hardSets == 43)
    #expect(report(fullBody).hardSets == 42)

    // And its one extreme figure sits where the model declines to say anything: past the studied
    // range, where a diminishing-returns fit cannot assert that another set is harmful.
    let chest = try! #require(
      VolumeAnalyzer.doseResponse(fractionalSets: r.sets(for: .chest), for: .chest).value
    )
    #expect(chest.isBeyondStudiedRange)
  }
}
