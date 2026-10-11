import Foundation

/// What a record says, on the row, in the summary and to VoiceOver.
///
/// Every line names what was beaten, so the claim can be checked rather than taken on trust. An
/// estimate is called "about" and is rounded like every derived number (guideline 1.4.1). It is
/// always in the lifter's unit: the PR banner was one of the places pounds mode read kilograms.
public enum RecordCopy {
  /// "105 kg, up from 100 kg".
  public static func detail(for record: PersonalRecord, formatter f: WeightFormatter) -> String {
    switch record.kind {
    case .heaviestLoad:
      let new = f.load(kilograms: record.weightKg)
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(f.load(kilograms: previous))"
    case .repsAtLoad:
      let new = "\(CountText.reps(record.reps)) at \(f.load(kilograms: record.weightKg))"
      guard let previousReps = record.previousReps else { return new }
      return "\(new), up from \(previousReps)"
    case .estimatedOneRepMax:
      let new = newEstimate(of: record).map { f.estimate(kilograms: $0) } ?? "estimated"
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(f.estimate(kilograms: previous))"
    }
  }

  /// "Heaviest weight: 105 kg, up from 100 kg".
  public static func line(for record: PersonalRecord, formatter: WeightFormatter) -> String {
    "\(record.kind.label): \(detail(for: record, formatter: formatter))"
  }

  /// Spoken when a set earns records, with units in full. Nil when there is nothing to say.
  public static func announcement(
    for records: [PersonalRecord], exerciseName: String, formatter: WeightFormatter
  ) -> String? {
    guard !records.isEmpty else { return nil }
    let lead =
      records.count == 1 ? "New record on \(exerciseName)." : "New records on \(exerciseName)."
    let parts = records.map { "\($0.kind.label): \(spokenDetail(for: $0, formatter: formatter))." }
    return ([lead] + parts).joined(separator: " ")
  }

  static func spokenDetail(for record: PersonalRecord, formatter f: WeightFormatter) -> String {
    switch record.kind {
    case .heaviestLoad:
      let new = f.spoken(kilograms: record.weightKg)
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(f.spoken(kilograms: previous))"
    case .repsAtLoad:
      let new = "\(CountText.reps(record.reps)) at \(f.spoken(kilograms: record.weightKg))"
      guard let previousReps = record.previousReps else { return new }
      return "\(new), up from \(previousReps)"
    case .estimatedOneRepMax:
      let new = newEstimate(of: record).map { spokenEstimate($0, f) } ?? "estimated"
      guard let previous = record.previousWeightKg else { return new }
      return "\(new), up from \(spokenEstimate(previous, f))"
    }
  }

  /// The record set's own estimate. `PersonalRecord` stores the set, not the estimate, so it is
  /// derived here the one way the detector derived it.
  private static func newEstimate(of record: PersonalRecord) -> Double? {
    StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps).value
  }

  /// Rounded exactly as the written estimate is, then spoken.
  private static func spokenEstimate(_ kilograms: Double, _ f: WeightFormatter) -> String {
    let rounded = StrengthMath.displayRounded(kilograms, in: f.unit)
    return "about \(f.spoken(kilograms: f.unit.toKilograms(rounded)))"
  }
}
