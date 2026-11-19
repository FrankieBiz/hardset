import Foundation

/// How a logged set compares with the same set on the same machine last session.
///
/// This is the live "I'm winning" signal between sets. It says nothing when a set fell short,
/// and it names what grew so the mark is checkable rather than a vague celebration.
public enum SetComparison: Hashable, Sendable {
  /// `addedKg` is zero when only reps grew. `addedReps` may be negative after a load jump.
  case beat(addedKg: Double, addedReps: Int)
  /// The same load and the same reps, within the record detector's 0.01 kg tolerance.
  case matched

  /// Compares a set with its partner from last session.
  ///
  /// Sets are paired by their position among working sets, which the caller does by passing the
  /// partner. A set beats its partner when it has more reps at the same or more weight, or more
  /// weight with reps at or above the movement's rep-range floor. With no rep range, a heavier
  /// set must also match the reps, so a load jump alone is not claimed as a win.
  public static func compare(
    weightKg: Double,
    reps: Int,
    against previous: PriorSetRecord?,
    repFloor: Int?
  ) -> SetComparison? {
    guard let previous else { return nil }
    let addedKg = weightKg - previous.weightKg
    let sameLoad = abs(addedKg) < PersonalRecordDetector.loadMatchingTolerance

    if sameLoad && reps == previous.reps { return .matched }

    let addedReps = reps - previous.reps
    if reps > previous.reps, sameLoad || addedKg > 0 {
      return .beat(addedKg: sameLoad ? 0 : addedKg, addedReps: addedReps)
    }

    // Not within tolerance of the same load: a hair of float noise on a typed weight is not a jump.
    if !sameLoad, addedKg > 0, reps >= (repFloor ?? previous.reps) {
      return .beat(addedKg: addedKg, addedReps: addedReps)
    }

    return nil
  }

  /// The mark the set row shows: "+2.5 kg · +1 rep", "+1 rep", or "Matched".
  ///
  /// A difference between two typed loads is itself a fact about typed loads, so it keeps the
  /// precision they were typed with, up to two decimals: "+1.25 kg", never rounded to a plate the
  /// way an estimate is. A part only appears when it grew.
  public func label(in unit: WeightUnit, locale: Locale = .current) -> String {
    switch self {
    case .matched:
      return "Matched"
    case let .beat(addedKg, addedReps):
      var parts: [String] = []
      if let weight = Self.addedWeight(addedKg, in: unit, locale: locale) { parts.append("+\(weight)") }
      if addedReps > 0 { parts.append(addedReps == 1 ? "+1 rep" : "+\(addedReps) reps") }
      return parts.joined(separator: " · ")
    }
  }

  /// The mark as VoiceOver reads it: "plus 1 rep on last time", "plus 2.5 kg and 1 rep on last
  /// time", "matched last time". It names exactly what the visible mark names, and no more.
  public func spokenLabel(in unit: WeightUnit, locale: Locale = .current) -> String {
    switch self {
    case .matched:
      return "matched last time"
    case let .beat(addedKg, addedReps):
      var parts: [String] = []
      if let weight = Self.addedWeight(addedKg, in: unit, locale: locale) { parts.append(weight) }
      if addedReps > 0 { parts.append(addedReps == 1 ? "1 rep" : "\(addedReps) reps") }
      guard !parts.isEmpty else { return "ahead of last time" }
      return "plus " + parts.joined(separator: " and ") + " on last time"
    }
  }

  /// "2.5 kg" or "10 lb" as a typed load, only when the load grew by at least the 0.01 the display
  /// can show.
  private static func addedWeight(_ addedKg: Double, in unit: WeightUnit, locale: Locale) -> String? {
    guard (unit.fromKilograms(addedKg) * 100).rounded() >= 1 else { return nil }
    return "\(LoadText.entered(addedKg, in: unit, locale: locale)) \(unit.abbreviation)"
  }
}
