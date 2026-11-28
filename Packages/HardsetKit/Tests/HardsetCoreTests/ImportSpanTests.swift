import Foundation
import Testing

@testable import HardsetCore

/// The import preview names the days a file's workouts began, in the lifter's calendar, and says
/// how many starts are still in the future.
@Suite("The import preview names the span of workout dates the file holds")
struct ImportSpanTests {
  private static let utc: TimeZone = TimeZone(identifier: "UTC")!
  private static let gregorianUTC: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
  }()
  private static let london = Locale(identifier: "en_GB")
  private static let american = Locale(identifier: "en_US")

  private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    gregorianUTC.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  private static func span(_ starts: [Date], now: Date) throws -> ImportSpan {
    try #require(ImportSpan(starts: starts, now: now))
  }

  @Test("Two years apart, each end names its year, in the passed locale")
  func twoYearSpan() throws {
    // Newest first, so the span is proven to order by date, not by the file's order.
    let span = try Self.span(
      [Self.date(2026, 11, 8, 19), Self.date(2024, 1, 3, 7)],
      now: Self.date(2026, 11, 9))
    #expect(span.earliestStart == Self.date(2024, 1, 3, 7))
    #expect(span.latestStart == Self.date(2026, 11, 8, 19))
    #expect(span.line(calendar: Self.gregorianUTC, locale: Self.london)
      == "Workout dates 3 Jan 2024 to 8 Nov 2026")
    #expect(span.line(calendar: Self.gregorianUTC, locale: Self.american)
      == "Workout dates Jan 3, 2024 to Nov 8, 2026")
  }

  @Test("Every start on one calendar day is one date, with no range")
  func oneDay() throws {
    let span = try Self.span(
      [Self.date(2026, 11, 8, 7), Self.date(2026, 11, 8, 19)],
      now: Self.date(2026, 11, 9))
    let line = span.line(calendar: Self.gregorianUTC, locale: Self.london)
    #expect(line == "Workout dates 8 Nov 2026")
    #expect(!line.contains(" to "))
  }

  @Test("A span inside one year still names the year on both ends")
  func sameYearSpan() throws {
    let span = try Self.span(
      [Self.date(2026, 1, 3), Self.date(2026, 11, 8)],
      now: Self.date(2026, 11, 9))
    #expect(span.line(calendar: Self.gregorianUTC, locale: Self.london)
      == "Workout dates 3 Jan 2026 to 8 Nov 2026")
    #expect(span.line(calendar: Self.gregorianUTC, locale: Self.american)
      == "Workout dates Jan 3, 2026 to Nov 8, 2026")
  }

  @Test("A start exactly at now is not later than now; the ones after it are, and are counted")
  func futureStarts() throws {
    let now = Self.date(2026, 11, 8, 12)
    let oneLate = try Self.span([now, now.addingTimeInterval(1)], now: now)
    #expect(oneLate.futureStarts == 1)
    #expect(oneLate.line(calendar: Self.gregorianUTC, locale: Self.london)
      == "Workout dates 8 Nov 2026 · 1 start later than now")

    let twoLate = try Self.span(
      [now, now.addingTimeInterval(1), now.addingTimeInterval(3 * 86_400)], now: now)
    #expect(twoLate.futureStarts == 2)
    #expect(twoLate.line(calendar: Self.gregorianUTC, locale: Self.london)
      == "Workout dates 8 Nov 2026 to 11 Nov 2026 · 2 starts later than now")
  }

  @Test("No starts gives no span, so the card draws nothing")
  func empty() {
    #expect(ImportSpan(starts: [], now: Self.date(2026, 11, 8)) == nil)
  }

  @Test("A day boundary follows the passed calendar, not the device's")
  func dayBoundaryFollowsCalendar() throws {
    // 23:30 UTC is still 8 Nov in UTC and already 9 Nov in a +13 zone; 00:10 UTC the next
    // morning is a second day in UTC but the same day in +13.
    let late = Self.date(2026, 11, 8, 23, 30)
    let after = Self.date(2026, 11, 9, 0, 10)
    let span = try Self.span([late, after], now: Self.date(2026, 11, 10))

    var plus13 = Self.gregorianUTC
    plus13.timeZone = TimeZone(secondsFromGMT: 13 * 3600)!

    #expect(span.line(calendar: Self.gregorianUTC, locale: Self.london)
      == "Workout dates 8 Nov 2026 to 9 Nov 2026")
    #expect(span.line(calendar: plus13, locale: Self.london) == "Workout dates 9 Nov 2026")

    let single = try Self.span([late], now: after)
    #expect(single.line(calendar: Self.gregorianUTC, locale: Self.london) == "Workout dates 8 Nov 2026")
    #expect(single.line(calendar: plus13, locale: Self.london) == "Workout dates 9 Nov 2026")
  }

  @Test("The span's words are facts only: nothing advises, scores or claims safety")
  func copyIsFactOnly() throws {
    let forbidden = [
      "should", "recommend", "aim for", "ideal", "goal", "will be added",
      "safe", "broken", "missing", "danger",
    ]
    let span = try Self.span(
      [Self.date(2024, 1, 3), Self.date(2026, 11, 8), Self.date(2026, 11, 9)],
      now: Self.date(2026, 11, 8))
    var strings = [
      ImportSpanCopy.label,
      ImportSpanCopy.line(range: "3 Jan 2024 to 8 Nov 2026"),
      ImportSpanCopy.single(day: "8 Nov 2026"),
      ImportSpanCopy.later(count: 0),
      ImportSpanCopy.later(count: 1),
      ImportSpanCopy.later(count: 2),
      ImportSpanCopy.joined(line: "Workout dates 8 Nov 2026", later: nil),
      ImportSpanCopy.joined(line: "Workout dates 8 Nov 2026", later: ImportSpanCopy.later(count: 2)),
      ImportSpanCopy.spoken(line: "Workout dates 8 Nov 2026", later: nil),
      ImportSpanCopy.spoken(line: "Workout dates 8 Nov 2026", later: ImportSpanCopy.later(count: 2)),
    ]
    for locale in [Self.london, Self.american] {
      strings.append(span.line(calendar: Self.gregorianUTC, locale: locale))
      strings.append(span.spokenLine(calendar: Self.gregorianUTC, locale: locale))
    }
    for string in strings {
      for word in forbidden {
        #expect(!string.lowercased().contains(word), "“\(string)” contains “\(word)”")
      }
    }
  }

  @Test("Read aloud, the dot becomes a pause and months are whole words")
  func spokenLine() throws {
    let span = try Self.span(
      [Self.date(2024, 1, 3, 7), Self.date(2026, 11, 8, 7), Self.date(2026, 11, 8, 19)],
      now: Self.date(2026, 11, 8, 0))
    #expect(span.spokenLine(calendar: Self.gregorianUTC, locale: Self.london)
      == "Workout dates 3 January 2024 to 8 November 2026, 2 starts later than now")
    #expect(span.spokenLine(calendar: Self.gregorianUTC, locale: Self.american)
      == "Workout dates January 3, 2024 to November 8, 2026, 2 starts later than now")
  }
}
