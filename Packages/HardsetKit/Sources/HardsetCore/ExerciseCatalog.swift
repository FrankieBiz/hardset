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

  /// Whether a one-rep max may be estimated from this modality's logged load.
  ///
  /// A bodyweight set records added load only, and body mass is not recorded with each set, so
  /// an estimate from the added load measures nothing: across rep counts it can rise while the
  /// load actually moved falls. Such estimates are unevaluated rather than guessed. An unknown
  /// modality must also withhold estimates until the load basis is known.
  public var estimatesOneRepMax: Bool { self != .bodyweight }

  public static let unknownLoadAssumption =
    "Logged load is assumed to be added load; the body's own load is unknown."
}

/// The v1 seed catalogue.
///
/// The original 50 entries and their permanent ids are retained. Additions are authored from
/// the corpus's loaded-action rule, with an explicit citation on every contribution. Anatomical
/// inference is not a movement-specific growth finding and never earns high certainty.
/// See docs/EXERCISE_CATALOGUE_AUDIT.md for execution, source limits, and omitted candidates.
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
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs/MuscleTaxonomy-spec.md 5.7"),
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
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs/MuscleTaxonomy-spec.md 5.7"),
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
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs/MuscleTaxonomy-spec.md 5.7"),
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
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs/MuscleTaxonomy-spec.md 5.7"),
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
        .init(.glutes, role: .direct, certainty: .moderate, source: .convention, citation: "Hardset convention; see docs/MuscleTaxonomy-spec.md 5.7"),
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

    CatalogExercise(
      id: "e2905df6-184f-5223-991c-6f2a05e5b83c",
      slug: "horizontal-leg-press",
      name: "Horizontal Leg Press",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "1c253d38-2b2c-5e8f-b2ba-c8fd251d7a0e",
      slug: "single-leg-press",
      name: "Single-Leg Press",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "f67ec066-8c46-58b1-bbb1-d56af7359f88",
      slug: "smith-machine-squat",
      name: "Smith Machine Squat",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "6a413ea2-8cb5-5c34-b885-c0187fdb9046",
      slug: "pendulum-squat",
      name: "Pendulum Squat",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "ae6add92-5dbc-5bd9-aa07-d4f4b2dab2f8",
      slug: "belt-squat",
      name: "Belt Squat",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "bb2fd281-bf5f-5500-930c-82922cd1020f",
      slug: "goblet-squat",
      name: "Goblet Squat",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.upperBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "df7a6ec9-6fc5-5aaa-80aa-7fff94c9d536",
      slug: "dumbbell-front-squat",
      name: "Dumbbell Front Squat",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.upperBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "895392c5-5946-5f9e-9f9f-76c008df9b1e",
      slug: "barbell-split-squat",
      name: "Barbell Split Squat",
      modality: .barbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "8fb3f86c-3cbc-595c-af59-613e84dbac1d",
      slug: "dumbbell-reverse-lunge",
      name: "Dumbbell Reverse Lunge",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "7570b68a-f102-5e79-9b60-19ba38555d92",
      slug: "dumbbell-walking-lunge",
      name: "Dumbbell Walking Lunge",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "ee1fb1dc-5b63-5f4d-9485-5366d71bc0ae",
      slug: "dumbbell-step-up",
      name: "Dumbbell Step-Up",
      modality: .dumbbell,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "fbcecc62-157d-5354-bbf5-98753130806f",
      slug: "smith-machine-split-squat",
      name: "Smith Machine Split Squat",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.adductors, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "5b7ccc74-a76f-58f1-825f-a9bdb8f8123c",
      slug: "single-leg-extension",
      name: "Single-Leg Extension",
      modality: .machine,
      primaryMuscle: .quadriceps,
      contributions: [
        .init(.quadriceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "0c1d994a-d6d4-5ec9-a755-ba541c72f0ec",
      slug: "standing-leg-curl",
      name: "Standing Leg Curl",
      modality: .machine,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.gastrocnemius, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: straight-knee plantarflexion or knee flexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "0b15b0cd-dda9-5cab-9233-3d1b8487442a",
      slug: "single-leg-seated-leg-curl",
      name: "Single-Leg Seated Leg Curl",
      modality: .machine,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.gastrocnemius, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: straight-knee plantarflexion or knee flexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "f73a70bc-6b4a-5c17-9026-c1adbc7cb4e0",
      slug: "nordic-hamstring-curl",
      name: "Nordic Hamstring Curl",
      modality: .bodyweight,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.gastrocnemius, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: straight-knee plantarflexion or knee flexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.glutes, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "3e104211-da92-5539-970f-881c37d4db81",
      slug: "dumbbell-romanian-deadlift",
      name: "Dumbbell Romanian Deadlift",
      modality: .dumbbell,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "8d6fb9df-f678-513a-aef3-0e8174e77185",
      slug: "single-leg-romanian-deadlift",
      name: "Single-Leg Romanian Deadlift",
      modality: .dumbbell,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "11c23621-900c-59d0-971c-a121bd9c4fb3",
      slug: "smith-machine-romanian-deadlift",
      name: "Smith Machine Romanian Deadlift",
      modality: .machine,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "b552ae66-dc15-5daf-aef9-b277d51281cc",
      slug: "barbell-good-morning",
      name: "Barbell Good Morning",
      modality: .barbell,
      primaryMuscle: .hamstrings,
      contributions: [
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "4e4b080d-cdb4-5459-8874-ae20b72e4e3b",
      slug: "cable-pull-through",
      name: "Cable Pull-Through",
      modality: .cable,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.hamstrings, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "10c199d7-67b5-5df1-90cc-afc8e50e3f64",
      slug: "machine-hip-thrust",
      name: "Machine Hip Thrust",
      modality: .machine,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.hamstrings, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "27bdb80a-58ce-5111-aa5c-a1c810e34ce4",
      slug: "dumbbell-hip-thrust",
      name: "Dumbbell Hip Thrust",
      modality: .dumbbell,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.hamstrings, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "5f01f79c-9a48-53f8-9471-8d3591f11bf4",
      slug: "glute-bridge",
      name: "Glute Bridge",
      modality: .bodyweight,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.hamstrings, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "44f3fdec-f2ea-5781-9701-65edd7964be2",
      slug: "cable-glute-kickback",
      name: "Cable Glute Kickback",
      modality: .cable,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.hamstrings, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "15f95a02-7a92-5cbd-865c-a0bb3e22d265",
      slug: "hip-extension-machine",
      name: "Hip Extension Machine",
      modality: .machine,
      primaryMuscle: .glutes,
      contributions: [
        .init(.glutes, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.hamstrings, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: knee flexion or hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "dd2e5975-a0e2-5982-8c72-4820006f649f",
      slug: "hip-adduction-machine",
      name: "Hip Adduction Machine",
      modality: .machine,
      primaryMuscle: .adductors,
      contributions: [
        .init(.adductors, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip adduction and assisted hip extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "065406b1-f7a6-5351-811e-7b2ed18c0ea7",
      slug: "hip-abduction-machine",
      name: "Hip Abduction Machine",
      modality: .machine,
      primaryMuscle: .hipAbductors,
      contributions: [
        .init(.hipAbductors, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "02057a33-45d9-532d-ac2e-da0d1a72c5f9",
      slug: "standing-cable-hip-abduction",
      name: "Standing Cable Hip Abduction",
      modality: .cable,
      primaryMuscle: .hipAbductors,
      contributions: [
        .init(.hipAbductors, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: hip abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "49be22e8-1366-5cdd-a555-6c80bd6d10cc",
      slug: "leg-press-calf-raise",
      name: "Leg Press Calf Raise",
      modality: .machine,
      primaryMuscle: .gastrocnemius,
      contributions: [
        .init(.gastrocnemius, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: straight-knee plantarflexion or knee flexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
        .init(.soleus, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: plantarflexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "23ab8549-58d8-5254-8618-f0e69fa5d398",
      slug: "single-leg-dumbbell-calf-raise",
      name: "Single-Leg Dumbbell Calf Raise",
      modality: .dumbbell,
      primaryMuscle: .gastrocnemius,
      contributions: [
        .init(.gastrocnemius, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: straight-knee plantarflexion or knee flexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
        .init(.soleus, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: plantarflexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "cb2361b3-5909-5633-baae-259a0be878e3",
      slug: "smith-machine-calf-raise",
      name: "Smith Machine Calf Raise",
      modality: .machine,
      primaryMuscle: .gastrocnemius,
      contributions: [
        .init(.gastrocnemius, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: straight-knee plantarflexion or knee flexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
        .init(.soleus, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: plantarflexion; docs/research/tax-spec.md §1 and §5 G1–G3; knee-position distinction §2.13; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "ec8578c4-366d-5977-a80a-93070d631405",
      slug: "decline-barbell-bench-press",
      name: "Decline Barbell Bench Press",
      modality: .barbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "b939d71c-f5fe-5508-b4ec-64fe360234c5",
      slug: "decline-dumbbell-bench-press",
      name: "Decline Dumbbell Bench Press",
      modality: .dumbbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "24503c7a-041f-5b53-8c7a-b8cdb79554aa",
      slug: "smith-machine-bench-press",
      name: "Smith Machine Bench Press",
      modality: .machine,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "3ebf28e1-450d-5ea1-bea7-beccced28baf",
      slug: "incline-smith-machine-press",
      name: "Incline Smith Machine Press",
      modality: .machine,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "9ffce5c0-923a-59d4-93ca-2cd1745d978f",
      slug: "incline-chest-press-machine",
      name: "Incline Chest Press Machine",
      modality: .machine,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "78b378ae-a39a-5cdb-afe3-f3bab040564e",
      slug: "single-arm-chest-press-machine",
      name: "Single-Arm Chest Press Machine",
      modality: .machine,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "4f0768b2-122f-5ff7-9bfc-4bda84e71cf9",
      slug: "cable-chest-press",
      name: "Cable Chest Press",
      modality: .cable,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "5b56ffb4-1518-5d75-a9de-697b1e3ad616",
      slug: "single-arm-cable-chest-press",
      name: "Single-Arm Cable Chest Press",
      modality: .cable,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "0e44d160-2616-54a8-8379-146931df1522",
      slug: "dumbbell-floor-press",
      name: "Dumbbell Floor Press",
      modality: .dumbbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "edeebedb-a3f6-586e-a06e-7c066f1a6ed6",
      slug: "push-up",
      name: "Push-up",
      modality: .bodyweight,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "21bb7b64-594f-57d9-9429-a9f919bc0283",
      slug: "feet-elevated-push-up",
      name: "Feet-Elevated Push-up",
      modality: .bodyweight,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "7c7632c3-b753-56e1-a68b-9b9098834d33",
      slug: "dumbbell-fly",
      name: "Dumbbell Fly",
      modality: .dumbbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.biceps, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "102c6f8b-83f8-53ad-bbcd-09891518c99b",
      slug: "incline-dumbbell-fly",
      name: "Incline Dumbbell Fly",
      modality: .dumbbell,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.biceps, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "57001253-2efa-5f56-b266-8e40e7cabe1c",
      slug: "single-arm-cable-fly",
      name: "Single-Arm Cable Fly",
      modality: .cable,
      primaryMuscle: .chest,
      contributions: [
        .init(.chest, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.biceps, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "d1179d9f-d9c8-5ace-8688-0314c5ebbba4",
      slug: "shoulder-press-machine",
      name: "Shoulder Press Machine",
      modality: .machine,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "5b56a6b3-6433-520a-b5ea-a2b57655060c",
      slug: "smith-machine-shoulder-press",
      name: "Smith Machine Shoulder Press",
      modality: .machine,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "5089c302-cd90-5970-b686-dc94bb3c13e1",
      slug: "standing-dumbbell-press",
      name: "Standing Dumbbell Press",
      modality: .dumbbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "e5a401b2-eff5-5c17-b529-570c75394b7a",
      slug: "single-arm-dumbbell-press",
      name: "Single-Arm Dumbbell Press",
      modality: .dumbbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.sideDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "03a64531-3141-50e5-8e75-d4953a624bb2",
      slug: "single-arm-landmine-press",
      name: "Single-Arm Landmine Press",
      modality: .barbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .low, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.chest, role: .indirect, certainty: .low, source: .anatomy, citation: "Anatomical inference: loaded shoulder horizontal adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.triceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "2d6ec09b-84a6-53e6-bfd7-f5b1c174f800",
      slug: "lateral-raise-machine",
      name: "Lateral Raise Machine",
      modality: .machine,
      primaryMuscle: .sideDelts,
      contributions: [
        .init(.sideDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "9654efee-6e33-5729-b4e8-bafe5b2ce9a1",
      slug: "cable-front-raise",
      name: "Cable Front Raise",
      modality: .cable,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "981ce31e-f2f3-5009-aff9-335dcd5282f0",
      slug: "dumbbell-front-raise",
      name: "Dumbbell Front Raise",
      modality: .dumbbell,
      primaryMuscle: .frontDelts,
      contributions: [
        .init(.frontDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder flexion in pressing or raising; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "13294f04-2b27-5bd1-bc9b-48a66b6f525c",
      slug: "bent-over-dumbbell-reverse-fly",
      name: "Bent-Over Dumbbell Reverse Fly",
      modality: .dumbbell,
      primaryMuscle: .rearDelts,
      contributions: [
        .init(.rearDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "bb498c3b-4669-59b8-8d9f-f38bc4856406",
      slug: "cable-reverse-fly",
      name: "Cable Reverse Fly",
      modality: .cable,
      primaryMuscle: .rearDelts,
      contributions: [
        .init(.rearDelts, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "a439709b-9e00-55dc-89a3-51006d7aa2db",
      slug: "single-arm-pulldown-machine",
      name: "Single-Arm Pulldown Machine",
      modality: .machine,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "ca8408a6-5e08-5223-b38a-0b487ea8f5de",
      slug: "chest-supported-t-bar-row",
      name: "Chest-Supported T-Bar Row",
      modality: .machine,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "8a47a1b5-b34e-5814-98c0-c4989ad8b2d8",
      slug: "pulldown-machine",
      name: "Pulldown Machine",
      modality: .machine,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "f66e9f9c-2d6d-5e84-b11b-635a3d478886",
      slug: "single-arm-cable-pulldown",
      name: "Single-Arm Cable Pulldown",
      modality: .cable,
      primaryMuscle: .lats,
      contributions: [
        .init(.lats, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.upperBack, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "b906a1f7-1a0b-5ac0-aae7-cb41887a9141",
      slug: "seated-row-machine",
      name: "Seated Row Machine",
      modality: .machine,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "85ab49da-e9a5-5131-8dab-19562938dde8",
      slug: "single-arm-seated-row-machine",
      name: "Single-Arm Seated Row Machine",
      modality: .machine,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "433e2872-1109-5a55-a8d2-ee2ce8cc870d",
      slug: "t-bar-row",
      name: "T-Bar Row",
      modality: .barbell,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "5f9f76ed-8791-5895-ab0c-2b946c6d3fb8",
      slug: "chest-supported-dumbbell-row",
      name: "Chest-Supported Dumbbell Row",
      modality: .dumbbell,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "12e269f5-477f-5026-a374-325ca13e9514",
      slug: "inverted-row",
      name: "Inverted Row",
      modality: .bodyweight,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "24a1df97-f6d8-558c-9cc4-87025dcc70e1",
      slug: "single-arm-cable-row",
      name: "Single-Arm Cable Row",
      modality: .cable,
      primaryMuscle: .upperBack,
      contributions: [
        .init(.upperBack, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular retraction and depression; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.lats, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder extension or adduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.rearDelts, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: shoulder horizontal abduction; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.abs, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "6066e5f1-1c3d-5750-83e8-e839f2521af0",
      slug: "dumbbell-shrug",
      name: "Dumbbell Shrug",
      modality: .dumbbell,
      primaryMuscle: .traps,
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular elevation; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "909b81f8-499f-59d2-b7b2-41747a6cf63c",
      slug: "smith-machine-shrug",
      name: "Smith Machine Shrug",
      modality: .machine,
      primaryMuscle: .traps,
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular elevation; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "3e652709-04a8-59e2-a6d1-84a7fe708a2b",
      slug: "cable-shrug",
      name: "Cable Shrug",
      modality: .cable,
      primaryMuscle: .traps,
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: scapular elevation; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "ffe80dbf-440e-5cf0-b4ce-20319316af55",
      slug: "cable-curl",
      name: "Cable Curl",
      modality: .cable,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "35bed3c3-bd3c-5498-aeec-8bac4aa722ca",
      slug: "high-cable-curl",
      name: "High Cable Curl",
      modality: .cable,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.sideDelts, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "d9ddd21f-cfae-5c45-8609-64bdb7c72b16",
      slug: "bayesian-cable-curl",
      name: "Bayesian Cable Curl",
      modality: .cable,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "90da314f-d29c-5af3-ae93-bc8786b6bd88",
      slug: "dumbbell-preacher-curl",
      name: "Dumbbell Preacher Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "bc9b0302-8e79-595e-a3c5-7695fb71c4ee",
      slug: "concentration-curl",
      name: "Concentration Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "07733656-d105-5448-ba9b-abc6f13a78df",
      slug: "spider-curl",
      name: "Spider Curl",
      modality: .dumbbell,
      primaryMuscle: .biceps,
      contributions: [
        .init(.biceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow flexion; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "fee28904-aaeb-55db-95c1-6daf95ca8c03",
      slug: "triceps-extension-machine",
      name: "Triceps Extension Machine",
      modality: .machine,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "e12543f3-ad3a-5c01-89c4-c2272d4c1f47",
      slug: "single-arm-cable-pushdown",
      name: "Single-Arm Cable Pushdown",
      modality: .cable,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "43b1256b-d26a-57f9-8d24-804fec6a46a7",
      slug: "dumbbell-overhead-triceps-extension",
      name: "Dumbbell Overhead Triceps Extension",
      modality: .dumbbell,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "78dc1ab8-854e-5150-b415-d20b0c0af8c5",
      slug: "single-arm-dumbbell-overhead-extension",
      name: "Single-Arm Dumbbell Overhead Extension",
      modality: .dumbbell,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "413e31b3-de6e-5033-aa4a-fd7a7df41cf8",
      slug: "lying-dumbbell-triceps-extension",
      name: "Lying Dumbbell Triceps Extension",
      modality: .dumbbell,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "186a2884-b83b-5357-9c86-128d0dddd8fc",
      slug: "dumbbell-triceps-kickback",
      name: "Dumbbell Triceps Kickback",
      modality: .dumbbell,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.rearDelts, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "c9b06f22-eb1a-58c9-930a-12535b1dfd0a",
      slug: "cable-triceps-kickback",
      name: "Cable Triceps Kickback",
      modality: .cable,
      primaryMuscle: .triceps,
      contributions: [
        .init(.triceps, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: elbow extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.rearDelts, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
        .init(.lowerBack, role: .stabilizer, certainty: .moderate, source: .convention, citation: "Hardset zero-credit convention: held grip or posture; docs/MuscleTaxonomy-spec.md §5 G2 (not a claim that isometrics cannot grow muscle)."),
      ]
    ),
    CatalogExercise(
      id: "0f4eac20-91a3-547d-8375-b064c621e985",
      slug: "barbell-wrist-curl",
      name: "Barbell Wrist Curl",
      modality: .barbell,
      primaryMuscle: .forearms,
      contributions: [
        .init(.forearms, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: wrist flexion or extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
    CatalogExercise(
      id: "665d4bf6-6894-5a87-b955-5bb4f62a4e05",
      slug: "barbell-reverse-wrist-curl",
      name: "Barbell Reverse Wrist Curl",
      modality: .barbell,
      primaryMuscle: .forearms,
      contributions: [
        .init(.forearms, role: .direct, certainty: .moderate, source: .anatomy, citation: "Anatomical inference: wrist flexion or extension; docs/research/tax-spec.md §1 and §5 G1–G3; not a variant-specific growth trial."),
      ]
    ),
  ]

  public static var slugs: [String] { v1.map(\.slug) }

  /// Tokens with no `direct` credit in the seed. Content debt, not a design statement.
  public static let unauthoredDirectTokens: Set<Muscle> = [
    .rotatorCuff, .obliques, .neck,
  ]
}
