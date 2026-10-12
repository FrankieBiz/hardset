import Foundation

/// One of the three things the first screen promises (spec 3.5).
public struct FirstRunPromise: Hashable, Sendable, Identifiable {
  public let id: String
  public let symbolName: String
  public let title: String
  public let detail: String
}

/// The words on the one first-run screen.
///
/// Three promises, the privacy line, and Start. No questionnaire, no goals, no program: each of
/// those would ask the lifter for a commitment the app then grades them against, and the app
/// refuses to grade (`HANDOFF.md` §6). A test holds this copy to that.
public enum FirstRunCopy {
  public static let promises: [FirstRunPromise] = [
    FirstRunPromise(
      id: "honest", symbolName: "checkmark.seal", title: "Honest numbers",
      detail:
        "Every estimate says how sure it is and where it comes from. When the app does not know, "
        + "it says so."),
    FirstRunPromise(
      id: "machines", symbolName: "dumbbell", title: "Your machines",
      detail:
        "Loads are kept per machine, so the same number on two different leg presses is never "
        + "mixed up."),
    FirstRunPromise(
      id: "fast", symbolName: "hand.tap", title: "Fast logging",
      detail: "Last time's numbers are filled in. One tap logs a set."),
  ]

  /// Spec §3, item 6, word for word.
  public static let privacy = "No account. Your data stays on your devices and in your iCloud."
  public static let start = "Start"
  public static let gymFieldPrompt = "Gym name (optional)"
  public static let gymFootnote = "Machines are tracked per gym. You can add one later."
}

extension WeightUnit {
  /// The unit a lifter in this region most likely reads, from the locale's measurement system.
  ///
  /// A guess, shown as one (`Assumption.unitFromRegion`), with the correction beside it. Only the
  /// US system means pounds: the UK measurement system still weighs gym plates in kilograms.
  public static func inferred(from locale: Locale) -> WeightUnit {
    locale.measurementSystem == .us ? .pounds : .kilograms
  }

  /// The region's guess, or nil when the lifter already chose a unit.
  ///
  /// The first screen states a guess as a guess (`Assumption.unitFromRegion`). A stored choice is
  /// not a guess and is never replaced by one, so nothing is said "from your region" about it.
  public static func regionGuess(stored: WeightUnit?, locale: Locale) -> WeightUnit? {
    stored == nil ? inferred(from: locale) : nil
  }
}
