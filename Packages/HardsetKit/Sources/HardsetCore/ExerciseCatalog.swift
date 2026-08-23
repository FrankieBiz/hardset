import Foundation

/// A curated movement, shipped with the app.
///
/// The primary key is a **fixed** UUID string, not a freshly minted one. That is what makes
/// seeding idempotent across every device without a uniqueness constraint on `catalogSlug` —
/// which is impossible, because SQLiteData forbids `UNIQUE` on anything but the primary key for
/// synchronized tables. Two devices seeding the same catalogue therefore write the same rows and
/// converge rather than producing duplicates.
///
/// These ids are permanent. Changing one orphans every logged set that references it, so a
/// renamed movement keeps its id and only its `name` changes.
public struct CatalogExercise: Hashable, Sendable, Identifiable {
  /// Lowercase UUID string. Stored as a string so the literal in this file *is* the value that
  /// reaches the database, with no formatting step in between to get wrong.
  ///
  /// **Assign it with `python3 Tools/catalog_id.py <slug>`, never by hand.** It is a UUID version 5
  /// derived from the slug:
  ///
  ///     id = uuid5(uuid5(NAMESPACE_DNS, "catalog.hardset.app"), slug)
  ///
  /// Hashing rather than minting is what makes two devices converge instead of duplicating, and
  /// there is no database-level backstop: SQLiteData forbids `UNIQUE` on anything but the primary
  /// key of a synchronized table. The scheme is enforced by `CatalogIdSchemeTests`.
  ///
  /// The first 50 entries were authored before this was recorded and do not follow it. Their ids
  /// are grandfathered in that test and are permanent.
  public let id: String
  public let slug: String
  public let name: String
  public let modality: ExerciseModality
  /// Display and sort key only. Always also present in `contributions` at `role: .direct` —
  /// enforced by a test, because a drift between the two would mean the label and the arithmetic
  /// disagree about what the movement trains.
  public let primaryMuscle: Muscle
  /// The COMPLETE attribution, including the primary. Roles carry the arithmetic: a `direct`
  /// muscle is credited a full set, `indirect` half, and `stabilizer` nothing at all.
  public let contributions: [MuscleContribution]

  public init(
    id: String,
    slug: String,
    name: String,
    modality: ExerciseModality,
    primaryMuscle: Muscle,
    contributions: [MuscleContribution]
  ) {
    self.id = id
    self.slug = slug
    self.name = name
    self.modality = modality
    self.primaryMuscle = primaryMuscle
    self.contributions = contributions
  }

  public var uuid: UUID? { UUID(uuidString: id) }

  /// Sets credited to each muscle per completed working set. Stabilisers are absent, because a
  /// zero-weight entry in a volume map is indistinguishable from a muscle that was trained and
  /// produced nothing.
  public var creditedSets: [MuscleKey: Double] {
    var result: [MuscleKey: Double] = [:]
    for contribution in contributions where contribution.setWeight > 0 {
      result[contribution.key] = contribution.setWeight
    }
    return result
  }
}

/// How the load is applied. Drives which gyms can perform a movement, and later the plate maths.
public enum ExerciseModality: String, Sendable, CaseIterable, Codable {
  case barbell, dumbbell, machine, cable, bodyweight

  public var label: String {
    switch self {
    case .barbell: "Barbell"
    case .dumbbell: "Dumbbell"
    case .machine: "Machine"
    case .cable: "Cable"
    case .bodyweight: "Bodyweight"
    }
  }
}

