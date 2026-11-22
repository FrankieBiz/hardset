import HardsetCore
import HardsetUI
import Testing

/// Facts the component kit relies on, pinned as executable checks. Nothing here renders: it asserts
/// the engine's certainty-by-reps rule and the UI's mapping of the engine's certainty onto its own
/// scale, through public API only.
@MainActor
@Suite("Kit logic the screens depend on")
struct KitLogicTests {
  /// Ruling R11, as amended by D15. The engine, not the design spec, decides which rep counts earn
  /// which word: a measured single is high, a formula's estimate is moderate up to 10 reps and
  /// never high, low at 11 and 12, and unevaluated beyond 12. A pitch that walks all four levels
  /// with reps 3, 8, 15 and 25 would show unevaluated twice and low never, so the walk uses 1, 3,
  /// 12 and 15.
  @Test func engineWalksCertaintyByReps() {
    let expected: [(reps: Int, certainty: Certainty)] = [
      (1, .high),
      (3, .moderate),
      (6, .moderate),
      (8, .moderate),
      (11, .low),
      (12, .low),
      (15, .unevaluated),
      (25, .unevaluated),
    ]
    for (reps, certainty) in expected {
      let claim = StrengthMath.estimatedOneRepMax(weightKg: 60, reps: reps)
      #expect(claim.certainty == certainty, "60 kg for \(reps) reps")
    }
  }

  /// Ruling R36. The engine's certainty maps onto the UI's level by name, for every case, and the
  /// raw values agree, so the three hand-written mappings the screens carry can be replaced by one.
  @Test func levelMappingCoversEveryCertainty() {
    #expect(CertaintyLevel(.high) == .high)
    #expect(CertaintyLevel(.moderate) == .moderate)
    #expect(CertaintyLevel(.low) == .low)
    #expect(CertaintyLevel(.unevaluated) == .unevaluated)

    for certainty in Certainty.allCases {
      #expect(CertaintyLevel(rawValue: certainty.rawValue) == CertaintyLevel(certainty))
    }
  }
}
