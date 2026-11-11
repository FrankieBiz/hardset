import Foundation
import Testing

@testable import HardsetCore

@Suite("Movement search finds the names lifters type, and nothing it has to guess")
struct CatalogSearchTests {
  private let entries: [CatalogEntry] = ExerciseCatalog.v1.map { exercise in
    CatalogEntry(
      id: ExerciseID(rawValue: UUID(uuidString: exercise.id)!),
      name: exercise.name,
      slug: exercise.slug,
      isCurated: true,
      modality: exercise.modality,
      primaryMuscle: MuscleKey(exercise.primaryMuscle),
      contributions: exercise.contributions
    )
  }

  private func names(_ query: String) -> [String] {
    CatalogSearch.rank(entries, query: query).map(\.name)
  }

  /// Each of these found nothing with a literal substring, and the picker said the movement was
  /// not in the catalogue.
  @Test(
    "Gym names, abbreviations and plurals find the movement first",
    arguments: [
      ("rdl", "Romanian Deadlift"),
      ("RDL", "Romanian Deadlift"),
      ("ohp", "Overhead Press"),
      ("military press", "Overhead Press"),
      ("shoulder press", "Overhead Press"),
      ("pull up", "Pull-up"),
      ("pullup", "Pull-up"),
      ("pull ups", "Pull-up"),
      ("chin up", "Chin-up"),
      ("chinups", "Chin-up"),
      ("lat pull down", "Lat Pulldown"),
      ("seated row", "Seated Cable Row"),
      ("incline bench", "Incline Barbell Bench Press"),
      ("db bench", "Dumbbell Bench Press"),
      ("skullcrusher", "Skull Crusher"),
      ("skull crushers", "Skull Crusher"),
      ("leg extensions", "Leg Extension"),
      ("calf raises", "Standing Calf Raise"),
      ("calves", "Standing Calf Raise"),
      ("tricep pushdown", "Cable Triceps Pushdown"),
      ("lat raise", "Lateral Raise"),
      ("hamstring curl", "Seated Leg Curl"),
      ("squats", "Barbell Back Squat"),
      ("dips", "Dip"),
      ("shrugs", "Shrug"),
      ("bench", "Barbell Bench Press"),
      ("deadlift", "Conventional Deadlift"),
      ("bent-over row", "Barbell Row"),
      ("chest flyes", "Cable Fly"),
      ("BENCH", "Barbell Bench Press"),
      ("Bénch", "Barbell Bench Press"),
    ]
  )
  func findsTypedNames(query: String, expected: String) {
    #expect(names(query).first == expected, "\(query) -> \(names(query))")
  }

  @Test("Every word must begin a word of the name, in any order")
  func everyWordMustMatch() {
    #expect(Set(names("dumbbell press")).isSuperset(of: [
      "Dumbbell Bench Press", "Incline Dumbbell Press", "Seated Dumbbell Press",
    ]))
    #expect(!names("dumbbell press").contains("Barbell Bench Press"))
    #expect(names("press dumbbell incline") == ["Incline Dumbbell Press"])
    #expect(Set(names("leg curl")) == ["Seated Leg Curl", "Lying Leg Curl"])
    #expect(Set(names("pull up")) == ["Pull-up"])
  }

  /// No edit-distance guessing: a word that begins nothing finds nothing, so the picker can say so
  /// honestly rather than surface the wrong movement.
  @Test("A query matching nothing returns nothing rather than a near miss")
  func noNearMisses() {
    #expect(names("benhc").isEmpty)
    #expect(names("zercher squat").isEmpty)
    #expect(names("leg press machine xyz").isEmpty)
    // A joined query must start at a word, not inside one.
    #expect(names("ullup").isEmpty)
  }

  @Test("Exact names rank before partial ones, and an empty query keeps everything in order")
  func ranking() {
    #expect(names("squat").first == "Barbell Back Squat")
    #expect(Set(names("squat")).isSuperset(of: ["Barbell Front Squat", "Hack Squat", "Bulgarian Split Squat"]))
    #expect(names("leg press").first == "Leg Press")
    #expect(names("").count == entries.count)
    #expect(names("   ") == entries.map(\.name))
  }

  /// Everything the old literal substring found is still found.
  @Test("Literal substrings still match", arguments: ["ress", "ench", "Curl", "-up", "ull"])
  func literalSubstrings(query: String) {
    let literal = entries.filter {
      $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }.map(\.name)
    #expect(!literal.isEmpty)
    #expect(Set(names(query)).isSuperset(of: literal))
  }

  @Test("Aliases name only curated movements that exist")
  func aliasesAreKeyedBySlug() {
    let slugs = Set(ExerciseCatalog.v1.map(\.slug))
    #expect(Set(CatalogSearch.aliases.keys).isSubset(of: slugs))
  }

  @Test("Plurals fold identically for names and queries")
  func stemming() {
    #expect(CatalogSearch.phraseWords("Squats") == ["squat"])
    #expect(CatalogSearch.phraseWords("Presses") == ["press"])
    #expect(CatalogSearch.phraseWords("Press") == ["press"])
    #expect(CatalogSearch.phraseWords("Flies") == ["fly"])
    #expect(CatalogSearch.phraseWords("Crunches") == ["crunch"])
    #expect(CatalogSearch.phraseWords("Triceps Pull-ups") == ["tricep", "pull", "up"])
    #expect(CatalogSearch.phraseWords("chin-ups") == ["chin", "up"])
    #expect(CatalogSearch.phraseWords("Glass") == ["glass"])
  }
}
