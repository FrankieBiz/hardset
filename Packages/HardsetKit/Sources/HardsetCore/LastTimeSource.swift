import Foundation

/// When the sets a live card quotes as "Last time" were done, and whether they came from this
/// machine. A fact about the prefill's source; it never adjusts the prefill or the target.
public struct LastTimeSource: Hashable, Sendable {
  public enum Equipment: Hashable, Sendable { case sameEquipment, otherMachine }

  /// The latest `completedAt` among the quoted session's working sets.
  public let lastDoneAt: Date
  public let equipment: Equipment

  /// `nil` when there is no prior or it has no sets.
  public init?(prior: PriorPerformance?, borrowed: Bool) {
    guard let prior, let lastDoneAt = prior.lastSets.lazy.map(\.completedAt).max() else { return nil }
    self.lastDoneAt = lastDoneAt
    self.equipment = borrowed ? .otherMachine : .sameEquipment
  }

  /// "25 Oct · 2 weeks ago", "25 Oct · yesterday", "today". A future date reads "today".
  /// The absolute day uses `calendar.timeZone`, so it names the day the sets were lifted.
  public func dateLine(
    now: Date, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    let phrase = LastDoneText.phrase(for: lastDoneAt, now: now, calendar: calendar)
    guard phrase != "today" else { return phrase }
    let day = lastDoneAt.formatted(
      Date.FormatStyle(locale: locale, timeZone: calendar.timeZone).month(.abbreviated).day()
    )
    return "\(day) · \(phrase)"
  }

  /// The same fact for VoiceOver: "25 October, 2 weeks ago", or "today".
  public func spokenDateLine(
    now: Date, calendar: Calendar = .current, locale: Locale = .current
  ) -> String {
    let phrase = LastDoneText.phrase(for: lastDoneAt, now: now, calendar: calendar)
    guard phrase != "today" else { return phrase }
    let day = lastDoneAt.formatted(
      Date.FormatStyle(locale: locale, timeZone: calendar.timeZone).month(.wide).day()
    )
    return "\(day), \(phrase)"
  }
}

/// The words a live card uses to say when the sets its "Last time" column quotes were done.
public enum LastTimeCopy {
  public static let label = "Last time"

  /// "Last time 25 Oct · 2 weeks ago".
  public static func line(dateLine: String) -> String { "\(label) \(dateLine)" }

  /// "From another machine · 25 Oct · 2 weeks ago".
  public static func borrowedContext(note: String, dateLine: String) -> String {
    "\(note) · \(dateLine)"
  }

  /// "Last time, 25 October, 2 weeks ago".
  public static func spoken(dateSpoken: String) -> String { "\(label), \(dateSpoken)" }
}
