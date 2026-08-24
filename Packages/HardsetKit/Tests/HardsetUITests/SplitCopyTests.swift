import Foundation
import Testing

@testable import HardsetUI

/// The planner's words, pinned.
///
/// Two reasons this suite exists. Plurals in this codebase are spelled with a ternary because
/// `^[\(n) day](inflect: true)` is only interpreted for a `LocalizedStringKey` and shipped as
/// visible markup once already -- so "1 days" is a regression a test should catch, not a screenshot.
/// And "deal" means two different things depending on whether the plan already has movements; the
/// footnote is the only thing that tells the lifter which, so it has to stay accurate.
@Suite("The planner says what it means, and counts in plain English")
struct SplitCopyTests {

  // MARK: - Plurals

  @Test("Day counts read as English, not as a template")
  func dayCountsArePluralised() {
    #expect(SplitPlannerView.dayCountText(1) == "1 day")
    #expect(SplitPlannerView.dayCountText(2) == "2 days")
    #expect(SplitPlannerView.dayCountText(0) == "0 days")
  }

  @Test("Movement counts read as English too")
  func movementCountsArePluralised() {
    #expect(SplitPlannerView.movementCountText(1) == "1 movement")
    #expect(SplitPlannerView.movementCountText(7) == "7 movements")
  }

  /// The bug this catches directly: the stepper and the button both read "1 days" on a one-day plan.
  @Test("No copy contains a bare plural after the number one")
  func noSingularPluralMismatch() {
    let strings = [
      SplitPlannerView.dayCountText(1),
      SplitPlannerView.movementCountText(1),
      SplitPlannerView.dealButtonText(1),
      SplitPlannerView.dealFootnote(.planContents(count: 1)),
      SplitPlannerView.dealFootnote(.loggedHistory(count: 1)),
      SplitPlannerView.arrangementText(
        PlanCoverageSummary(
          movementCount: 1, dayCount: 1, uncreditedMuscleNames: [],
          leastCreditedModelledNames: [], isLowerBound: false
        )
      ),
    ]
    for text in strings {
      #expect(!text.contains("1 days"), "\"\(text)\" reads as a template, not English")
      #expect(!text.contains("1 movements"), "\"\(text)\" reads as a template, not English")
    }
  }

  /// Inflection markup is only interpreted for a `LocalizedStringKey`. In an interpolated `String` it
  /// reaches the screen verbatim, which this app has already shipped once.
  @Test("No copy carries inflection markup that would render literally")
  func noInflectionMarkup() {
    let strings = [
      SplitPlannerView.dayCountText(3),
      SplitPlannerView.dealButtonText(3),
      SplitPlannerView.dealFootnote(.planContents(count: 3)),
      SplitPlannerView.dealFootnote(.loggedHistory(count: 3)),
      SplitPlannerView.dealFootnote(.planContents(count: 0)),
      SplitPlannerView.dealConfirmation(.planContents(count: 3)),
      SplitPlannerView.dealConfirmation(.loggedHistory(count: 3)),
    ]
    for text in strings {
      #expect(!text.contains("^["), "\"\(text)\" contains inflection markup")
      #expect(!text.contains("inflect:"), "\"\(text)\" contains inflection markup")
    }
  }

  // MARK: - Which movements a deal uses

  /// Found by running the screen: an empty plan's own empty state says "deal the movements you
  /// already train", and the button read from the empty plan, so it did nothing. The two sources are
  /// now distinct and the footnote is what tells the lifter which one applies.
  @Test("An empty plan says it will start from what has been logged")
  func emptyPlanFootnoteNamesHistory() {
    let text = SplitPlannerView.dealFootnote(.loggedHistory(count: 12))
    #expect(text.contains("12 movements"))
    #expect(text.contains("logged"))
    // And it must promise not to invent movements, which is the actual constraint.
    #expect(text.contains("adds nothing you have not trained"))
  }

  @Test("A populated plan says it will rearrange what is in it")
  func populatedPlanFootnoteNamesThePlan() {
    let text = SplitPlannerView.dealFootnote(.planContents(count: 12))
    #expect(text.contains("12 movements"))
    #expect(text.contains("already in this plan"))
    // The refusal, restated where the lifter is about to act on it.
    #expect(text.contains("does not add movements"))
    #expect(text.contains("decide how many sets"))
  }

  /// A plan with nothing in it and no history is a third case, and it must not promise a deal it
  /// cannot perform.
  @Test("With nothing to deal, the copy asks for input rather than promising a deal")
  func nothingToDealSaysSo() {
    let text = SplitPlannerView.dealFootnote(.planContents(count: 0))
    #expect(text.contains("Add a movement"))
    #expect(!text.contains("Spreads the"))
  }

  @Test("Confirmation says which movements are about to be arranged")
  func confirmationMatchesTheSource() {
    let rearrange = SplitPlannerView.dealConfirmation(.planContents(count: 5))
    #expect(rearrange.contains("replaces the current arrangement"))
    // Reassures about the thing a lifter would actually fear losing.
    #expect(rearrange.contains("logged workouts are not affected"))

    let seed = SplitPlannerView.dealConfirmation(.loggedHistory(count: 5))
    #expect(seed.contains("have not trained"))
  }

  // MARK: - The refusals, in the words the lifter reads

  /// "Balanced" is the word this feature must not use, and the planner is where it would creep in.
  @Test("No planner copy claims a plan is balanced, optimal or scored")
  func noEvaluativeVocabulary() {
    let banned = ["balanced", "optimal", "score", "rating", "ideal", "perfect", "should"]
    let strings = [
      SplitPlannerView.dealButtonText(4),
      SplitPlannerView.dealFootnote(.planContents(count: 4)),
      SplitPlannerView.dealFootnote(.loggedHistory(count: 4)),
      SplitPlannerView.dealFootnote(.planContents(count: 0)),
      SplitPlannerView.dealConfirmation(.planContents(count: 4)),
      SplitPlannerView.dealConfirmation(.loggedHistory(count: 4)),
      SplitPlannerView.arrangementText(
        PlanCoverageSummary(
          movementCount: 4, dayCount: 2, uncreditedMuscleNames: ["Neck"],
          leastCreditedModelledNames: ["Hamstrings"], isLowerBound: true
        )
      ),
    ]
    for text in strings {
      let lowered = text.lowercased()
      for word in banned {
        #expect(!lowered.contains(word), "\"\(text)\" uses evaluative word '\(word)'")
      }
    }
  }

  @Test("The arrangement line states movements and days and nothing else")
  func arrangementTextIsAReadback() {
    let text = SplitPlannerView.arrangementText(
      PlanCoverageSummary(
        movementCount: 12, dayCount: 3, uncreditedMuscleNames: [],
        leastCreditedModelledNames: [], isLowerBound: false
      )
    )
    #expect(text == "12 movements across 3 days.")
  }
}
