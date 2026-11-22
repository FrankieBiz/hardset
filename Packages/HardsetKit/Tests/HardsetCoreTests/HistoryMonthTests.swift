import Foundation
import Testing

@testable import HardsetCore

@Suite("The month picker groups months under the year they start in")
struct HistoryMonthTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func month(_ year: Int, _ month: Int, count: Int) -> HistoryMonth {
    let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    return HistoryMonth(
      start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!, workoutCount: count)
  }

  @Test("Years keep the order they arrive in and each holds its months")
  func years() {
    let months = [
      month(2024, 1, count: 2), month(2023, 12, count: 5), month(2023, 3, count: 1),
      month(2021, 6, count: 4),
    ]

    let groups = HistoryMonth.years(months, calendar: calendar)

    #expect(groups.map(\.year) == [2024, 2023, 2021])
    #expect(groups.map { $0.months.count } == [1, 2, 1])
    #expect(groups.map(\.workoutCount) == [2, 6, 4])
    #expect(groups[1].months.map(\.workoutCount) == [5, 1])
  }

  @Test("December and January are different years, however close")
  func yearBoundary() {
    let groups = HistoryMonth.years(
      [month(2024, 1, count: 1), month(2023, 12, count: 1)], calendar: calendar)
    #expect(groups.map(\.year) == [2024, 2023])
  }

  @Test("Months that arrive out of order still make one heading per year")
  func outOfOrder() {
    let groups = HistoryMonth.years(
      [month(2023, 5, count: 1), month(2022, 5, count: 1), month(2023, 2, count: 1)],
      calendar: calendar)
    #expect(groups.map(\.year) == [2023, 2022])
    #expect(groups[0].months.count == 2)
  }

  @Test("No months, no years")
  func none() {
    #expect(HistoryMonth.years([], calendar: calendar).isEmpty)
  }

  @Test("A month's id is its first instant")
  func identity() {
    let march = month(2023, 3, count: 1)
    #expect(march.id == march.start)
  }
}
