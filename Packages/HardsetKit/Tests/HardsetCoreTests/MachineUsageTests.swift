import Foundation
import Testing

@testable import HardsetCore

/// A machine's log is a fact about the equipment, so the words that state it may not become advice.
@Suite("Machine usage states the log without judging the lifter")
struct MachineUsageTests {
  @Test("A used machine reads last used, sessions, working sets and heaviest load")
  func summaryJoinsEveryFragment() {
    #expect(
      MachineUsageCopy.summary(
        lastUsed: "6 Nov", sessions: 14, workingSets: 312, heaviest: "80 kg"
      ) == "Last used 6 Nov · 14 sessions · 312 working sets · heaviest 80 kg"
    )
  }

  @Test("One session and one working set are singular")
  func singularForms() {
    #expect(
      MachineUsageCopy.summary(lastUsed: nil, sessions: 1, workingSets: 1, heaviest: nil)
        == "1 session · 1 working set"
    )
    #expect(
      MachineUsageCopy.summary(lastUsed: "6 Nov", sessions: 1, workingSets: 2, heaviest: nil)
        == "Last used 6 Nov · 1 session · 2 working sets"
    )
    #expect(
      MachineUsageCopy.summary(lastUsed: "6 Nov", sessions: 2, workingSets: 1, heaviest: nil)
        == "Last used 6 Nov · 2 sessions · 1 working set"
    )
  }

  /// A machine with nothing logged has no date and no load to state, and "0 sessions" would read
  /// as a measurement of absence rather than the absence itself.
  @Test("No working sets says so and never composes zero sessions")
  func neverUsedRefusesZeroes() {
    let summary = MachineUsageCopy.summary(
      lastUsed: "6 Nov", sessions: 0, workingSets: 0, heaviest: "80 kg"
    )
    #expect(summary == MachineUsageCopy.neverUsed)
    #expect(!summary.contains("0 sessions"))
    #expect(!summary.contains("heaviest"))
    #expect(!summary.contains("Last"))
  }

  @Test("A missing heaviest load drops only its own fragment")
  func missingHeaviestLeavesCleanSeparators() {
    let summary = MachineUsageCopy.summary(
      lastUsed: "6 Nov", sessions: 2, workingSets: 9, heaviest: nil
    )
    #expect(summary == "Last used 6 Nov · 2 sessions · 9 working sets")
    #expect(!summary.hasSuffix(" · "))
  }

  @Test("A missing date drops only its own fragment")
  func missingDateLeavesCleanSeparators() {
    let summary = MachineUsageCopy.summary(
      lastUsed: nil, sessions: 2, workingSets: 9, heaviest: "80 kg"
    )
    #expect(summary == "2 sessions · 9 working sets · heaviest 80 kg")
    #expect(!summary.hasPrefix("Last used"))
    #expect(!summary.hasSuffix(" · "))
  }

  /// "Best" and "record" would turn the log's maximum into a claim about the lifter's achievement;
  /// the rest would turn a statement of fact into an instruction.
  @Test("No machine usage copy gives advice or claims a record")
  func copyHygiene() {
    let strings = [
      MachineUsageCopy.summary(
        lastUsed: "6 Nov", sessions: 14, workingSets: 312, heaviest: "80 kg"),
      MachineUsageCopy.summary(lastUsed: nil, sessions: 1, workingSets: 1, heaviest: nil),
      MachineUsageCopy.summary(lastUsed: "6 Nov", sessions: 2, workingSets: 9, heaviest: nil),
      MachineUsageCopy.neverUsed,
      MachineUsageCopy.importsAndFreeWeights,
    ]
    let forbidden = ["should", "recommend", "best", "record", "ideal", "goal", "must", "streak"]
    for string in strings {
      let folded = string.lowercased()
      for word in forbidden {
        #expect(!folded.contains(word), "“\(string)” contains “\(word)”")
      }
    }
  }

  @Test("A usage is never used exactly when it holds no working sets")
  func isNeverUsedFollowsTheCount() {
    let unused = MachineUsage(
      sessionCount: 0, workingSetCount: 0, heaviestLoadKg: nil, lastUsedAt: nil)
    #expect(unused.isNeverUsed)

    let used = MachineUsage(
      sessionCount: 1, workingSetCount: 1, heaviestLoadKg: 60, lastUsedAt: Date())
    #expect(!used.isNeverUsed)
  }
}
