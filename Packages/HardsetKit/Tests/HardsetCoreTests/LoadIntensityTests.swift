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

/// Settling time, which is what the hand actually waits for.
///
/// `CommitShapeTests` above pins duration and bounce separately, and both are monotonic in load.
/// Settling time is **not**, because the two move in opposite directions: raising duration
/// lengthens the settle while lowering bounce shortens it. A mid-weight set therefore settles
/// marginally *faster* than a light one. That was discovered rather than designed, so it is pinned
/// here -- the point is that a future change to the constants cannot alter the felt envelope
/// without a test saying so.
@Suite("Commit settling stays inside the snappy envelope")
struct CommitSettlingTests {
  /// Time for a damped spring to enter and stay within 0.5% of its target.
  ///
  /// Duplicated deliberately from the design-language maths rather than imported: this is the
  /// independent check. If the production formula and this one ever disagree, that disagreement is
  /// the finding.
  private func settleSeconds(duration: Double, bounce: Double) -> Double {
    let zeta = 1 - bounce
    let w0 = 2 * Double.pi / duration
    func displacement(_ t: Double) -> Double {
      // Written out with explicit calls: the `.exp`/`.cos` static-member shorthand made the
      // type-checker give up on this expression.
      if zeta < 1 {
        let wd: Double = w0 * (1 - zeta * zeta).squareRoot()
        let decay: Double = exp(-zeta * w0 * t)
        let oscillation: Double = cos(wd * t) + (zeta * w0 / wd) * sin(wd * t)
        return 1 - decay * oscillation
      }
      let decay: Double = exp(-w0 * t)
      return 1 - decay * (1 + w0 * t)
    }
    let step = 0.0005
    var last = step
    var t = step
    while t <= duration * 8 {
      if abs(displacement(t) - 1) > 0.005 { last = t }
      t += step
    }
    return Swift.max(last + step, duration * 0.4)
  }

  private func settleMilliseconds(forIntensity intensity: Double?) -> Int {
    let shape = LoadIntensity.commitShape(intensity: intensity)
    return Int((settleSeconds(duration: shape.duration, bounce: shape.bounce) * 1000).rounded())
  }

  @Test("Every commit settles inside 160 ms, so nothing on the log path feels slow")
  func envelopeCeiling() {
    for step in 0...20 {
      let ms = settleMilliseconds(forIntensity: Double(step) / 20)
      #expect(ms <= 160, "intensity \(Double(step) / 20) settled in \(ms) ms")
    }
  }

  @Test("The acknowledgement budget is met at every load")
  func acknowledgementIsImmediate() {
    // The press scale begins on touch-down, so acknowledgement is not gated on settling. What must
    // hold is that the *spring* itself is never so long that the control looks stuck: guideline M3
    // allows 320 ms for completion.
    for step in 0...20 {
      #expect(settleMilliseconds(forIntensity: Double(step) / 20) <= 320)
    }
  }

  @Test("Settling is NOT monotonic in load, and that is a known property")
  func settlingDipsInTheMiddle() {
    let light = settleMilliseconds(forIntensity: 0)
    let middle = settleMilliseconds(forIntensity: 0.5)
    let heavy = settleMilliseconds(forIntensity: 1)

    // Documented, not desired: damping falls faster than duration rises across the lower half.
    #expect(middle <= light)
    // The heavy end is unambiguously the longest, which is what carries the sense of mass.
    #expect(heavy > light)
    #expect(heavy > middle)
    // And the dip is far too small to perceive, which is why it is acceptable rather than a bug.
    #expect(light - middle <= 15, "dip of \(light - middle) ms would become noticeable")
  }

  @Test("An unknown load settles exactly as the base shape does")
  func unknownMatchesBase() {
    #expect(settleMilliseconds(forIntensity: nil) == settleMilliseconds(forIntensity: 0))
  }
}

/// Bodyweight movements. Five ship in the catalogue, and before this a pull-up was recorded as
/// "0 kg x 8" -- a number that reads as no load at all.
@Suite("A bodyweight set is not an unloaded set")
struct BodyweightLoggingTests {
  private func state(modality: ExerciseModality?) -> ExerciseLogState {
    ExerciseLogState.build(
      exerciseID: ExerciseID(),
      exerciseName: "Pull-up",
      modality: modality,
      snapshot: .empty(capturedAt: .distantPast)
    )
  }

  @Test("A bodyweight movement with no history starts at zero added load")
  func bodyweightStartsAtZero() {
    let row = state(modality: .bodyweight)
    // Zero, not nil. Nil would leave the row unloggable until the lifter typed a "0" for a set
    // that genuinely had no added weight.
    #expect(row.slots.first?.draft.weightKg == 0)
  }

  @Test("Only reps are missing, so one entry makes it loggable")
  func onlyRepsAreOutstanding() {
    var row = state(modality: .bodyweight)
    #expect(row.slots.first?.draft.isLoggable == false)
    row.slots[0].draft.reps = 8
    #expect(row.slots[0].draft.isLoggable)
  }

  @Test("A loaded movement with no history stays empty rather than claiming zero")
  func loadedMovementDoesNotAssumeZero() {
    for modality in [ExerciseModality.barbell, .dumbbell, .machine, .cable] {
      let row = state(modality: modality)
      // Zero kilograms on a barbell movement is a claim about the lift. Absence is the honest
      // starting state.
      #expect(row.slots.first?.draft.weightKg == nil, "\(modality) should not assume 0 kg")
    }
  }

  @Test("An unknown modality is treated as loaded, which is the safe direction")
  func unknownModalityStaysEmpty() {
    #expect(state(modality: nil).slots.first?.draft.weightKg == nil)
  }

  @Test("Modality survives onto the log state so the row can render it")
  func modalityIsCarried() {
    #expect(state(modality: .bodyweight).modality == .bodyweight)
    #expect(state(modality: .barbell).modality == .barbell)
  }
}
