import Foundation

/// The one place kilograms become something else.
///
/// Storage is kilograms, always — `LoggedSet.weightKg` is canonical and no other unit is ever
/// persisted. Conversion happens at the display boundary and nowhere else. The alternative,
/// converting opportunistically at call sites, is how an app ends up with pounds in the
/// database and a volume total nobody can reproduce.
public enum WeightUnit: String, Sendable, CaseIterable, Codable {
  case kilograms
  case pounds

  public var abbreviation: String {
    switch self {
    case .kilograms: "kg"
    case .pounds: "lb"
    }
  }

  /// The international avoirdupois pound, exactly 0.45359237 kg by definition.
  private static let kilogramsPerPound = 0.45359237

  /// Canonical kilograms to whatever the user reads.
  public func fromKilograms(_ kilograms: Double) -> Double {
    switch self {
    case .kilograms: kilograms
    case .pounds: kilograms / Self.kilogramsPerPound
    }
  }

  /// Whatever the user typed back to canonical kilograms.
  public func toKilograms(_ value: Double) -> Double {
    switch self {
    case .kilograms: value
    case .pounds: value * Self.kilogramsPerPound
    }
  }

  /// Decimals a load is displayed and seeded with.
  ///
  /// One, which is finer than any plate stocked in either unit. Entry fields hold more than this so
  /// a lifter with micro-plates can type 62.75; this is about what the app *produces*.
  public static let displayFractionDigits = 1

  /// Canonical kilograms to a value the entry field can show exactly.
  ///
  /// The conversion and its rounding in one place, because separating them is how "185.19 lb"
  /// reached a set row: 84 kg read in pounds is 185.188..., and a prefill carrying that precision is
  /// both unloadable and inconsistent with the "185.2 lb" printed beside it.
  public func displayValue(fromKilograms kilograms: Double) -> Double {
    let scale = pow(10.0, Double(Self.displayFractionDigits))
    return (fromKilograms(kilograms) * scale).rounded() / scale
  }

  /// Smallest step the plate stack realistically moves in, in this unit.
  ///
  /// Used for stepper increments and for rounding a suggested load. Proposing 62.3 kg is a
  /// lie about what the equipment can do.
  public var plateIncrement: Double {
    switch self {
    case .kilograms: 2.5
    case .pounds: 5
    }
  }

  /// Rounds a display value to the nearest achievable step.
  public func roundedToIncrement(_ value: Double, increment: Double? = nil) -> Double {
    let step = increment ?? plateIncrement
    guard step > 0 else { return value }
    return (value / step).rounded() * step
  }
}
