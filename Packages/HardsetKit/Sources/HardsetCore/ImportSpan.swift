import Foundation

/// The span of workout starts a file holds, and how many are later than the moment it was read.
/// A fact about the file; it never filters, clamps or reorders what an import will do.
public struct ImportSpan: Hashable, Sendable {
  public let earliestStart: Date
  public let latestStart: Date
  /// Starts strictly after `now`, counted by instant. Left intact by the import.
  public let futureStarts: Int

  /// `nil` when `starts` is empty.
  public init?(starts: [Date], now: Date) {
    guard let earliest = starts.min(), let latest = starts.max() else { return nil }
    self.earliestStart = earliest
    self.latestStart = latest
    self.futureStarts = starts.count { $0 > now }
  }

  /// "Workout dates 3 Jan 2024 to 8 Nov 2026", "Workout dates 8 Nov 2026",
  /// and "… · 2 starts later than now" when any start is in the future.
  public func line(calendar: Calendar = .current, locale: Locale = .current) -> String {
    ImportSpanCopy.joined(line: datedLine(calendar: calendar, locale: locale), later: laterCopy)
  }

  /// The same for VoiceOver: "Workout dates 3 January 2024 to 8 November 2026,
  /// 2 starts later than now".
  public func spokenLine(calendar: Calendar = .current, locale: Locale = .current) -> String {
    ImportSpanCopy.spoken(line: datedLine(calendar: calendar, locale: locale, wide: true), later: laterCopy)
  }

  private var laterCopy: String? {
    futureStarts > 0 ? ImportSpanCopy.later(count: futureStarts) : nil
  }

  /// One date when every start falls on one day of `calendar`, a range otherwise. Both ends
  /// name the year, so a span is never mistaken for this year's.
  private func datedLine(calendar: Calendar, locale: Locale, wide: Bool = false) -> String {
    let earliest = day(earliestStart, calendar: calendar, locale: locale, wide: wide)
    guard !calendar.isDate(earliestStart, inSameDayAs: latestStart) else {
      return ImportSpanCopy.single(day: earliest)
    }
    let latest = day(latestStart, calendar: calendar, locale: locale, wide: wide)
    return ImportSpanCopy.line(range: "\(earliest) to \(latest)")
  }

  /// "3 Jan 2024" in `calendar`'s zone, or "3 January 2024" for a line read aloud.
  private func day(_ date: Date, calendar: Calendar, locale: Locale, wide: Bool) -> String {
    let style = Date.FormatStyle(locale: locale, timeZone: calendar.timeZone)
    return wide
      ? date.formatted(style.day().month(.wide).year())
      : date.formatted(style.day().month(.abbreviated).year())
  }
}

/// Every sentence the preview uses about the span. The view carries none of its own.
public enum ImportSpanCopy {
  public static let label = "Workout dates"

  /// "Workout dates 3 Jan 2024 to 8 Nov 2026".
  public static func line(range: String) -> String {
    "\(label) \(range)"
  }

  /// "Workout dates 8 Nov 2026".
  public static func single(day: String) -> String {
    "\(label) \(day)"
  }

  /// "2 starts later than now", "1 start later than now".
  public static func later(count: Int) -> String {
    count == 1 ? "1 start later than now" : "\(count) starts later than now"
  }

  /// "… · 2 starts later than now", the separator provenance lines already use.
  public static func joined(line: String, later: String?) -> String {
    guard let later else { return line }
    return "\(line) · \(later)"
  }

  /// The same sentence for VoiceOver, with a pause where the dot is.
  public static func spoken(line: String, later: String?) -> String {
    guard let later else { return line }
    return "\(line), \(later)"
  }
}
