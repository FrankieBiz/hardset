import Foundation

/// What a finished workout contained, as the summary sheet shows it.
///
/// A value with no database handle, so the sheet can only render what `WorkoutSummaryStore` read
/// from storage. Named `WorkoutSummary` because `SessionSummary` is already the history row.
/// Deliberately absent: any target, goal, streak or comparison with a plan. The summary states
/// what was done and does not grade it (`HANDOFF.md` §6).
public struct WorkoutSummary: Hashable, Sendable {
  public struct RecordLine: Hashable, Sendable, Identifiable {
    public let setID: SetID
    public let exerciseName: String
    public let machineName: String?
    public let record: PersonalRecord

    public init(setID: SetID, exerciseName: String, machineName: String?, record: PersonalRecord) {
      self.setID = setID
      self.exerciseName = exerciseName
      self.machineName = machineName
      self.record = record
    }

    public var id: String { "\(setID)-\(record.kind.rawValue)" }
  }

  public struct MuscleLine: Hashable, Sendable, Identifiable {
    public let muscle: MuscleKey
    public let fractionalSets: Double
    /// True when some sets could not be attributed, so this figure is a floor, not a total.
    public let isLowerBound: Bool

    public init(muscle: MuscleKey, fractionalSets: Double, isLowerBound: Bool) {
      self.muscle = muscle
      self.fractionalSets = fractionalSets
      self.isLowerBound = isLowerBound
    }

    public var id: String { muscle.storedValue }

    /// "4 sets", "1 set", "0.5 sets", or "≥ 2.5 sets" for a lower bound. The "≥" is the caveat:
    /// it is said in the number itself, not in a warning colour (spec §3, item 2).
    public func setsText(locale: Locale = .current) -> String {
      "\(isLowerBound ? "≥ " : "")\(count(locale)) \(noun)"
    }

    /// For VoiceOver, which reads "≥" badly: "at least 2.5 sets".
    public func spokenSetsText(locale: Locale = .current) -> String {
      "\(isLowerBound ? "at least " : "")\(count(locale)) \(noun)"
    }

    /// The number alone, for a row that draws its noun elsewhere: "12", "2.5", "≥ 2,5". Through the
    /// locale, so a German lifter reads "2,5"; the volume tab printed "%.1f" and always used ".".
    public func countText(locale: Locale = .current) -> String {
      "\(isLowerBound ? "≥ " : "")\(count(locale))"
    }

    /// How sure the app is of this figure (spec 3.1).
    public var certainty: Certainty {
      SetCounting.certainty(for: muscle, fractionalSets: fractionalSets)
    }

    private func count(_ locale: Locale) -> String {
      WeightFormatter.text(fractionalSets, fractionDigits: 1, locale: locale)
    }

    private var noun: String { fractionalSets == 1 ? "set" : "sets" }
  }

  public let sessionID: SessionID
  public let timeline: SessionTimeline
  public let volume: SessionVolume
  public let records: [RecordLine]
  public let muscles: [MuscleLine]
  public let unattributedSets: Int
  public let machinesUsed: [String]

  public init(
    sessionID: SessionID,
    timeline: SessionTimeline,
    volume: SessionVolume,
    records: [RecordLine],
    muscles: [MuscleLine],
    unattributedSets: Int,
    machinesUsed: [String]
  ) {
    self.sessionID = sessionID
    self.timeline = timeline
    self.volume = volume
    self.records = records
    self.muscles = muscles
    self.unattributedSets = unattributedSets
    self.machinesUsed = machinesUsed
  }

  /// The workout's length, or nil when it cannot be known. That covers a session still open, one
  /// that took no time, one whose clock ran backwards, and one longer than any real workout (`DECISIONS.md` §21).
  public var length: Duration? {
    timeline.knownLength
  }

  public var lengthText: String { length?.clockString ?? "Length unknown" }

  public var isEmpty: Bool { volume.isEmpty }

  /// Muscles credited this session, most first, then in vocabulary order.
  public static func muscleLines(from report: MuscleVolumeReport) -> [MuscleLine] {
    let order = Dictionary(uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) })
    return report.fractionalSets
      .filter { $0.value > 0 }
      .map { MuscleLine(muscle: $0.key, fractionalSets: $0.value, isLowerBound: report.isLowerBound) }
      .sorted { lhs, rhs in
        if lhs.fractionalSets != rhs.fractionalSets { return lhs.fractionalSets > rhs.fractionalSets }
        let l = lhs.muscle.muscle.flatMap { order[$0] } ?? Int.max
        let r = rhs.muscle.muscle.flatMap { order[$0] } ?? Int.max
        if l != r { return l < r }
        return lhs.muscle.storedValue < rhs.muscle.storedValue
      }
  }
}
