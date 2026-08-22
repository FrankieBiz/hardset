import Foundation

/// What a finished workout amounted to.
///
/// Assembled once when the session closes and then only read, so the summary screen does no work
/// per render and cannot disagree with the logger about what happened. Everything here is derived
/// from values that already exist -- `SessionVolume` for the totals, `SessionTimeline` for the
/// span, `PersonalRecordDetector` for the records -- because a second definition of "how many sets
/// was that" is a second thing that can be wrong.
public struct SessionOutcome: Hashable, Sendable {
  /// Working sets, warm-ups, tonnage, reps.
  public let volume: SessionVolume

  /// How long it took, or `nil` when that cannot honestly be stated.
  ///
  /// `nil` in two distinct situations that both mean "we are not going to claim a number": the
  /// session is still open, or the recorded span is longer than any real workout. The ancestor app
  /// shipped 9,749-minute sessions to its history screen as achievements; withholding is the whole
  /// point, so this is deliberately not an interval the caller can reconstruct.
  public let duration: Duration?

  /// Records set during this session, in the order they were achieved.
  public let records: [PersonalRecord]

  /// Movements with at least one logged set. An exercise that was added and never used is not
  /// something the lifter did.
  public let exerciseCount: Int

  public init(volume: SessionVolume, duration: Duration?, records: [PersonalRecord], exerciseCount: Int) {
    self.volume = volume
    self.duration = duration
    self.records = records
    self.exerciseCount = exerciseCount
  }

  public init(
    exercises: [ExerciseLogState],
    timeline: SessionTimeline,
    records: [PersonalRecord]
  ) {
    self.volume = SessionVolume(exercises: exercises)
    self.duration = timeline.isImplausible ? nil : timeline.duration
    self.records = records
    self.exerciseCount = exercises.count { $0.loggedCount > 0 }
  }

  /// True when nothing was logged. The summary must then say so rather than showing a row of
  /// zeroes, which reads as a measurement.
  public var isEmpty: Bool { volume.isEmpty }
}
