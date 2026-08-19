import Foundation

/// Invariant: a session's duration is derived from two immutable instants, never stored
/// and never recomputed against the wall clock at render time.
///
/// The reference app recomputed `Date().timeIntervalSince(startedAt)` while rendering, so
/// a session the user abandoned kept accumulating and shipped 9,749-minute workouts. Here
/// an unfinished session simply has no duration -- `nil`, not "however long ago it began".
public struct SessionTimeline: Hashable, Sendable, Codable {
  public let startedAt: Date
  public private(set) var finishedAt: Date?

  public init(startedAt: Date, finishedAt: Date? = nil) {
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }

  /// Elapsed time, or `nil` while the session is still open.
  ///
  /// Deliberately not a function of "now". A live view showing a running clock should use
  /// `Text(timerInterval:)`, which needs no ticks and no recomputation.
  public var duration: Duration? {
    guard let finishedAt else { return nil }
    let seconds = finishedAt.timeIntervalSince(startedAt)
    guard seconds >= 0 else { return nil }
    return .seconds(seconds)
  }

  public var isOpen: Bool { finishedAt == nil }

  /// Longest session the app treats as real. Anything beyond this is a forgotten
  /// session, not a workout, and is reported as implausible rather than displayed.
  public static let plausibleLimit: Duration = .seconds(6 * 60 * 60)

  /// True when the recorded span exceeds what a human workout can be. Used to quarantine
  /// bad rows instead of rendering them as achievements.
  public var isImplausible: Bool {
    guard let duration else { return false }
    return duration > Self.plausibleLimit
  }

  /// Close the session at `date`. Refuses to finish before it started, and refuses to
  /// re-finish an already-closed session, so `finishedAt` can never drift.
  public mutating func finish(at date: Date) throws {
    guard finishedAt == nil else { throw SessionTimelineError.alreadyFinished }
    guard date >= startedAt else { throw SessionTimelineError.finishedBeforeStart }
    finishedAt = date
  }
}

public enum SessionTimelineError: Error, Equatable, Sendable {
  case alreadyFinished
  case finishedBeforeStart
}
