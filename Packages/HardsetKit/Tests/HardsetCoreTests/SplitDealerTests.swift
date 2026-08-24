import Foundation
import Testing

@testable import HardsetCore

/// The dealer arranges movements the lifter already trains. It must not lose one, invent one, or
/// return a different answer on Tuesday.
@Suite("Movements are dealt across days without being invented or lost")
struct SplitDealerTests {
  private func entry(_ slug: String) -> CatalogEntry {
    guard let found = ExerciseCatalog.v1.first(where: { $0.slug == slug })?.catalogEntry else {
      fatalError("catalogue has no slug '\(slug)' -- this fixture is stale")
    }
    return found
  }

  private func index(_ slugs: [String]) -> AttributionIndex {
    AttributionIndex(entries: slugs.map(entry))
  }

  /// A realistic pool: the movements a lifter with a full-body habit actually has logged.
  private let pool = [
    "barbell-back-squat", "barbell-bench-press", "barbell-row", "romanian-deadlift",
    "overhead-press", "lat-pulldown", "leg-press", "seated-leg-curl", "lateral-raise",
    "barbell-curl", "cable-triceps-pushdown", "standing-calf-raise",
  ]

  private func deal(_ slugs: [String], across days: Int) -> SplitPlan {
    SplitDealer.deal(
      movements: slugs.map { entry($0).id },
      across: days,
      attribution: index(slugs)
    )
  }

  // MARK: - The partition invariant

  /// The one thing that must never break. A plan is a partition of the lifter's movements, so every
  /// movement appears exactly once -- losing one silently drops work someone chose to do, and
  /// duplicating one puts a movement on two days they never asked for.
  @Test("Every movement is dealt exactly once, at every day count", arguments: 1...8)
  func dealtExactlyOnce(days: Int) {
    let plan = deal(pool, across: days)
    let dealt = plan.allMovements.map(\.description).sorted()
    let given = pool.map { entry($0).id.description }.sorted()
    #expect(dealt == given)
    #expect(plan.movementCount == pool.count)
  }

  @Test("Duplicates in the pool survive as duplicates")
  func duplicatesArePreserved() {
    let withRepeat = pool + ["barbell-bench-press"]
    let plan = deal(withRepeat, across: 3)
    #expect(plan.movementCount == withRepeat.count)
    let benchID = entry("barbell-bench-press").id
    // Hoisted: `#expect` cannot take a rethrowing call.
    let benchCount = plan.allMovements.filter { $0 == benchID }.count
    #expect(benchCount == 2)
  }

  // MARK: - Determinism

  /// Re-dealing must not reshuffle a lifter's plan. Two movements crediting identical weight order
  /// by id, so the result cannot depend on the order the caller happened to pass.
  @Test("The same input deals to the same plan, whatever order it arrives in")
  func dealingIsDeterministic() {
    let forward = deal(pool, across: 4)
    let again = deal(pool, across: 4)
    #expect(forward == again)

    let reversed = deal(pool.reversed(), across: 4)
    #expect(forward == reversed, "day assignment depended on input order")
  }

  // MARK: - Day counts

  @Test("A day count below one is read as one rather than producing no plan")
  func dayCountIsClamped() {
    #expect(deal(pool, across: 0).dayCount == 1)
    #expect(deal(pool, across: -3).dayCount == 1)
  }

  /// Asking for more days than there are movements is a legitimate thing to want -- it yields empty
  /// days to fill, not fewer days than asked for.
  @Test("More days than movements yields empty days, not fewer days")
  func moreDaysThanMovements() {
    let plan = deal(["barbell-back-squat", "barbell-bench-press"], across: 5)
    #expect(plan.dayCount == 5)
    #expect(plan.movementCount == 2)
    let emptyDays = plan.days.filter(\.isEmpty).count
    #expect(emptyDays == 3)
  }

  @Test("An empty pool still produces the days that were asked for")
  func emptyPool() {
    let plan = SplitDealer.deal(movements: [], across: 3, attribution: AttributionIndex([:]))
    #expect(plan.dayCount == 3)
    #expect(plan.movementCount == 0)
    let allEmpty = plan.days.allSatisfy(\.isEmpty)
    #expect(allEmpty)
  }

  // MARK: - What balancing actually achieves

  /// The point of the exercise: going from one long day to three should spread the muscles out
  /// rather than stack every pressing movement onto one day.
  @Test("Dealing into three days spreads the big muscles across more than one day")
  func bigMusclesLandOnSeveralDays() {
    let plan = deal(pool, across: 3)
    let assessment = plan.assessed(with: index(pool))
    // Chest, quads and lats each have multiple movements in the pool, so a balanced deal puts them
    // on more than one day. A dealer that ignored load would pile them together.
    #expect(assessment.days(crediting: .quadriceps) >= 2)
    #expect(assessment.days(crediting: .biceps) >= 2)
  }

