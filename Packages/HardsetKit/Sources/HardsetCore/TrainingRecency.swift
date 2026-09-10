import Foundation

/// How long ago something was trained, in words.
///
/// This exists because `Date.formatted(.relative(presentation: .named))` is wrong for this app's
/// question. It collapses everything from seven to thirteen days into "last week", which is exactly
/// the range a weekly split lives in: a day trained ten days ago and a day trained seven days ago
/// are the two the lifter is choosing between, and that phrasing renders them identical. Precision
/// in days is also *shorter* to read than the named form, so nothing is traded for it.
///
/// Counted in calendar days rather than elapsed seconds. "Yesterday" means the previous day, not
/// some point twenty-four hours back — a workout at 07:00 and one at 22:00 the day before are one
/// day apart to the person who did them.
public enum TrainingRecency {
  /// Days beyond which the phrase switches from days to weeks.
  ///
  /// Thirteen is the last day-count worth printing: at fourteen "two weeks" is what a person would
  /// say, and it also means the weeks branch can never emit "1 weeks ago".
  static let lastDayCounted = 13

  /// A phrase for how long ago `date` was, relative to `now`.
  ///
  /// Future dates read as "today" rather than inventing a tense for something that cannot have
  /// happened yet. A clock set forward, a timezone move, or a device whose date was wrong when a
  /// set was logged all produce one, and none of them are worth a separate sentence.
  public static func phrase(
    since date: Date,
    asOf now: Date,
    calendar: Calendar = .current
  ) -> String {
    let from = calendar.startOfDay(for: date)
    let to = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0

    switch days {
    case ..<1: return "today"
    case 1: return "yesterday"
    case 2...lastDayCounted: return "\(days) days ago"
    default: return "\(days / 7) weeks ago"
    }
  }
}
