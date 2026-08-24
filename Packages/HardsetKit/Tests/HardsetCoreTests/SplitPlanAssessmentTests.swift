import Foundation
import Testing

@testable import HardsetCore

/// What a plan is allowed to say about itself, and what it must refuse to say.
///
/// The refusals here are the point. `SplitCalibrationProbe` established that no quality axis
/// survives contact with the evidence -- no weekly target exists, coverage marks down every real
/// plan identically, and two legitimate plans differ two-fold in volume. These tests keep a future
/// session from reintroducing a score by making the refusals cost a named failure.
@Suite("A plan says what it covers, and refuses to grade itself")
struct SplitPlanAssessmentTests {

  // MARK: - A hand-built fixture, so every count is exact

  private func contribution(_ muscle: Muscle, _ role: MuscleRole) -> MuscleContribution {
    MuscleContribution(muscle, role: role, certainty: .moderate, source: .anatomy)
  }

  /// Three movements with attribution written here rather than read from the catalogue, so the
  /// expected counts below are arithmetic rather than a snapshot of content that may change.
  private struct Fixture {
    let press: ExerciseID
    let squat: ExerciseID
    let curl: ExerciseID
    let attribution: AttributionIndex
  }

  private func makeFixture() -> Fixture {
    let press = ExerciseID()
    let squat = ExerciseID()
    let curl = ExerciseID()
    let attribution = AttributionIndex([
      // Chest direct, triceps indirect, and a stabiliser that must never be credited.
      press: [
        contribution(.chest, .direct),
        contribution(.triceps, .indirect),
        contribution(.forearms, .stabilizer),
      ],
      squat: [contribution(.quadriceps, .direct), contribution(.glutes, .indirect)],
      curl: [contribution(.biceps, .direct)],
    ])
    return Fixture(press: press, squat: squat, curl: curl, attribution: attribution)
  }

  // MARK: - Movements, never sets

