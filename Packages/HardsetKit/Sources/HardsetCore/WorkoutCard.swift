import Foundation

/// How long ago a saved workout was last done, in the words a lifter would use.
public enum LastDoneText {
  /// "not done yet", "last done today", "last done yesterday", "last done 4 days ago", then weeks
  /// from two weeks on, then months from two months on.
  ///
  /// Counted in calendar days, not hours, so a workout finished late last night is "yesterday" this
  /// morning however few hours have passed. A date in the future, from a clock set back, reads as
  /// today rather than as a negative number.
  public static func text(for lastDone: Date?, now: Date, calendar: Calendar = .current) -> String {
    guard let lastDone else { return "not done yet" }
    return "last done " + phrase(for: lastDone, now: now, calendar: calendar)
  }

  /// The same calendar-day wording without the "last done" prefix: "today", "yesterday",
  /// "4 days ago", then weeks from two weeks on, then months from two months on. Shared so a
  /// live card's dated "Last time" line cannot drift from the workout cards' wording.
  public static func phrase(for lastDone: Date, now: Date, calendar: Calendar = .current) -> String {
    let days =
      calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: lastDone), to: calendar.startOfDay(for: now)
      ).day ?? 0
    switch days {
    case ..<1: return "today"
    case 1: return "yesterday"
    case 2..<14: return "\(days) days ago"
    case 14..<60: return "\(days / 7) weeks ago"
    default: return "\(days / 30) months ago"
    }
  }
}

/// One saved workout as the Train tab's cards draw it.
///
/// The workout done longest ago, or never, is first and the one offered: Upper A and Upper B take
/// turns without any schedule. Its line reads like a coach's note: it is up next, when it was last
/// done, and how that session went against the one before it.
public struct WorkoutCard: Hashable, Sendable, Identifiable {
  /// How the most recent session of one workout compared with last time, from its scorecard.
  public struct LastResult: Hashable, Sendable {
    public let workout: TemplateID
    public let beaten: Int
    public let compared: Int

    public init(workout: TemplateID, beaten: Int, compared: Int) {
      self.workout = workout
      self.beaten = beaten
      self.compared = compared
    }
  }

  public let id: TemplateID
  public let name: String
  public let movementCount: Int
  public let isUpNext: Bool
  /// "Up next · last done 4 days ago · beat 4 of 6 last time", or "Last done 4 days ago".
  public let contextLine: String
  /// "3 movements", "1 movement".
  public let movementsLine: String

  public init(
    id: TemplateID, name: String, movementCount: Int, isUpNext: Bool, contextLine: String,
    movementsLine: String
  ) {
    self.id = id
    self.name = name
    self.movementCount = movementCount
    self.isUpNext = isUpNext
    self.contextLine = contextLine
    self.movementsLine = movementsLine
  }

  /// Cards in the order they are offered: up next first, then the rest as the rotation reaches them.
  ///
  /// `lastResult` is claimed only for the workout it belongs to, and only when something was
  /// actually compared. A first session has nothing to have beaten, and saying "beat 0 of 0" would
  /// be a claim about nothing.
  public static func cards(
    templates: [WorkoutTemplate], now: Date, calendar: Calendar = .current,
    lastResult: LastResult? = nil
  ) -> [WorkoutCard] {
    WorkoutRotation.upNextOrder(templates).enumerated().map { index, template in
      let isUpNext = index == 0
      let lastDone = LastDoneText.text(for: template.lastDoneAt, now: now, calendar: calendar)
      var line: String
      if isUpNext {
        line = "Up next · " + lastDone
        if let lastResult, lastResult.workout == template.id, lastResult.compared > 0 {
          line += " · beat \(lastResult.beaten) of \(lastResult.compared) last time"
        }
      } else {
        line = lastDone.prefix(1).uppercased() + lastDone.dropFirst()
      }
      let count = template.exercises.count
      return WorkoutCard(
        id: template.id, name: template.name, movementCount: count, isUpNext: isUpNext,
        contextLine: line, movementsLine: count == 1 ? "1 movement" : "\(count) movements")
    }
  }
}
