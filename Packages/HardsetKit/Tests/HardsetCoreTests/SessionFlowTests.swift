import Foundation
import Testing

@testable import HardsetCore

@Suite("Finishing asks only when something would be lost")
struct FinishFlowTests {
  private func exercise(_ slots: [SetSlot]) -> ExerciseLogState {
    ExerciseLogState(exerciseID: ExerciseID(), exerciseName: "Leg Press", prior: nil, slots: slots)
  }
  private func logged(_ weight: Double = 100, warmup: Bool = false) -> SetSlot {
    SetSlot(draft: SetEntryDraft(weightKg: weight, reps: 8), isWarmup: warmup, loggedSetID: SetID())
  }
  private func prefilled(warmup: Bool = false) -> SetSlot {
    SetSlot(draft: SetEntryDraft(weightKg: 100, reps: 8), isWarmup: warmup)
  }
  private func empty() -> SetSlot { SetSlot(draft: SetEntryDraft(weightKg: nil, reps: nil)) }
  private func halfTyped() -> SetSlot { SetSlot(draft: SetEntryDraft(weightKg: 100, reps: nil)) }

  @Test("Everything with values was logged: finish without asking")
  func finishes() {
    #expect(FinishFlow.decision(for: [exercise([logged(), logged(), empty()])]) == .finish)
  }

  @Test("Prefilled rows never logged are counted, warm-ups included")
  func countsUnlogged() {
    let decision = FinishFlow.decision(for: [
      exercise([logged(), prefilled(), prefilled(warmup: true)]),
      exercise([prefilled(), empty(), halfTyped()]),
    ])
    #expect(decision == .confirmUnlogged(count: 3))
  }

  @Test("Nothing logged: the only thing to offer is discarding")
  func nothingLogged() {
    #expect(FinishFlow.decision(for: [exercise([prefilled(), prefilled()])]) == .discardEmpty)
    #expect(FinishFlow.decision(for: []) == .discardEmpty)
  }

  @Test("A logged warm-up is logged work: the workout is not empty")
  func warmupCounts() {
    #expect(FinishFlow.decision(for: [exercise([logged(warmup: true)])]) == .finish)
  }

  @Test("The warning names the count, with the noun agreeing")
  func copy() {
    #expect(FinishFlow.unloggedTitle(count: 1) == "1 set wasn't logged and won't be saved")
    #expect(FinishFlow.unloggedTitle(count: 2) == "2 sets weren't logged and won't be saved")
    #expect(FinishFlow.discardTitle == "Nothing was logged")
    #expect(
      FinishFlow.discardMessage == "There's nothing to save, so this workout will be discarded.")
  }
}

@Suite("The current set is the one the lifter is about to do")
struct ActiveSetTests {
  private func slot(logged: Bool) -> SetSlot {
    SetSlot(
      draft: SetEntryDraft(weightKg: 100, reps: 8), loggedSetID: logged ? SetID() : nil)
  }
  private func exercise(_ logged: [Bool]) -> ExerciseLogState {
    ExerciseLogState(
      exerciseID: ExerciseID(), exerciseName: "Lift", prior: nil,
      slots: logged.map { slot(logged: $0) })
  }

  @Test("Nothing logged yet: the first row")
  func first() {
    let session = [exercise([false, false]), exercise([false])]
    #expect(
      ActiveSet.next(in: session, after: nil)
        == ActiveSet(exerciseID: session[0].id, slotID: session[0].slots[0].id))
  }

  @Test("After a log, the next row of the same exercise")
  func nextInExercise() {
    let session = [exercise([true, false, false])]
    #expect(
      ActiveSet.next(in: session, after: session[0].slots[0].id)?.slotID
        == session[0].slots[1].id)
  }

  @Test("After an exercise's last row, the next exercise")
  func nextExercise() {
    let session = [exercise([true, true]), exercise([false])]
    #expect(
      ActiveSet.next(in: session, after: session[0].slots[1].id)?.slotID
        == session[1].slots[0].id)
  }

  @Test("Logging out of order follows the lifter, then wraps to what was skipped")
  func followsTheLifter() {
    let session = [exercise([true, false]), exercise([true, false])]
    #expect(
      ActiveSet.next(in: session, after: session[1].slots[0].id)?.slotID
        == session[1].slots[1].id)
    let done = [exercise([true, false]), exercise([true, true])]
    #expect(
      ActiveSet.next(in: done, after: done[1].slots[1].id)?.slotID == done[0].slots[1].id)
  }

  @Test("A last-logged row that no longer exists falls back to the first open row")
  func unknownLastLogged() {
    let session = [exercise([true, false])]
    #expect(ActiveSet.next(in: session, after: UUID())?.slotID == session[0].slots[1].id)
  }

  @Test("Everything logged: there is no current set")
  func allDone() {
    let session = [exercise([true, true])]
    #expect(ActiveSet.next(in: session, after: session[0].slots[1].id) == nil)
  }
}
