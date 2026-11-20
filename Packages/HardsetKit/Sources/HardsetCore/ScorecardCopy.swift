import Foundation

/// The words on a finished workout's scorecard, held apart from any view so they are tested without
/// one, and so the share text says exactly what the screen says.
///
/// Counted by movement. Nothing here celebrates what was not earned: a first time is stated as a
/// first time, a movement that fell short is carried by the headline's count rather than drawn as a
/// failure, and a record is a movement the detector said set one.
public enum ScorecardCopy {
  /// "A record on 1 movement", "Records on 3 movements", or nil when none was set.
  public static func recordsText(_ card: WorkoutScorecard) -> String? {
    switch card.recordMovementCount {
    case ..<1: nil
    case 1: "A record on 1 movement"
    default: "Records on \(card.recordMovementCount) movements"
    }
  }

  /// "Biggest gain: Chest press, estimated max +6%": the movement, the metric and the change, or nil
  /// when nothing grew.
  public static func gainText(_ card: WorkoutScorecard) -> String? {
    guard let gain = card.biggestGain else { return nil }
    let metric = ProgressCopy.metricName(gain.metric).lowercased()
    return "Biggest gain: \(gain.exerciseName), \(metric) \(ProgressCopy.signedPercent(gain.fraction))"
  }

  /// The biggest-gain line as shared in text. A figure that is an estimate says how far to trust it
  /// in the same words the app's badge uses ("Moderate confidence"); on the screen the badge draws
  /// beside `gainText` instead, so the words are not said twice. A measured gain says nothing more.
  public static func gainShareText(_ card: WorkoutScorecard) -> String? {
    guard let line = gainText(card) else { return nil }
    guard let certainty = card.biggestGain?.certainty else { return line }
    return "\(line) · \(confidenceWords(certainty))"
  }

  /// Held in step with `CertaintyLevel.label` in HardsetUI, which Core cannot see.
  private static func confidenceWords(_ certainty: Certainty) -> String {
    switch certainty {
    case .high: "High confidence"
    case .moderate: "Moderate confidence"
    case .low: "Low confidence"
    case .unevaluated: "Not evaluated"
    }
  }

  /// What a movement earned, in the figures of its sets: "+1 rep", "+2.5 kg · +1 rep", "Record" when
  /// only a record applies, "Matched", or "First time on this machine". Nil for a movement that
  /// fell short, which the headline already counts.
  public static func markText(_ entry: WorkoutScorecard.Entry, unit: WeightUnit) -> String? {
    switch entry.outcome {
    case .beat(let comparison):
      guard let comparison else { return "Record" }
      let label = comparison.label(in: unit)
      return label.isEmpty ? "Ahead of last time" : label
    case .matched: return "Matched"
    case .firstTime: return "First time on this machine"
    case .notBeaten: return nil
    }
  }
}
