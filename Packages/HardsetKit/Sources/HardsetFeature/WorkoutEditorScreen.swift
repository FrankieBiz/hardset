import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The saved-workout editor, wired.
///
/// Makes a new workout or changes one, adds movements through the same picker the live workout
/// uses (and the same movement editor for one that is not on the list, so there is one way to make
/// a movement), and shows what the whole rotation plans for each body group while it is edited.
/// A failed save keeps the sheet up with everything typed and says why in an alert, because the
/// editor scrolls and a banner at the top would be out of sight beside the button it answers.
///
/// Deleting a workout archives it. Workouts already done from it keep every set, because a session
/// copies what it needs when it starts and never reads the plan back.
@MainActor
public struct WorkoutEditorScreen: View {
  @State private var draft: WorkoutDraft
  @State private var balance: SplitBalance?
  @State private var saveError: String?
  @State private var deleteFailed = false
  @State private var isConfirmingDelete = false
  @State private var isPickingMovement = false
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  @State private var pickerRecent: [CatalogEntry] = []
  @State private var pickerError: String?
  @State private var newMovement: EditorNewMovement?
  @State private var newMovementError: String?

  private let templates: TemplateStore
  private let catalog: CatalogSeeder
  private let volume: VolumeStore
  /// The rest of the rotation, without the workout being edited, so the balance can add this one.
  private let others: [WorkoutTemplate]
  private let onSaved: () -> Void
  private let onClose: () -> Void

  /// - Parameters:
  ///   - template: The workout to change, or nil to make a new one, last in the rotation.
  ///   - others: Every other saved workout, for the split balance.
  ///   - onSaved: Called after the workout was saved or deleted, so the Train tab re-reads.
  ///   - onClose: Dismisses the editor, saved or not.
  public init(
    templates: TemplateStore,
    catalog: CatalogSeeder,
    volume: VolumeStore,
    template: WorkoutTemplate?,
    others: [WorkoutTemplate],
    onSaved: @escaping () -> Void,
    onClose: @escaping () -> Void
  ) {
    self.templates = templates
    self.catalog = catalog
    self.volume = volume
    self.others = others
    self.onSaved = onSaved
    self.onClose = onClose
    if let template {
      self._draft = State(initialValue: WorkoutDraft(template: template))
    } else {
      let next = (others.map(\.position).max() ?? -1) + 1
      self._draft = State(initialValue: WorkoutDraft(newAtPosition: next))
    }
  }

  public var body: some View {
    NavigationStack {
      WorkoutEditorView(
        draft: $draft,
        balance: balance,
        onAddMovement: { isPickingMovement = true },
        onSave: save,
        onDelete: draft.isNew ? nil : { isConfirmingDelete = true }
      )
      .hardsetNavigationTitle(draft.isNew ? "New workout" : "Edit workout")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onClose)
        }
      }
      // Re-read when the movements or their set counts change, which is all the balance depends on.
      .task(id: draft.movements.map { "\($0.exerciseID.rawValue.uuidString)#\($0.plannedSets)" }) {
        refreshBalance()
      }
      .sheet(
        isPresented: $isPickingMovement,
        onDismiss: {
          pickerQuery = ""
          pickerError = nil
        }
      ) {
        movementPicker
      }
      .alert(
        "Could not save this workout",
        isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(saveError ?? "")
      }
      .alert("Could not delete this workout", isPresented: $deleteFailed) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Nothing was removed. Try again.")
      }
      .confirmationDialog(
        "Delete this workout?", isPresented: $isConfirmingDelete, titleVisibility: .visible
      ) {
        Button("Delete workout", role: .destructive) { delete() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Workouts you have already done from it keep all of their sets.")
      }
    }
    // A brushed swipe must not throw away a plan being made. Cancel stays the explicit way out.
    .interactiveDismissDisabled(!draft.movements.isEmpty || !draft.trimmedName.isEmpty)
  }

  // MARK: - Movement picker

  private var movementPicker: some View {
    NavigationStack {
      ExercisePickerView(
        query: $pickerQuery,
        entries: pickerEntries,
        recent: pickerRecent,
        errorMessage: pickerError,
        onCancel: { isPickingMovement = false },
        onCreate: { name in newMovement = EditorNewMovement(name: name) },
        onSelect: { entry in
          draft.add(entry)
          isPickingMovement = false
        }
      )
      .hardsetNavigationTitle("Add movement")
      // The same editor the live workout opens for a movement that is not on the list.
      .sheet(item: $newMovement, onDismiss: { newMovementError = nil }) { typed in
        MovementEditorSheet(
          title: "New movement",
          confirmLabel: "Add to workout",
          errorMessage: $newMovementError,
          draft: MovementEditorDraft(name: typed.name),
          onSave: { name, attribution in createMovement(named: name, attribution: attribution) },
          onCancel: { newMovement = nil }
        )
        .hardsetSheet()
      }
    }
    .hardsetSheet()
    // Searching hits the database, so it happens here and the picker stays free of storage.
    .task(id: pickerQuery) { refreshPicker() }
  }

  private func refreshPicker() {
    do {
      pickerEntries = try catalog.search(pickerQuery)
      pickerRecent = try pickerQuery.isEmpty ? catalog.recent(limit: 8) : []
      pickerError = nil
    } catch {
      // Not an empty catalogue, and not worth blocking the plan over: the lists stay as they were
      // and the picker says what happened.
      pickerError = "Your movements could not be read. Close this and try again."
    }
  }

  private func createMovement(named name: String, attribution: CustomAttribution) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      // Returns the existing movement for a name that is already there, so retyping one selects it.
      let entry = try catalog.createCustomExercise(named: trimmed, attribution: attribution)
      draft.add(entry)
      newMovement = nil
      isPickingMovement = false
    } catch CatalogSeederError.blankName {
      newMovementError = "Type the movement's name first."
    } catch {
      newMovementError = "“\(trimmed)” could not be added. Try again."
    }
  }

  // MARK: - Balance, save, delete

  /// Left out, not shown as empty, when the attributions cannot be read: a split balance that
  /// claimed "nothing planned" on a failed read would be a statement the app could not check.
  private func refreshBalance() {
    guard let attribution = try? volume.attributionIndex() else {
      balance = nil
      return
    }
    let planned = draft.movements.isEmpty ? others : others + [draft.template]
    balance = SplitBalanceAnalyzer.balance(templates: planned, attribution: attribution)
  }

  private func save() {
    guard draft.canSave else { return }
    let template = draft.template
    let name = template.name
    Task {
      do {
        try await templates.save(template)
        onSaved()
        onClose()
      } catch TemplateStoreError.blankName {
        saveError = "Name the workout first."
      } catch TemplateStoreError.noExercises {
        saveError = "Add a movement first."
      } catch TemplateStoreError.unknownExercise {
        saveError = "A movement in this workout is no longer available. Remove it and try again."
      } catch {
        saveError = "“\(name)” could not be saved. Try again."
      }
    }
  }

  private func delete() {
    let id = draft.template.id
    Task {
      do {
        try await templates.archive(id)
        onSaved()
        onClose()
      } catch TemplateStoreError.notFound {
        // Already gone, for example removed on another device. The list re-reads and shows the truth.
        onSaved()
        onClose()
      } catch {
        deleteFailed = true
      }
    }
  }
}

/// The name typed in the picker for a movement it does not list, so `sheet(item:)` has something
/// `Identifiable` to present.
private nonisolated struct EditorNewMovement: Identifiable {
  let name: String
  var id: String { name }
}
