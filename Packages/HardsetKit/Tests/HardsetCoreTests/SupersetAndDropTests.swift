import Foundation
import Testing

@testable import HardsetCore

@Suite("A set kind survives the round trip through two flags")
struct SetKindStorageTests {
  @Test("Every kind maps to storage and back unchanged")
  func roundTrips() {
    for kind in SetKind.allCases {
      let stored = kind.storage
      #expect(SetKind(isWarmup: stored.isWarmup, isDropSet: stored.isDropSet) == kind)
    }
  }

  /// The pair is only ever produced by `storage`, so this combination is unwritable by the app.
  /// It is still decodable, because the decode sits on the crash-recovery path and throwing there
  /// would take a whole workout's written sets down with one bad row.
  @Test("A row flagged both ways reads as a warm-up rather than throwing")
  func impossibleCombinationResolvesConservatively() {
    #expect(SetKind(isWarmup: true, isDropSet: true) == .warmup)
    // The reading that cannot inflate anything: both kinds are outside the working-set count.
    #expect(!SetKind(isWarmup: true, isDropSet: true).countsAsWorkingSet)
  }

  @Test("Only a working set counts as one")
  func onlyWorkingCounts() {
    #expect(SetKind.working.countsAsWorkingSet)
    #expect(!SetKind.warmup.countsAsWorkingSet)
    #expect(!SetKind.drop.countsAsWorkingSet)
  }
}

@Suite("A drop continues the set above it and adds no set")
struct DropSetTests {
  let now = Date(timeIntervalSince1970: 5_000_000)
  let exercise = ExerciseID()
  let machine = MachineID()

  private func state(sets: [(Double, Int)]) -> ExerciseLogState {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    let records = sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: now) }
    let snapshot = PriorPerformanceSnapshot(
      entries: [key: PriorPerformance(key: key, lastSets: records, heaviestSet: records.last)],
      capturedAt: now
    )
    return .build(
      exerciseID: exercise, machineID: machine, exerciseName: "Leg Press", snapshot: snapshot
    )
  }

  @Test("A drop takes the load of the row it continues and no reps")
  func seedsFromParent() {
    var state = self.state(sets: [(100, 10)])
    #expect(state.appendDropSet() != nil)

    let drop = state.slots.last!
    #expect(drop.kind == .drop)
    // The load is the parent's, so the reduction is an edit the lifter makes. The app has no
    // established drop percentage and does not invent one.
    #expect(drop.draft.weightKg == 100)
    // Reps are empty: a drop is taken to whatever it is taken to.
    #expect(drop.draft.reps == nil)
    #expect(!drop.draft.isLoggable)
  }

  @Test("There is nothing to continue on an empty movement or under a warm-up")
  func refusesWithoutAParent() {
    var empty = ExerciseLogState(
      exerciseID: exercise, exerciseName: "Leg Press", prior: nil, slots: []
    )
    #expect(!empty.canAppendDropSet)
    #expect(empty.appendDropSet() == nil)

    var warmingUp = state(sets: [(100, 10)])
    warmingUp.slots = [SetSlot(draft: SetEntryDraft(weightKg: 40, reps: 10), kind: .warmup)]
    #expect(!warmingUp.canAppendDropSet)
    #expect(warmingUp.appendDropSet() == nil)
  }

  /// The whole point of the counting convention, asserted at the type that counts.
  @Test("Dropping twice still leaves one working set")
  func dropsDoNotAddSets() {
    var state = self.state(sets: [(100, 10)])
    #expect(state.workingSetCount == 1)
    state.appendDropSet()
    state.appendDropSet()
    #expect(state.slots.count == 3)
    #expect(state.workingSetCount == 1)
  }

  @Test("A drop shares the number of the set it continues")
  func dropBorrowsItsParentsOrdinal() {
    var state = self.state(sets: [(100, 10), (100, 9)])
    state.appendDropSet()

    let second = state.slots[1]
    let drop = state.slots[2]
    #expect(state.workingOrdinal(ofSlotID: second.id) == 2)
    // Not 3. Numbering it separately is what would put "Set 3 of 2" on the Lock Screen.
    #expect(state.workingOrdinal(ofSlotID: drop.id) == 2)
  }

  /// A drop is the lightest load of the session by construction, so letting it seed the next row
  /// makes every hard session lighter than the one before it.
  @Test("The next row is suggested from the last working set, not from a drop")
  func dropsDoNotSeedTheNextRow() {
    var state = self.state(sets: [(100, 10)])
    state.markLogged(slotID: state.slots[0].id, setID: SetID())
    state.appendDropSet()
    state.slots[1].draft.weightKg = 60
    state.slots[1].draft.reps = 12
    state.markLogged(slotID: state.slots[1].id, setID: SetID())

    state.appendSlot()
    #expect(state.slots.last?.draft.weightKg == 100)
  }

  /// Warm-ups already did not shift the history index. Drops must not either, or the row that is
  /// working set 2 gets prefilled from last week's set 3.
  @Test("A drop does not shift which historical set the next row is prefilled from")
  func dropsDoNotShiftPrefillIndex() {
    var state = self.state(sets: [(100, 10), (105, 8), (110, 6)])
    state.slots = [state.slots[0]]
    state.appendDropSet()

    state.appendSlot()
    // Working set 2, so last week's second set, not its third.
    #expect(state.slots.last?.draft.weightKg == 105)
    #expect(state.slots.last?.draft.reps == 8)
  }

  @Test("Changing machine re-seeds an open drop from the row above it")
  func machineChangeReseedsDrops() {
    var state = self.state(sets: [(100, 10)])
    state.appendDropSet()
    #expect(state.slots[1].draft.weightKg == 100)

    let otherKey = ProgressionKey(exerciseID: exercise, machineID: MachineID())
    let records = [PriorSetRecord(weightKg: 60, reps: 10, completedAt: now)]
    state.changeMachine(
      to: otherKey.machineID,
      machineName: "Cybex",
      machineIncrementKg: 5,
      prior: PriorPerformance(key: otherKey, lastSets: records, heaviestSet: records.first)
    )

    // Follows its parent onto the new machine rather than keeping the old one's load.
    #expect(state.slots[0].draft.weightKg == 60)
    #expect(state.slots[1].draft.weightKg == 60)
    #expect(state.slots[1].kind == .drop)
  }
}

