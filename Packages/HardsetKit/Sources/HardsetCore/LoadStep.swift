import Foundation

/// How far one ± press moves a load, in the unit the lifter reads.
///
/// The machine's own stack increment when it is known, because a +2.5 kg press on a stack that
/// moves in 5 kg jumps proposes a weight the machine cannot be set to. Otherwise the unit's plate
/// step. Steps only adjust a value that exists: an empty field stays empty, since a ± that
/// invented a load would be a `?? 0` with extra steps.
public struct LoadStep: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    /// The machine's `stackIncrementKg`.
    case machine
    /// No usable increment is known, so 2.5 kg or 5 lb.
    case unitDefault
  }

  /// The step in display units. A 5 kg stack read in pounds steps by 11.02 lb, which is what the
  /// pin really moves.
  public let amount: Double
  public let source: Source

  public init(machineIncrementKg: Double?, unit: WeightUnit) {
    if let increment = machineIncrementKg, increment.isFinite, increment > 0 {
      amount = unit.fromKilograms(increment)
      source = .machine
    } else {
      amount = unit.plateIncrement
      source = .unitDefault
    }
  }

  /// `value` moved by `steps` increments, or nil when nothing should change: there is no value
  /// to move, or the result would be negative.
  public func moved(_ value: Double?, by steps: Int) -> Double? {
    guard let value else { return nil }
    let result = value + amount * Double(steps)
    // The tolerance absorbs binary noise, so 2.5 − 2.5 lands on zero rather than a hair below it.
    guard result > -1e-9 else { return nil }
    return max(0, result)
  }
}
