import Foundation

/// Payload shown on the Lock Screen / Dynamic Island while a rest timer runs.
///
/// Foundation-only and deliberately small: it is archived into a Live Activity, compiled
/// into both the app and the widget extension, and gains its `AlarmKit.AlarmMetadata`
/// conformance in `HardsetAlarm` so this module stays platform-free.
public struct RestMetadata: Codable, Hashable, Sendable {
  /// Shown as the primary label, e.g. "Incline Press".
  public let exerciseName: String
  /// 1-based position of the set just completed.
  public let setOrdinal: Int
  /// Planned sets for this exercise, when known.
  public let plannedSets: Int?
  /// Machine the set was performed on, when identified.
  public let machineName: String?
  /// The whole rest this alarm belongs to: the length the lifter chose plus every ±15 s, with
  /// paused time left out. AlarmKit schedules each adjustment as a fresh alarm whose countdown is
  /// only what remained, so the Lock Screen bar is drawn from this instead, and does not restart
  /// at full after every tap. `nil` for a rest saved before it was recorded.
  ///
  /// Optional so a journal row or Live Activity written by an older build still decodes.
  public let totalRest: Duration?

  public init(
    exerciseName: String,
    setOrdinal: Int,
    plannedSets: Int? = nil,
    machineName: String? = nil,
    totalRest: Duration? = nil
  ) {
    self.exerciseName = exerciseName
    self.setOrdinal = setOrdinal
    self.plannedSets = plannedSets
    self.machineName = machineName
    self.totalRest = totalRest
  }

  /// The same payload with `totalRest` replaced.
  public func withTotalRest(_ total: Duration?) -> RestMetadata {
    RestMetadata(exerciseName: exerciseName, setOrdinal: setOrdinal, plannedSets: plannedSets,
      machineName: machineName, totalRest: total)
  }

  /// e.g. "Set 2 of 4" or "Set 2".
  public var setLabel: String {
    guard setOrdinal > 0 else { return "Rest" }
    if let plannedSets { return "Set \(setOrdinal) of \(plannedSets)" }
    return "Set \(setOrdinal)"
  }
}
