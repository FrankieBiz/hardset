import Foundation
import Testing

@testable import HardsetCore

/// The one place a muscle key becomes words.
///
/// It used to live inside `ExercisePickerView`, which meant `HardsetStore` could not see it -- so
/// catalogue search matched movement names only, and "quads" returned nothing on a list grouped by
/// muscle. `Muscle.displayNameKey` and `MuscleGroup.displayNameKey`, a whole localisation scheme,
/// had no readers at all while the words were hardcoded in a view.
@Suite("Every muscle and group has authored words")
struct MuscleDisplayNameTests {
  /// The point of keying off `displayNameKey`: a new case cannot ship without a word for it.
  @Test("Every muscle resolves to something other than its raw value")
  func everyMuscleHasWords() {
    for muscle in Muscle.allCases {
      let name = MuscleVocabulary.displayName(muscle)
      #expect(!name.isEmpty, "\(muscle) has no words")
      // A generated display name looks authored and is not, so falling back to the raw value is a
      // failure rather than a default.
      #expect(name != muscle.rawValue || name == "Neck" || name == "Abs" || name == "Traps",
              "\(muscle) fell through to its raw value")
    }
  }

  @Test("Every muscle group resolves too")
  func everyGroupHasWords() {
    for group in MuscleGroup.allCases {
      let name = MuscleVocabulary.displayName(group)
      #expect(!name.isEmpty, "\(group) has no words")
      #expect(name.first?.isUppercase == true, "\(group) is not capitalised")
    }
  }

  /// "Nobody has attributed this yet" and "a newer version knows something this one does not" are
  /// different facts about a row and must not collapse into one phrase.
  @Test("The two absent cases stay distinct")
  func absentCasesAreDistinct() {
    let notAttributed = MuscleVocabulary.displayName(MuscleKey(stored: MuscleKey.notAttributedRawValue))
    let notRecognised = MuscleVocabulary.displayName(MuscleKey(stored: "somethingNewerKnows"))
    #expect(notAttributed == "Not attributed")
    #expect(notRecognised == "Not recognised")
    #expect(notAttributed != notRecognised)
  }

  @Test("The vocabulary is enumerable, which is what search matches against")
  func vocabularyIsEnumerable() {
    let names = MuscleVocabulary.allMuscleNames
    #expect(names.count == Muscle.allCases.count)
    #expect(names.contains("Quads"))
    #expect(names.contains("Front delts"))
  }

  /// The specific renaming that makes search work: the enum case is `quadriceps`, the word is
  /// "Quads", and a lifter types the word.
  @Test("A muscle whose word differs from its case name is reachable by the word")
  func wordDiffersFromCaseName() {
    #expect(MuscleVocabulary.displayName(.quadriceps) == "Quads")
    #expect(MuscleVocabulary.displayName(.frontDelts) == "Front delts")
    #expect(MuscleVocabulary.displayName(.hipAbductors) == "Hip abductors")
  }
}
