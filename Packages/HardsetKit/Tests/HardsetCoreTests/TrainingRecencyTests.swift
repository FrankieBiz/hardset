import Foundation
import Testing

@testable import HardsetCore

@Suite("How long ago a day was trained is said precisely enough to choose by")
struct TrainingRecencyTests {
  /// A fixed calendar, so a machine in another timezone reads these the same way.
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13:20 UTC

  private func phrase(daysAgo: Double) -> String {
    TrainingRecency.phrase(
      since: now.addingTimeInterval(-daysAgo * 86_400), asOf: now, calendar: calendar
    )
  }

  @Test("Today and yesterday are named, not counted")
  func namesTheNearestTwoDays() {
    #expect(phrase(daysAgo: 0) == "today")
    #expect(phrase(daysAgo: 1) == "yesterday")
  }

  /// The whole reason this type exists. `.relative(presentation: .named)` renders every one of
  /// these as "last week", which is the range a weekly split actually lives in.
  @Test("The second week is counted in days, where the named format says only last week")
  func keepsDaysThroughTheSecondWeek() {
    #expect(phrase(daysAgo: 5) == "5 days ago")
    #expect(phrase(daysAgo: 7) == "7 days ago")
    #expect(phrase(daysAgo: 10) == "10 days ago")
    #expect(phrase(daysAgo: 13) == "13 days ago")
  }

  @Test("Past a fortnight it switches to weeks, and never says one week")
  func switchesToWeeks() {
    #expect(phrase(daysAgo: 14) == "2 weeks ago")
    #expect(phrase(daysAgo: 20) == "2 weeks ago")
    #expect(phrase(daysAgo: 21) == "3 weeks ago")
    #expect(phrase(daysAgo: 140) == "20 weeks ago")

    // The boundary exists so this phrase is unreachable.
    let phrases = (0...400).map { phrase(daysAgo: Double($0)) }
    let saysOneWeek = phrases.contains("1 weeks ago")
    #expect(!saysOneWeek)
  }

  /// Calendar days, not elapsed hours. Spelled with explicit instants because the distinction only
  /// shows up either side of a midnight, which an offset in hours obscures.
  @Test("Days are calendar days rather than twenty-four hour spans")
  func countsCalendarDays() {
    func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
      calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: 30)
      )!
    }
    // The reference instant, restated locally so the arithmetic is visible.
    let evening = at(2023, 11, 14, 22)

    // Same calendar day, twenty hours earlier: still today.
    #expect(TrainingRecency.phrase(since: at(2023, 11, 14, 2), asOf: evening, calendar: calendar)
      == "today")
    // Under twenty-four hours earlier, but across midnight: yesterday.
    #expect(TrainingRecency.phrase(since: at(2023, 11, 13, 23), asOf: evening, calendar: calendar)
      == "yesterday")
    // Just over twenty-four hours, and still only yesterday.
    #expect(TrainingRecency.phrase(since: at(2023, 11, 13, 1), asOf: evening, calendar: calendar)
      == "yesterday")
  }

  @Test("A date in the future reads as today rather than inventing a tense")
  func toleratesFutureDates() {
    #expect(phrase(daysAgo: -3) == "today")
  }
}
