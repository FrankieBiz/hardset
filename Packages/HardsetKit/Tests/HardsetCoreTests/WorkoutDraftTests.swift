import Foundation
import Testing

@testable import HardsetCore

@Suite("Editing a saved workout")
struct WorkoutDraftTests {
  private func entry(_ name: String, modality: ExerciseModality? = .machine) -> CatalogEntry {
    CatalogEntry(
      id: ExerciseID(), name: name, slug: nil, isCurated: false, modality: modality,
      primaryMuscle: MuscleKey(.chest), contributions: [])
  }

  @Test("A new workout starts empty, and last in the rotation")
  func newDraft() {
    let draft = WorkoutDraft(newAtPosition: 3)

    #expect(draft.isNew)
    #expect(draft.position == 3)
    #expect(draft.movements.isEmpty)
    #expect(!draft.canSave)
    #expect(draft.whatIsMissing == "Name the workout.")
  }

  @Test("It needs a name and at least one movement")
  func saveNeedsANameAndAMovement() {
    var draft = WorkoutDraft(newAtPosition: 0)
    draft.name = "  Upper A "
    #expect(draft.whatIsMissing == "Add a movement.")
    #expect(!draft.canSave)

    draft.add(entry("Chest press"))
    #expect(draft.canSave)
    #expect(draft.whatIsMissing == nil)
    #expect(draft.template.name == "Upper A")
    draft.name = "   "
    #expect(!draft.canSave)
  }

  @Test("An added movement opens on three sets with no range, no rest and no machine")
  func addedMovementDefaults() throws {
    var draft = WorkoutDraft(newAtPosition: 0)
    let press = entry("Chest press")

    draft.add(press)

    let movement = try #require(draft.movements.first)
    #expect(movement.exerciseID == press.id)
    #expect(movement.exerciseName == "Chest press")
    #expect(movement.plannedSets == 3)
    #expect(movement.repRange == nil)
    #expect(movement.restSeconds == nil)
    #expect(movement.machineID == nil)
  }

  @Test("The same movement can be added twice, as two blocks")
  func sameMovementTwice() {
    var draft = WorkoutDraft(newAtPosition: 0)
    let press = entry("Chest press")
    draft.add(press)
    draft.add(press)

    #expect(draft.movements.count == 2)
    #expect(Set(draft.movements.map(\.id)).count == 2)
  }

  @Test("Sets stay between one and ten")
  func setsAreClamped() throws {
    var draft = WorkoutDraft(newAtPosition: 0)
    draft.add(entry("Chest press"))
    let id = try #require(draft.movements.first?.id)

    draft.setSets(id, to: 0)
    #expect(draft.movements[0].plannedSets == 1)
    draft.setSets(id, to: 14)
    #expect(draft.movements[0].plannedSets == 10)
    draft.stepSets(id, by: -1)
    #expect(draft.movements[0].plannedSets == 9)
    draft.setSets(id, to: 5)
    draft.stepSets(id, by: 1)
    #expect(draft.movements[0].plannedSets == 6)
  }

  @Test("A rep range turns on at 8 to 12 and its ends step without crossing")
  func repRangeSteps() throws {
    var draft = WorkoutDraft(newAtPosition: 0)
    draft.add(entry("Chest press"))
    let id = try #require(draft.movements.first?.id)

    draft.enableRepRange(id)
    #expect(draft.movements[0].repRange == RepRange(lower: 8, upper: 12))

    draft.stepRepLower(id, by: 10)
    #expect(draft.movements[0].repRange == RepRange(lower: 12, upper: 12))
    draft.stepRepUpper(id, by: -5)
    #expect(draft.movements[0].repRange == RepRange(lower: 12, upper: 12))
    draft.stepRepUpper(id, by: 100)
    #expect(draft.movements[0].repRange == RepRange(lower: 12, upper: 50))
    draft.stepRepLower(id, by: -100)
    #expect(draft.movements[0].repRange == RepRange(lower: 1, upper: 50))

    draft.clearRepRange(id)
    #expect(draft.movements[0].repRange == nil)
    draft.stepRepLower(id, by: 1)
    #expect(draft.movements[0].repRange == nil)
  }

