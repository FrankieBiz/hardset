import Foundation

/// How one saved workout has gone: its recent finished sessions, newest first, each with the
/// movements that session actually recorded and the working sets and measured volume of each.
///
/// The Progress tab answers "is this movement going anywhere?"; this answers the same question for
/// a saved workout. Nothing here compares one session with another, so nothing can claim a trend
/// the read did not compute. A session's movements come from the sets it logged, not from the
/// plan's current movements, so a movement added or removed mid-workout is still reported honestly.
public struct TemplateHistory: Hashable, Sendable {
  /// One movement a session actually logged, grouped by movement and machine.
  public struct Movement: Hashable, Sendable, Identifiable {
    /// `"exerciseID|machineID"`, stable across renders. Empty machine when none was recorded.
    public let id: String
    public let exerciseName: String
    /// `nil` when the sets recorded no machine.
    public let machineName: String?
    /// Logged working sets, never warm-ups.
    public let workingSetCount: Int
    /// Σ (weight × reps) over those working sets, in canonical kilograms.
    public let volumeKg: Double

    public init(
      id: String, exerciseName: String, machineName: String?, workingSetCount: Int, volumeKg: Double
    ) {
      self.id = id
      self.exerciseName = exerciseName
      self.machineName = machineName
      self.workingSetCount = workingSetCount
      self.volumeKg = volumeKg
    }
  }

  /// One finished session of the workout.
  public struct Session: Hashable, Sendable, Identifiable {
    public let id: SessionID
    public let finishedAt: Date
    /// Logged working sets in the session, never warm-ups.
    public let workingSetCount: Int
    /// Σ (weight × reps) over those working sets, in canonical kilograms.
    public let volumeKg: Double
    /// Plan order, then movement name. Only movements the session logged appear.
    public let movements: [Movement]

    public init(
      id: SessionID, finishedAt: Date, workingSetCount: Int, volumeKg: Double, movements: [Movement]
    ) {
      self.id = id
      self.finishedAt = finishedAt
      self.workingSetCount = workingSetCount
      self.volumeKg = volumeKg
      self.movements = movements
    }

    /// A session whose totals are its movements' totals, so the two can never disagree.
    public init(id: SessionID, finishedAt: Date, movements: [Movement]) {
      self.init(
        id: id, finishedAt: finishedAt,
        workingSetCount: movements.reduce(0) { $0 + $1.workingSetCount },
        volumeKg: movements.reduce(0) { $0 + $1.volumeKg },
        movements: movements)
    }
  }

  /// Newest first, at most `limit`.
  public let sessions: [Session]
  /// How many finished sessions this workout has in total, so "12 of 37" is a fact.
  public let totalSessionCount: Int
  public let limit: Int

  /// Trims and orders the page so the type's own promise holds even if a caller hands it more than
  /// the page it asked for. The store still reads only `limit` sessions, in this same order.
  public init(sessions: [Session], totalSessionCount: Int, limit: Int) {
    self.limit = max(limit, 0)
    self.totalSessionCount = totalSessionCount
    self.sessions = Array(
      sessions
        .sorted { lhs, rhs in
          if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt > rhs.finishedAt }
          return lhs.id.description < rhs.id.description
        }
        .prefix(max(limit, 0)))
  }
}

/// The words the workout history sheet uses, held apart from the view so they are tested without
/// one and the sheet cannot claim a comparison its read did not make.
public enum TemplateHistoryCopy {
  /// What the sheet says when the workout has no finished session yet.
  public static let empty = "No finished sessions from this workout yet."

  /// "12 of 37 finished sessions", or the singular forms. When the whole history fits on the page
  /// the count stands on its own rather than saying "12 of 12".
  public static func sessionsLine(shown: Int, total: Int) -> String {
    guard total > 1 else {
      return total == 1 ? "1 finished session" : "0 finished sessions"
    }
    if shown >= total { return "\(total) finished sessions" }
    return "\(shown) of \(total) finished sessions"
  }

  /// The working sets and measured volume of one movement or one session: "4 working sets ·
  /// 1,200 kg volume". `volume` is already formatted in the lifter's unit; the numbers are never
  /// compared with anything, so there is no percentage here.
  public static func movementDetail(sets: Int, volume: String) -> String {
    let count = sets == 1 ? "1 working set" : "\(sets) working sets"
    return "\(count) · \(volume) volume"
  }
}