@Suite("Rest waits for the work to actually stop")
struct SupersetRestTests {
  let exercise = ExerciseID()

  private func movement(_ name: String, sets: Int, group: Int? = nil) -> ExerciseLogState {
    ExerciseLogState(
      exerciseID: ExerciseID(),
      exerciseName: name,
      prior: nil,
      supersetGroup: group,
      slots: (0..<sets).map { _ in SetSlot(draft: SetEntryDraft(weightKg: 60, reps: 8)) }
    )
  }

  private func log(_ state: inout ExerciseLogState, _ index: Int) -> UUID {
    let id = state.slots[index].id
    state.markLogged(slotID: id, setID: SetID())
    return id
  }

  @Test("A warm-up starts nothing")
  func warmupsDoNotRest() {
    var state = movement("Leg Press", sets: 1)
    state.slots[0].kind = .warmup
    let id = log(&state, 0)
    #expect(!SupersetRest.shouldArmRest(afterLogging: id, in: state, session: [state]))
  }

  @Test("A movement on its own rests after every working set")
  func soloMovementRests() {
    var state = movement("Leg Press", sets: 3)
    let id = log(&state, 0)
    #expect(SupersetRest.shouldArmRest(afterLogging: id, in: state, session: [state]))
  }

  /// The definition of a drop: no rest is taken before it.
  @Test("A set with a drop queued behind it does not rest, and the drop does")
  func dropChainRestsOnceAtItsEnd() {
    var state = movement("Leg Press", sets: 1)
    state.appendDropSet()
    state.appendDropSet()
    state.slots[1].draft.reps = 8
    state.slots[2].draft.reps = 6

    let first = log(&state, 0)
    #expect(!SupersetRest.shouldArmRest(afterLogging: first, in: state, session: [state]))

    // Nor does the middle of the chain.
    let middle = log(&state, 1)
    #expect(!SupersetRest.shouldArmRest(afterLogging: middle, in: state, session: [state]))

    // The last link does: the work has stopped.
    let last = log(&state, 2)
    #expect(SupersetRest.shouldArmRest(afterLogging: last, in: state, session: [state]))
  }