  @Test("Rest is a choice from the offered lengths, or none")
  func restChoices() throws {
    var draft = WorkoutDraft(newAtPosition: 0)
    draft.add(entry("Chest press"))
    let id = try #require(draft.movements.first?.id)

    draft.setRest(id, to: 90)
    #expect(draft.movements[0].restSeconds == 90)
    draft.setRest(id, to: nil)
    #expect(draft.movements[0].restSeconds == nil)
    draft.setRest(id, to: 0)
    #expect(draft.movements[0].restSeconds == nil)
    #expect(WorkoutDraft.restChoices[0] == nil)
    #expect(WorkoutDraft.restChoices.compactMap { $0 }.allSatisfy { $0 > 0 })
  }

  @Test("Movements reorder and delete, and an offset past either end stays put")
  func reorderAndDelete() throws {
    var draft = WorkoutDraft(newAtPosition: 0)
    for name in ["A", "B", "C"] { draft.add(entry(name)) }
    let a = draft.movements[0].id
    let c = draft.movements[2].id

    draft.move(a, by: 1)
    #expect(draft.movements.map(\.exerciseName) == ["B", "A", "C"])
    draft.move(a, by: 5)
    #expect(draft.movements.map(\.exerciseName) == ["B", "C", "A"])
    draft.move(c, by: -9)
    #expect(draft.movements.map(\.exerciseName) == ["C", "B", "A"])
    draft.remove(draft.movements[1].id)
    #expect(draft.movements.map(\.exerciseName) == ["C", "A"])
  }

  @Test("Editing keeps the saved workout's identity, and each movement its own")
  func editKeepsIdentities() throws {
    let exercise = ExerciseID()
    let machine = MachineID()
    let saved = WorkoutTemplate(
      name: "Upper A", position: 2,
      exercises: [
        TemplateExercise(
          exerciseID: exercise, exerciseName: "Chest press", machineID: machine,
          machineName: "Hammer Chest press", plannedSets: 4,
          repRange: RepRange(lower: 6, upper: 10), restSeconds: 120)
      ],
      lastDoneAt: Date(timeIntervalSince1970: 5))

    var draft = WorkoutDraft(template: saved)
    #expect(!draft.isNew)
    draft.name = "Upper A2"
    let roundTripped = draft.template

    #expect(roundTripped.id == saved.id)
    #expect(roundTripped.position == 2)
    #expect(roundTripped.name == "Upper A2")
    #expect(roundTripped.exercises == saved.exercises)
    // Last done is the store's to know, never the editor's.
    #expect(roundTripped.lastDoneAt == nil)
  }

  @Test("A saved machine can be cleared, so the start uses the one last used")
  func machineCanBeCleared() throws {
    let saved = WorkoutTemplate(
      name: "Upper A", position: 0,
      exercises: [
        TemplateExercise(
          exerciseID: ExerciseID(), exerciseName: "Chest press", machineID: MachineID(),
          machineName: "Hammer", plannedSets: 3)
      ])
    var draft = WorkoutDraft(template: saved)
    let id = try #require(draft.movements.first?.id)

    draft.clearMachine(id)

    #expect(draft.movements[0].machineID == nil)
    #expect(draft.movements[0].machineName == nil)
    #expect(draft.template.exercises[0].machineID == nil)
  }

  @Test("Rest lengths read as seconds, then minutes where they come out whole")
  func restLabels() {
    #expect(WorkoutDraft.restLabel(nil) == "None")
    #expect(WorkoutDraft.restLabel(30) == "30 s")
    #expect(WorkoutDraft.restLabel(45) == "45 s")
    #expect(WorkoutDraft.restLabel(60) == "1 min")
    #expect(WorkoutDraft.restLabel(90) == "90 s")
    #expect(WorkoutDraft.restLabel(120) == "2 min")
    #expect(WorkoutDraft.restLabel(300) == "5 min")
    #expect(WorkoutDraft.restChoices.map(WorkoutDraft.restLabel).count == WorkoutDraft.restChoices.count)
  }
}
