import Foundation
import Testing

@testable import HardsetCore

/// Copying a curated movement's muscles onto the lifter's own, without copying its evidence.
///
/// The centrepiece of "add my own stuff", and the one part of it that can be dishonest. A movement
/// typed at the rack credited exactly one muscle while the curated row it is plainly a variant of
/// credits four, so every weekly figure it touched was quietly short. Carrying the muscles across
/// fixes that. Carrying the *citation* across would launder a trial about a chest-supported row
/// into a claim about a Nautilus lever row, which is the thing this whole app exists not to do.
@Suite("An inherited attribution keeps the muscles and drops the evidence")
struct InheritedAttributionTests {
  /// A curated row as stored: a cited trial, a textbook synergist, and a stabiliser.
  private let template = [
    MuscleContribution(
      .upperBack, role: .direct, certainty: .high, source: .trial,
      citation: "Some trial, J Strength Cond Res 2019."
    ),
    MuscleContribution(
      .rearDelts, role: .indirect, certainty: .moderate, source: .anatomy,
      citation: "Textbook anatomy."
    ),
    MuscleContribution(.biceps, role: .indirect, certainty: .moderate, source: .pellandTable1),
    MuscleContribution(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
  ]

  @Test("The muscles and their roles carry over")
  func musclesCarryOver() {
    let result = InheritedAttribution.inherited(from: template, primary: .upperBack)
    let byKey = Dictionary(uniqueKeysWithValues: result.map { ($0.key, $0) })

    #expect(byKey[MuscleKey(.upperBack)]?.role == .direct)
    #expect(byKey[MuscleKey(.rearDelts)]?.role == .indirect)
    #expect(byKey[MuscleKey(.biceps)]?.role == .indirect)
    // The whole point: four credits where a hand-typed movement had one.
    #expect(result.filter { $0.setWeight > 0 }.count == 3)
  }

  /// The load-bearing assertion. If this ever fails, the app is citing a study for a machine the
  /// study never looked at.
  @Test("No inherited contribution keeps its citation or its curated source")
  func evidenceIsNotLaundered() {
    let result = InheritedAttribution.inherited(from: template, primary: .upperBack)
    #expect(!result.isEmpty)
    for contribution in result {
      #expect(contribution.citation == nil)
      #expect(contribution.sourceID == MuscleContribution.userSourceID)
      // Never any curated source id, whatever the allowlist grows to hold.
      #expect(AttributionSourceID(rawValue: contribution.sourceID) == nil)
    }
  }

  @Test("Certainty is capped at low, however confident the original was")
  func certaintyIsCapped() {
    let result = InheritedAttribution.inherited(from: template, primary: .upperBack)
    for contribution in result {
      #expect(contribution.certainty <= InheritedAttribution.ceiling)
    }
  }

  /// Capped by `min`, not assigned. A contribution the catalogue could not evaluate must not be
  /// promoted to `.low` on its way through — that would be inventing confidence, in the direction
  /// the rest of this type exists to prevent.
  @Test("An unevaluated contribution stays unevaluated rather than being raised to low")
  func cappingNeverPromotes() {
    let unevaluated = [
      MuscleContribution(.gastrocnemius, role: .indirect, certainty: .unevaluated, source: .convention)
    ]
    let result = InheritedAttribution.inherited(from: unevaluated, primary: .quadriceps)
    let calves = try? #require(result.first { $0.key == MuscleKey(.gastrocnemius) })
    #expect(calves?.certainty == .unevaluated)
  }

  /// Stabilisers credit nothing, so dropping one changes no arithmetic. What it avoids is a claim
  /// the lifter never saw: the sheet lists credited muscles only, so an inherited stabiliser would
  /// be written without ever appearing on screen to be switched off.
  @Test("Stabilisers are not inherited, because they are never shown to be endorsed")
  func stabilisersAreDropped() {
    let result = InheritedAttribution.inherited(from: template, primary: .upperBack)
    #expect(!result.contains { $0.key == MuscleKey(.forearms) })
  }

  @Test("The chosen muscle is always credited, even when the template does not mention it")
  func chosenMuscleAlwaysSurvives() {
    let result = InheritedAttribution.inherited(from: template, primary: .lats)
    let lats = try? #require(result.first { $0.key == MuscleKey(.lats) })
    #expect(lats?.role == .direct)
    #expect(result.first?.key == MuscleKey(.lats), "The lifter's own choice leads the list.")
  }

  /// The lifter said this is the prime mover. The template calling it a synergist must not quietly
  /// halve what their own sets count for.
  @Test("The chosen muscle stays direct even when the template calls it indirect")
  func chosenMuscleIsNeverDowngraded() {
    let result = InheritedAttribution.inherited(from: template, primary: .biceps)
    let biceps = try? #require(result.first { $0.key == MuscleKey(.biceps) })
    #expect(biceps?.role == .direct)
    #expect(biceps?.setWeight == 1.0)
    #expect(result.filter { $0.key == MuscleKey(.biceps) }.count == 1, "Credited once, not twice.")
  }

  @Test("Nothing inherited means the movement still credits what the lifter chose")
  func freehandStillWorks() {
    let result = InheritedAttribution.inherited(from: [], primary: .chest)
    #expect(result.count == 1)
    #expect(result.first?.key == MuscleKey(.chest))
    #expect(result.first?.role == .direct)
    #expect(result.first?.certainty == .low)
  }
}
