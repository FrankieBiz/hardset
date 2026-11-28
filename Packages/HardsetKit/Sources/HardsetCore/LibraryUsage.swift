import Foundation

/// What the Library knows about one movement's logged sets: how many working sets are native, how
/// many came from an import, and when the newest native one was done.
///
/// It is a count of what was logged, never a target, a judgement or a nudge. A movement with only
/// warm-ups, or nothing logged, has no line at all rather than "0 sets" or "not done yet".
public struct LibraryUsage: Hashable, Sendable {
  /// Non-warm-up sets not from an import. Includes future-dated sets (D31 totals).
  public let workingSets: Int
  /// Non-warm-up sets whose session notes begin "Imported from ".
  public let importedSets: Int
  /// Newest native, non-warm-up set at or before the read's `now`; never a future date. Nil when
  /// there is no such set.
  public let lastDoneAt: Date?

  public init(workingSets: Int, importedSets: Int, lastDoneAt: Date?) {
    self.workingSets = workingSets
    self.importedSets = importedSets
    self.lastDoneAt = lastDoneAt
  }

  /// `nil` when both counts are zero. Otherwise:
  ///   native only      "38 working sets · last done 12 days ago"
  ///   native + imported "38 working sets · last done 12 days ago · 42 imported sets"
  ///   imported only    "42 imported sets"
  ///   future-only      "38 working sets" (no date)
  ///
  /// Imported sets are kept apart from native history, so they are never added to the native count
  /// and never make a "last done" claim. A native set dated after `now` is in the count but not in
  /// the phrase: the date is drawn only when it is at or before `now`, so a clock set back cannot
  /// turn a future date into "today".
  public func line(now: Date, calendar: Calendar = .current) -> String? {
    let parts = phrases(now: now, calendar: calendar)
    guard !parts.isEmpty else { return nil }
    return LibraryUsageCopy.joined(parts)
  }

  /// The same words for VoiceOver: the middle dots become commas:
  /// "38 working sets, last done 12 days ago, 42 imported sets".
  public func spokenLine(now: Date, calendar: Calendar = .current) -> String? {
    let parts = phrases(now: now, calendar: calendar)
    guard !parts.isEmpty else { return nil }
    return LibraryUsageCopy.spoken(parts)
  }

  /// The phrases in the order the line states them, without a separator.
  private func phrases(now: Date, calendar: Calendar) -> [String] {
    var parts: [String] = []
    if workingSets > 0 {
      parts.append(LibraryUsageCopy.workingSets(workingSets))
      if let lastDoneAt, lastDoneAt <= now {
        parts.append(LastDoneText.text(for: lastDoneAt, now: now, calendar: calendar))
      }
    }
    if importedSets > 0 {
      parts.append(LibraryUsageCopy.importedSets(importedSets))
    }
    return parts
  }
}

/// Every sentence the line can use. The view carries none of its own.
public enum LibraryUsageCopy {
  /// "38 working sets", "1 working set".
  public static func workingSets(_ count: Int) -> String {
    count == 1 ? "1 working set" : "\(count) working sets"
  }

  /// "42 imported sets", "1 imported set".
  public static func importedSets(_ count: Int) -> String {
    count == 1 ? "1 imported set" : "\(count) imported sets"
  }

  /// The on-screen separator: " · ".
  public static func joined(_ parts: [String]) -> String {
    parts.joined(separator: " · ")
  }

  /// The VoiceOver separator: ", ".
  public static func spoken(_ parts: [String]) -> String {
    parts.joined(separator: ", ")
  }
}
