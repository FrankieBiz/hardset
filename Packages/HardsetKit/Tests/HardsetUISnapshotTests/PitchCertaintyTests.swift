import HardsetCore
import HardsetUI
import Testing

/// The second pitch page claims the estimate "says how sure it is", and it walks the lifter through
/// all four answers. The page does not decide those answers; the engine does. This reads the same
/// four segments back through `StrengthMath`, so if the engine's rep bands ever move, the page
/// stops promising a level it no longer reaches and this test says so.
@MainActor
@Suite("The honest-numbers pitch reaches every certainty level through the engine")
struct PitchCertaintyTests {
  @Test func eachSegmentLandsOnItsOwnCertaintyLevel() {
    let expected: [CertaintyLevel] = [.high, .moderate, .low, .unevaluated]
    #expect(PitchEstimateDemo.repOptions.count == expected.count)

    for (reps, level) in zip(PitchEstimateDemo.repOptions, expected) {
      let claim = StrengthMath.estimatedOneRepMax(weightKg: PitchEstimateDemo.weightKg, reps: reps)
      #expect(CertaintyLevel(claim.certainty) == level, "\(reps) reps")
    }
  }

  @Test func theUnevaluatedSegmentShowsNoNumber() {
    let claim = StrengthMath.estimatedOneRepMax(
      weightKg: PitchEstimateDemo.weightKg, reps: PitchEstimateDemo.repOptions.last ?? 0)
    #expect(claim.value == nil)
  }

  @Test func everyEvaluatedSegmentShowsANumber() {
    for reps in PitchEstimateDemo.repOptions.dropLast() {
      let claim = StrengthMath.estimatedOneRepMax(weightKg: PitchEstimateDemo.weightKg, reps: reps)
      #expect(claim.value != nil, "\(reps) reps")
    }
  }
}
