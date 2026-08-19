import Foundation
import Testing

@testable import HardsetCore

@Suite("An exercise's rows are built from history, honestly")
struct ExerciseLogStateTests {
  let now = Date(timeIntervalSince1970: 5_000_000)
  let exercise = ExerciseID()
  let machine = MachineID()
  let otherMachine = MachineID()

  private func snapshot(
    key: ProgressionKey,
    sets: [(Double, Int)]
  ) -> PriorPerformanceSnapshot {
    let records = sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: now) }
    let performance = PriorPerformance(
      key: key,
      lastSets: records,
      heaviestSet: records.max { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }
    )
    return PriorPerformanceSnapshot(entries: [key: performance], capturedAt: now)
  }

  @Test("Each row is prefilled from the matching set last time")
  func prefillsPerRow() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    let state = ExerciseLogState.build(
      exerciseID: exercise,
      machineID: machine,
      exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10), (105, 8), (110, 6)])
    )

    #expect(state.slots.count == 3)
    #expect(state.slots.map { $0.draft.weightKg } == [100, 105, 110])
    #expect(state.slots.map { $0.draft.reps } == [10, 8, 6])
    // Hoisted: #expect cannot take a rethrows call directly.
    let allLoggable = state.slots.allSatisfy(\.draft.isLoggable)
    #expect(allLoggable)
    #expect(state.priorNote == nil)
  }

  /// No history must not become an invented "3 × 10". One empty row, not loggable.
  @Test("With no history there is one empty row and nothing is loggable")
  func noHistoryIsEmpty() {
    let state = ExerciseLogState.build(
      exerciseID: exercise,
      exerciseName: "Unknown Lift",
      snapshot: .empty(capturedAt: now)
    )
    #expect(state.slots.count == 1)
    #expect(state.slots[0].draft.weightKg == nil)
    #expect(!state.slots[0].draft.isLoggable)
    #expect(state.priorNote == nil)
  }

  @Test("An explicit plan overrides the historical set count")
  func plannedSetsWins() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    let state = ExerciseLogState.build(
      exerciseID: exercise,
      machineID: machine,
      exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10)]),
      plannedSets: 4
    )
    #expect(state.slots.count == 4)
    // Past the recorded sets, the last one is the honest fallback rather than a guess.
    #expect(state.slots.map { $0.draft.weightKg } == [100, 100, 100, 100])
  }

  /// The differentiator, stated rather than hidden: borrowed history is labelled.
  @Test("History borrowed from another machine is labelled")
  func crossMachineIsLabelled() {
    let otherKey = ProgressionKey(exerciseID: exercise, machineID: otherMachine)
    let state = ExerciseLogState.build(
      exerciseID: exercise,
      machineID: machine,
      exerciseName: "Leg Press",
      snapshot: snapshot(key: otherKey, sets: [(80, 10)])
    )
    #expect(state.priorNote == "From another machine")
    #expect(state.slots[0].draft.weightKg == 80)
  }

  @Test("A first session on new equipment can refuse to borrow")
  func canRefuseToBorrow() {
    let otherKey = ProgressionKey(exerciseID: exercise, machineID: otherMachine)
    let state = ExerciseLogState.build(
      exerciseID: exercise,
      machineID: machine,
      exerciseName: "Leg Press",
      snapshot: snapshot(key: otherKey, sets: [(80, 10)]),
      allowingOtherMachines: false
    )
    #expect(state.priorNote == nil)
    #expect(state.slots[0].draft.weightKg == nil)
  }

  // MARK: - Progress through the exercise

  @Test("The next unlogged row is what the log control acts on")
  func nextUnloggedSlot() throws {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10), (100, 10)])
    )
    let first = try #require(state.nextUnloggedSlotID)
    #expect(first == state.slots[0].id)

    state.markLogged(slotID: first, setID: SetID())
    #expect(state.loggedCount == 1)
    #expect(state.nextUnloggedSlotID == state.slots[1].id)

    state.markLogged(slotID: state.slots[1].id, setID: SetID())
    #expect(state.loggedCount == 2)
    #expect(state.nextUnloggedSlotID == nil)
  }

  @Test("A stale slot id is ignored rather than trapping")
  func staleSlotIDIsIgnored() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Leg Press", snapshot: .empty(capturedAt: now)
    )
    state.markLogged(slotID: UUID(), setID: SetID())
    #expect(state.loggedCount == 0)
  }

  /// Within a session the honest suggestion is what you just did, not last week.
  @Test("A new row opens at what was just logged")
  func appendUsesThisSession() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10)])
    )
    // The user actually did more than history suggested.
    state.slots[0].draft.weightKg = 120
    state.slots[0].draft.reps = 6
    state.markLogged(slotID: state.slots[0].id, setID: SetID())

    state.appendSlot()
    #expect(state.slots.count == 2)
    #expect(state.slots[1].draft.weightKg == 120)
    #expect(state.slots[1].draft.reps == 6)
  }

  @Test("Before anything is logged, a new row falls back to history")
  func appendFallsBackToHistory() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10), (105, 8)])
    )
    state.appendSlot()
    // Index 2 is past the recorded sets, so the last recorded set is the fallback.
    #expect(state.slots[2].draft.weightKg == 105)
  }

  /// A warm-up load must never become a working-set suggestion.
  @Test("A logged warm-up does not seed the next row")
  func warmupDoesNotSeed() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10)])
    )
    state.slots[0].isWarmup = true
    state.slots[0].draft.weightKg = 40
    state.slots[0].draft.reps = 15
    state.markLogged(slotID: state.slots[0].id, setID: SetID())

    state.appendSlot()
    // Falls back to history rather than to the 40 kg warm-up.
    #expect(state.slots[1].draft.weightKg == 100)
  }

  @Test("An empty state holds no database handle and stays a value")
  func isAValue() {
    let a = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Leg Press", snapshot: .empty(capturedAt: now)
    )
    #expect(a == a)
    #expect(a.progressionKey == ProgressionKey(exerciseID: exercise, machineID: nil))
  }
}