  @Test("Inside a superset, rest waits for the round rather than the set")
  func supersetRestsOncePerRound() {
    var a = movement("Bench", sets: 3, group: 1)
    var b = movement("Row", sets: 3, group: 1)

    let a1 = log(&a, 0)
    #expect(!SupersetRest.shouldArmRest(afterLogging: a1, in: a, session: [a, b]))

    let b1 = log(&b, 0)
    #expect(SupersetRest.shouldArmRest(afterLogging: b1, in: b, session: [a, b]))

    // And again on the next round, not before it.
    let a2 = log(&a, 1)
    #expect(!SupersetRest.shouldArmRest(afterLogging: a2, in: a, session: [a, b]))
    let b2 = log(&b, 1)
    #expect(SupersetRest.shouldArmRest(afterLogging: b2, in: b, session: [a, b]))
  }

  /// A partner with fewer sets must not block rest forever once it has finished. Without this the
  /// lifter's last two sets of the longer movement would never start a timer.
  @Test("A finished partner stops blocking the round")
  func finishedPartnerDoesNotBlock() {
    var a = movement("Bench", sets: 4, group: 1)
    var b = movement("Row", sets: 2, group: 1)

    for round in 0..<2 {
      _ = log(&a, round)
      _ = log(&b, round)
    }
    // b is done; a still has two sets to go and is now doing straight sets.
    #expect(!b.hasRemainingWorkingSets)

    let a3 = log(&a, 2)
    #expect(SupersetRest.shouldArmRest(afterLogging: a3, in: a, session: [a, b]))
  }

  @Test("A superset of three waits for all three")
  func threeWayRound() {
    var a = movement("Bench", sets: 2, group: 1)
    var b = movement("Row", sets: 2, group: 1)
    var c = movement("Curl", sets: 2, group: 1)

    let a1 = log(&a, 0)
    #expect(!SupersetRest.shouldArmRest(afterLogging: a1, in: a, session: [a, b, c]))
    let b1 = log(&b, 0)
    #expect(!SupersetRest.shouldArmRest(afterLogging: b1, in: b, session: [a, b, c]))
    let c1 = log(&c, 0)
    #expect(SupersetRest.shouldArmRest(afterLogging: c1, in: c, session: [a, b, c]))
  }

  /// Two groups in one workout must not wait for each other.
  @Test("A different superset's progress is irrelevant")
  func groupsAreIndependent() {
    var a = movement("Bench", sets: 2, group: 1)
    var b = movement("Row", sets: 2, group: 1)
    let c = movement("Squat", sets: 2, group: 2)
    let d = movement("Curl", sets: 2, group: 2)

    _ = log(&a, 0)
    let b1 = log(&b, 0)
    #expect(SupersetRest.shouldArmRest(afterLogging: b1, in: b, session: [a, b, c, d]))
  }

  /// Both rules at once, which is where a lifter who supersets and drops actually lands.
  @Test("A drop inside a superset withholds rest until the chain and the round are both done")
  func dropInsideASuperset() {
    var a = movement("Bench", sets: 2, group: 1)
    var b = movement("Row", sets: 2, group: 1)
    a.appendDropSet()
    a.slots[2].draft.reps = 8

    // Set 1 of A, with a drop queued after set 2 -- but this is set 1, so only the round matters.
    let a1 = log(&a, 0)
    #expect(!SupersetRest.shouldArmRest(afterLogging: a1, in: a, session: [a, b]))
    let b1 = log(&b, 0)
    #expect(SupersetRest.shouldArmRest(afterLogging: b1, in: b, session: [a, b]))

    // Set 2 of A has the drop behind it: no rest even though B is one round behind anyway.
    let a2 = log(&a, 1)
    #expect(!SupersetRest.shouldArmRest(afterLogging: a2, in: a, session: [a, b]))

    // The drop finishes A's work, but B has not caught up, so the round is not over.
    let drop = log(&a, 2)
    #expect(!SupersetRest.shouldArmRest(afterLogging: drop, in: a, session: [a, b]))

    let b2 = log(&b, 1)
    #expect(SupersetRest.shouldArmRest(afterLogging: b2, in: b, session: [a, b]))
  }

  @Test("An unknown row arms nothing")
  func unknownSlotIsRefused() {
    let state = movement("Leg Press", sets: 1)
    #expect(!SupersetRest.shouldArmRest(afterLogging: UUID(), in: state, session: [state]))
  }
}

