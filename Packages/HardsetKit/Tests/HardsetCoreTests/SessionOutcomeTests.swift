import Foundation
import Testing

@testable import HardsetCore

/// The summary screen is the first thing that ever shows a lifter a personal record, so what it is
/// willing to state matters. These pin the two refusals.
@Suite("A session outcome withholds what it cannot state")
struct SessionOutcomeTests {
  private func state(logged: Int, weightKg: Double = 60, reps: Int = 10) -> ExerciseLogState {
    var slots: [SetSlot] = []
    for i in 0..<logged {
      var slot = SetSlot(draft: SetEntryDraft(weightKg: weightKg, reps: reps))
      slot.loggedSetID = SetID()
      slots.append(slot)
      _ = i
    }
    return ExerciseLogState(
      exerciseID: ExerciseID(), exerciseName: "Chest Press", prior: nil, slots: slots
    )
  }

  @Test("An open session has no duration, however long ago it began")
  func openSessionHasNoDuration() {
    let outcome = SessionOutcome(
      exercises: [state(logged: 2)],
      timeline: SessionTimeline(startedAt: .distantPast),
      records: []
    )
    // Not "however long ago it started" -- that is the 9,749-minute bug.
    #expect(outcome.duration == nil)
  }

  @Test("An implausible span is withheld rather than displayed")
  func implausibleDurationIsWithheld() {
    let start = Date(timeIntervalSince1970: 0)
    let outcome = SessionOutcome(
      exercises: [state(logged: 1)],
      timeline: SessionTimeline(
        startedAt: start, finishedAt: start.addingTimeInterval(20 * 60 * 60)
      ),
      records: []
    )
    #expect(outcome.duration == nil)
  }

  @Test("A real span is reported")
  func plausibleDurationSurvives() {
    let start = Date(timeIntervalSince1970: 0)
    let outcome = SessionOutcome(
      exercises: [state(logged: 3)],
      timeline: SessionTimeline(startedAt: start, finishedAt: start.addingTimeInterval(3_600)),
      records: []
    )
    #expect(outcome.duration == .seconds(3_600))
  }

  @Test("Only movements with a logged set count as done")
  func exerciseCountIgnoresUntouchedMovements() {
    let outcome = SessionOutcome(
      exercises: [state(logged: 2), state(logged: 0), state(logged: 1)],
      timeline: SessionTimeline(startedAt: .now),
      records: []
    )
    // An exercise added and never used is not something the lifter did.
    #expect(outcome.exerciseCount == 2)
  }

  @Test("Totals come from SessionVolume rather than a second count")
  func volumeMatchesTheOneDefinition() {
    let exercises = [state(logged: 3, weightKg: 50, reps: 10)]
    let outcome = SessionOutcome(
      exercises: exercises, timeline: SessionTimeline(startedAt: .now), records: []
    )
    #expect(outcome.volume == SessionVolume(exercises: exercises))
    #expect(outcome.volume.workingSets == 3)
    #expect(!outcome.isEmpty)
  }

  @Test("A session with nothing logged says so")
  func emptyIsEmpty() {
    let outcome = SessionOutcome(
      exercises: [state(logged: 0)], timeline: SessionTimeline(startedAt: .now), records: []
    )
    #expect(outcome.isEmpty)
  }
}
