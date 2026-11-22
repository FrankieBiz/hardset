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

  /// Highest rep count that still earns Moderate. Past it a formula's estimate is Low, and past
  /// `maximumEstimableReps` there is none.
  public static let maximumModerateReps = 10

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
      "Estimated from a completed set with the Epley formula, weight x (1 + reps / 30). This is "
      + "a plan-structure heuristic for comparing loads over time, not a measurement of maximal "
      + "strength. Validation work finds the formula most accurate near a 3-rep max and "
      + "overestimating from 5 reps, so a formula's figure is never reported with high "
      + "confidence: it is moderate up to 10 repetitions, low at 11 and 12, and no estimate is "
      + "produced above 12. Only a measured single is high.",
    citation: "Epley, B. (1985). Poundage Chart. Boyd Epley Workout.",
    validRange: "2-12 repetitions, sub-maximal to maximal effort."
  )

  /// Estimated one-rep max in kilograms, with certainty attached.
  ///
  /// Returns `.unevaluated` for non-positive input, implausible loads, and any set longer
  /// than `maximumEstimableReps`. There is no neutral fallback value.
  ///
  /// Certainty is decided here, beside the figure, and nowhere else: every surface that states how
  /// sure an estimate is reads `Claim.certainty` from this result. A formula's figure is capped at
  /// Moderate, because the research this app rests on finds Epley overestimating from a 5-rep max
  /// and recommends a band over a point; a measured single is the only High. The figure stays a
  /// point because `Claim<Double>` carries one value and every chart, record and trend reads it as
  /// one; the cap is what keeps that point from claiming more than it knows.
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

    // A formula is never High. Past the Moderate band, certainty keeps falling with the distance
    // from the low-rep region the equation was fitted on.
    let certainty: Certainty = reps <= maximumModerateReps ? .moderate : .low

    return Claim(estimate, certainty: certainty, source: epleySource)
  }

  /// Display rounding. Never two decimals: a load estimate implying 10 g precision reads
  /// as a measurement, which is exactly the impression guideline 1.4.1 penalises.
  /// Kilograms round to the nearest 0.5; pounds to the nearest 1.
  ///
  /// Conversion goes through `WeightUnit` rather than a local factor. This function used to
  /// carry its own `2.2046226218`, which is both a second definition of the pound and a
  /// slightly different one from the defined 1/0.45359237 — exactly the divergence the
  /// single-source-of-truth rule exists to prevent.
  public static func displayRounded(_ kg: Double, in unit: WeightUnit) -> Double {
    let displayed = unit.fromKilograms(kg)
    switch unit {
    case .pounds: return displayed.rounded()
    case .kilograms: return (displayed * 2).rounded() / 2
    }
  }
  /// One selection rule for chart points, Progress changes and receipt gains. Equal-valued
  /// estimates keep the better-supported claim, so set order cannot change the displayed trust.
  static func bestSupportedEstimate(_ estimates: [Claim<Double>]) -> Claim<Double>? {
    estimates.filter { $0.value != nil }.max {
      if $0.value != $1.value { return ($0.value ?? 0) < ($1.value ?? 0) }
      return $0.certainty < $1.certainty
    }
  }

}
