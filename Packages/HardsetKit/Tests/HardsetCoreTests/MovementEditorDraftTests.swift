import Foundation
import Testing

@testable import HardsetCore

@Suite("The movement editor's rules, before any view draws them")
struct MovementEditorDraftTests {
  private func entry(
    primary: Muscle?, secondary: [Muscle] = [], modality: ExerciseModality? = .machine,
    name: String = "Lever row"
  ) -> CatalogEntry {
    var contributions: [MuscleContribution] = []
    if let primary {
      contributions.append(.init(primary, role: .direct, certainty: .moderate, source: .user))
    }
    contributions += secondary.map { .init($0, role: .indirect, certainty: .moderate, source: .user) }
    return CatalogEntry(
      id: ExerciseID(), name: name, slug: nil, isCurated: false, modality: modality,
      primaryMuscle: primary.map(MuscleKey.init) ?? MuscleKey(stored: MuscleKey.notAttributedRawValue),
      contributions: contributions)
  }

  @Test("Every surface that refuses a taken name says it in the same words, with the typed name")
  func takenNameIsRefusedInOneVoice() {
    #expect(
      MovementEditorDraft.nameTakenMessage("Pendulum Squat")
        == "A movement called “Pendulum Squat” already exists. Choose another name.")
  }

  @Test("A body part with one muscle is that muscle, with nothing more to ask")
  func singleMemberBodyPartSelectsItsMuscle() {
    var draft = MovementEditorDraft(name: "Pec fly")

    draft.choose(bodyPart: .chest)

    #expect(draft.primary == .chest)
    #expect(!draft.asksForSpecificMuscle)
    #expect(draft.canSave)
  }

  @Test("A body part with several muscles waits for the lifter to pick one")
  func multiMemberBodyPartWaitsForAChoice() {
    var draft = MovementEditorDraft(name: "Lever row")

    draft.choose(bodyPart: .back)

    #expect(draft.asksForSpecificMuscle)
    #expect(draft.specificMuscles == MuscleFilterCategory.back.members)
    #expect(draft.primary == nil)
    #expect(!draft.canSave)

    draft.choose(primary: .lats)

    #expect(draft.primary == .lats)
    #expect(draft.canSave)
  }

  @Test("Nothing is saved without a name, or without a muscle")
  func saveNeedsANameAndAMuscle() {
    var draft = MovementEditorDraft(name: "   ")
    draft.choose(bodyPart: .chest)
    #expect(!draft.canSave)
    #expect(draft.attribution != nil)

    draft.name = "Pec fly"
    #expect(draft.canSave)
    #expect(draft.trimmedName == "Pec fly")

    #expect(MovementEditorDraft(name: "Pec fly").attribution == nil)
    #expect(!MovementEditorDraft(name: "Pec fly").canSave)
  }

  @Test("Changing the body part drops a muscle that no longer belongs to it")
  func changingBodyPartClearsAnIncompatiblePrimary() {
    var draft = MovementEditorDraft(name: "Lever row")
    draft.choose(bodyPart: .back)
    draft.choose(primary: .lats)

    draft.choose(bodyPart: .shoulders)

    #expect(draft.primary == nil)
    #expect(draft.bodyPart == .shoulders)

    draft.choose(bodyPart: .back)
    draft.choose(primary: .traps)
    draft.choose(bodyPart: .back)
    #expect(draft.primary == .traps)
  }

  @Test("Up to three secondary muscles, never the primary, and a muscle chosen as primary leaves them")
  func secondaryLimitAndPrimaryExclusion() {
    var draft = MovementEditorDraft(name: "Lever row")
    draft.choose(bodyPart: .back)
    draft.choose(primary: .lats)

    let first = draft.toggleSecondary(.biceps)
    let second = draft.toggleSecondary(.forearms)
    let third = draft.toggleSecondary(.rearDelts)
    #expect(first && second && third)
    #expect(draft.secondaryLimitReached)
    let fourth = draft.toggleSecondary(.traps)
    #expect(!fourth)
    #expect(draft.secondary == [.biceps, .forearms, .rearDelts])
    let primaryAgain = draft.toggleSecondary(.lats)
    #expect(!primaryAgain)

    let removed = draft.toggleSecondary(.forearms)
    #expect(removed)
    #expect(!draft.secondaryLimitReached)
    let added = draft.toggleSecondary(.traps)
    #expect(added)
    #expect(draft.secondary == [.biceps, .rearDelts, .traps])

    draft.choose(primary: .traps)
    #expect(draft.secondary == [.biceps, .rearDelts])
  }

  @Test("The attribution carries the choice, and the equipment")
  func attributionCarriesTheChoice() throws {
    var draft = MovementEditorDraft(name: "Nautilus lever row", modality: .machine)
    draft.choose(bodyPart: .back)
    draft.choose(primary: .lats)
    draft.toggleSecondary(.biceps)
    draft.modality = .cable

    let attribution = try #require(draft.attribution)

    #expect(attribution.primary == .lats)
    #expect(attribution.secondary == [.biceps])
    #expect(attribution.modality == .cable)
  }

  @Test("Equipment offers the five ways a load is applied, machine first")
  func equipmentOptions() {
    #expect(MovementEditorDraft.equipment == [.machine, .cable, .barbell, .dumbbell, .bodyweight])
  }

  /// A new movement used to open pre-selected to Machine, so a lifter who named a barbell lift and
  /// saved it as shown later found it was "machine, no machine recorded". Nothing is chosen now,
  /// and the editor says what that withholds.
  @Test("A new movement opens with no equipment chosen and says what that withholds")
  func aNewMovementDeclaresNoEquipment() throws {
    var draft = MovementEditorDraft(name: "Zercher squat")
    #expect(draft.modality == nil)
    #expect(draft.equipmentIsUnset)
    #expect(draft.savedNote.contains("no max will be estimated"))

    draft.choose(bodyPart: .quads)
    #expect(draft.canSave)
    #expect(try #require(draft.attribution).modality == nil)

    draft.modality = .barbell
    #expect(!draft.equipmentIsUnset)
    #expect(!draft.savedNote.contains("no max will be estimated"))
  }

  @Test("Editing starts from what the movement already says")
  func prefillFromAnEntry() {
    let draft = MovementEditorDraft(
      entry: entry(primary: .lats, secondary: [.biceps, .rearDelts], modality: .cable))

    #expect(draft.name == "Lever row")
    #expect(draft.bodyPart == .back)
    #expect(draft.primary == .lats)
    #expect(draft.secondary == [.biceps, .rearDelts])
    #expect(draft.modality == .cable)
    #expect(draft.canSave)
  }

  @Test("An untagged movement opens with no body part, and with no equipment chosen for it")
  func prefillFromAnUntaggedEntry() {
    let draft = MovementEditorDraft(entry: entry(primary: nil, modality: nil))

    #expect(draft.bodyPart == nil)
    #expect(draft.primary == nil)
    #expect(draft.secondary.isEmpty)
    // Once defaulted to machine; saving a body part then declared equipment nobody had named.
    #expect(draft.modality == nil)
    #expect(draft.equipmentIsUnset)
    #expect(!draft.canSave)
  }

  @Test("Naming a body part for a movement with no equipment saves no equipment, so none is declared")
  func savingABodyPartDoesNotDeclareEquipment() throws {
    var draft = MovementEditorDraft(entry: entry(primary: nil, modality: nil))
    draft.choose(bodyPart: .chest)

    let attribution = try #require(draft.attribution)

    #expect(draft.canSave)
    #expect(attribution.primary == .chest)
    #expect(attribution.modality == nil)
  }

  @Test("Equipment the lifter picks is what is saved, and the note about it goes away")
  func pickingEquipmentIsADeclaration() throws {
    var draft = MovementEditorDraft(entry: entry(primary: .chest, modality: nil))
    #expect(draft.equipmentIsUnset)

    draft.modality = .barbell

    #expect(!draft.equipmentIsUnset)
    #expect(try #require(draft.attribution).modality == .barbell)
  }

  @Test("A movement with equipment on record keeps it, and a new one opens with none")
  func recordedEquipmentIsKept() {
    #expect(MovementEditorDraft(entry: entry(primary: .lats, modality: .dumbbell)).modality == .dumbbell)
    #expect(!MovementEditorDraft(entry: entry(primary: .lats, modality: .dumbbell)).equipmentIsUnset)
    #expect(MovementEditorDraft().modality == nil)
  }

  @Test("An imported movement's name is fixed, and a lifter's own is not")
  func importedNameIsFixed() {
    let imported = CatalogEntry(
      id: ExerciseID(), name: "Bench Press (Barbell) (Imported • Strong)", slug: nil,
      isCurated: false, modality: nil,
      primaryMuscle: MuscleKey(stored: MuscleKey.notAttributedRawValue), contributions: [],
      isImported: true)

    let draft = MovementEditorDraft(entry: imported)

    #expect(draft.nameIsFixed)
    #expect(draft.name == "Bench Press (Barbell) (Imported • Strong)")
    #expect(!MovementEditorDraft(entry: entry(primary: .lats)).nameIsFixed)
    #expect(!MovementEditorDraft(name: "Pec fly").nameIsFixed)
    #expect(draft.savedNote.contains("imported sets count"))
    #expect(!MovementEditorDraft(name: "Pec fly").savedNote.contains("imported"))
  }

  @Test("A catalogue entry says it was not imported unless told otherwise")
  func entriesAreNotImportedByDefault() {
    #expect(!entry(primary: .lats).isImported)
  }

  @Test("Stabilisers and unknown tokens are not carried into the secondaries")
  func prefillIgnoresStabilisersAndUnknowns() {
    let source = CatalogEntry(
      id: ExerciseID(), name: "Carry", slug: nil, isCurated: false, modality: .barbell,
      primaryMuscle: MuscleKey(.traps),
      contributions: [
        .init(.traps, role: .direct, certainty: .moderate, source: .user),
        .init(.forearms, role: .stabilizer, certainty: .moderate, source: .user),
        MuscleContribution(
          key: MuscleKey(stored: "from-a-newer-version"), role: .indirect, certainty: .low,
          sourceID: "user"),
        .init(.biceps, role: .indirect, certainty: .moderate, source: .user),
      ])

    let draft = MovementEditorDraft(entry: source)

    #expect(draft.secondary == [.biceps])
  }

  @Test("A disabled Save says what is still missing, name first")
  func whatIsMissingNamesTheNextStep() {
    var draft = MovementEditorDraft(name: "  ")
    #expect(draft.whatIsMissing == "Name the movement.")

    draft.name = "Lever row"
    #expect(draft.whatIsMissing == "Choose a body part.")

    draft.choose(bodyPart: .back)
    #expect(draft.whatIsMissing == "Choose which muscle it trains most.")

    draft.choose(primary: .lats)
    #expect(draft.whatIsMissing == nil)
  }
}
