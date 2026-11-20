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
    #expect(MovementEditorDraft(name: "x").modality == .machine)
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

  @Test("An untagged movement opens with no body part, and equipment defaulting to machine")
  func prefillFromAnUntaggedEntry() {
    let draft = MovementEditorDraft(entry: entry(primary: nil, modality: nil))

    #expect(draft.bodyPart == nil)
    #expect(draft.primary == nil)
    #expect(draft.secondary.isEmpty)
    #expect(draft.modality == .machine)
    #expect(!draft.canSave)
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
