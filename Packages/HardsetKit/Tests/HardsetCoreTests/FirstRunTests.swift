import Foundation
import Testing

@testable import HardsetCore

@Suite("The first screen promises three things and asks for nothing")
struct FirstRunTests {
  @Test("Three promises, each with its own glyph")
  func threePromises() {
    #expect(FirstRunCopy.promises.map(\.id) == ["honest", "machines", "fast"])
    #expect(Set(FirstRunCopy.promises.map(\.symbolName)).count == 3)
    for promise in FirstRunCopy.promises {
      #expect(!promise.title.isEmpty)
      #expect(!promise.detail.isEmpty)
    }
  }

  @Test("The privacy line is the spec's, word for word")
  func privacy() {
    #expect(FirstRunCopy.privacy == "No account. Your data stays on your devices and in your iCloud.")
  }

  /// `HANDOFF.md` §6: no targets, no program, no coaching. The first screen is where an app is
  /// most tempted to ask for a goal.
  @Test("Nothing on the screen asks for a goal, a target, a program or a streak")
  func asksForNothing() {
    let copy =
      FirstRunCopy.promises.flatMap { [$0.title, $0.detail] }
      + [FirstRunCopy.privacy, FirstRunCopy.start, FirstRunCopy.gymFieldPrompt, FirstRunCopy.gymFootnote]
    let refused: Set<String> = [
      "goal", "goals", "target", "targets", "program", "programme", "plan", "streak", "coach",
      "questionnaire",
    ]
    for line in copy {
      let words = line.lowercased().split { !$0.isLetter }.map(String.init)
      #expect(refused.isDisjoint(with: words), "\(line)")
    }
  }

  @Test("Naming a gym is offered as optional")
  func gymIsOptional() {
    #expect(FirstRunCopy.gymFieldPrompt.contains("optional"))
  }

  @Test("The unit is guessed from the region: pounds only for the US system")
  func inferredUnit() {
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_US")) == .pounds)
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_LR")) == .pounds)
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_GB")) == .kilograms)
    #expect(WeightUnit.inferred(from: Locale(identifier: "de_DE")) == .kilograms)
    #expect(WeightUnit.inferred(from: Locale(identifier: "en_CA")) == .kilograms)
  }

  @Test("A unit the lifter already chose is never called a region guess")
  func storedUnitIsNotAGuess() {
    let us = Locale(identifier: "en_US")
    let uk = Locale(identifier: "en_GB")
    #expect(WeightUnit.regionGuess(stored: .kilograms, locale: us) == nil)
    #expect(WeightUnit.regionGuess(stored: .pounds, locale: uk) == nil)
    #expect(WeightUnit.regionGuess(stored: .pounds, locale: us) == nil)
    #expect(WeightUnit.regionGuess(stored: nil, locale: us) == .pounds)
    #expect(WeightUnit.regionGuess(stored: nil, locale: uk) == .kilograms)
  }
}
