import Foundation
import Testing

@testable import HardsetCore

@Suite("Recovering an interrupted workout reconstructs, never guesses")
struct ResumeTests {
  let now = Date(timeIntervalSince1970: 8_000_000)
  let exercise = ExerciseID()
  let machine = MachineID()

  private func snapshot(sets: [(Double, Int)]) -> PriorPerformanceSnapshot {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    let records = sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: now) }
    return PriorPerformanceSnapshot(
      entries: [
        key: PriorPerformance(key: key, lastSets: records, heaviestSet: records.last)
      ],
      capturedAt: now
    )
  }

  private func logged(
    _ sets: [(Double, Int, Bool)]
  ) -> [ExerciseLogState.LoggedSetSummary] {
    sets.map {
      .init(setID: SetID(), weightKg: $0.0, reps: $0.1, isWarmup: $0.2)
    }
  }

  @Test("Written sets come back exactly as logged, and already ticked")
  func writtenSetsReturn() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: logged([(120, 6, false), (115, 6, false)]),
      snapshot: snapshot(sets: [(100, 10)]),
      plannedSets: 3
    )

    #expect(state.slots.count == 3)
    #expect(state.slots[0].isLogged)
    #expect(state.slots[1].isLogged)
    #expect(!state.slots[2].isLogged)
    // The written values win over what history would have suggested.
    #expect(state.slots[0].draft.weightKg == 120)
    #expect(state.slots[1].draft.weightKg == 115)
    #expect(state.loggedCount == 2)
  }

  @Test("The remaining rows are open and prefilled from history")
  func remainingRowsArePrefilled() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: logged([(100, 10, false)]),
      snapshot: snapshot(sets: [(100, 10), (105, 8), (110, 6)]),
      plannedSets: 3
    )
    #expect(state.slots.count == 3)
    #expect(state.slots[1].draft.weightKg == 105)
    #expect(state.slots[2].draft.weightKg == 110)
    let openAreLoggable = state.slots[1...].allSatisfy(\.draft.isLoggable)
    #expect(openAreLoggable)
  }

  /// The written record wins over the plan. Performing more than planned must not discard work.
  @Test("More sets performed than planned keeps all of them")
  func extraSetsSurvive() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: logged([(100, 10, false), (100, 9, false), (100, 8, false), (100, 7, false)]),
      snapshot: snapshot(sets: [(100, 10)]),
      plannedSets: 3
    )
    #expect(state.slots.count == 4)
    #expect(state.loggedCount == 4)
  }

  @Test("A logged warm-up returns as a warm-up and does not consume a working slot")
  func warmupsSurvive() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: logged([(40, 15, true), (100, 8, false)]),
      snapshot: snapshot(sets: [(100, 8)]),
      plannedSets: 3
    )
    // One warm-up plus one working set logged, so two working rows remain open: 4 total.
    #expect(state.slots.count == 4)
    #expect(state.slots[0].isWarmup)
    #expect(state.slots[0].isLogged)
    #expect(state.workingSetCount == 3)
    #expect(state.workingOrdinal(ofSlotID: state.slots[1].id) == 1)
  }

  @Test("Nothing logged yet resumes as a fresh exercise")
  func nothingLoggedIsFresh() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: [],
      snapshot: snapshot(sets: [(100, 10)]),
      plannedSets: 2
    )
    #expect(state.slots.count == 2)
    #expect(state.loggedCount == 0)
    #expect(state.slots[0].draft.weightKg == 100)
  }

  @Test("With no plan, the written sets alone define the exercise")
  func noPlanUsesWhatWasWritten() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: logged([(100, 10, false), (100, 8, false)]),
      snapshot: .empty(capturedAt: now)
    )
    #expect(state.slots.count == 2)
    #expect(state.loggedCount == 2)
  }

  /// A resumed exercise must still say where a borrowed suggestion came from.
  @Test("Borrowed history is still labelled after a resume")
  func borrowedHistoryStillLabelled() {
    let otherMachine = MachineID()
    let otherKey = ProgressionKey(exerciseID: exercise, machineID: otherMachine)
    let records = [PriorSetRecord(weightKg: 80, reps: 10, completedAt: now)]
    let snapshot = PriorPerformanceSnapshot(
      entries: [otherKey: PriorPerformance(key: otherKey, lastSets: records, heaviestSet: records.first)],
      capturedAt: now
    )

    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      loggedSets: [], snapshot: snapshot, plannedSets: 2
    )
    #expect(state.priorNote == "From another machine")
    #expect(state.slots[0].draft.weightKg == 80)
  }
}
