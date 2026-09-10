import Foundation

/// Where the lifter is in their own plan.
///
/// On a three- or four-day split the question "which day am I due?" is answered from memory today,
/// and memory is exactly what a training log exists to replace. Nothing here is a recommendation:
/// every value is a fact about sessions the lifter already finished, and the app still refuses to
/// say what they *should* train. See `docs/SPLITS-spec.md` §1 for why that line matters.
public enum SplitRotation {
  /// One day of a plan, with when it was last trained.
  public nonisolated struct Day: Hashable, Sendable, Identifiable {
    public let id: SplitDayID
    /// The lifter's own arrangement. Used only to break ties, never to rank.
    public let position: Int
    /// When a finished session started from this day, or nil when none ever has.
    public let lastTrained: Date?

    public init(id: SplitDayID, position: Int, lastTrained: Date?) {
      self.id = id
      self.position = position
      self.lastTrained = lastTrained
    }
  }

  /// The day that has gone longest without being trained.
  ///
  /// Returns nil rather than guessing in the two cases where the question has no answer:
  ///
  /// - **Fewer than two days.** There is no rotation to be at a point in.
  /// - **No day ever trained.** Every day is equally untrained, so naming one would assert an
  ///   order the lifter has not established. A brand-new plan says nothing instead.
  ///
  /// A never-trained day counts as longest — it has been waiting since before the record begins.
  /// Ties break on `position` ascending, so the answer is stable across reads and follows the order
  /// the lifter arranged rather than whatever order the rows arrived in.
  public static func longestSinceTrained(among days: [Day]) -> SplitDayID? {
    guard days.count >= 2 else { return nil }
    let hasHistory = days.contains { $0.lastTrained != nil }
    guard hasHistory else { return nil }

    // `nil` sorts before every date, so an untrained day wins outright. Comparing on
    // `.distantPast` keeps that in one comparator instead of a special case at the call site.
    let ranked = days.min { left, right in
      let leftDate = left.lastTrained ?? .distantPast
      let rightDate = right.lastTrained ?? .distantPast
      if leftDate == rightDate { return left.position < right.position }
      return leftDate < rightDate
    }
    return ranked?.id
  }
}
