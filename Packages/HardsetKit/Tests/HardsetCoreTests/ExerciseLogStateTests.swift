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

  @Test("Next-set prefill follows save order when rows are logged out of display order")
  func appendUsesMostRecentlySavedRow() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      snapshot: .empty(capturedAt: now), plannedSets: 2
    )
    state.slots[1].draft = SetEntryDraft(weightKg: 150, reps: 6)
    state.markLogged(slotID: state.slots[1].id, setID: SetID())
    state.slots[0].draft = SetEntryDraft(weightKg: 120, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID())
    state.appendSlot()
    #expect(state.slots[2].draft.weightKg == 120)
    #expect(state.slots[2].draft.reps == 8)
  }

  @Test("Editing a displayed logged draft cannot rewrite the values used for next-set prefill")
  func appendUsesCapturedLoggedValues() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      snapshot: .empty(capturedAt: now)
    )
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: SetID())
    state.slots[0].draft = SetEntryDraft(weightKg: 999, reps: 1)
    state.appendSlot()
    #expect(state.slots[1].draft.weightKg == 100)
    #expect(state.slots[1].draft.reps == 8)
  }

  @Test("Returning to equipment reuses its own latest working set and skips warm-ups")
  func rememberedLoadsStayPerEquipment() {
    var state = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Press", snapshot: .empty(capturedAt: now)
    )
    let equipment: [MachineID?] = [machine, nil, otherMachine]
    let weights = [100.0, 20.0, 50.0]
    for (index, machineID) in equipment.enumerated() {
      state.changeMachine(to: machineID, machineName: nil, machineIncrementKg: nil, prior: nil)
      state.appendSlot()
      let slot = state.slots.count - 1
      state.slots[slot].draft = SetEntryDraft(weightKg: weights[index], reps: 8)
      state.markLogged(slotID: state.slots[slot].id, setID: SetID())
    }
    for (index, machineID) in equipment.enumerated() {
      state.changeMachine(to: machineID, machineName: nil, machineIncrementKg: nil, prior: nil)
      state.appendSlot()
      #expect(state.slots.last?.draft.weightKg == weights[index])
    }
    let warmup = state.slots.count - 1
    state.slots[warmup].isWarmup = true
    state.slots[warmup].draft = SetEntryDraft(weightKg: 5, reps: 15)
    state.markLogged(slotID: state.slots[warmup].id, setID: SetID())
    state.appendSlot()
    #expect(state.slots.last?.draft.weightKg == 50)
  }

  @Test("A repeated logged callback cannot move a written set to another machine")
  func repeatedMarkPreservesEquipment() {
    let key = ProgressionKey(exerciseID: exercise, machineID: otherMachine)
    let prior = PriorPerformance(key: key,
      lastSets: [PriorSetRecord(weightKg: 30, reps: 10, completedAt: now)], heaviestSet: nil)
    var state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      snapshot: .empty(capturedAt: now)
    )
    let original = SetID()
    state.slots[0].draft = SetEntryDraft(weightKg: 100, reps: 8)
    state.markLogged(slotID: state.slots[0].id, setID: original)
    state.changeMachine(to: otherMachine, machineName: "Other press", machineIncrementKg: nil, prior: prior)
    state.markLogged(slotID: state.slots[0].id, setID: SetID())
    #expect(state.slots[0].loggedSetID == original)
    #expect(state.slots[0].loggedMachineID == machine)
    state.appendSlot()
    #expect(state.slots[1].draft.weightKg == 30)
  }

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

  @Test("A negative set index asks for nothing rather than the final set")
  func negativeIndexHasNoSuggestion() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    let state = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press",
      snapshot: snapshot(key: key, sets: [(100, 10), (105, 8)])
    )
    #expect(state.suggestion(forSetIndex: -1) == nil)
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

  @Test("Machine switch does not leak previous machine load when appending slot")
  func machineSwitchDoesNotLeakLoad() {
    let machineA = MachineID()
    let machineB = MachineID()
    let keyA = ProgressionKey(exerciseID: exercise, machineID: machineA)
    let keyB = ProgressionKey(exerciseID: exercise, machineID: machineB)
    let priorB = PriorPerformance(
      key: keyB,
      lastSets: [PriorSetRecord(weightKg: 30, reps: 10, completedAt: now)],
      heaviestSet: nil
    )
    let snap = PriorPerformanceSnapshot(
      entries: [
        keyA: PriorPerformance(key: keyA, lastSets: [PriorSetRecord(weightKg: 100, reps: 8, completedAt: now)], heaviestSet: nil),
        keyB: priorB
      ],
      capturedAt: now
    )

    var state = ExerciseLogState.build(
      exerciseID: exercise,
      machineID: machineA,
      exerciseName: "Chest Press",
      snapshot: snap
    )
    state.slots[0].draft.weightKg = 100
    state.slots[0].draft.reps = 8
    state.markLogged(slotID: state.slots[0].id, setID: SetID())

    // Switch to machine B
    state.changeMachine(
      to: machineB,
      machineName: "Dumbbells",
      machineIncrementKg: 2.0,
      prior: priorB
    )

    // Appending a slot on machine B must use machine B's prior (30 kg), not machine A's 100 kg.
    state.appendSlot()
    #expect(state.slots.count == 2)
    #expect(state.slots[1].draft.weightKg == 30)
    #expect(state.slots[1].draft.reps == 10)
  }

  @Test("An empty state holds no database handle and stays a value")
  func isAValue() {
    let a = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Leg Press", snapshot: .empty(capturedAt: now)
    )
    #expect(a == a)
    #expect(a.progressionKey == ProgressionKey(exerciseID: exercise, machineID: nil))
  }

  // MARK: - Double-progression targets and beat-last-time marks

  private let range = RepRange(lower: 8, upper: 12)!

  private func state(
    sets: [(Double, Int)], range: RepRange? = nil, onMachine: MachineID? = nil,
    historyOn: MachineID? = nil, increment: Double? = nil, unit: WeightUnit = .kilograms,
    addsLoad: Bool = true, plannedSets: Int? = nil
  ) -> ExerciseLogState {
    let current = onMachine ?? machine
    return ExerciseLogState.build(
      exerciseID: exercise,
      machineID: current,
      exerciseName: "Chest Press",
      machineIncrementKg: increment,
      snapshot: snapshot(key: ProgressionKey(exerciseID: exercise, machineID: historyOn ?? current), sets: sets),
      plannedSets: plannedSets,
      repRange: range,
      weightUnit: unit,
      addsLoad: addsLoad
    )
  }

  @Test("A rep range with history on this machine prefills each row with its target")
  func rangeWithHistoryPrefillsTargets() {
    let built = state(sets: [(40, 10), (40, 9)], range: range, increment: 2.5)

    #expect(built.slots.map { $0.draft.weightKg } == [40, 40])
    #expect(built.slots.map { $0.draft.reps } == [11, 10])
    #expect(built.slots.allSatisfy { $0.draft.target != nil })
    #expect(built.slots.map { $0.draft.target?.rule } == [.addRep, .addRep])
    // The history that produced the target is still there, as what last time actually was.
    #expect(built.slots.map { $0.draft.suggestion?.reps } == [10, 9])
    #expect(built.previousSet(forSlotID: built.slots[0].id)?.reps == 10)
  }

  @Test("History borrowed from another machine gives no target, because it is not this machine's")
  func otherMachineHistoryGivesNoTargets() {
    let built = ExerciseLogState.build(
      exerciseID: exercise,
      machineID: machine,
      exerciseName: "Chest Press",
      snapshot: snapshot(
        key: ProgressionKey(exerciseID: exercise, machineID: otherMachine), sets: [(40, 10)]),
      repRange: range
    )

    #expect(built.priorNote != nil)
    #expect(built.slots[0].draft.target == nil)
    // Prefilled exactly as it was before ranges existed.
    #expect(built.slots[0].draft.weightKg == 40)
    #expect(built.slots[0].draft.reps == 10)
  }

  @Test("Without a rep range the prefill is today's, with no target")
  func noRangeKeepsTodaysPrefill() {
    let built = state(sets: [(40, 10), (40, 9)])

    #expect(built.slots.map { $0.draft.reps } == [10, 9])
    #expect(built.slots.allSatisfy { $0.draft.target == nil })
  }

  @Test("A range with no history on the machine still has nothing to build a target on")
  func rangeWithoutHistoryHasNoTarget() {
    let built = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Chest Press",
      snapshot: .empty(capturedAt: now), repRange: range
    )

    #expect(built.slots.count == 1)
    #expect(built.slots[0].draft.target == nil)
    #expect(built.slots[0].draft.weightKg == nil)
  }

  @Test("Moving to a machine with history recomputes the open rows' targets")
  func changeMachineRecomputesTargets() {
    var built = state(sets: [], range: range, plannedSets: 2)
    #expect(built.slots.allSatisfy { $0.draft.target == nil })
    let newKey = ProgressionKey(exerciseID: exercise, machineID: otherMachine)
    let newPrior = PriorPerformance(
      key: newKey,
      lastSets: [
        PriorSetRecord(weightKg: 40, reps: 10, completedAt: now),
        PriorSetRecord(weightKg: 40, reps: 9, completedAt: now),
      ],
      heaviestSet: nil
    )

    built.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: 2.5, prior: newPrior)

    #expect(built.slots.map { $0.draft.reps } == [11, 10])
    #expect(built.slots.allSatisfy { $0.draft.target != nil })

    built.changeMachine(
      to: machine, machineName: nil, machineIncrementKg: nil, prior: newPrior,
      priorNote: "From another machine")
    #expect(built.slots.allSatisfy { $0.draft.target == nil })
    #expect(built.slots.map { $0.draft.reps } == [10, 9])
  }

  @Test("The assumed step is one plate in the lifter's own unit")
  func assumedStepFollowsUnit() {
    let kilograms = state(sets: [(40, 12), (40, 12)], range: range, unit: .kilograms)
    let pounds = state(sets: [(40, 12), (40, 12)], range: range, unit: .pounds)

    #expect(kilograms.slots[0].draft.weightKg == 42.5)
    #expect(abs((pounds.slots[0].draft.weightKg ?? 0) - (40 + 2.26796185)) < 1e-6)
    #expect(kilograms.slots[0].draft.reps == 8)
    if case let .addLoad(_, assumed)? = pounds.slots[0].draft.target?.rule {
      #expect(assumed)
    } else {
      Issue.record("expected an add-load target")
    }
  }

  @Test("A bodyweight movement's target only ever adds reps")
  func bodyweightTargetsAddRepsOnly() {
    let built = state(sets: [(0, 12), (0, 12)], range: range, addsLoad: false)

    #expect(built.slots.map { $0.draft.weightKg } == [0, 0])
    #expect(built.slots.map { $0.draft.reps } == [13, 13])
  }

  @Test("A logged set that beats the same set last time is compared with it")
  func comparisonAfterLogging() {
    var built = state(sets: [(40, 10), (40, 9)], range: range)
    let first = built.slots[0].id
    built.markLogged(slotID: first, setID: SetID(), completedAt: now)

    #expect(built.comparison(forSlotID: first) == .beat(addedKg: 0, addedReps: 1))
    // A row that has not been logged says nothing.
    #expect(built.comparison(forSlotID: built.slots[1].id) == nil)
  }

  @Test("A set that fell short, or matched, is compared honestly")
  func comparisonMatchedAndShort() {
    var built = state(sets: [(40, 10), (40, 10)], range: range)
    built.slots[0].draft.reps = 10
    built.slots[1].draft.reps = 9
    built.markLogged(slotID: built.slots[0].id, setID: SetID(), completedAt: now)
    built.markLogged(slotID: built.slots[1].id, setID: SetID(), completedAt: now)

    #expect(built.comparison(forSlotID: built.slots[0].id) == .matched)
    #expect(built.comparison(forSlotID: built.slots[1].id) == nil)
  }

  @Test("A warm-up is never compared with a working set")
  func warmupHasNoComparison() {
    var built = state(sets: [(40, 10)], range: range)
    built.appendSlot(isWarmup: true)
    let warmup = built.slots.first { $0.isWarmup }!
    built.slots[built.slots.firstIndex { $0.id == warmup.id }!].draft = SetEntryDraft(weightKg: 40, reps: 12)
    built.markLogged(slotID: warmup.id, setID: SetID(), completedAt: now)

    #expect(built.comparison(forSlotID: warmup.id) == nil)
  }

  @Test("Nothing is compared against another machine's history")
  func comparisonNeedsThisMachinesHistory() {
    var built = ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Chest Press",
      snapshot: snapshot(
        key: ProgressionKey(exerciseID: exercise, machineID: otherMachine), sets: [(40, 10)]),
      repRange: range
    )
    built.markLogged(slotID: built.slots[0].id, setID: SetID(), completedAt: now)

    #expect(built.comparison(forSlotID: built.slots[0].id) == nil)
  }

  @Test("A set done on the previous machine is not compared with the new machine's history")
  func comparisonIgnoresSetsFromBeforeAMachineChange() {
    var built = state(sets: [(40, 10), (40, 10)], range: range)
    built.markLogged(slotID: built.slots[0].id, setID: SetID(), completedAt: now)
    let doneBefore = built.slots[0].id
    let newPrior = PriorPerformance(
      key: ProgressionKey(exerciseID: exercise, machineID: otherMachine),
      lastSets: [PriorSetRecord(weightKg: 30, reps: 8, completedAt: now)], heaviestSet: nil)

    built.changeMachine(
      to: otherMachine, machineName: nil, machineIncrementKg: nil, prior: newPrior)

    #expect(built.comparison(forSlotID: doneBefore) == nil)
  }

  // MARK: - A machine change and what the lifter already did or typed

  private func history(_ machineID: MachineID, _ sets: [(Double, Int)]) -> PriorPerformance {
    PriorPerformance(
      key: ProgressionKey(exerciseID: exercise, machineID: machineID),
      lastSets: sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: now) },
      heaviestSet: nil)
  }

  /// A block on `machine` with 95 x 8 history, three rows open.
  private func threeRowBlock() -> ExerciseLogState {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    return ExerciseLogState.build(
      exerciseID: exercise, machineID: machine, exerciseName: "Press",
      snapshot: snapshot(key: key, sets: [(95, 8), (95, 8), (95, 8)]), plannedSets: 3)
  }

  @Test("A machine change keeps what the lifter typed in an open row, and re-prefills the rest")
  func machineChangeKeepsTypedRow() {
    var state = threeRowBlock()
    // Typed, not logged: this is the lifter's own number, and nothing in history knows about it.
    state.slots[1].draft.weightKg = 87.5
    state.slots[1].draft.reps = 6

    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: history(otherMachine, [(60, 10), (60, 10), (60, 10)]))

    #expect(state.slots[1].draft.weightKg == 87.5)
    #expect(state.slots[1].draft.reps == 6)
    #expect(state.slots[1].draft.isLoggable)
    // The rows still holding their own prefill follow the machine, as before.
    #expect(state.slots[0].draft.weightKg == 60)
    #expect(state.slots[2].draft.weightKg == 60)
  }

  @Test("A typed row survives a change to a machine that has no history at all")
  func machineChangeKeepsTypedRowWithoutHistory() {
    var state = threeRowBlock()
    state.slots[1].draft.weightKg = 87.5
    state.slots[1].draft.reps = 6

    state.changeMachine(to: otherMachine, machineName: "Other", machineIncrementKg: nil, prior: nil)

    #expect(state.slots[1].draft.weightKg == 87.5)
    #expect(state.slots[1].draft.reps == 6)
    #expect(state.slots[1].draft.isLoggable)
    // An untouched row has nothing honest to hold, so it empties rather than keep the old load.
    #expect(state.slots[0].draft.weightKg == nil)
    #expect(!state.slots[0].draft.isLoggable)
  }

  @Test("A row with only one field typed is kept whole, not mixed with the new machine's numbers")
  func machineChangeKeepsPartlyTypedRow() {
    var state = threeRowBlock()
    state.slots[2].draft.reps = 5

    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: history(otherMachine, [(60, 10), (60, 10), (60, 10)]))

    #expect(state.slots[2].draft.reps == 5)
    #expect(state.slots[2].draft.weightKg == 95)
  }

  @Test("A typed row is kept across a change however the number got there, including a stepper")
  func machineChangeKeepsSteppedRow() {
    var state = threeRowBlock()
    state.slots[0].draft.weightKg = 97.5

    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: history(otherMachine, [(60, 10), (60, 10), (60, 10)]))

    #expect(state.slots[0].draft.weightKg == 97.5)
  }

  @Test("An undone set's values are the lifter's and survive a machine change")
  func machineChangeKeepsUndoneRow() {
    var state = threeRowBlock()
    state.slots[0].draft.weightKg = 100
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)
    state.unmarkLogged(slotID: state.slots[0].id)

    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: history(otherMachine, [(60, 10)]))

    #expect(state.slots[0].draft.weightKg == 100)
  }

  @Test("Returning to a machine used today prefills open rows from what was just done on it")
  func returnToMachineUsesTodaysSet() {
    let priorHere = history(machine, [(95, 8), (95, 8), (95, 8)])
    var state = threeRowBlock()
    // The lifter hand-typed 100 x 8 and logged it, so it is not any history's number.
    state.slots[0].draft.weightKg = 100
    state.markLogged(slotID: state.slots[0].id, setID: SetID(), completedAt: now)

    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: history(otherMachine, [(60, 10), (60, 10), (60, 10)]))
    state.changeMachine(to: machine, machineName: "Press", machineIncrementKg: nil, prior: priorHere)

    // Same answer as "Add set" gives on this machine, so the card does not say two things.
    #expect(state.slots[1].draft.weightKg == 100)
    #expect(state.slots[1].draft.reps == 8)
    #expect(state.slots[2].draft.weightKg == 100)
    state.appendSlot()
    #expect(state.slots[3].draft.weightKg == 100)
    // The "Last time" column is still last time's, never today's.
    #expect(state.previousSet(forSlotID: state.slots[1].id)?.weightKg == 95)
  }

  @Test("A machine trained on today is not called borrowed when the lifter comes back to it")
  func machineWithSetsTodayIsNeverBorrowed() {
    let borrowed = history(machine, [(95, 8), (95, 8)])
    var state = threeRowBlock()
    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: borrowed, priorNote: "From another machine")
    #expect(state.priorNote == "From another machine")
    state.slots[1].draft = SetEntryDraft(weightKg: 70, reps: 10)
    state.markLogged(slotID: state.slots[1].id, setID: SetID(), completedAt: now)

    state.changeMachine(to: machine, machineName: "Press", machineIncrementKg: nil,
      prior: history(machine, [(95, 8), (95, 8)]))
    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: borrowed, priorNote: "From another machine")

    #expect(state.priorNote == nil)
    // Another machine's history is not offered as this machine's "last time" either.
    #expect(state.previousSet(forSlotID: state.slots[2].id) == nil)
    // Open rows start at what was just done here, not at the other machine's load.
    for slot in state.slots where !slot.isLogged {
      #expect(slot.draft.weightKg == 70)
      #expect(slot.draft.reps == 10)
    }
  }

  @Test("A machine with sets saved only as a warm-up is still labelled borrowed")
  func warmupOnlyMachineStillBorrows() {
    let borrowed = history(machine, [(95, 8)])
    var state = threeRowBlock()
    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: borrowed, priorNote: "From another machine")
    state.appendSlot(isWarmup: true)
    let warmup = state.slots.first { $0.isWarmup }!
    state.slots[state.slots.firstIndex { $0.id == warmup.id }!].draft = SetEntryDraft(weightKg: 20, reps: 10)
    state.markLogged(slotID: warmup.id, setID: SetID(), completedAt: now)

    state.changeMachine(
      to: otherMachine, machineName: "Other", machineIncrementKg: nil,
      prior: borrowed, priorNote: "From another machine")

    #expect(state.priorNote == "From another machine")
  }
}
