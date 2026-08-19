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
  public let primaryMuscle: String
  public let secondaryMuscles: [String]

  public init(
    id: String,
    slug: String,
    name: String,
    modality: ExerciseModality,
    primaryMuscle: String,
    secondaryMuscles: [String]
  ) {
    self.id = id
    self.slug = slug
    self.name = name
    self.modality = modality
    self.primaryMuscle = primaryMuscle
    self.secondaryMuscles = secondaryMuscles
  }

  public var uuid: UUID? { UUID(uuidString: id) }
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
public enum ExerciseCatalog {
  public static let v1: [CatalogExercise] = [
    CatalogExercise(
      id: "2141aeb9-8b67-5832-91dd-0884206173a6",
      slug: "barbell-back-squat",
      name: "Barbell Back Squat",
      modality: .barbell,
      primaryMuscle: "quadriceps",
      secondaryMuscles: ["glutes", "hamstrings", "lowerBack", "abs"]
    ),
    CatalogExercise(
      id: "46b7b2d2-42f2-51e9-8535-d00134b5473b",
      slug: "barbell-front-squat",
      name: "Barbell Front Squat",
      modality: .barbell,
      primaryMuscle: "quadriceps",
      secondaryMuscles: ["glutes", "abs", "upperBack"]
    ),
    CatalogExercise(
      id: "ae073606-c6d4-5ff9-8043-cddc202f5a5d",
      slug: "hack-squat",
      name: "Hack Squat",
      modality: .machine,
      primaryMuscle: "quadriceps",
      secondaryMuscles: ["glutes"]
    ),
    CatalogExercise(
      id: "806fa1fa-8da3-5fae-b3ad-113e91d9fe98",
      slug: "leg-press",
      name: "Leg Press",
      modality: .machine,
      primaryMuscle: "quadriceps",
      secondaryMuscles: ["glutes", "hamstrings"]
    ),
    CatalogExercise(
      id: "3ff3622c-e166-581d-ab47-bdbee49afa0a",
      slug: "leg-extension",
      name: "Leg Extension",
      modality: .machine,
      primaryMuscle: "quadriceps",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "e15f932c-bd9f-5182-abc7-442763cfbce9",
      slug: "romanian-deadlift",
      name: "Romanian Deadlift",
      modality: .barbell,
      primaryMuscle: "hamstrings",
      secondaryMuscles: ["glutes", "lowerBack", "lats"]
    ),
    CatalogExercise(
      id: "4d6fab67-0dfd-5304-ad2d-09710c22ecae",
      slug: "conventional-deadlift",
      name: "Conventional Deadlift",
      modality: .barbell,
      primaryMuscle: "hamstrings",
      secondaryMuscles: ["glutes", "lowerBack", "upperBack", "traps"]
    ),
    CatalogExercise(
      id: "049c5267-2be5-5e29-9aa5-9ddd5d4b5aac",
      slug: "seated-leg-curl",
      name: "Seated Leg Curl",
      modality: .machine,
      primaryMuscle: "hamstrings",
      secondaryMuscles: ["calves"]
    ),
    CatalogExercise(
      id: "f442b84c-cc45-5437-97a3-b5fdde3f4327",
      slug: "lying-leg-curl",
      name: "Lying Leg Curl",
      modality: .machine,
      primaryMuscle: "hamstrings",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "7665ad74-7f11-566b-be9a-bd8e9feb9d95",
      slug: "hip-thrust",
      name: "Hip Thrust",
      modality: .barbell,
      primaryMuscle: "glutes",
      secondaryMuscles: ["hamstrings"]
    ),
    CatalogExercise(
      id: "3b270010-5d55-506b-8199-0f53b80440c0",
      slug: "bulgarian-split-squat",
      name: "Bulgarian Split Squat",
      modality: .dumbbell,
      primaryMuscle: "quadriceps",
      secondaryMuscles: ["glutes", "hamstrings"]
    ),
    CatalogExercise(
      id: "940029be-c7e6-5d22-87f7-bbcef1d2143f",
      slug: "standing-calf-raise",
      name: "Standing Calf Raise",
      modality: .machine,
      primaryMuscle: "calves",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "686670d7-855d-5b7e-8242-487e501b53ed",
      slug: "seated-calf-raise",
      name: "Seated Calf Raise",
      modality: .machine,
      primaryMuscle: "calves",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "668d15d9-1181-534e-b8e7-b3aece6c914a",
      slug: "barbell-bench-press",
      name: "Barbell Bench Press",
      modality: .barbell,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts", "triceps"]
    ),
    CatalogExercise(
      id: "29c5f886-e58a-5c94-9a20-a9e1a0485ec6",
      slug: "incline-barbell-bench-press",
      name: "Incline Barbell Bench Press",
      modality: .barbell,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts", "triceps"]
    ),
    CatalogExercise(
      id: "446a021e-d536-5b7d-96f2-d54f0141f73f",
      slug: "dumbbell-bench-press",
      name: "Dumbbell Bench Press",
      modality: .dumbbell,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts", "triceps"]
    ),
    CatalogExercise(
      id: "a0623ea0-682f-55d1-ad7a-0a720703ed7d",
      slug: "incline-dumbbell-press",
      name: "Incline Dumbbell Press",
      modality: .dumbbell,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts", "triceps"]
    ),
    CatalogExercise(
      id: "f19e9ce0-67c8-5d82-a2dd-6b1b5e1ada13",
      slug: "chest-press-machine",
      name: "Chest Press",
      modality: .machine,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts", "triceps"]
    ),
    CatalogExercise(
      id: "32ec43d7-a514-5845-98f0-7eae2a9e35ae",
      slug: "pec-deck",
      name: "Pec Deck",
      modality: .machine,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts"]
    ),
    CatalogExercise(
      id: "6fd64ea9-2b23-5cec-bebe-ffd6caa409eb",
      slug: "cable-fly",
      name: "Cable Fly",
      modality: .cable,
      primaryMuscle: "chest",
      secondaryMuscles: ["frontDelts"]
    ),
    CatalogExercise(
      id: "2bccda58-87f0-5418-b61f-2815619a73b5",
      slug: "dip",
      name: "Dip",
      modality: .bodyweight,
      primaryMuscle: "chest",
      secondaryMuscles: ["triceps", "frontDelts"]
    ),
    CatalogExercise(
      id: "259d7c14-500b-5c05-a39a-edc859c28a20",
      slug: "pull-up",
      name: "Pull-up",
      modality: .bodyweight,
      primaryMuscle: "lats",
      secondaryMuscles: ["biceps", "upperBack", "forearms"]
    ),
    CatalogExercise(
      id: "b9cfb919-457c-5873-b001-8a842d065545",
      slug: "chin-up",
      name: "Chin-up",
      modality: .bodyweight,
      primaryMuscle: "lats",
      secondaryMuscles: ["biceps", "upperBack", "forearms"]
    ),
    CatalogExercise(
      id: "df0d3510-25f3-5f98-a63e-232a13f30ef3",
      slug: "lat-pulldown",
      name: "Lat Pulldown",
      modality: .cable,
      primaryMuscle: "lats",
      secondaryMuscles: ["biceps", "upperBack", "forearms"]
    ),
    CatalogExercise(
      id: "611b1ae7-fc7e-5aba-a9b3-441b5684d30d",
      slug: "seated-cable-row",
      name: "Seated Cable Row",
      modality: .cable,
      primaryMuscle: "upperBack",
      secondaryMuscles: ["lats", "biceps", "rearDelts"]
    ),
    CatalogExercise(
      id: "0a21aac0-209b-5627-bf6d-80120ceb3a5b",
      slug: "barbell-row",
      name: "Barbell Row",
      modality: .barbell,
      primaryMuscle: "upperBack",
      secondaryMuscles: ["lats", "biceps", "rearDelts", "lowerBack"]
    ),
    CatalogExercise(
      id: "9afbe580-9c2d-554e-bd5a-b5e98c523ca8",
      slug: "chest-supported-row",
      name: "Chest-Supported Row",
      modality: .machine,
      primaryMuscle: "upperBack",
      secondaryMuscles: ["lats", "biceps", "rearDelts"]
    ),
    CatalogExercise(
      id: "1f1b4e17-b104-51a6-98c2-96510a5d8c18",
      slug: "single-arm-dumbbell-row",
      name: "Single-Arm Dumbbell Row",
      modality: .dumbbell,
      primaryMuscle: "lats",
      secondaryMuscles: ["upperBack", "biceps"]
    ),
    CatalogExercise(
      id: "9236077a-6784-5e79-969e-811b9f3aa16f",
      slug: "straight-arm-pulldown",
      name: "Straight-Arm Pulldown",
      modality: .cable,
      primaryMuscle: "lats",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "a5449d5a-4bd2-5b60-881c-dcbe4fd2ffad",
      slug: "overhead-press",
      name: "Overhead Press",
      modality: .barbell,
      primaryMuscle: "frontDelts",
      secondaryMuscles: ["triceps", "sideDelts", "abs"]
    ),
    CatalogExercise(
      id: "af2a4a3b-01c7-5f3e-9c03-9c88e9f1a450",
      slug: "seated-dumbbell-press",
      name: "Seated Dumbbell Press",
      modality: .dumbbell,
      primaryMuscle: "frontDelts",
      secondaryMuscles: ["triceps", "sideDelts"]
    ),
    CatalogExercise(
      id: "6b823bc2-186c-5022-9f4a-ece3d2b16d8b",
      slug: "lateral-raise",
      name: "Lateral Raise",
      modality: .dumbbell,
      primaryMuscle: "sideDelts",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "513144a3-3f12-562b-af79-6673fddeb061",
      slug: "cable-lateral-raise",
      name: "Cable Lateral Raise",
      modality: .cable,
      primaryMuscle: "sideDelts",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "ee726368-4213-5624-a385-170afbbc61af",
      slug: "reverse-pec-deck",
      name: "Reverse Pec Deck",
      modality: .machine,
      primaryMuscle: "rearDelts",
      secondaryMuscles: ["upperBack"]
    ),
    CatalogExercise(
      id: "332c9e5f-caf6-5820-87bb-eea1033c0705",
      slug: "face-pull",
      name: "Face Pull",
      modality: .cable,
      primaryMuscle: "rearDelts",
      secondaryMuscles: ["upperBack"]
    ),
    CatalogExercise(
      id: "8668ff40-3999-5eca-8b89-32c33747ec7a",
      slug: "barbell-curl",
      name: "Barbell Curl",
      modality: .barbell,
      primaryMuscle: "biceps",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "58ea086e-223d-5d81-afbe-c1df1be63ef3",
      slug: "dumbbell-curl",
      name: "Dumbbell Curl",
      modality: .dumbbell,
      primaryMuscle: "biceps",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "95df7daa-8ada-52ff-b4ab-a4d0a27ae525",
      slug: "incline-dumbbell-curl",
      name: "Incline Dumbbell Curl",
      modality: .dumbbell,
      primaryMuscle: "biceps",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "78054ad4-73ab-540f-8a7b-995046cf6b88",
      slug: "preacher-curl",
      name: "Preacher Curl",
      modality: .machine,
      primaryMuscle: "biceps",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "9eb4470d-e452-5e57-a8d6-0308ea34f0fb",
      slug: "hammer-curl",
      name: "Hammer Curl",
      modality: .dumbbell,
      primaryMuscle: "biceps",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "f8c888ce-a223-5025-8f87-a9c12de07a5a",
      slug: "cable-triceps-pushdown",
      name: "Cable Triceps Pushdown",
      modality: .cable,
      primaryMuscle: "triceps",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "dc10175f-308b-56d7-8e8b-0e79f8c05190",
      slug: "overhead-cable-extension",
      name: "Overhead Cable Triceps Extension",
      modality: .cable,
      primaryMuscle: "triceps",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "8ff53fd6-a4e6-5115-a5fd-b48e9674c34b",
      slug: "skull-crusher",
      name: "Skull Crusher",
      modality: .barbell,
      primaryMuscle: "triceps",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "0b8342ec-7bd7-5b49-acea-077aec8249fd",
      slug: "close-grip-bench-press",
      name: "Close-Grip Bench Press",
      modality: .barbell,
      primaryMuscle: "triceps",
      secondaryMuscles: ["chest", "frontDelts"]
    ),
    CatalogExercise(
      id: "8e9234e6-6ef4-5e84-8814-4fae767c0e83",
      slug: "shrug",
      name: "Shrug",
      modality: .barbell,
      primaryMuscle: "traps",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "4bb8fb96-0fac-5e37-8f55-073860eefd4b",
      slug: "cable-crunch",
      name: "Cable Crunch",
      modality: .cable,
      primaryMuscle: "abs",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "d804c206-70be-559d-aade-02cbb159c723",
      slug: "hanging-leg-raise",
      name: "Hanging Leg Raise",
      modality: .bodyweight,
      primaryMuscle: "abs",
      secondaryMuscles: ["forearms"]
    ),
    CatalogExercise(
      id: "404f7e81-5a0d-5a6b-bbf6-6eb72e85489d",
      slug: "back-extension",
      name: "Back Extension",
      modality: .bodyweight,
      primaryMuscle: "lowerBack",
      secondaryMuscles: ["glutes", "hamstrings"]
    ),
    CatalogExercise(
      id: "472004ef-5b01-52f6-8550-519880c45d6c",
      slug: "wrist-curl",
      name: "Wrist Curl",
      modality: .dumbbell,
      primaryMuscle: "forearms",
      secondaryMuscles: []
    ),
    CatalogExercise(
      id: "0b0f4101-98b5-5e8e-8ece-fb8681e0ca21",
      slug: "reverse-wrist-curl",
      name: "Reverse Wrist Curl",
      modality: .dumbbell,
      primaryMuscle: "forearms",
      secondaryMuscles: []
    ),
  ]