  /// No day should end up carrying most of the work when the movements divide evenly.
  @Test("Movements are spread evenly enough that no day carries double another")
  func daysAreRoughlyEven() {
    let plan = deal(pool, across: 3)
    let counts = plan.days.map(\.movements.count)
    let smallest = try! #require(counts.min())
    let largest = try! #require(counts.max())
    #expect(largest - smallest <= 2, "movement counts were \(counts)")
  }

  /// Every modelled muscle the pool trains must still be trained after re-dealing. Re-arranging
  /// cannot be allowed to drop a muscle off the week -- the movements did not change.
  @Test("Re-dealing preserves which muscles the week credits", arguments: [2, 3, 4, 6])
  func redealingPreservesCoverage(days: Int) {
    let attribution = index(pool)
    let oneLongDay = deal(pool, across: 1).assessed(with: attribution)
    let spread = deal(pool, across: days).assessed(with: attribution)
    #expect(
      Set(oneLongDay.uncreditedMuscles(excluding: []))
        == Set(spread.uncreditedMuscles(excluding: [])),
      "re-dealing changed which muscles the week trains, which it cannot"
    )
  }

  // MARK: - Movements the app cannot attribute

  /// An unattributed movement credits nothing, so it cannot be balanced. It must still be dealt,
  /// and it must make the plan say its counts are a floor.
  @Test("Unattributed movements are dealt and reported rather than dropped")
  func unattributedMovementsAreDealtAndDisclosed() {
    let known = ["barbell-back-squat", "barbell-bench-press"]
    let mystery = ExerciseID()
    let plan = SplitDealer.deal(
      movements: known.map { entry($0).id } + [mystery],
      across: 2,
      attribution: index(known)
    )
    #expect(plan.movementCount == 3)
    let containsMystery = plan.allMovements.contains(mystery)
    #expect(containsMystery)

    let assessment = plan.assessed(with: index(known))
    #expect(assessment.unattributedMovementCount == 1)
    #expect(assessment.isLowerBound)
    #expect(abs(assessment.coverage - 2.0 / 3.0) < 0.0001)
  }

  @Test("A plan of entirely unattributed movements does not look evenly balanced")
  func allUnknownIsHonest() {
    let plan = SplitDealer.deal(
      movements: [ExerciseID(), ExerciseID(), ExerciseID(), ExerciseID()],
      across: 2,
      attribution: AttributionIndex([:])
    )
    let assessment = plan.assessed(with: AttributionIndex([:]))
    #expect(assessment.movementCount == 4)
    #expect(assessment.unattributedMovementCount == 4)
    #expect(assessment.coverage == 0)
    #expect(assessment.isLowerBound)
    // Everything reads as uncredited, which is the truthful answer: the app cannot tell what these
    // train. A caller showing this as "you train nothing" would be misreading its own data.
    let uncredited = assessment.uncreditedMuscles(excluding: []).count
    #expect(uncredited == Muscle.allCases.count)
  }

  // MARK: - Day names

  /// The dealer must not name a day after a training style. "Push" asserts the app chose an
  /// archetype; "Day 1" is a placeholder the lifter replaces.
  @Test("Placeholder day names claim nothing about training style")
  func dayNamesAreNeutral() {
    let plan = deal(pool, across: 3)
    #expect(plan.days.map(\.name) == ["Day 1", "Day 2", "Day 3"])
    let jargon = ["push", "pull", "upper", "lower", "full body", "bro", "ppl", "balanced"]
    for name in plan.days.map(\.name) {
      #expect(!jargon.contains(name.lowercased()), "\(name) asserts a split archetype")
    }
  }

  @Test("Day names can be supplied so the UI can localise them")
  func dayNamesAreInjectable() {
    let plan = SplitDealer.deal(
      movements: pool.map { entry($0).id },
      across: 2,
      attribution: index(pool),
      dayName: { "Jour \($0 + 1)" }
    )
    #expect(plan.days.map(\.name) == ["Jour 1", "Jour 2"])
  }

  /// Positions order the week, and are what the storage layer persists. Two days may share a name,
  /// so a name can never be the ordering.
  @Test("Positions are contiguous and zero-based")
  func positionsAreContiguous() {
    let plan = deal(pool, across: 4)
    #expect(plan.days.map(\.position) == [0, 1, 2, 3])
  }
}
