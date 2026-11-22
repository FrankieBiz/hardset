import Foundation
import HardsetCore
import SQLiteData

nonisolated extension HistoryStore {
  /// The months that hold finished workouts, newest first, with how many each holds.
  ///
  /// Months are the lifter's own: the `calendar` decides where one ends, because a workout at
  /// 11:30 pm on the 31st belongs to the month its owner would say, not the one it falls in at
  /// UTC. That is also why this reads the start times and groups them here rather than grouping in
  /// SQL, where a month could only be cut at UTC. It is one column of one row per workout, read in
  /// index order, and it runs when the lifter opens the month picker, not on a keystroke.
  public func loadMonths(calendar: Calendar = .current) async throws -> [HistoryMonth] {
    try Task.checkCancellation()
    let starts: [Date] = try await database.read { db in
      try Session.where { $0.finishedAt.isNot(nil) }
        .order { $0.startedAt.desc() }
        .select { $0.startedAt }
        .fetchAll(db)
    }
    try Task.checkCancellation()
    return Self.months(of: starts, calendar: calendar)
  }

  /// Groups start times that are already newest first into months. Pure, so the boundaries are
  /// testable without a database.
  static func months(of starts: [Date], calendar: Calendar) -> [HistoryMonth] {
    var months: [HistoryMonth] = []
    var current: (start: Date, end: Date)?
    var count = 0

    func close() {
      if let current { months.append(HistoryMonth(start: current.start, end: current.end, workoutCount: count)) }
    }

    for date in starts {
      // Half-open, so an instant exactly at the next month's start belongs to that month.
      if let current, date >= current.start, date < current.end {
        count += 1
        continue
      }
      close()
      if let interval = calendar.dateInterval(of: .month, for: date) {
        current = (interval.start, interval.end)
      } else {
        // A calendar with no months cannot say where this one ends. Keep the workout reachable as
        // its own one-second place rather than dropping it.
        current = (date, date.addingTimeInterval(1))
      }
      count = 1
    }
    close()
    return months
  }
}
