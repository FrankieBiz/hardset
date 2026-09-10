import Foundation

/// A rolling, half-open seven-day reporting window.
///
/// This is deliberately not a calendar week. A Monday boundary makes the volume tab appear to lose
/// a whole training week overnight; a window ending at a specific instant moves continuously with
/// the lifter instead. Adjacent windows meet but never overlap, so a set on their boundary is never
/// counted twice.
public nonisolated struct SevenDayWindow: Hashable, Sendable {
  public static let duration: TimeInterval = 7 * 86_400

  /// Exclusive upper bound.
  public let endingAt: Date

  public init(endingAt: Date) {
    self.endingAt = endingAt
  }

  /// Inclusive lower bound, paired with the exclusive `endingAt`.
  public var startingAt: Date {
    endingAt.addingTimeInterval(-Self.duration)
  }

  /// A neighbouring window. Negative values move into the past; positive values move forward.
  public func shifted(byWeeks weeks: Int) -> Self {
    Self(endingAt: endingAt.addingTimeInterval(Double(weeks) * Self.duration))
  }
}
