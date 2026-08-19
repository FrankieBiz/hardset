import Foundation
import Testing

@testable import HardsetCore

/// The reference app's scorers fell back to a neutral 70, so three unrecognised exercises
/// composed into a confident "78/100 -- Dialed in". These tests pin the property that makes
/// that impossible: there is no neutral default, and unknown inputs poison the composite.
@Suite("Claims cannot invent confidence")
struct CertaintyTests {
  let source = EvidenceSource(
    id: "test", title: "Test", methodology: "For testing."
  )

  @Test("An unevaluated claim carries no value")
  func unevaluatedHasNoValue() {
    let claim = Claim<Double>.unevaluated(source: source)
    #expect(claim.value == nil)
    #expect(claim.certainty == .unevaluated)
    #expect(!claim.isEvaluated)
  }

  @Test("Combining certainties takes the weakest, never an average")
  func combineTakesMinimum() {
    #expect(Certainty.combine([.high, .high, .moderate]) == .moderate)
    #expect(Certainty.combine([.high, .low]) == .low)
    // The load-bearing case: one unknown input makes the whole composite unknown. An
    // averaging rule would have produced a confident-looking middling score instead.
    #expect(Certainty.combine([.high, .high, .unevaluated]) == .unevaluated)
    #expect(Certainty.combine([]) == .unevaluated)
  }

  @Test("Certainty ordering is strict")
  func ordering() {
    #expect(Certainty.unevaluated < .low)
    #expect(Certainty.low < .moderate)
    #expect(Certainty.moderate < .high)
  }

  @Test("Mapping a claim preserves certainty and provenance")
  func mapPreservesProvenance() throws {
    let claim = Claim(10.0, certainty: .moderate, source: source)
    let mapped = claim.map { $0 * 2 }
    #expect(mapped.value == 20)
    #expect(mapped.certainty == .moderate)
    #expect(mapped.source.id == "test")
  }

  @Test("Mapping an unevaluated claim stays unevaluated")
  func mapKeepsUnevaluated() {
    let mapped = Claim<Double>.unevaluated(source: source).map { $0 * 2 }
    #expect(mapped.value == nil)
    #expect(mapped.certainty == .unevaluated)
  }

  @Test("Assumptions travel with the claim so the UI can always offer a correction")
  func assumptionsTravel() {
    let assumption = Assumption(
      id: "experience", label: "assumes intermediate",
      correctionPrompt: "Set your training experience"
    )
    let claim = Claim(1.0, certainty: .low, source: source, assumptions: [assumption])
    #expect(claim.assumptions.count == 1)
    #expect(claim.assumptions[0].label == "assumes intermediate")
    #expect(!claim.assumptions[0].correctionPrompt.isEmpty)
  }
}