  /// Every id is a well-formed UUID and no two entries collide. Asserted by a test rather than
  /// trusted, because a malformed literal here would fail at seed time on a user's device.
  public static var slugs: [String] { v1.map(\.slug) }
}

/// A selectable movement, as a picker sees it.
///
/// Lives here rather than in `HardsetStore` so the UI layer can render a list of movements
/// without taking a dependency on the database. `HardsetStore` maps rows into it.
public struct CatalogEntry: Hashable, Sendable, Identifiable {
  public let id: ExerciseID
  public let name: String
  /// Present for curated movements, `nil` for ones the user created.
  public let slug: String?
  public let isCurated: Bool
  /// `nil` when a stored row carries a modality this build does not know — a forward-compatible
  /// unknown rather than a crash or a silent default.
  public let modality: ExerciseModality?
  public let primaryMuscle: String
  public let secondaryMuscles: [String]

  public init(
    id: ExerciseID,
    name: String,
    slug: String?,
    isCurated: Bool,
    modality: ExerciseModality?,
    primaryMuscle: String,
    secondaryMuscles: [String]
  ) {
    self.id = id
    self.name = name
    self.slug = slug
    self.isCurated = isCurated
    self.modality = modality
    self.primaryMuscle = primaryMuscle
    self.secondaryMuscles = secondaryMuscles
  }
}
