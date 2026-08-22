import Foundation
import Testing

@testable import HardsetCore

/// The motion layer scales a set's commit by how heavy it is. These tests pin the one property
/// that matters for honesty: "we don't know" is a distinct answer from "medium", because a
/// mid-weight feel on an unknown lift is the same neutral fallback that made the ancestor app
/// score three unrecognised exercises as "78/100 -- Dialed in".
@Suite("Load intensity says when it does not know")
struct LoadIntensityTests {
  @Test("No history is unknown, not light and not medium")
  func noHistoryIsUnknown() {
    #expect(LoadIntensity.fraction(weightKg: 100, heaviestKg: nil) == nil)
  }

  @Test("Bodyweight-only history cannot form a ratio")
  func zeroDenominatorIsUnknown() {
    #expect(LoadIntensity.fraction(weightKg: 0, heaviestKg: 0) == nil)
    #expect(LoadIntensity.fraction(weightKg: 20, heaviestKg: -5) == nil)
  }

  @Test("A set at the previous best is full intensity")
  func atBestIsOne() {
    #expect(LoadIntensity.fraction(weightKg: 120, heaviestKg: 120) == 1)
  }

  @Test("Beating the best clamps to full intensity rather than exceeding it")
  func aboveBestClamps() {
    // A record gets the most solid commit in the app, and it falls out of the arithmetic
    // rather than being a celebration bolted on.
    #expect(LoadIntensity.fraction(weightKg: 200, heaviestKg: 120) == 1)
  }

  @Test("Half the previous best is half intensity")
  func proportional() {
    let f = LoadIntensity.fraction(weightKg: 60, heaviestKg: 120)
    #expect(f != nil)
    #expect(abs((f ?? 0) - 0.5) < 0.0001)
  }

  @Test("A bodyweight set against loaded history is the lightest thing there is")
  func zeroLoadIsZeroNotUnknown() {
    // Zero added load with real reps is a valid set, so this is 0 -- not nil.
    #expect(LoadIntensity.fraction(weightKg: 0, heaviestKg: 100) == 0)
  }

  @Test("A negative or non-finite load is not a set")
  func rejectsNonsense() {
    #expect(LoadIntensity.fraction(weightKg: -1, heaviestKg: 100) == nil)
    #expect(LoadIntensity.fraction(weightKg: .infinity, heaviestKg: 100) == nil)
    #expect(LoadIntensity.fraction(weightKg: .nan, heaviestKg: 100) == nil)
  }

  @Test("The heaviest prior comes off the log state, and re-bases with the machine")
  func logStateExposesHeaviest() {
    let exercise = ExerciseID()
    let key = ProgressionKey(exerciseID: exercise, machineID: nil)
    let sets = [
      PriorSetRecord(weightKg: 80, reps: 8, completedAt: .distantPast),
      PriorSetRecord(weightKg: 100, reps: 5, completedAt: .distantPast),
    ]
    let snapshot = PriorPerformanceSnapshot(
      entries: [key: PriorPerformance(key: key, lastSets: sets, heaviestSet: sets[1])],
      capturedAt: .distantPast
    )
    let state = ExerciseLogState.build(
      exerciseID: exercise, exerciseName: "Chest Press", snapshot: snapshot
    )
    #expect(state.heaviestPriorKg == 100)

    let noHistory = ExerciseLogState.build(
      exerciseID: ExerciseID(), exerciseName: "New Lift",
      snapshot: .empty(capturedAt: .distantPast)
    )
    #expect(noHistory.heaviestPriorKg == nil)
  }
}

/// The mass signature: heavier sets commit more solidly. These pin the properties that keep it
/// from becoming either a lie or a lag.
@Suite("Commit shape carries mass without carrying delay")
struct CommitShapeTests {
  @Test("Unknown intensity applies no effect at all")
  func unknownIsUnmodulated() {
    // Not "medium". The base shape, exactly -- absence of signal is absence of effect.
    #expect(LoadIntensity.commitShape(intensity: nil) == LoadIntensity.baseShape)
  }

  @Test("Zero intensity is the base shape, so the scale is continuous")
  func zeroMatchesBase() {
    #expect(LoadIntensity.commitShape(intensity: 0) == LoadIntensity.baseShape)
  }

  @Test("Heavier damps harder, monotonically")
  func bounceFallsWithLoad() {
    let shapes = stride(from: 0.0, through: 1.0, by: 0.1)
      .map { LoadIntensity.commitShape(intensity: $0) }
    for (a, b) in zip(shapes, shapes.dropFirst()) {
      #expect(b.bounce < a.bounce)
    }
    #expect(shapes.last!.bounce < 0.05)
  }

  @Test("Duration rises with load but never past the snappy ceiling")
  func durationStaysSnappy() {
    let shapes = stride(from: 0.0, through: 1.0, by: 0.1)
      .map { LoadIntensity.commitShape(intensity: $0) }
    for (a, b) in zip(shapes, shapes.dropFirst()) {
      #expect(b.duration > a.duration)
    }
    let longest = shapes.map(\.duration).max() ?? 0
    #expect(longest <= LoadIntensity.maximumCommitDuration)
    // The felt difference has to be damping, not waiting: the whole range is 50 ms.
    #expect(longest - LoadIntensity.baseShape.duration <= 0.05 + 1e-9)
  }

  @Test("Out-of-range intensities clamp rather than producing nonsense springs")
  func clampsInput() {
    #expect(LoadIntensity.commitShape(intensity: -3) == LoadIntensity.baseShape)
    #expect(LoadIntensity.commitShape(intensity: 9) == LoadIntensity.commitShape(intensity: 1))
    #expect(LoadIntensity.commitShape(intensity: 1).bounce >= 0)
  }
}
