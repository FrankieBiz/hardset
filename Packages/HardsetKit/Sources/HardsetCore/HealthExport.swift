import Foundation

/// The only kind of workout Hardset writes to Apple Health.
public enum HealthActivity: String, Hashable, Sendable {
  /// `HKWorkoutActivityType.traditionalStrengthTraining`: "strength training exercises primarily
  /// using machines or free weights".
  case traditionalStrengthTraining
}

/// One workout, as Apple Health will receive it.
///
/// Deliberately small. There is no energy, distance or heart-rate field, so none can be sent:
/// nothing in Hardset measures them, and an estimate written into Health becomes someone else's
/// "measurement" (spec 4.4). There is no indoor/outdoor flag either, because the app does not know.
public struct HealthWorkoutPlan: Hashable, Sendable {
  public let sessionID: SessionID
  public let activity: HealthActivity
  public let start: Date
  public let end: Date

  public init(sessionID: SessionID, activity: HealthActivity, start: Date, end: Date) {
    self.sessionID = sessionID
    self.activity = activity
    self.start = start
    self.end = end
  }

  /// Written as `HKMetadataKeyExternalUUID`, so a workout in Health can be traced to its session.
  public var externalID: String { sessionID.description }
}

/// Why a finished workout is not sent to Apple Health.
public enum HealthExportSkip: String, Hashable, Sendable, CaseIterable {
  /// The lifter has not turned it on. Checked first: when off, nothing else is looked at.
  case notEnabled
  case alreadyExported
  case stillOpen
  case nothingLogged
  /// The clock gives no length (it ran backwards, or start and end are the same instant).
  case lengthUnknown
  /// Longer than any real workout (`SessionTimeline.plausibleLimit`): a session left open.
  case implausiblyLong
  /// Ends after now: a clock has moved (this device's, or the one that synced it), so the times
  /// cannot be trusted. The cause is not knowable here, so the copy names none.
  case endsInFuture
}

public enum HealthExportDecision: Hashable, Sendable {
  case export(HealthWorkoutPlan)
  case skip(HealthExportSkip)
}

/// Decides whether a finished workout goes to Apple Health, and with which times.
///
/// Start and end are the session's own immutable instants (`SessionTimeline`), never "now" and
/// never the first and last set. A length the app would withhold on its own screens
/// (`DECISIONS.md` §21) is withheld from Health too.
public enum HealthExportPolicy {
  public static func decide(
    sessionID: SessionID,
    timeline: SessionTimeline,
    loggedSets: Int,
    isEnabled: Bool,
    alreadyExported: Bool,
    now: Date
  ) -> HealthExportDecision {
    guard isEnabled else { return .skip(.notEnabled) }
    guard !alreadyExported else { return .skip(.alreadyExported) }
    guard let end = timeline.finishedAt else { return .skip(.stillOpen) }
    guard loggedSets > 0 else { return .skip(.nothingLogged) }
    guard !timeline.isImplausible else { return .skip(.implausiblyLong) }
    guard timeline.knownLength != nil else { return .skip(.lengthUnknown) }
    guard end <= now else { return .skip(.endsInFuture) }
    return .export(
      HealthWorkoutPlan(
        sessionID: sessionID, activity: .traditionalStrengthTraining,
        start: timeline.startedAt, end: end))
  }
}

/// What became of one workout and Apple Health, for a line under the summary.
public enum HealthExportOutcome: Hashable, Sendable {
  case saved
  case failed
  case skipped(HealthExportSkip)
}

/// The words around the Apple Health setting and its results.
public enum HealthExportCopy {
  public static let settingTitle = "Save workouts to Apple Health"
  public static let settingFooter =
    "Each workout you finish on this iPhone is added to Health as strength training, with its "
    + "start and end time. Nothing else is sent: no calories, because nothing here measures them. "
    + "Hardset never reads your Health data."
  public static let accessDenied =
    "Hardset can't save to Health. Turn it on in Settings › Health › Data Access & Devices › Hardset."

  /// The line under the summary, or nil when there is nothing worth saying.
  public static func summaryLine(for outcome: HealthExportOutcome) -> String? {
    switch outcome {
    case .saved: return "Saved to Apple Health as strength training."
    case .failed: return "Couldn't save this workout to Apple Health. It is still saved here."
    case .skipped(let reason):
      switch reason {
      case .notEnabled, .alreadyExported, .stillOpen, .nothingLogged: return nil
      case .lengthUnknown, .implausiblyLong:
        return "Not sent to Apple Health, because its length is unknown."
      case .endsInFuture:
        return "Not sent to Apple Health, because its end time is in the future."
      }
    }
  }
}
