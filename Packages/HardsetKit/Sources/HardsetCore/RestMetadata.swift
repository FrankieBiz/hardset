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

  public init(
    exerciseName: String,
    setOrdinal: Int,
    plannedSets: Int? = nil,
    machineName: String? = nil
  ) {
    self.exerciseName = exerciseName
    self.setOrdinal = setOrdinal
    self.plannedSets = plannedSets
    self.machineName = machineName
  }

  /// e.g. "Set 2 of 4" or "Set 2".
  public var setLabel: String {
    if let plannedSets { return "Set \(setOrdinal) of \(plannedSets)" }
    return "Set \(setOrdinal)"
  }
}