  /// The load-bearing distinction. A plan records no set counts, so every figure it reports is a
  /// count of movements. A fractional-set number here would have to come from an invented set
  /// count per movement, which is the exact class of laundered guess this app exists to refuse.
  @Test("Counts are movements, not sets, so an indirect credit still counts as one movement")
  func countsAreMovementsNotSets() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press])
    ])
    let assessment = plan.assessed(with: f.attribution)

    // If these were fractional sets, triceps would read 0.5. They are movements, so it is 1.
    #expect(assessment.movements(crediting: .chest) == 1)
    #expect(assessment.movements(crediting: .triceps) == 1)
    #expect(assessment.movementCount == 1)
  }

  /// Grip is a stabiliser at weight 0. It is involved and it is not trained work, so it must not
  /// appear as a credited muscle -- the same rule that keeps ~5 phantom sets of forearm work out of
  /// every 12 sets of pulling.
  @Test("A stabilising muscle is never credited by a plan")
  func stabilisersAreNotCredited() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press])
    ])
    let assessment = plan.assessed(with: f.attribution)
    #expect(assessment.movements(crediting: .forearms) == 0)
    let uncredited = assessment.uncreditedMuscles(excluding: [])
    #expect(uncredited.contains(.forearms))
  }

  @Test("A movement on two days credits its muscles on both")
  func daysAreCountedDistinctly() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press]),
      SplitPlanDay(position: 1, name: "Day 2", movements: [f.press, f.curl]),
    ])
    let assessment = plan.assessed(with: f.attribution)
    // Two movements in the arrangement credit chest, across two days.
    #expect(assessment.movements(crediting: .chest) == 2)
    #expect(assessment.days(crediting: .chest) == 2)
    // The curl is on one day only.
    #expect(assessment.movements(crediting: .biceps) == 1)
    #expect(assessment.days(crediting: .biceps) == 1)
  }

  /// Two movements crediting a muscle on the same day is one day, not two. A day count that could
  /// exceed the number of days would be meaningless.
  @Test("Two movements for one muscle on one day is still one day")
  func sameDayIsNotDoubleCounted() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press, f.press])
    ])
    let assessment = plan.assessed(with: f.attribution)
    #expect(assessment.movements(crediting: .chest) == 2)
    #expect(assessment.days(crediting: .chest) == 1)
    #expect(assessment.days(crediting: .chest) <= assessment.dayCount)
  }

  // MARK: - The first sayable statement: what nothing credits

  @Test("Muscles no movement credits are reported, and credited ones are not")
  func uncreditedMusclesAreReported() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press, f.squat, f.curl])
    ])
    let assessment = plan.assessed(with: f.attribution)
    let uncredited = Set(assessment.uncreditedMuscles(excluding: []))

    for credited in [Muscle.chest, .triceps, .quadriceps, .glutes, .biceps] {
      #expect(!uncredited.contains(credited), "\(credited) is credited and was reported as a gap")
    }
    for gap in [Muscle.hamstrings, .lats, .abs, .neck] {
      #expect(uncredited.contains(gap), "\(gap) is credited by nothing and was not reported")
    }
  }

  /// Reporting a gap for a muscle the app ships no movement for blames the lifter for content debt.
  /// The exclusion parameter is how a caller suppresses that, and it must actually work.
  @Test("The exclusion set suppresses gaps the catalogue cannot fill")
  func exclusionSuppressesContentDebt() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press])
    ])
    let assessment = plan.assessed(with: f.attribution)
    let suppressed = Set(assessment.uncreditedMuscles(excluding: [.neck, .obliques]))
    #expect(!suppressed.contains(.neck))
    #expect(!suppressed.contains(.obliques))
    #expect(suppressed.contains(.hamstrings))
  }

  // MARK: - The second sayable statement: comparison among the modelled six

  /// Only the six modelled muscles may carry a direction, so only they may be compared this way.
  @Test("The least-credited modelled muscles are modelled, and are genuinely the fewest")
  func leastCreditedIsRestrictedToModelledMuscles() {
    let f = makeFixture()
    // Chest gets two movements, biceps and quads one each. Triceps also gets two (both presses).
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press, f.press, f.squat]),
      SplitPlanDay(position: 1, name: "Day 2", movements: [f.curl]),
    ])
    let assessment = plan.assessed(with: f.attribution)
    let least = assessment.leastCreditedModelledMuscles

    #expect(!least.isEmpty)
    for muscle in least {
      #expect(muscle.tier == .modelled, "\(muscle) is not a modelled muscle")
    }
    // Biceps and quadriceps have one movement each; chest and triceps have two.
    #expect(Set(least) == [.biceps, .quadriceps])
  }

  /// A modelled muscle nothing credits belongs in the gap list, not in the comparison. Reporting it
  /// in both would present one gap as two separate findings.
  @Test("A modelled muscle at zero is a gap, not the least-credited")
  func zeroIsAGapNotAComparison() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.curl])
    ])
    let assessment = plan.assessed(with: f.attribution)
    // Only biceps is credited, so it is trivially the least-credited of the six.
    #expect(assessment.leastCreditedModelledMuscles == [.biceps])
    // Hamstrings is modelled and credited by nothing: it is a gap and must not be in the comparison.
    let least = Set(assessment.leastCreditedModelledMuscles)
    #expect(!least.contains(.hamstrings))
    #expect(assessment.uncreditedMuscles(excluding: []).contains(.hamstrings))
  }

  @Test("A plan crediting none of the six modelled muscles compares nothing")
  func noModelledMusclesMeansNoComparison() {
    let onlyGlutes = ExerciseID()
    let attribution = AttributionIndex([onlyGlutes: [contribution(.glutes, .direct)]])
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [onlyGlutes])
    ])
    let assessment = plan.assessed(with: attribution)
    #expect(assessment.leastCreditedModelledMuscles.isEmpty)
  }

  // MARK: - Coverage

  @Test("An unattributed movement makes every count a floor")
  func unattributedMakesCountsALowerBound() {
    let f = makeFixture()
    let mystery = ExerciseID()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press, mystery])
    ])
    let assessment = plan.assessed(with: f.attribution)
    #expect(assessment.unattributedMovementCount == 1)
    #expect(assessment.coverage == 0.5)
    #expect(assessment.isLowerBound)
  }

  @Test("A fully attributed plan is not flagged as a lower bound")
  func fullCoverageIsNotAFloor() {
    let f = makeFixture()
    let plan = SplitPlan(days: [
      SplitPlanDay(position: 0, name: "Day 1", movements: [f.press, f.squat])
    ])
    let assessment = plan.assessed(with: f.attribution)
    #expect(assessment.coverage == 1)
    #expect(!assessment.isLowerBound)
  }

  @Test("An empty plan reports full coverage rather than dividing by zero")
  func emptyPlanCoverage() {
    let plan = SplitPlan(days: [SplitPlanDay(position: 0, name: "Day 1", movements: [])])
    let assessment = plan.assessed(with: AttributionIndex([:]))
    #expect(assessment.coverage == 1)
    #expect(!assessment.isLowerBound)
    #expect(assessment.movementCount == 0)
  }

  // MARK: - The refusals, asserted

  /// The disclosure App Review reads must keep saying that no plan is graded and no target exists.
  /// `SetCounting.source.methodology` is held to the same standard for the 0.5 indirect credit, and
  /// for the same reason: a claim the code no longer honours is worse than no claim.
  @Test("The plan disclosure states that there is no target and no grade")
  func disclosureRefusesToGrade() {
    let text = SplitPlanAssessment.source.methodology.lowercased()
    #expect(text.contains("counts movements"))
    #expect(text.contains("never sets"))
    #expect(text.contains("no weekly set target"))
    #expect(text.contains("no plan is graded"))
    // And it names where a direction is available at all.
    let range = try! #require(SplitPlanAssessment.source.validRange).lowercased()
    #expect(range.contains("six muscles"))
  }

  /// "Balanced" is the word this feature must not use. It reads as an evaluation, and the probe
  /// showed there is no computation behind it: a coverage score marks down a well-built PPL and a
  /// bro split identically, for not training necks.
  @Test("No user-facing plan text claims a plan is balanced, optimal or scored")
  func noEvaluativeVocabulary() {
    // The disclosure is *allowed* to use these words to deny them -- "no plan is graded or scored"
    // is the sentence App Review needs to read. Substring matching cannot tell a denial from a
    // claim, so the denials are removed first and the remainder is what gets scanned. Anything the
    // stripping does not recognise is treated as an affirmative use, which is the safe direction.
    let permittedDenials = [
      "no plan is graded or scored",
      "the app cannot tell you a plan is short of one",
    ]
    let banned = ["balanced", "optimal", "score", "grade", "rating", "ideal", "perfect"]
    let source = SplitPlanAssessment.source
    let strings = [source.title, source.methodology, source.validRange ?? ""]

    for text in strings {
      var remainder = text.lowercased()
      for denial in permittedDenials {
        remainder = remainder.replacingOccurrences(of: denial, with: " ")
      }
      for word in banned {
        #expect(
          !remainder.contains(word),
          "plan disclosure uses evaluative word '\(word)' outside a denial"
        )
      }
    }

    // And the denial itself must still be there -- stripping it must not be a way to pass by
    // deleting the sentence.
    #expect(source.methodology.lowercased().contains("no plan is graded or scored"))
  }

  /// The app has no registered finding about training frequency, so `creditingDays` is reportable
  /// and not rankable. This pins the honest half: it is a plain count, with no claim attached.
  @Test("A weekly set target is still unevaluated for every muscle a plan touches")
  func noTargetLeaksIntoPlans() {
    for muscle in Muscle.allCases {
      let target = VolumeAnalyzer.weeklyTarget(for: muscle)
      #expect(target.value == nil, "\(muscle) acquired a weekly target")
      #expect(target.certainty == .unevaluated)
    }
  }

  // MARK: - Descriptive day subtitles

  /// A day may be described by what is on it, and may not be labelled with a training archetype.
  ///
  /// The ranking must be by *credit*, not by how many movements touch a group. A bench press credits
  /// chest directly and triceps indirectly, so a day of one bench press is a chest day -- counting
  /// group touches makes it a tie and hands the lead to whichever name sorts first.
  @Test("A day of one press leads with chest, not with arms")
  func dominantGroupsRankByCredit() {
    let f = makeFixture()
    let day = SplitPlanDay(position: 0, name: "Day 1", movements: [f.press])
    let groups = day.dominantGroups(with: f.attribution)
    #expect(groups.first == .chest, "ranked by group touches rather than by credit: \(groups)")
    // Arms is still there -- the triceps credit is real, just smaller.
    #expect(groups.contains(.arms))
    // The stabiliser credits nothing, so its group must not appear at all from this movement.
    #expect(groups == [.chest, .arms])
  }

  /// The regression this replaces, found by looking at a real dealt day rather than by any test: a
  /// day of rows, bench, leg press and leg curls was described as "Arms · Legs · Shoulders",
  /// omitting chest and back and leading with the least important thing on it.
  @Test("A mixed day leads with the group it actually trains most")
  func mixedDayLeadsWithItsRealEmphasis() {
    let f = makeFixture()
    // Two leg movements against one press: legs must lead.
    let day = SplitPlanDay(
      position: 0, name: "Day 1", movements: [f.squat, f.squat, f.press]
    )
    let groups = day.dominantGroups(with: f.attribution)
    #expect(groups.first == .legs, "expected legs to lead, got \(groups)")
  }

  @Test("A day of unattributed movements describes nothing rather than guessing")
  func dominantGroupsOfUnknownDay() {
    let day = SplitPlanDay(
      position: 0, name: "Day 1", movements: [ExerciseID(), ExerciseID()]
    )
    #expect(day.dominantGroups(with: AttributionIndex([:])).isEmpty)
  }

  /// Ties must break deterministically, or a day's subtitle reshuffles between renders.
  @Test("Equal credit breaks ties by name, so a subtitle does not reshuffle")
  func tiesAreDeterministic() {
    let f = makeFixture()
    let day = SplitPlanDay(position: 0, name: "Day 1", movements: [f.press, f.curl])
    let first = day.dominantGroups(with: f.attribution)
    let second = day.dominantGroups(with: f.attribution)
    #expect(first == second)
  }
}