/// The v1 seed catalogue.
///
/// **This is a starting seed, not the shipping catalogue.** Fifty movements covering every major
/// muscle group is enough to log real training and to build against; the research puts a
/// defensible v1 at roughly 240 hand-curated entries, which is 260–340 hours of content work
/// that has not been done. Nothing here should be read as that work being finished.
///
/// Every one of the 22 muscle tokens now has at least one movement crediting it `direct`. The five
/// that did not -- `rotatorCuff`, `obliques`, `adductors`, `hipAbductors`, `neck` -- were a recorded
/// content debt held as a shrinking allowlist in test 14; that allowlist is now empty, so the test
/// asserts the property permanently rather than tracking a debt.
///
/// On roles: grip is `stabilizer`, never `direct` on `forearms`, and isometric bracing is
/// `stabilizer`, never `indirect` on `abs`. The first draft of this file credited both as
/// secondaries, which under fractional counting would have invented roughly five sets of forearm
/// work for anyone doing twelve sets of pulling.
public enum ExerciseCatalog {
  public static let v1: [CatalogExercise] = [
    CatalogExercise(
      id: "2141aeb9-8b67-5832-91dd-0884206173a6",
      slug: "barbell-back-squat",
      name: "Barbell Back Squat",
      modality: .barbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs-MuscleTaxonomy-spec.md 5.7"),
        .init(.adductors, role: .indirect, certainty: .moderate, source: .trial, citation: "Kubo 2019, DOI 10.1007/s00421-019-04181-y"),
      ]
    ),
    CatalogExercise(
      id: "46b7b2d2-42f2-51e9-8535-d00134b5473b",
      slug: "barbell-front-squat",
      name: "Barbell Front Squat",
      modality: .barbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.upperBack, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs-MuscleTaxonomy-spec.md 5.7"),
        .init(.adductors, role: .indirect, certainty: .moderate, source: .trial, citation: "Kubo 2019, DOI 10.1007/s00421-019-04181-y"),
      ]
    ),
    CatalogExercise(
      id: "ae073606-c6d4-5ff9-8043-cddc202f5a5d",
      slug: "hack-squat",
      name: "Hack Squat",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "806fa1fa-8da3-5fae-b3ad-113e91d9fe98",
      slug: "leg-press",
      name: "Leg Press",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.glutes, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.adductors, role: .indirect, certainty: .moderate, source: .trial, citation: "Kubo 2019, DOI 10.1007/s00421-019-04181-y"),
      ]
    ),
    CatalogExercise(
      id: "3ff3622c-e166-581d-ab47-bdbee49afa0a",
      slug: "leg-extension",
      name: "Leg Extension",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "e15f932c-bd9f-5182-abc7-442763cfbce9",
      slug: "romanian-deadlift",
      name: "Romanian Deadlift",
      modality: .barbell,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.lats, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .indirect, certainty: .low, source: .anatomy),
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs-MuscleTaxonomy-spec.md 5.7"),
      ]
    ),
    CatalogExercise(
      id: "4d6fab67-0dfd-5304-ad2d-09710c22ecae",
      slug: "conventional-deadlift",
      name: "Conventional Deadlift",
      modality: .barbell,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.traps, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .indirect, certainty: .low, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.quadriceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs-MuscleTaxonomy-spec.md 5.7"),
      ]
    ),
    CatalogExercise(
      id: "049c5267-2be5-5e29-9aa5-9ddd5d4b5aac",
      slug: "seated-leg-curl",
      name: "Seated Leg Curl",
      modality: .machine,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.gastrocnemius, role: .indirect, certainty: .low, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "f442b84c-cc45-5437-97a3-b5fdde3f4327",
      slug: "lying-leg-curl",
      name: "Lying Leg Curl",
      modality: .machine,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.gastrocnemius, role: .indirect, certainty: .low, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "7665ad74-7f11-566b-be9a-bd8e9feb9d95",
      slug: "hip-thrust",
      name: "Hip Thrust",
      modality: .barbell,
      primaryMuscle: .glutes,
      contributions: [
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "3b270010-5d55-506b-8199-0f53b80440c0",
      slug: "bulgarian-split-squat",
      name: "Bulgarian Split Squat",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs-MuscleTaxonomy-spec.md 5.7"),
        .init(.adductors, role: .indirect, certainty: .moderate, source: .trial, citation: "Kubo 2019, DOI 10.1007/s00421-019-04181-y"),
      ]
    ),
    CatalogExercise(
      id: "940029be-c7e6-5d22-87f7-bbcef1d2143f",
      slug: "standing-calf-raise",
      name: "Standing Calf Raise",
      modality: .machine,
      primaryMuscle: .gastrocnemius,
      contributions: [
        .init(.gastrocnemius, role: .direct, certainty: .high, source: .trial, citation: "Kinoshita 2023, Front Physiol 14:1272106"),
        .init(.soleus, role: .direct, certainty: .high, source: .trial, citation: "Kinoshita 2023, Front Physiol 14:1272106"),
      ]
    ),
    CatalogExercise(
      id: "686670d7-855d-5b7e-8242-487e501b53ed",
      slug: "seated-calf-raise",
      name: "Seated Calf Raise",
      modality: .machine,
      primaryMuscle: .soleus,
      contributions: [
        .init(.soleus, role: .direct, certainty: .high, source: .trial, citation: "Kinoshita 2023, Front Physiol 14:1272106"),
      ]
    ),
    CatalogExercise(
      id: "668d15d9-1181-534e-b8e7-b3aece6c914a",
      slug: "barbell-bench-press",
      name: "Barbell Bench Press",
      modality: .barbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "29c5f886-e58a-5c94-9a20-a9e1a0485ec6",
      slug: "incline-barbell-bench-press",
      name: "Incline Barbell Bench Press",
      modality: .barbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "446a021e-d536-5b7d-96f2-d54f0141f73f",
      slug: "dumbbell-bench-press",
      name: "Dumbbell Bench Press",
      modality: .dumbbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "a0623ea0-682f-55d1-ad7a-0a720703ed7d",
      slug: "incline-dumbbell-press",
      name: "Incline Dumbbell Press",
      modality: .dumbbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "f19e9ce0-67c8-5d82-a2dd-6b1b5e1ada13",
      slug: "chest-press-machine",
      name: "Chest Press",
      modality: .machine,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "32ec43d7-a514-5845-98f0-7eae2a9e35ae",
      slug: "pec-deck",
      name: "Pec Deck",
      modality: .machine,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "6fd64ea9-2b23-5cec-bebe-ffd6caa409eb",
      slug: "cable-fly",
      name: "Cable Fly",
      modality: .cable,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "2bccda58-87f0-5418-b61f-2815619a73b5",
      slug: "dip",
      name: "Dip",
      modality: .bodyweight,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "259d7c14-500b-5c05-a39a-edc859c28a20",
      slug: "pull-up",
      name: "Pull-up",
      modality: .bodyweight,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "b9cfb919-457c-5873-b001-8a842d065545",
      slug: "chin-up",
      name: "Chin-up",
      modality: .bodyweight,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "df0d3510-25f3-5f98-a63e-232a13f30ef3",
      slug: "lat-pulldown",
      name: "Lat Pulldown",
      modality: .cable,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "611b1ae7-fc7e-5aba-a9b3-441b5684d30d",
      slug: "seated-cable-row",
      name: "Seated Cable Row",
      modality: .cable,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "0a21aac0-209b-5627-bf6d-80120ceb3a5b",
      slug: "barbell-row",
      name: "Barbell Row",
      modality: .barbell,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "9afbe580-9c2d-554e-bd5a-b5e98c523ca8",
      slug: "chest-supported-row",
      name: "Chest-Supported Row",
      modality: .machine,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "1f1b4e17-b104-51a6-98c2-96510a5d8c18",
      slug: "single-arm-dumbbell-row",
      name: "Single-Arm Dumbbell Row",
      modality: .dumbbell,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "9236077a-6784-5e79-969e-811b9f3aa16f",
      slug: "straight-arm-pulldown",
      name: "Straight-Arm Pulldown",
      modality: .cable,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "a5449d5a-4bd2-5b60-881c-dcbe4fd2ffad",
      slug: "overhead-press",
      name: "Overhead Press",
      modality: .barbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "af2a4a3b-01c7-5f3e-9c03-9c88e9f1a450",
      slug: "seated-dumbbell-press",
      name: "Seated Dumbbell Press",
      modality: .dumbbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "6b823bc2-186c-5022-9f4a-ece3d2b16d8b",
      slug: "lateral-raise",
      name: "Lateral Raise",
      modality: .dumbbell,
      primaryMuscle: .sideDelts,
      contributions: [
        .init(.sideDelts, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "513144a3-3f12-562b-af79-6673fddeb061",
      slug: "cable-lateral-raise",
      name: "Cable Lateral Raise",
      modality: .cable,
      primaryMuscle: .sideDelts,
      contributions: [
        .init(.sideDelts, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "ee726368-4213-5624-a385-170afbbc61af",
      slug: "reverse-pec-deck",
      name: "Reverse Pec Deck",
      modality: .machine,
      primaryMuscle: .rearDelts,
      contributions: [
        .init(.rearDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "332c9e5f-caf6-5820-87bb-eea1033c0705",
      slug: "face-pull",
      name: "Face Pull",
      modality: .cable,
      primaryMuscle: .rearDelts,
      contributions: [
        .init(.rearDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.rotatorCuff, role: .indirect, certainty: .low, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "8668ff40-3999-5eca-8b89-32c33747ec7a",
      slug: "barbell-curl",
      name: "Barbell Curl",
      modality: .barbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "58ea086e-223d-5d81-afbe-c1df1be63ef3",
      slug: "dumbbell-curl",
      name: "Dumbbell Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "95df7daa-8ada-52ff-b4ab-a4d0a27ae525",
      slug: "incline-dumbbell-curl",
      name: "Incline Dumbbell Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "78054ad4-73ab-540f-8a7b-995046cf6b88",
      slug: "preacher-curl",
      name: "Preacher Curl",
      modality: .machine,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "9eb4470d-e452-5e57-a8d6-0308ea34f0fb",
      slug: "hammer-curl",
      name: "Hammer Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "f8c888ce-a223-5025-8f87-a9c12de07a5a",
      slug: "cable-triceps-pushdown",
      name: "Cable Triceps Pushdown",
      modality: .cable,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "dc10175f-308b-56d7-8e8b-0e79f8c05190",
      slug: "overhead-cable-extension",
      name: "Overhead Cable Triceps Extension",
      modality: .cable,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "8ff53fd6-a4e6-5115-a5fd-b48e9674c34b",
      slug: "skull-crusher",
      name: "Skull Crusher",
      modality: .barbell,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .pellandTable1, citation: "Pelland 2025 Table 1, DOI 10.1007/s40279-025-02344-w"),
      ]
    ),
    CatalogExercise(
      id: "0b8342ec-7bd7-5b49-acea-077aec8249fd",
      slug: "close-grip-bench-press",
      name: "Close-Grip Bench Press",
      modality: .barbell,
      primaryMuscle: .triceps,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "8e9234e6-6ef4-5e84-8814-4fae767c0e83",
      slug: "shrug",
      name: "Shrug",
      modality: .barbell,
      primaryMuscle: .traps,
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "4bb8fb96-0fac-5e37-8f55-073860eefd4b",
      slug: "cable-crunch",
      name: "Cable Crunch",
      modality: .cable,
      primaryMuscle: .abs,
      contributions: [
        .init(.abs, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "d804c206-70be-559d-aade-02cbb159c723",
      slug: "hanging-leg-raise",
      name: "Hanging Leg Raise",
      modality: .bodyweight,
      primaryMuscle: .abs,
      contributions: [
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "404f7e81-5a0d-5a6b-bbf6-6eb72e85489d",
      slug: "back-extension",
      name: "Back Extension",
      modality: .bodyweight,
      primaryMuscle: .lowerBack,
      contributions: [
        .init(.lowerBack, role: .direct, certainty: .low, source: .anatomy),
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "472004ef-5b01-52f6-8550-519880c45d6c",
      slug: "wrist-curl",
      name: "Wrist Curl",
      modality: .dumbbell,
      primaryMuscle: .forearms,
      contributions: [
        .init(.forearms, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "0b0f4101-98b5-5e8e-8ece-fb8681e0ca21",
      slug: "reverse-wrist-curl",
      name: "Reverse Wrist Curl",
      modality: .dumbbell,
      primaryMuscle: .forearms,
      contributions: [
        .init(.forearms, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),

    // Closing the five tokens that had no `direct` credit anywhere in the first fifty. Every
    // attribution below is `.anatomy` at `.moderate` and cites nothing, deliberately: no
    // hypertrophy outcome trial isolates these tokens, and inventing a citation to look rigorous
    // is worse than saying plainly that this rests on anatomy.
    CatalogExercise(
      id: "4b71541d-f566-5ebc-9267-8f88d33bd409",
      slug: "hip-adduction-machine",
      name: "Hip Adduction",
      modality: .machine,
      primaryMuscle: .adductors,
      // Adduction is the only joint action moving under load, which is what makes this the first
      // entry to credit `adductors` directly -- squats and leg press only ever reached `indirect`.
      contributions: [
        .init(.adductors, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "4ee99752-2d90-548b-b47d-a5fa3c05f712",
      slug: "cable-hip-adduction",
      name: "Cable Hip Adduction",
      modality: .cable,
      primaryMuscle: .adductors,
      contributions: [
        .init(.adductors, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "bbfdb297-a7b9-540c-a745-68e77c79a7ee",
      slug: "hip-abduction-machine",
      name: "Hip Abduction",
      modality: .machine,
      primaryMuscle: .hipAbductors,
      contributions: [
        .init(.hipAbductors, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "905acb82-d9bb-56d6-8170-7e5b95bf4f16",
      slug: "cable-hip-abduction",
      name: "Cable Hip Abduction",
      modality: .cable,
      primaryMuscle: .hipAbductors,
      // Standing and unilateral, so the trunk resists the cable's lateral pull. That is bracing, so
      // `obliques` is a stabiliser at weight zero and contributes no volume.
      contributions: [
        .init(.hipAbductors, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.obliques, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "77586ce2-5439-56ac-9379-3dd6571ada16",
      slug: "cable-external-rotation",
      name: "Cable External Rotation",
      modality: .cable,
      primaryMuscle: .rotatorCuff,
      // The `rotatorCuff` token is four muscles held as one unit -- supraspinatus, infraspinatus,
      // subscapularis, teres minor. External rotation loads the two external rotators and leaves
      // subscapularis, an internal rotator, largely unloaded, so a full direct credit here is
      // coarser than the tissue actually trained. That is inherited from the taxonomy declining to
      // split internal from external rotation, not a claim this entry is making; it is recorded so
      // nobody reads the credit as more precise than it is.
      contributions: [
        .init(.rotatorCuff, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "d003fe75-6e68-5296-8ad3-9b5013954819",
      slug: "side-lying-dumbbell-external-rotation",
      name: "Side-Lying Dumbbell External Rotation",
      modality: .dumbbell,
      primaryMuscle: .rotatorCuff,
      contributions: [
        .init(.rotatorCuff, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "3b20f479-3952-59ad-99f0-1450f277f82e",
      slug: "torso-rotation-machine",
      name: "Torso Rotation Machine",
      modality: .machine,
      primaryMuscle: .obliques,
      // Trunk rotation against the pads is the loaded action. The pelvis is fixed by the seat, so
      // `abs` and `lowerBack` only brace.
      contributions: [
        .init(.obliques, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "372e9093-9b05-5632-9303-be01a069965d",
      slug: "dumbbell-side-bend",
      name: "Dumbbell Side Bend",
      modality: .dumbbell,
      primaryMuscle: .obliques,
      // Lateral flexion is the second action the token owns, so it ships alongside rotation rather
      // than crediting `obliques` from one action only. `forearms` is listed because the load is a
      // heavy held dumbbell, matching `shrug` and the curls rather than the light cable movements.
      contributions: [
        .init(.obliques, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "6e5357b6-3693-5e41-98bd-9bbe480fbee4",
      slug: "neck-extension",
      name: "Neck Extension",
      modality: .machine,
      primaryMuscle: .neck,
      // `neck` is already user-visible in the picker, so without these two entries a lifter could see
      // a muscle the catalogue can never train -- which is the hole test 14 exists to catch.
      contributions: [
        .init(.neck, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "a2efe5e1-ed63-5595-b0dc-2ddae8b521b9",
      slug: "neck-flexion",
      name: "Neck Flexion",
      modality: .machine,
      primaryMuscle: .neck,
      contributions: [
        .init(.neck, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),

    // Second content pass: filling the muscles that had one or two movements. Same standard as the
    // rest -- `.anatomy` at `.moderate` unless a real source says more, conservative roles, and
    // grip as a stabiliser rather than a credited muscle.
    CatalogExercise(
      id: "4428d922-f485-5917-b1d4-ee188d099d26",
      slug: "glute-bridge",
      name: "Glute Bridge",
      modality: .bodyweight,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "794b1311-b671-5828-a206-1085c17a8496",
      slug: "cable-glute-kickback",
      name: "Cable Glute Kickback",
      modality: .cable,
      primaryMuscle: .glutes,
      // Hip extension is the only loaded action, which is what makes glutes direct here rather
      // than a partner to a squat pattern.
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "18ea1768-2336-5ecb-be87-4a041a472459",
      slug: "dumbbell-step-up",
      name: "Dumbbell Step-Up",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs-MuscleTaxonomy-spec.md 5.7"),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "90352dc4-4898-51e4-b60c-63176e66d1bb",
      slug: "machine-hip-thrust",
      name: "Machine Hip Thrust",
      modality: .machine,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "f39be666-91fd-5107-ad6a-d207a3e9e795",
      slug: "standing-dumbbell-calf-raise",
      name: "Standing Dumbbell Calf Raise",
      modality: .dumbbell,
      primaryMuscle: .gastrocnemius,
      // Knee straight, so gastrocnemius is direct and soleus indirect. The catalogue's calf split
      // follows knee position, and a seeder test pins it.
      contributions: [
        .init(.gastrocnemius, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.soleus, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "7a00099f-eb65-54db-853d-8bccc3668f13",
      slug: "leg-press-calf-raise",
      name: "Leg Press Calf Raise",
      modality: .machine,
      primaryMuscle: .gastrocnemius,
      contributions: [
        .init(.gastrocnemius, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.soleus, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "b1823ab9-710c-5c93-95c2-abec156fcef9",
      slug: "seated-dumbbell-calf-raise",
      name: "Seated Dumbbell Calf Raise",
      modality: .dumbbell,
      primaryMuscle: .soleus,
      // Knee bent, which reverses the split: soleus direct, gastrocnemius indirect.
      contributions: [
        .init(.soleus, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.gastrocnemius, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "cf5ee176-b61f-5a7a-ae1c-7c47fc0e9c1d",
      slug: "dumbbell-shrug",
      name: "Dumbbell Shrug",
      modality: .dumbbell,
      primaryMuscle: .traps,
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "3545ec28-3abf-5ed6-934b-58c1183d4a73",
      slug: "machine-shrug",
      name: "Machine Shrug",
      modality: .machine,
      primaryMuscle: .traps,
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "3165b92f-69a8-5025-96b8-20784ca45451",
      slug: "barbell-good-morning",
      name: "Barbell Good Morning",
      modality: .barbell,
      primaryMuscle: .hamstrings,
      // Two direct credits, which is the cap: the hamstrings and the spinal erectors are both
      // resisting the same hip hinge under load rather than one assisting the other.
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "324e8a61-9bd5-5f01-814b-e4ca60b2fda5",
      slug: "reverse-hyperextension",
      name: "Reverse Hyperextension",
      modality: .machine,
      primaryMuscle: .lowerBack,
      contributions: [
        .init(.lowerBack, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.glutes, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.hamstrings, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "ed3d76bb-9cff-5547-911b-bc03640d3cc8",
      slug: "machine-shoulder-press",
      name: "Machine Shoulder Press",
      modality: .machine,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "61e39025-ee83-59d6-b0c3-f81353597b0c",
      slug: "dumbbell-front-raise",
      name: "Dumbbell Front Raise",
      modality: .dumbbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "5e0341b2-2a17-5aac-9493-3eaf196d3926",
      slug: "machine-lateral-raise",
      name: "Machine Lateral Raise",
      modality: .machine,
      primaryMuscle: .sideDelts,
      contributions: [
        .init(.sideDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.traps, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "7e6be534-1506-530b-85d8-4206069dc147",
      slug: "dumbbell-rear-delt-fly",
      name: "Dumbbell Rear Delt Fly",
      modality: .dumbbell,
      primaryMuscle: .rearDelts,
      contributions: [
        .init(.rearDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "b32f9835-c117-5549-bebf-4c31dcedcd5e",
      slug: "cable-rear-delt-fly",
      name: "Cable Rear Delt Fly",
      modality: .cable,
      primaryMuscle: .rearDelts,
      contributions: [
        .init(.rearDelts, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "be20282e-c9e0-5dd0-8744-5d8a30a25811",
      slug: "machine-crunch",
      name: "Machine Crunch",
      modality: .machine,
      primaryMuscle: .abs,
      contributions: [
        .init(.abs, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.obliques, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "b6558d83-74b1-537d-a7a2-0a69c3838c4f",
      slug: "hanging-knee-raise",
      name: "Hanging Knee Raise",
      modality: .bodyweight,
      primaryMuscle: .abs,
      // A hang, so grip is a stabiliser at weight zero -- never an indirect credit on forearms.
      contributions: [
        .init(.abs, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.obliques, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "7a3120f1-ebab-5f8a-bfb1-9fd9f648d333",
      slug: "ab-wheel-rollout",
      name: "Ab Wheel Rollout",
      modality: .bodyweight,
      primaryMuscle: .abs,
      contributions: [
        .init(.abs, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "ee61bb89-e650-5aa5-8cef-372d14926d42",
      slug: "barbell-reverse-curl",
      name: "Barbell Reverse Curl",
      modality: .barbell,
      primaryMuscle: .forearms,
      // Both direct: a pronated curl loads the wrist extensors and the elbow flexors through the
      // same excursion rather than one merely assisting.
      contributions: [
        .init(.forearms, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy),
      ]
    ),
    CatalogExercise(
      id: "48589228-e27d-5faf-aa1a-a0c32a5e5733",
      slug: "dumbbell-hammer-curl",
      name: "Dumbbell Hammer Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy),
        .init(.forearms, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
    ),
  ]

  public static var slugs: [String] { v1.map(\.slug) }

  /// Tokens with no `direct` credit in the seed. Content debt, not a design statement.
  ///
  /// Empty, and that is the point: every one of the 22 tokens now has at least one movement that
  /// trains it directly. Keeping the property rather than deleting it keeps test 14 meaningful --
  /// it now asserts permanently that no token can be shown in the picker while being untrainable.
  public static let unauthoredDirectTokens: Set<Muscle> = []
}
