import Foundation

/// A calendar month that holds at least one finished workout, as a place to land in History.
///
/// Only months with data exist, so a jump can never land on an empty month, and the months a lifter
/// did not train in are visible as the ones that are missing. Lives in Core so the store that finds
/// the months and the screen that offers them share one value, and so how they group is tested
/// without a database or a view.
public struct HistoryMonth: Hashable, Sendable, Identifiable {
  /// The first instant of the month, in the calendar that grouped it.
  public let start: Date
  /// The first instant of the next month. A page that lands on this month holds the workouts that
  /// started before it, newest first, so the month's last workout leads.
  public let end: Date
  /// Finished workouts that started in this month.
  public let workoutCount: Int

  public var id: Date { start }

  public init(start: Date, end: Date, workoutCount: Int) {
    self.start = start
    self.end = end
    self.workoutCount = workoutCount
  }
}

/// The months of one calendar year, newest first, for a picker that groups under year headings.
public struct HistoryYear: Hashable, Sendable, Identifiable {
  public let year: Int
  public let months: [HistoryMonth]

  public var id: Int { year }
  public var workoutCount: Int { months.reduce(0) { $0 + $1.workoutCount } }
}

extension HistoryMonth {
  /// `months` grouped by the year each starts in, keeping their order, which is newest first when
  /// they come from `HistoryStore.loadMonths`. Keyed on the year rather than on adjacency, so a
  /// list that arrives out of order cannot produce two headings for one year.
  public static func years(_ months: [HistoryMonth], calendar: Calendar = .current) -> [HistoryYear] {
    var order: [Int] = []
    var buckets: [Int: [HistoryMonth]] = [:]
    for month in months {
      let year = calendar.component(.year, from: month.start)
      if buckets[year] == nil { order.append(year) }
      buckets[year, default: []].append(month)
    }
    return order.map { HistoryYear(year: $0, months: buckets[$0] ?? []) }
  }
}
