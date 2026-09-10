import Foundation
import HardsetCore
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

  /// The lifter's own intended set count, and the silence that is the default.
  ///
  /// nil must render as nothing at all. A row that showed "0 sets planned" or a suggested figure
  /// would be the app having a view on volume, which is the one thing the column may not become.
  @Test("An intended set count reads as the lifter's own, and says nothing when unset")
  func targetSetsCopy() {
    func row(_ sets: Int?) -> PlannedMovementRow {
      PlannedMovementRow(
        id: SplitEntryID(rawValue: UUID()),
        exerciseID: ExerciseID(rawValue: UUID()),
        name: "Bench Press",
        creditedMuscleNames: ["Chest"],
        machineID: nil,
        machineName: nil,
        isUnattributed: false,
        targetSets: sets
      )
    }

    #expect(row(nil).targetSetsText == nil)
    #expect(row(0).targetSetsText == nil)
    #expect(row(1).targetSetsText == "1 set planned")
    #expect(row(4).targetSetsText == "4 sets planned")

    // The markup form is only honoured for a LocalizedStringKey; it shipped verbatim once.
    let interpolated = row(3).targetSetsText ?? ""
    #expect(!interpolated.contains("inflect"))
  }

  /// A confirmation has to describe what the button really does.
  ///
  /// This used to pin "replaces the current arrangement" and nothing more, which was true and
  /// materially incomplete: dealing also discarded every machine the lifter had named and reset
  /// their day names to "Day 1". Both are carried across now, so the copy names them — and these
  /// expectations exist so a future change cannot quietly drop either the behaviour or the promise.
  @Test("Confirmation says what dealing moves and what it keeps")
  func confirmationMatchesTheSource() {
    let rearrange = SplitPlannerView.dealConfirmation(.planContents(count: 5))
    #expect(rearrange.contains("onto different days"))
    // Reassures about the things a lifter would actually fear losing.
    #expect(rearrange.contains("logged workouts are not affected"))
    #expect(rearrange.contains("Machines you have named"))
    #expect(rearrange.contains("day names are kept"))

    let seed = SplitPlannerView.dealConfirmation(.loggedHistory(count: 5))
    #expect(seed.contains("have not trained"))
    #expect(seed.contains("day names are kept"))
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

  @Test("Plan building and redistribution are two explicit jobs")
  func planBuilderExplainsItsTwoJobs() {
    #expect(SplitPlannerView.planPurposeText.contains("reusable"))
    #expect(SplitPlannerView.manualBuildButtonText == "Build it myself")
    #expect(SplitPlannerView.historyStartButtonText == "Start from training history")
    #expect(SplitPlannerView.redistributionSectionTitle == "Redistribute exercises")
    #expect(SplitPlannerView.redistributionButtonText(3) == "Redistribute across 3 days")

    let redistribution = SplitPlannerView.redistributionExplanation(movementCount: 8)
    #expect(redistribution.contains("8 movements already in this plan"))
    #expect(redistribution.contains("similar-muscle"))
    #expect(redistribution.contains("does not add or remove"))
    #expect(redistribution.contains("does not decide your sets"))

    let history = SplitPlannerView.historyStartExplanation(movementCount: 8)
    #expect(history.contains("8 movements from completed workouts"))
    #expect(history.contains("does not change completed workouts"))
  }

  @Test("Reducing plan days discloses the history link that is removed")
  func fewerDaysWarnsAboutRemovedDayHistory() {
    let text = SplitPlannerView.redistributionExplanation(
      movementCount: 8, currentDayCount: 4, targetDayCount: 3)
    #expect(text.contains("weights and reps stay"))
    #expect(text.contains("removed day"))
    #expect(text.contains("rotation history"))
  }

  @Test("The builder state never makes history start look like redistribution")
  func planBuilderModeSeparatesTheTwoFlows() {
    #expect(PlanBuilderMode(planMovementCount: 0, historyMovementCount: 8) == .empty(historyCount: 8))
    #expect(PlanBuilderMode(planMovementCount: 0, historyMovementCount: 0) == .empty(historyCount: 0))
    #expect(PlanBuilderMode(planMovementCount: 4, historyMovementCount: 8) == .populated)
  }

  @Test("Adding an empty day keeps the history-based setup flow visible")
  func emptyDayStillUsesEmptyBuilderMode() {
    let emptyDay = PlannedDay(
      id: SplitDayID(), name: "Day 1", subtitle: "Nothing planned", movements: [])

    #expect(SplitPlannerView.builderMode(for: [emptyDay], historyMovementCount: 8) == .empty(historyCount: 8))
  }
}