@Suite("A superset is lettered by where a movement sits in it")
struct SupersetGroupingTests {
  private func movement(_ name: String, group: Int?) -> ExerciseLogState {
    ExerciseLogState(
      exerciseID: ExerciseID(), exerciseName: name, prior: nil, supersetGroup: group, slots: []
    )
  }

  @Test("Members are lettered in session order")
  func lettersFollowOrder() {
    let a = movement("Bench", group: 1)
    let b = movement("Row", group: 1)
    let solo = movement("Squat", group: nil)
    let session = [a, solo, b]

    #expect(SupersetGrouping.letter(for: a, in: session) == "A")
    #expect(SupersetGrouping.letter(for: b, in: session) == "B")
    #expect(SupersetGrouping.letter(for: solo, in: session) == nil)
  }

  /// Reachable by removing one of a pair. A lone "A" promises a partner that is not there.
  @Test("A group of one is not a superset")
  func groupOfOneIsNotLettered() {
    let lonely = movement("Bench", group: 1)
    #expect(SupersetGrouping.letter(for: lonely, in: [lonely]) == nil)
    #expect(SupersetGrouping.members(of: lonely, in: [lonely]).isEmpty)
  }

  @Test("Lettering does not run out at Z")
  func lettersPastZ() {
    #expect(SupersetGrouping.letter(at: 0) == "A")
    #expect(SupersetGrouping.letter(at: 25) == "Z")
    #expect(SupersetGrouping.letter(at: 26) == "AA")
    #expect(SupersetGrouping.letter(at: 27) == "AB")
  }

  @Test("The next group number skips the ones in use")
  func nextGroupIsFree() {
    let session = [movement("Bench", group: 1), movement("Row", group: 4)]
    #expect(SupersetGrouping.nextGroup(in: session) == 5)
    #expect(SupersetGrouping.nextGroup(in: []) == 1)
  }
}

/// Recovery counted written *rows* against expected *working sets*, which are different units.
/// Every warm-up or drop already logged therefore added one phantom open row to the movement.
/// The warm-up half of this predates supersets and drops entirely.
@Suite("Recovery opens rows for the work left, counted in sets")
struct ResumeRowCountTests {
  let now = Date(timeIntervalSince1970: 5_000_000)
  let exercise = ExerciseID()

  private func resumed(_ logged: [(SetKind, Double, Int)]) -> ExerciseLogState {
    .resume(
      exerciseID: exercise,
      exerciseName: "Chest Press",
      loggedSets: logged.map { kind, kg, reps in
        ExerciseLogState.LoggedSetSummary(
          setID: SetID(), weightKg: kg, reps: reps, kind: kind
        )
      },
      snapshot: .empty(capturedAt: now)
    )
  }

  @Test("A warm-up already logged does not add a fourth row to a three-set movement")
  func warmupsDoNotInflateTheRecoveredPlan() {
    let state = resumed([(.warmup, 40, 10), (.working, 80, 8), (.working, 80, 8), (.working, 80, 7)])
    #expect(state.workingSetCount == 3)
    #expect(state.slots.count == 4)
    let openRows = state.slots.count { !$0.isLogged }
    #expect(openRows == 0)
    #expect(state.slots.map(\.kind) == [.warmup, .working, .working, .working])
  }

  @Test("A drop already logged does not add a row either")
  func dropsDoNotInflateTheRecoveredPlan() {
    let state = resumed([(.working, 80, 8), (.drop, 60, 6), (.working, 80, 7)])
    #expect(state.workingSetCount == 2)
    #expect(state.slots.count == 3)
    #expect(state.slots.map(\.kind) == [.working, .drop, .working])
    #expect(state.slots.count { !$0.isLogged } == 0)
  }

  /// The plan still wins when there is one: three planned, two written, one row left open.
  @Test("An explicit plan still opens the rows it expects")
  func plannedSetsStillGovern() {
    let state = ExerciseLogState.resume(
      exerciseID: exercise,
      exerciseName: "Chest Press",
      loggedSets: [
        .init(setID: SetID(), weightKg: 80, reps: 8, kind: .working),
        .init(setID: SetID(), weightKg: 60, reps: 6, kind: .drop),
      ],
      snapshot: .empty(capturedAt: now),
      plannedSets: 3
    )
    #expect(state.slots.map(\.kind) == [.working, .drop, .working, .working])
    #expect(state.slots.count { !$0.isLogged } == 2)
  }
}
