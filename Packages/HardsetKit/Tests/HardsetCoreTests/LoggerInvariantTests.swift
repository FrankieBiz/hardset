import Foundation
import Testing

@testable import HardsetCore

/// Invariant 3, plus the set-row prefill bug.
@Suite("The logger reads history once and cannot log a phantom set")
struct LoggerInvariantTests {
  let now = Date(timeIntervalSince1970: 3_000_000)
  let exercise = ExerciseID()
  let machine = MachineID()

  /// The reference app showed the previous set's numbers as `TextField` *placeholder* text.
  /// An untouched field looked filled but read back empty, and the weight was accepted as
  /// empty, so a row visibly reading "60" was persisted at 0 kg -- zeroing session volume.
  @Test("A prefilled row holds a real value, not a placeholder")
  func prefillIsARealValue() {
    let prior = PriorSetRecord(weightKg: 60, reps: 8, completedAt: now)
    let draft = SetEntryDraft(suggestion: prior)
    #expect(draft.weightKg == 60)
    #expect(draft.reps == 8)
    #expect(draft.isLoggable)
    #expect(draft.resolved()?.weightKg == 60)
  }

  @Test("An untouched row with no history is not loggable, so it cannot write 0 kg")
  func untouchedRowIsNotLoggable() {
    let draft = SetEntryDraft(suggestion: nil)
    #expect(draft.weightKg == nil)
    #expect(draft.reps == nil)
    #expect(!draft.isLoggable)
    #expect(draft.resolved() == nil)
  }

  @Test("A row with weight but no reps is not loggable")
  func partialRowIsNotLoggable() {
    let draft = SetEntryDraft(weightKg: 60, reps: nil)
    #expect(!draft.isLoggable)
  }

  @Test("Zero reps is not a logged set")
  func zeroRepsIsNotASet() {
    #expect(!SetEntryDraft(weightKg: 60, reps: 0).isLoggable)
  }

  /// Bodyweight work legitimately carries no added load, so 0 kg with real reps is valid --
  /// the guard is against *missing* input, not against zero.
  @Test("Zero added load with real reps is a valid bodyweight set")
  func zeroLoadIsValidForBodyweight() {
    #expect(SetEntryDraft(weightKg: 0, reps: 12).isLoggable)
  }

  @Test("The snapshot answers from memory and holds no database handle")
  func snapshotIsAValue() {
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    let performance = PriorPerformance(
      key: key,
      lastSets: [PriorSetRecord(weightKg: 80, reps: 6, completedAt: now)],
      heaviestSet: PriorSetRecord(weightKg: 80, reps: 6, completedAt: now)
    )
    let snapshot = PriorPerformanceSnapshot(entries: [key: performance], capturedAt: now)
    #expect(snapshot.prior(for: key)?.lastSets.count == 1)
    #expect(snapshot.count == 1)
    // Repeated reads are pure -- there is nothing to query.
    #expect(snapshot.prior(for: key) == snapshot.prior(for: key))
  }

  @Test("An empty snapshot returns nothing rather than inventing a starting load")
  func emptySnapshot() {
    let snapshot = PriorPerformanceSnapshot.empty(capturedAt: now)
    let key = ProgressionKey(exerciseID: exercise, machineID: machine)
    #expect(snapshot.prior(for: key) == nil)
    #expect(!SetEntryDraft(suggestion: nil).isLoggable)
  }

  /// Machine-level progression is the point: the same exercise on different equipment is a
  /// different load history, and borrowing across machines must be visible.
  @Test("Falling back to another machine's history is flagged as such")
  func crossMachineFallbackIsFlagged() throws {
    let otherMachine = MachineID()
    let otherKey = ProgressionKey(exerciseID: exercise, machineID: otherMachine)
    let performance = PriorPerformance(
      key: otherKey,
      lastSets: [PriorSetRecord(weightKg: 70, reps: 10, completedAt: now)],
      heaviestSet: PriorSetRecord(weightKg: 70, reps: 10, completedAt: now)
    )
    let snapshot = PriorPerformanceSnapshot(entries: [otherKey: performance], capturedAt: now)

    let asked = ProgressionKey(exerciseID: exercise, machineID: machine)
    let result = try #require(snapshot.priorAllowingOtherMachines(for: asked))
    #expect(result.wasOtherMachine)
    #expect(result.performance.key.machineID == otherMachine)

    // An exact match is never flagged.
    let exact = try #require(snapshot.priorAllowingOtherMachines(for: otherKey))
    #expect(!exact.wasOtherMachine)
  }
}
