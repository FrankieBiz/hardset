import Foundation

/// The quick steps the keypad offers beside its keys, in the pad's own unit.
///
/// A step that lands on a load the equipment cannot hold is a small lie in the lifter's own log. So
/// the weight steps are the machine's real increment when one is recorded: a pin stack that moves in
/// 4.5 kg offers −9, −4.5, +4.5 and +9, and the same stack read in pounds offers the same steps as
/// pounds, 9.92 and 19.84. The row's own −/+ already use the machine's increment through
/// `machineIncrementKg`; this is the same number on the pad, so the two cannot disagree about what
/// one step is.
///
/// When no increment is recorded the pad falls back to 2.5 and 5 in whatever unit it is showing. That
/// claims nothing about the equipment, which is why the row's −/+ do not appear without a recorded
/// increment and these keys do: they are a convenience for a number the lifter is typing, not a
/// statement of what the machine does.
public enum QuickSteps {
  /// The step used when the machine's own is not recorded, in the pad's unit.
  public static let fallbackWeightStep: Double = 2.5

  /// Reps move by one or two. Never a machine's.
  public static let reps: [Double] = [-1, 1, 2]

  /// The weight steps, smallest first on each side: minus two, minus one, plus one, plus two.
  ///
  /// - Parameters:
  ///   - machineIncrementKg: The recorded increment in canonical kilograms, or `nil` when none is.
  ///     A value that is not finite and positive is treated as none.
  ///   - unit: The unit the pad shows. The increment is converted once, here, and rounded to the
  ///     pad's two decimal places so a step never carries digits the display cannot show.
  public static func weight(machineIncrementKg: Double?, unit: WeightUnit) -> [Double] {
    let step = machineStep(machineIncrementKg, unit: unit) ?? fallbackWeightStep
    return [-2 * step, -step, step, 2 * step]
  }

  /// Whether `weight(machineIncrementKg:unit:)` is the machine's own step and not the fallback, for
  /// a caller that wants to say so.
  public static func usesMachineStep(machineIncrementKg: Double?, unit: WeightUnit) -> Bool {
    machineStep(machineIncrementKg, unit: unit) != nil
  }

  private static func machineStep(_ kilograms: Double?, unit: WeightUnit) -> Double? {
    guard let kilograms, kilograms.isFinite, kilograms > 0 else { return nil }
    let shown = (unit.fromKilograms(kilograms) * 100).rounded() / 100
    return shown > 0 ? shown : nil
  }
}
