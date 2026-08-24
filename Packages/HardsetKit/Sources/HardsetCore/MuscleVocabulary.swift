import Foundation

/// The one place a muscle key becomes words.
///
/// This table used to live inside `ExercisePickerView`, with a comment correctly calling it "the ONE
/// place that turns a key into words". It is data rather than presentation, and keeping it in the UI
/// layer had a cost: `HardsetStore` cannot import `HardsetUI`, so the catalogue's search could not
/// see the vocabulary and matched only movement names -- "quads" and "cable" returned nothing on a
/// list that is *grouped* by muscle. It also left `Muscle.displayNameKey` and
/// `MuscleGroup.displayNameKey` -- a whole localisation scheme -- with no readers, while the words
/// themselves were hardcoded in a view.
///
/// Keyed off `displayNameKey`, so the localisation scheme is the thing being read. When a String
/// Catalog exists, `resolve` becomes `String(localized:)` and this stays the only edit.
public nonisolated enum MuscleVocabulary {
  /// Words for one muscle key.
  ///
  /// Deliberately does not title-case an unknown raw value: a generated display name looks authored
  /// and is not. "Not attributed" and "Not recognised" stay distinct, because "nobody has attributed
  /// this yet" and "a newer version of the app knows something this one does not" are different
  /// facts about the row.
  public static func displayName(_ key: MuscleKey) -> String {
    resolve(key.displayNameKey) ?? key.muscle?.rawValue ?? "Not recognised"
  }

  public static func displayName(_ muscle: Muscle) -> String {
    resolve(muscle.displayNameKey) ?? muscle.rawValue
  }

  public static func displayName(_ group: MuscleGroup) -> String {
    resolve(group.displayNameKey) ?? group.rawValue
  }

  /// Every word this vocabulary can produce for a muscle, for callers that need to match against
  /// them -- catalogue search, most obviously.
  public static var allMuscleNames: [String] {
    Muscle.allCases.map(displayName)
  }

  /// The English copy, by key. One lookup, one table.
  private static func resolve(_ key: String) -> String? { english[key] }

  private static let english: [String: String] = [
    "muscle.chest": "Chest",
    "muscle.frontDelts": "Front delts",
    "muscle.sideDelts": "Side delts",
    "muscle.rearDelts": "Rear delts",
    "muscle.rotatorCuff": "Rotator cuff",
    "muscle.lats": "Lats",
    "muscle.upperBack": "Upper back",
    "muscle.traps": "Traps",
    "muscle.lowerBack": "Lower back",
    "muscle.biceps": "Biceps",
    "muscle.triceps": "Triceps",
    "muscle.forearms": "Forearms",
    "muscle.abs": "Abs",
    "muscle.obliques": "Obliques",
    "muscle.neck": "Neck",
    "muscle.quadriceps": "Quads",
    "muscle.hamstrings": "Hamstrings",
    "muscle.glutes": "Glutes",
    "muscle.adductors": "Adductors",
    "muscle.hipAbductors": "Hip abductors",
    "muscle.gastrocnemius": "Gastrocnemius",
    "muscle.soleus": "Soleus",
    "muscle.notAttributed": "Not attributed",
    "muscle.notRecognised": "Not recognised",
    // The eight real groups, matching `MuscleGroup`'s cases exactly. A test asserts every case
    // resolves, so a ninth group cannot be added without a word for it.
    "muscleGroup.chest": "Chest",
    "muscleGroup.shoulders": "Shoulders",
    "muscleGroup.back": "Back",
    "muscleGroup.arms": "Arms",
    "muscleGroup.core": "Core",
    "muscleGroup.neck": "Neck",
    "muscleGroup.legs": "Legs",
    "muscleGroup.glutes": "Glutes",
  ]
}
