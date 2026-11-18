import Foundation
import Testing

@testable import HardsetCore

@Suite("Best at each weight")
struct RepMaxLedgerTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ n: Int) -> Date { epoch.addingTimeInterval(Double(n) * 86_400) }

  private func sample(_ kg: Double, _ reps: Int, day dayNumber: Int) -> ProgressionSample {
    ProgressionSample(
      sessionID: SessionID(), machineID: nil, weightKg: kg, reps: reps, completedAt: day(dayNumber)
    )
  }

  @Test func ledgerKeepsMostRepsAndWhenFirstReached() {
    let samples = [
      sample(40, 10, day: 1),
      sample(40, 12, day: 2),
      sample(40, 12, day: 3),
      sample(45, 8, day: 3),
      sample(40.004, 11, day: 4),
    ]
    #expect(
      RepMaxLedger.bests(from: samples) == [
        BestAtWeight(weightKg: 45, reps: 8, achievedAt: day(3)),
        BestAtWeight(weightKg: 40, reps: 12, achievedAt: day(2)),
      ]
    )
  }

  @Test func emptyLedger() { #expect(RepMaxLedger.bests(from: []).isEmpty) }
}
