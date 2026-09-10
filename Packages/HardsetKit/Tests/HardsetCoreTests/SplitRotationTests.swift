import Foundation
import Testing

@testable import HardsetCore

@Suite("A plan can say where the lifter is in it without prescribing")
struct SplitRotationTests {
  private let now = Date(timeIntervalSince1970: 20_000_000)

  private func day(_ position: Int, daysAgo: Double?) -> SplitRotation.Day {
    SplitRotation.Day(
      id: SplitDayID(rawValue: UUID()),
      position: position,
      lastTrained: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
    )
  }

  @Test("The day trained longest ago is the one named")
  func namesTheStalestDay() {
    let recent = day(0, daysAgo: 1)
    let stale = day(1, daysAgo: 6)
    let middle = day(2, daysAgo: 3)

    #expect(SplitRotation.longestSinceTrained(among: [recent, stale, middle]) == stale.id)
  }

  @Test("A day never trained outranks every day that has been")
  func neverTrainedComesFirst() {
    let trained = day(0, daysAgo: 30)
    let never = day(1, daysAgo: nil)

    #expect(SplitRotation.longestSinceTrained(among: [trained, never]) == never.id)
  }

  /// The tie-break is the lifter's own arrangement, so two untrained days resolve the way the plan
  /// reads top to bottom rather than by row order out of SQLite.
  @Test("Equally untrained days break the tie on the lifter's own ordering")
  func tiesBreakOnPosition() {
    let trained = day(0, daysAgo: 2)
    let laterUntrained = day(2, daysAgo: nil)
    let earlierUntrained = day(1, daysAgo: nil)

    let answer = SplitRotation.longestSinceTrained(
      among: [trained, laterUntrained, earlierUntrained]
    )
    #expect(answer == earlierUntrained.id)
  }

  @Test("Two days trained at the same instant break the tie on ordering too")
  func identicalDatesBreakOnPosition() {
    let second = day(1, daysAgo: 4)
    let first = day(0, daysAgo: 4)

    #expect(SplitRotation.longestSinceTrained(among: [second, first]) == first.id)
  }

  /// The two refusals. Both would be easy to answer wrongly, and both would put a label on screen
  /// asserting an order the lifter never established.
  @Test("A plan nothing has ever been trained from says nothing")
  func untrainedPlanHasNoAnswer() {
    let days = [day(0, daysAgo: nil), day(1, daysAgo: nil), day(2, daysAgo: nil)]
    #expect(SplitRotation.longestSinceTrained(among: days) == nil)
  }

  @Test("A single-day plan has no rotation to be at a point in")
  func singleDayPlanHasNoAnswer() {
    #expect(SplitRotation.longestSinceTrained(among: [day(0, daysAgo: 9)]) == nil)
    #expect(SplitRotation.longestSinceTrained(among: []) == nil)
  }
}
