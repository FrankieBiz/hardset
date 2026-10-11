import Foundation
import Testing

@testable import HardsetCore

@Suite("Two tips that point at features, and never a word of coaching")
struct FeatureTipsTests {
  private func facts(
    gym: Bool = true, movement: Bool = true, history: Bool = true, typing: Bool = false
  ) -> FeatureTipFacts {
    FeatureTipFacts(
      sessionHasGym: gym, hasMovementOnScreen: movement, movementWithHistoryOnScreen: history,
      isEnteringNumbers: typing)
  }

  @Test("There are exactly two, each with its own glyph")
  func two() {
    #expect(FeatureTip.allCases == [.machineChip, .movementHistory])
    #expect(Set(FeatureTip.allCases.map(\.symbolName)).count == 2)
  }

  @Test("Each names the control it points at")
  func pointsAtAControl() {
    #expect(FeatureTip.machineChip.message.contains("machine chip"))
    #expect(FeatureTip.movementHistory.message.contains("name"))
  }

  /// `HANDOFF.md` §6: no targets, no coaching. A tip is the easiest place for one to creep in.
  @Test("Nothing in a tip tells the lifter what to do with their training")
  func neverCoaching() {
    let refused: Set<String> = [
      "should", "try", "aim", "goal", "goals", "target", "targets", "push", "beat", "improve",
      "progress", "more", "harder", "heavier", "record", "streak", "must", "need",
    ]
    for tip in FeatureTip.allCases {
      for line in [tip.title, tip.message] {
        let words = line.lowercased().split { !$0.isLetter }.map(String.init)
        #expect(refused.isDisjoint(with: words), "\(line)")
      }
    }
  }

  @Test("Nothing covers the keypad")
  func notWhileTyping() {
    for tip in FeatureTip.allCases {
      #expect(!FeatureTipPlan.isEligible(tip, facts: facts(typing: true)))
    }
  }

  @Test("The machine tip needs a chip to point at")
  func machineTipNeedsAChip() {
    #expect(FeatureTipPlan.isEligible(.machineChip, facts: facts()))
    #expect(!FeatureTipPlan.isEligible(.machineChip, facts: facts(gym: false)))
    #expect(!FeatureTipPlan.isEligible(.machineChip, facts: facts(movement: false)))
  }

  @Test("The history tip needs history to open")
  func historyTipNeedsHistory() {
    #expect(FeatureTipPlan.isEligible(.movementHistory, facts: facts()))
    #expect(!FeatureTipPlan.isEligible(.movementHistory, facts: facts(history: false)))
  }
}
