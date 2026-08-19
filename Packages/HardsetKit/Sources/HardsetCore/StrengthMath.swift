import Foundation

/// One-rep-max estimation that refuses to answer outside the range it was validated on.
///
/// The reference app applied raw Epley to anything with `reps <= 30`, so 60 kg x 25 reps
/// reported a 110 kg e1RM -- arithmetically faithful to the formula and physiologically
/// nonsense. Epley was fitted on low-rep sets; past roughly a dozen reps the estimate is
/// dominated by conditioning rather than maximal strength. Beyond that bound this returns
/// `.unevaluated` instead of a confident number.
public enum StrengthMath {
  /// Highest rep count still eligible for an estimate. Above this, the honest answer is
  /// that a set this long does not predict a one-rep max.
  public static let maximumEstimableReps = 12

  /// Sanity ceiling. Above this the input is a data-entry error, not a lift.
  public static let implausibleWeightKg: Double = 1_000

  public static let measuredSource = EvidenceSource(
    id: "one-rep-max.measured",
    title: "Measured single",
    methodology:
      "A completed single at this load is reported directly. No estimation is involved.",
    citation: nil,
    validRange: "Exactly 1 repetition."
  )

  public static let epleySource = EvidenceSource(
    id: "one-rep-max.epley",
    title: "Epley one-rep-max estimate",
    methodology:
      "Estimated from a completed set as weight x (1 + reps / 30). This is a plan-structure "
      + "heuristic for comparing loads over time, not a measurement of maximal strength. "
      + "Accuracy falls as repetitions rise, so certainty is reduced above 6 repetitions "
      + "and no estimate is produced above 12.",
    citation: "Epley, B. (1985). Poundage Chart. Boyd Epley Workout.",
    validRange: "2-12 repetitions, sub-maximal to maximal effort."
  )

  /// Estimated one-rep max in kilograms, with certainty attached.
  ///
  /// Returns `.unevaluated` for non-positive input, implausible loads, and any set longer
  /// than `maximumEstimableReps`. There is no neutral fallback value.
  public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Claim<Double> {
    guard weightKg > 0, weightKg <= implausibleWeightKg, reps >= 1 else {
      return .unevaluated(source: epleySource)
    }

    // A single at this load is not an estimate -- it is the observation itself.
    if reps == 1 {
      return Claim(weightKg, certainty: .high, source: measuredSource)
    }

    guard reps <= maximumEstimableReps else {
      return .unevaluated(source: epleySource)
    }

    let estimate = weightKg * (1.0 + Double(reps) / 30.0)

    // Certainty tracks distance from the low-rep region the equation was fitted on.
    let certainty: Certainty =
      switch reps {
      case 2...6: .high
      case 7...10: .moderate
      default: .low
      }

    return Claim(estimate, certainty: certainty, source: epleySource)
  }

  /// Display rounding. Never two decimals: a load estimate implying 10 g precision reads
  /// as a measurement, which is exactly the impression guideline 1.4.1 penalises.
  /// Kilograms round to the nearest 0.5; pounds to the nearest 1.
  public static func displayRounded(_ kg: Double, imperial: Bool) -> Double {
    if imperial {
      let lb = kg * 2.2046226218
      return (lb).rounded()
    }
    return (kg * 2).rounded() / 2
  }
}
