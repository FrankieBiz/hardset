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

    if addedKg > 0, reps >= (repFloor ?? previous.reps) {
      return .beat(addedKg: addedKg, addedReps: addedReps)
    }

    return nil
  }

  /// The mark the set row shows: "+2.5 kg · +1 rep", "+1 rep", or "Matched".
  ///
  /// The load is rounded as every displayed load is rounded, so a pound lifter sees "+10 lb"
  /// rather than "+9.99 lb". A part only appears when it grew.
  public func label(in unit: WeightUnit) -> String {
    switch self {
    case .matched:
      return "Matched"
    case let .beat(addedKg, addedReps):
      var parts: [String] = []
      let added = StrengthMath.displayRounded(addedKg, in: unit)
      if added > 0 {
        let text = added == added.rounded()
          ? String(Int(added))
          : String(format: "%.1f", added)
        parts.append("+\(text) \(unit.abbreviation)")
      }
      if addedReps > 0 {
        parts.append(addedReps == 1 ? "+1 rep" : "+\(addedReps) reps")
      }
      return parts.joined(separator: " · ")
    }
  }
}
