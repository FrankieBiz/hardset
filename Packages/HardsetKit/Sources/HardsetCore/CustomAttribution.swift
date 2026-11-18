import Foundation

/// The muscles a lifter says one of their own movements trains.
///
/// Nothing is inferred from a name. This is the lifter's word, stored as their own attribution:
/// the primary muscle gets a full set, each secondary half a set, and every one of them says it
/// came from the lifter, at moderate certainty, so volume never presents it as the catalogue's
/// finding. A movement the lifter has not tagged stays unattributed rather than guessed.
public struct CustomAttribution: Hashable, Sendable {
  /// A movement rarely has more than a few synergists worth crediting; more is a sign of guessing.
  public static let maximumSecondaries = 3

  public let primary: Muscle
  public let secondary: [Muscle]
  /// How the load is applied. Nil leaves a movement's equipment as it already is.
  public let modality: ExerciseModality?

  /// Nil when there are more than three secondaries, when a secondary repeats, or when one is the
  /// primary: a muscle cannot be credited twice for the same movement.
  public init?(primary: Muscle, secondary: [Muscle] = [], modality: ExerciseModality? = nil) {
    guard secondary.count <= Self.maximumSecondaries,
      Set(secondary).count == secondary.count,
      !secondary.contains(primary)
    else { return nil }
    self.primary = primary
    self.secondary = secondary
    self.modality = modality
  }

  /// The primary direct, the secondaries indirect, all moderate and sourced to the lifter.
  public var contributions: [MuscleContribution] {
    [MuscleContribution(primary, role: .direct, certainty: .moderate, source: .user)]
      + secondary.map { MuscleContribution($0, role: .indirect, certainty: .moderate, source: .user) }
  }
}
