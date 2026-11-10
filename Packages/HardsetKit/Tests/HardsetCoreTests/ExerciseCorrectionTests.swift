import Foundation
import Testing

@testable import HardsetCore

/// Correcting a live exercise: undoing a saved row, removing a spare one, placing warm-ups where
/// they are performed, and restoring last time's rows when the machine is chosen late.
@Suite("A live exercise can be corrected without rewriting what was saved")
struct ExerciseCorrectionTests {
  let now = Date(timeIntervalSince1970: 5_000_000)
  let exercise = ExerciseID()
  let machine = MachineID()

  private func prior(_ sets: [(Double, Int)], machineID: MachineID? = nil) -> PriorPerformance {
    let key = ProgressionKey(exerciseID: exercise, machineID: machineID)
    let records = sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: now) }
    return PriorPerformance(key: key, lastSets: records, heaviestSet: records.first)
  }

  private func snapshot(_ performance: PriorPerformance) -> PriorPerformanceSnapshot {
    PriorPerformanceSnapshot(entries: [performance.key: performance], capturedAt: now)
  }

  private func empty(plannedSets: Int? = nil) -> ExerciseLogState {
    ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      snapshot: .empty(capturedAt: now), plannedSets: plannedSets
    )
  }

  // MARK: - Un-logging

  @Test("Un-logging a row keeps its values and reopens it under a new write identity")
  func unmarkKeepsValues() throws {
    var state = empty()
    let slotID = state.slots[0].id
    #expect(state.slots[0].commandID == slotID)
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: slotID, setID: SetID(), completedAt: now)
    #expect(state.slots[0].loggedAt == now)
    #expect(state.slots[0].loggedMachineID == machine)

    // Hoisted: #expect cannot take a mutating call directly.
    let unmarked = state.unmarkLogged(slotID: slotID)
    #expect(unmarked)
    let slot = state.slots[0]
    #expect(slot.id == slotID)
    #expect(!slot.isLogged)
    #expect(slot.loggedMachineID == nil)
    #expect(slot.loggedAt == nil)
    #expect(slot.draft.weightKg == 100)
    #expect(slot.draft.reps == 8)
    // A re-log must be a new record, never the deleted one resurrected under its old key.
    #expect(slot.commandID != slotID)
    #expect(state.nextUnloggedSlotID == slotID)
    #expect(state.loggedCount == 0)
    // Nothing to undo the second time, and an unknown id is ignored rather than trapping.
    let again = state.unmarkLogged(slotID: slotID)
    let unknown = state.unmarkLogged(slotID: UUID())
    #expect(!again)
    #expect(!unknown)
  }

  @Test("Un-logging the latest set restores the previous saved set as the next-row prefill")
  func unmarkRestoresPreviousPrefill() {
    var state = empty(plannedSets: 2)
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    // An edit to a displayed logged draft must not leak into the prefill after an undo either.
    state.slots[0].draft = SetEntryDraft(weightKg: 999, reps: 1)
    state.slots[1].draft = SetEntryDraft(weightKg: 110, reps: 6)
    state.markLogged(slotID: state.slots[1].id, setID: SetID(), completedAt: now + 60)

    state.unmarkLogged(slotID: state.slots[1].id)
    state.appendSlot()
    #expect(state.slots[2].draft.weightKg == 100)
    #expect(state.slots[2].draft.reps == 8)
  }

  @Test("Un-logging every set falls back to history for the next row")
  func unmarkAllFallsBackToHistory() {
    let history = prior([(90, 10)], machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press", snapshot: snapshot(history)
    )
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.unmarkLogged(slotID: state.slots[0].id)
    state.appendSlot()
    #expect(state.slots[1].draft.weightKg == 90)
    #expect(state.slots[1].draft.reps == 10)
  }

  // MARK: - Removing rows

  @Test("Only an unlogged row can be removed")
  func removeOnlyUnlogged() {
    var state = empty(plannedSets: 3)
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    let logged = state.slots[0].id
    let spare = state.slots[2].id
    state.markLogged(slotID: logged, setID: SetID(), completedAt: now)

    let removedLogged = state.removeSlot(id: logged)
    #expect(!removedLogged)
    #expect(state.slots.count == 3)
    let removedSpare = state.removeSlot(id: spare)
    #expect(removedSpare)
    #expect(state.slots.map(\.id).contains(spare) == false)
    #expect(state.slots.count == 2)
    #expect(state.workingSetCount == 2)
    let removedUnknown = state.removeSlot(id: UUID())
    #expect(!removedUnknown)
  }

  // MARK: - Save times

  @Test("The newest save time is reported, and forgotten when that set is undone")
  func lastLoggedAtFollowsSaves() {
    var state = empty(plannedSets: 2)
    #expect(state.lastLoggedAt == nil)
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.slots[1].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.markLogged(slotID: state.slots[1].id, setID: SetID(), completedAt: now + 90)
    #expect(state.lastLoggedAt == now + 90)
    state.unmarkLogged(slotID: state.slots[1].id)
    #expect(state.lastLoggedAt == now)
    state.unmarkLogged(slotID: state.slots[0].id)
    #expect(state.lastLoggedAt == nil)
  }

  @Test("A recovered exercise reports when its sets were saved")
  func resumeRestoresSaveTimes() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      loggedSets: [
        .init(setID: SetID(), weightKg: 100, reps: 8, isWarmup: false, machineID: machine, completedAt: now),
        .init(setID: SetID(), weightKg: 105, reps: 6, isWarmup: false, machineID: machine, completedAt: now + 120),
      ],
      snapshot: .empty(capturedAt: now)
    )
    #expect(state.slots.map(\.loggedAt) == [now, now + 120])
    #expect(state.lastLoggedAt == now + 120)
  }

  @Test("Undoing a recovered set restores the earlier recovered set as the next-row prefill")
  func unmarkAfterResume() {
    var state = ExerciseLogState.resume(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      loggedSets: [
        .init(setID: SetID(), weightKg: 100, reps: 8, isWarmup: false, machineID: machine, completedAt: now),
        .init(setID: SetID(), weightKg: 105, reps: 6, isWarmup: false, machineID: machine, completedAt: now + 120),
      ],
      snapshot: .empty(capturedAt: now)
    )
    state.unmarkLogged(slotID: state.slots[1].id)
    state.appendSlot()
    #expect(state.slots.last?.draft.weightKg == 100)
  }

  // MARK: - Warm-ups

  @Test("A warm-up is placed before the first unlogged working row and is not prefilled")
  func warmupGoesFirstAndBlank() {
    let history = prior([(100, 10), (105, 8)], machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press", snapshot: snapshot(history)
    )
    state.appendSlot(isWarmup: true)
    #expect(state.slots.map(\.isWarmup) == [true, false, false])
    #expect(state.slots[0].draft.weightKg == nil)
    #expect(state.slots[0].draft.reps == nil)
    #expect(!state.slots[0].draft.isLoggable)
    #expect(state.nextUnloggedSlotID == state.slots[0].id)
    // The working rows keep their own prefills and ordinals.
    #expect(state.slots[1].draft.weightKg == 100)
    #expect(state.workingOrdinal(ofSlotID: state.slots[1].id) == 1)
  }

  @Test("A warm-up added after a working set sits before the next working row")
  func warmupAfterLoggedWorkingSet() {
    var state = empty(plannedSets: 2)
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.appendSlot(isWarmup: true)
    #expect(state.slots.map(\.isWarmup) == [false, true, false])
    // Never seeded from the working set just logged.
    #expect(state.slots[1].draft.weightKg == nil)
  }

  @Test("With every working row logged, a warm-up is appended")
  func warmupAppendedWhenAllWorkingLogged() {
    var state = empty()
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.appendSlot(isWarmup: true)
    #expect(state.slots.map(\.isWarmup) == [false, true])
  }

  @Test("A second warm-up opens at the warm-up just logged, after it")
  func secondWarmupUsesLoggedWarmup() {
    var state = empty()
    state.appendSlot(isWarmup: true)
    state.slots[0].draft = SetEntryDraft(weightKg: 40, reps: 12)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.appendSlot(isWarmup: true)
    #expect(state.slots.map(\.isWarmup) == [true, true, false])
    #expect(state.slots[1].draft.weightKg == 40)
    #expect(state.slots[1].draft.reps == 12)
    #expect(state.nextUnloggedSlotID == state.slots[1].id)
  }

  @Test("A warm-up row has no working set to show as last time")
  func warmupHasNoPreviousSet() {
    let history = prior([(100, 10), (105, 8)], machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press", snapshot: snapshot(history)
    )
    state.appendSlot(isWarmup: true)
    #expect(state.previousSet(forSlotID: state.slots[0].id) == nil)
    #expect(state.previousSet(forSlotID: state.slots[1].id)?.weightKg == 100)
    #expect(state.previousSet(forSlotID: state.slots[2].id)?.weightKg == 105)
    #expect(state.previousSet(forSlotID: UUID()) == nil)
  }

  // MARK: - Choosing the machine late

  @Test("Choosing a machine before any working set restores last time's row count there")
  func machineChoiceTopsUpRows() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Press", snapshot: .empty(capturedAt: now)
    )
    #expect(state.slots.count == 1)
    let history = prior([(100, 10), (105, 8), (110, 6)], machineID: machine)
    state.changeMachine(to: machine, machineName: "Hammer", machineIncrementKg: nil, prior: history)
    #expect(state.slots.count == 3)
    #expect(state.slots.map(\.draft.weightKg) == [100, 105, 110])
  }

  @Test("After a working set is logged, a machine change adds no rows")
  func machineChoiceAfterLoggingAddsNothing() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Press", snapshot: .empty(capturedAt: now)
    )
    state.slots[0].draft = SetEntryDraft(weightKg: 60, reps: 10)
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    let history = prior([(100, 10), (105, 8), (110, 6)], machineID: machine)
    state.changeMachine(to: machine, machineName: "Hammer", machineIncrementKg: nil, prior: history)
    #expect(state.slots.count == 1)
  }

  @Test("A machine change never removes rows the lifter already has")
  func machineChoiceNeverRemovesRows() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Press", snapshot: .empty(capturedAt: now), plannedSets: 4
    )
    let history = prior([(100, 10)], machineID: machine)
    state.changeMachine(to: machine, machineName: "Hammer", machineIncrementKg: nil, prior: history)
    #expect(state.slots.count == 4)
    #expect(state.slots.map(\.draft.weightKg) == [100, 100, 100, 100])
  }
}
