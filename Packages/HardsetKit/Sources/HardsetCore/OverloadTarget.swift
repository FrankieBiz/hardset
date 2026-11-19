import Foundation

/// A target for one set, chosen by double progression, with the rule that produced it.
///
/// The rule travels with the number so the set row can say why it suggests it. A target is a
/// suggestion from history, never a claim about what the lifter did.
public struct SetTarget: Hashable, Sendable {
  public let weightKg: Double
  public let reps: Int
  public let rule: Rule

  public enum Rule: Hashable, Sendable {
    /// One rep more than last time at the same load.
    case addRep
    /// Already at the top of the rep range; hold it without adding load.
    case holdTop
    /// Every set hit the top of the range, so add one load step and start at the bottom.
    case addLoad(stepKg: Double, isAssumedStep: Bool)
  }

  public init(weightKg: Double, reps: Int, rule: Rule) {
    self.weightKg = weightKg
    self.reps = reps
    self.rule = rule
  }

  /// The target as VoiceOver reads it after the row's own values: "target 11 reps", or, when the
  /// load itself is the news, "target 42.5 kg for 8 reps".
  public func spokenLabel(in unit: WeightUnit, locale: Locale = .current) -> String {
    let repsText = reps == 1 ? "1 rep" : "\(reps) reps"
    guard case .addLoad = rule else { return "target \(repsText)" }
    // A typed load plus a step is a typed load: 92.5 lb is said as 92.5, not rounded to a plate.
    let load = LoadText.entered(weightKg, in: unit, locale: locale)
    return "target \(load) \(unit.abbreviation) for \(repsText)"
  }

  /// Fixed copy, so a target never reads as an unexplained number.
  public var explanation: String {
    switch rule {
    case .addRep: "One more rep than last time"
    case .holdTop: "Top of your range; hold it"
    case let .addLoad(_, isAssumedStep):
      isAssumedStep
        ? "Every set hit the top of your range: add one plate (assumed step)"
        : "Every set hit the top of your range: add one step"
    }
  }
}

/// The double-progression rule for a movement with a rep range and history on this machine.
///
/// While every set is below the top of the range, one rep is added to each set at the same load.
/// Once every set reached the top at the same load, one load step is added and the sets return to
/// the bottom of the range. Bodyweight movements only add reps, because the estimate and the
/// load step do not apply to them.
public enum OverloadTarget {
  /// Exactly `setCount` targets, or nil per row when there is no history to build on.
  public static func targets(
    lastSets: [PriorSetRecord],
    range: RepRange,
    setCount: Int,
    incrementKg: Double?,
    unit: WeightUnit,
    addsLoad: Bool
  ) -> [SetTarget?] {
    guard setCount > 0 else { return [] }
    guard !lastSets.isEmpty, let last = lastSets.last else {
      return Array(repeating: nil, count: setCount)
    }

    let step: Double
    let isAssumedStep: Bool
    if let incrementKg, incrementKg > 0 {
      step = incrementKg
      isAssumedStep = false
    } else {
      step = unit.toKilograms(unit.plateIncrement)
      isAssumedStep = true
    }

    let heaviest = lastSets.map(\.weightKg).max() ?? last.weightKg
    let everySetAtTop = addsLoad && lastSets.allSatisfy {
      $0.reps >= range.upper && abs($0.weightKg - heaviest) < PersonalRecordDetector.loadMatchingTolerance
    }
    if everySetAtTop {
      return Array(
        repeating: SetTarget(
          weightKg: heaviest + step,
          reps: range.lower,
          rule: .addLoad(stepKg: step, isAssumedStep: isAssumedStep)
        ),
        count: setCount
      )
    }

    return (0..<setCount).map { index in
      let base = index < lastSets.count ? lastSets[index] : last
      if !addsLoad || base.reps < range.upper {
        return SetTarget(weightKg: base.weightKg, reps: base.reps + 1, rule: .addRep)
      }
      return SetTarget(weightKg: base.weightKg, reps: range.upper, rule: .holdTop)
    }
  }
}
