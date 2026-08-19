import Foundation
import Testing

@testable import HardsetCore

@Suite("A record has to actually beat something")
struct PersonalRecordsTests {
  let now = Date(timeIntervalSince1970: 10_000_000)

  private func history(_ sets: [(Double, Int)]) -> [PriorSetRecord] {
    sets.map { PriorSetRecord(weightKg: $0.0, reps: $0.1, completedAt: now) }
  }

  private func records(
    _ weight: Double, _ reps: Int, history sets: [(Double, Int)],
    isWarmup: Bool = false, increment: Double? = nil
  ) -> [PersonalRecordKind] {
    PersonalRecordDetector.records(
      for: .init(weightKg: weight, reps: reps, isWarmup: isWarmup),
      history: history(sets),
      increment: increment
    )
    .map(\.kind)
  }

  /// Rule 1. "PR!" on the first set of a new movement is noise that devalues every later one.
  @Test("The first ever set for a lift is never a record")
  func firstSetIsNotARecord() {
    #expect(records(200, 5, history: []).isEmpty)
  }

  /// The ancestor's actual bug: it fired on `>=`, so repeating last week announced a record.
  @Test("Matching a previous best is not a record")
  func matchingIsNotARecord() {
    #expect(records(100, 8, history: [(100, 8)]).isEmpty)
  }

  @Test("A trivial increase is not a record")
  func trivialIncreaseIsNotARecord() {
    // +0.5 kg on 100 clears neither 2.5% nor one 2.5 kg plate step.
    #expect(!records(100.5, 8, history: [(100, 8)]).contains(.heaviestLoad))
  }

  @Test("A real load increase is a heaviest-weight record")
  func realIncreaseIsARecord() {
    let kinds = records(105, 5, history: [(100, 8)])
    #expect(kinds.contains(.heaviestLoad))
  }

  /// A coarse stack must not produce records from rounding artefacts.
  @Test("The margin respects the machine's actual increment")
  func marginRespectsIncrement() {
    // 2.5% of 100 is 2.5, but this stack moves in 10 kg steps.
    #expect(!records(105, 5, history: [(100, 8)], increment: 10).contains(.heaviestLoad))
    #expect(records(110, 5, history: [(100, 8)], increment: 10).contains(.heaviestLoad))
  }

  @Test("More reps at the same load is its own record")
  func repsAtLoadIsSeparate() {
    let all = PersonalRecordDetector.records(
      for: .init(weightKg: 100, reps: 9), history: history([(100, 8)])
    )
    let repRecord = try! #require(all.first { $0.kind == .repsAtLoad })
    #expect(repRecord.previousReps == 8)
    #expect(repRecord.weightKg == 100)
    // Not a heaviest-load record: the weight did not change.
    #expect(!all.map(\.kind).contains(.heaviestLoad))
  }

  /// Rule 5: reps-at-load compares like with like.
  @Test("Reps at a different load are not compared")
  func repsAtDifferentLoadIgnored() {
    // 12 reps at 90 says nothing about the 100 kg record.
    #expect(!records(100, 9, history: [(90, 12)]).contains(.repsAtLoad))
  }

  @Test("A lighter set can still set an estimated 1RM record")
  func estimateCanBeatOnReps() {
    // 100 x 8 estimates 126.7; 95 x 12 estimates 133 -- a real e1RM improvement at less load.
    let kinds = records(95, 12, history: [(100, 8)])
    #expect(kinds.contains(.estimatedOneRepMax))
    #expect(!kinds.contains(.heaviestLoad))
  }

  /// Rule 4: an unevaluated estimate cannot beat anything.
  @Test("A set too long to estimate sets no 1RM record")
  func unevaluatedEstimateSetsNoRecord() {
    // 20 reps is past StrengthMath's 12-rep bound, so there is no estimate to compare.
    #expect(StrengthMath.estimatedOneRepMax(weightKg: 60, reps: 20).value == nil)
    #expect(!records(60, 20, history: [(100, 8)]).contains(.estimatedOneRepMax))
  }

  @Test("History that cannot be estimated is skipped rather than treated as zero")
  func unevaluatedHistoryIsSkipped() {
    // The only history is unevaluable, so there is no e1RM benchmark and no e1RM record --
    // rather than beating an implied zero.
    #expect(!records(100, 5, history: [(50, 25)]).contains(.estimatedOneRepMax))
  }

  /// Rule 3.
  @Test("A warm-up is never a record, however heavy")
  func warmupIsNeverARecord() {
    #expect(records(200, 5, history: [(100, 8)], isWarmup: true).isEmpty)
  }

  @Test("Zero reps and negative load produce nothing")
  func invalidInputProducesNothing() {
    #expect(records(100, 0, history: [(100, 8)]).isEmpty)
    #expect(records(-5, 8, history: [(100, 8)]).isEmpty)
  }

  /// Bodyweight work: reps are the only axis, so a rep record must still fire.
  @Test("Bodyweight reps set a reps-at-load record")
  func bodyweightRepRecord() {
    #expect(records(0, 15, history: [(0, 12)]).contains(.repsAtLoad))
  }

  @Test("A big jump can set all three records at once")
  func allThreeAtOnce() {
    let kinds = records(120, 10, history: [(100, 8), (120, 6)])
    #expect(kinds.contains(.repsAtLoad))
    #expect(kinds.contains(.estimatedOneRepMax))
    // 120 does not clear 120 + margin, so the heaviest-load record is correctly absent.
    #expect(!kinds.contains(.heaviestLoad))
  }

  @Test("A record states what it beat, so the claim is checkable")
  func recordsStateWhatTheyBeat() {
    let all = PersonalRecordDetector.records(
      for: .init(weightKg: 110, reps: 5), history: history([(100, 5)])
    )
    let heaviest = try! #require(all.first { $0.kind == .heaviestLoad })
    #expect(heaviest.previousWeightKg == 100)
    #expect(heaviest.weightKg == 110)
  }
}
