import Foundation

/// How much one press of a plus or minus should move a load.
///
/// Entering a weight is the single most repeated action in the app -- twenty-odd times a session --
/// and almost every one of those entries is the last one plus or minus one step. Typing three digits
/// to move 82.5 to 85 is the tax this removes.
///
/// The step is returned **in the unit on screen**, because plates do not exist in the abstract. A
/// gym stocked in kilograms has 1.25 kg as its smallest plate, so a bar moves in 2.5 kg; a gym
/// stocked in pounds has 2.5 lb, so the same bar moves in 5 lb. Converting one into the other gives
/// 2.27 kg or 5.51 lb -- a number no gym on earth can produce.
///
/// The exception is a machine whose real step is recorded. That wins, unconverted-in-spirit: a stack
/// that moves in 5 kg jumps offers 11 lb steps to someone reading pounds, which looks odd and is
/// simply true. The equipment does not care which unit the lifter thinks in.
public nonisolated enum PlateMath {
  /// Smallest step offered when nothing better is known, per unit.
  ///
  /// Chosen as "two of the smallest plate a commercial gym reliably stocks", since a barbell is
  /// loaded from both ends. Machines and cables get the same figure: selectorised stacks vary far
  /// too much to guess, and the honest fix there is recording the machine's own increment, which
  /// overrides this entirely.
  static func defaultStep(for modality: ExerciseModality?, unit: WeightUnit) -> Double {
    switch modality {
    // Derived from `WeightUnit.plateIncrement` rather than restating 2.5 and 5, so there is one
    // definition of what a plate step is and these cases describe only how they differ from it.
    case .barbell, .machine, .cable, .none: unit.plateIncrement
    // Dumbbells come in a ladder, not in plates. 2 kg is the common commercial rung; in pounds the
    // ladder rung and the plate step are both 5.
    case .dumbbell: unit == .kilograms ? 2 : unit.plateIncrement
    // Added load on a pull-up or dip is a belt carrying one small plate, so the step is finer.
    case .bodyweight: unit.plateIncrement / 2
    }
  }

  /// The step for one press, in the unit on screen.
  ///
  /// - Parameter machineIncrementKg: The equipment's own step, when it has been recorded. Takes
  ///   precedence over every default, because it is the only figure here that is a fact rather than
  ///   a convention.
  public static func step(
    modality: ExerciseModality?,
    machineIncrementKg: Double?,
    unit: WeightUnit
  ) -> Double {
    if let machineIncrementKg, machineIncrementKg > 0 {
      // Rounded to display precision, so the step the control is labelled with is exactly the step
      // it applies. A 5 kg stack is 11.023 lb; carrying that would label a button "11" and move the
      // field by 11.02, and pressing it three times would not equal three times the label.
      //
      // The cost is a bounded approximation of the real stack -- 0.02 lb a press, under a third of a
      // pound across ten -- which is far below the smallest plate in either unit. The alternative,
      // an honest 11.02 on the button, is a number no stack is marked with and no lifter reads.
      return unit.displayValue(fromKilograms: machineIncrementKg)
    }
    // Deliberately *not* rounded. These are exact by construction, and 1.25 kg -- a belt with one
    // small plate -- would become 1.3 and walk every press off the plate grid.
    return defaultStep(for: modality, unit: unit)
  }

  /// Applies one press to the displayed value.
  ///
  /// `nil` in means `nil` out: an empty field has no basis to step from, and starting a bench press
  /// at 2.5 kg because the lifter pressed plus would be an invention. The caller disables the
  /// control instead of substituting a number.
  ///
  /// Clamped at zero. Below it there is no such thing as a set, and for a bodyweight movement zero
  /// is a real, meaningful value -- the set is the body.
  public static func stepped(_ displayed: Double?, by presses: Int, step: Double) -> Double? {
    guard let displayed, step > 0 else { return nil }
    let moved = displayed + Double(presses) * step
    // Two decimals, matching what the entry field can hold. Without any rounding, repeated presses
    // accumulate binary dust and a field that read 85 reads 84.99999999999999; with only one, a
    // 1.25 kg step becomes 1.3 and walks off the plate grid.
    return max(0, (moved * 100).rounded() / 100)
  }
}
