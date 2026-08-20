import Foundation

/// A selectable movement, as a picker sees it.
///
/// Lives in `HardsetCore` rather than in `HardsetStore` so the UI can render a list of movements
/// without taking a dependency on the database. `HardsetStore` maps rows into it.
///
/// Deliberately in its own file: `ExerciseCatalog.swift` is machine-generated and gets overwritten
/// wholesale, so anything hand-written there is one regeneration away from being lost.
public struct CatalogEntry: Hashable, Sendable, Identifiable {
  public let id: ExerciseID
  public let name: String
  /// Present for curated movements, `nil` for ones the user created.
  public let slug: String?
  public let isCurated: Bool
  /// `nil` when a stored row carries a modality this build does not know — a forward-compatible
  /// unknown rather than a crash or a silent default.
  public let modality: ExerciseModality?
  /// Display and sort key. A `MuscleKey`, not a `Muscle`, because a row may carry the reserved
  /// `"unknown"` sentinel or a token a newer app version introduced.
  public let primaryMuscle: MuscleKey
  /// The complete attribution as stored, including the primary at `role: .direct`.
  public let contributions: [MuscleContribution]
  /// What the decoder could not read. Carried rather than dropped: a tolerant decoder that hides
  /// its failures is worse than a strict one, so this travels with the value.
  public let unreadableEntryCount: Int

  public init(
    id: ExerciseID,
    name: String,
    slug: String?,
    isCurated: Bool,
    modality: ExerciseModality?,
    primaryMuscle: MuscleKey,
    contributions: [MuscleContribution],
    unreadableEntryCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.slug = slug
    self.isCurated = isCurated
    self.modality = modality
    self.primaryMuscle = primaryMuscle
    self.contributions = contributions
    self.unreadableEntryCount = unreadableEntryCount
  }

  /// Muscles credited a nonzero share of a set, in vocabulary order. Excludes stabilisers, so a
  /// caller cannot accidentally show grip as trained work.
  public var creditedMuscles: [MuscleContribution] {
    contributions.filter { $0.setWeight > 0 }
  }

  /// Muscles that are involved but credited nothing — grip, bracing, a held torso. Shown
  /// separately, if at all, and never in a volume total.
  public var stabilisingMuscles: [MuscleContribution] {
    contributions.filter { $0.role == .stabilizer }
  }

  /// True when the row has no usable attribution at all, so the UI must say "not attributed"
  /// rather than render an empty muscle list as though it meant "trains nothing".
  public var isUnattributed: Bool {
    !primaryMuscle.isAttributed && creditedMuscles.isEmpty
  }
}

extension CatalogExercise {
  /// The picker's view of a curated movement, without going through the database.
  ///
  /// Used by previews and by any caller that wants the shipped catalogue directly. Returns `nil`
  /// only for a malformed id literal, which a test already makes impossible.
  public var catalogEntry: CatalogEntry? {
    guard let uuid else { return nil }
    return CatalogEntry(
      id: ExerciseID(rawValue: uuid),
      name: name,
      slug: slug,
      isCurated: true,
      modality: modality,
      primaryMuscle: MuscleKey(primaryMuscle),
      contributions: contributions
    )
  }
}
