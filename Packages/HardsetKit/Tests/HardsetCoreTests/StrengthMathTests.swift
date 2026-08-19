import Foundation
import Testing

@testable import HardsetCore

/// The reference app applied raw Epley to anything with `reps <= 30` and had no tests at all.
/// These are the tests it lacked.
@Suite("One-rep-max estimation refuses to guess")
struct StrengthMathTests {
  /// The exact case from the reference app: 60 kg x 25 reps reported a 110 kg e1RM.
  /// Arithmetically faithful to Epley, physiologically nonsense.
  @Test("The reference app's 60 kg x 25 reps case is unevaluated, not 110 kg")
  func theRegression() {
    let claim = StrengthMath.estimatedOneRepMax(weightKg: 60, reps: 25)
    #expect(claim.certainty == .unevaluated)
    #expect(claim.value == nil)

    // Confirm the arithmetic that produced the bad number, so this test documents what was
    // being refused rather than merely asserting nil.
    let rawEpley = 60.0 * (1 + 25.0 / 30.0)
    #expect(abs(rawEpley - 110.0) < 0.001)
  }

  @Test("A single at the load is reported as measured, not estimated")
  func singleIsMeasured() throws {
    let claim = StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 1)
    #expect(claim.value == 100)
    #expect(claim.certainty == .high)
    #expect(claim.source.id == "one-rep-max.measured")
  }

  @Test(
    "Certainty degrades as reps rise, then stops entirely",
    arguments: [
      (2, Certainty.high), (6, .high),
      (7, .moderate), (10, .moderate),
      (11, .low), (12, .low),
      (13, .unevaluated), (20, .unevaluated), (30, .unevaluated),
    ]
  )
  func certaintyByReps(reps: Int, expected: Certainty) {
    let claim = StrengthMath.estimatedOneRepMax(weightKg: 100, reps: reps)
    #expect(claim.certainty == expected)
    #expect(claim.isEvaluated == (expected != .unevaluated))
  }

  @Test("Nonsense input is unevaluated rather than defaulted")
  func nonsenseInput() {
    #expect(StrengthMath.estimatedOneRepMax(weightKg: 0, reps: 5).value == nil)
    #expect(StrengthMath.estimatedOneRepMax(weightKg: -20, reps: 5).value == nil)
    #expect(StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 0).value == nil)
    #expect(StrengthMath.estimatedOneRepMax(weightKg: 100, reps: -3).value == nil)
    #expect(StrengthMath.estimatedOneRepMax(weightKg: 5_000, reps: 5).value == nil)
  }

  @Test("Epley is applied correctly inside its valid range")
  func epleyWithinRange() throws {
    let claim = StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 5)
    let value = try #require(claim.value)
    #expect(abs(value - 100 * (1 + 5.0 / 30.0)) < 0.001)
  }

  /// A load shown to 10 g precision reads as a measurement, which is exactly the impression
  /// App Review guideline 1.4.1 penalises.
  @Test("Displayed loads are never rendered at two-decimal precision")
  func displayRounding() {
    let kg = StrengthMath.displayRounded(116.6666666, in: .kilograms)
    #expect(kg == 116.5)
    #expect(kg * 2 == (kg * 2).rounded(), "kg must land on a 0.5 boundary")

    let lb = StrengthMath.displayRounded(116.6666666, in: .pounds)
    #expect(lb == lb.rounded(), "lb must land on a whole number")
  }

  @Test("Every estimate carries a methodology and a stated valid range for 1.4.1 disclosure")
  func evidenceIsDisclosable() {
    let claim = StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 5)
    #expect(!claim.source.methodology.isEmpty)
    #expect(claim.source.validRange != nil)
    #expect(claim.source.citation != nil)
    // Framed as a heuristic, never as a health measurement.
    #expect(claim.source.methodology.contains("heuristic"))
  }
}
