import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Gyms and the machines added at them, for correcting what was added: a typo'd name, a
/// duplicate, a gym the lifter no longer trains at.
///
/// Choosing stays in the recency-first pickers; this list is alphabetical because it is for
/// finding a name, not for picking the machine in front of you. Renaming keeps the identity, so
/// every logged set follows the new name. Removing archives the row: it leaves the pickers and this
/// list and is never deleted, because logged sets reference it. The word the lifter reads is
/// "Remove", not "Archive", because nothing in the app lists archived equipment or brings it back,
/// and "Archive" promises both. Adding the same name later makes a new row with a new identity.
struct GymManagementScreen: View {
  let store: GymStore
  /// Called after a rename or archive is saved, so screens showing gym names can re-read them.
  let onChanged: () -> Void

  @State private var inventory: [GymInventory]?
  @State private var loadFailed = false
  @State private var editing: EquipmentEdit?
  @State private var archiving: EquipmentArchive?
  @State private var failure: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        Text("Renaming keeps every logged set attached. Removing takes a gym or machine out of the pickers for good: nothing lists removed ones or brings them back, and adding the same name starts a new one. Sets already logged stay in History and, for a machine, its load chart stays in Progress.")
          .font(Tokens.Text.provenance)
          .foregroundStyle(Tokens.Color.chalkDim)
          .fixedSize(horizontal: false, vertical: true)

        if let inventory {
          if inventory.isEmpty {
            HardsetEmptyState(
              title: "No gyms yet",
              detail: "A gym you add when starting a workout appears here, with its machines.",
              systemImage: "building.2"
            )
          } else {
            ForEach(inventory) { item in gymSection(item) }
          }
        } else if loadFailed {
          HardsetEmptyState(
            title: "Could not read your gyms",
            detail: "Your gyms and logged sets are safe.",
            systemImage: "exclamationmark.triangle",
            actionTitle: "Try again",
            actionSystemImage: "arrow.clockwise",
            action: { Task { await load() } }
          )
        } else {
          HardsetLoadingState("Reading your gyms…")
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.top, Tokens.Spacing.loose)
      .padding(.bottom, Tokens.Spacing.block)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Tokens.Color.canvas)
    .hardsetNavigationTitle("Gyms and machines")
    .task { await load() }
    .sheet(item: $editing) { edit in
      EquipmentRenameSheet(edit: edit, onSave: { name, brand in rename(edit, name: name, brand: brand) }) {
        editing = nil
      }
      .hardsetSheet()
    }
    .confirmationDialog(
      archiving?.title ?? "",
      isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }),
      titleVisibility: .visible,
      presenting: archiving
    ) { request in
      Button("Remove", role: .destructive) { archive(request) }
      Button("Cancel", role: .cancel) {}
    } message: { request in
      Text(request.message)
    }
    .alert(
      "Could not update your gyms and machines",
      // A rename sheet presents its own save error. A failed background refresh waits until
      // that sheet closes, so two presenters never compete for the same alert.
      isPresented: Binding(get: { failure != nil && editing == nil }, set: { if !$0 { failure = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure ?? "")
    }
  }

  // MARK: - Rows

  private func gymSection(_ item: GymInventory) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      ManagedRow(
        title: item.gym.name,
        detail: Self.machineCount(item.machines.count),
        onRename: { editing = .gym(item.gym) },
        onArchive: { archiving = .gym(item.gym) }
      )
      // Machines sit under their gym, inset, so the list reads as gym then its equipment.
      ForEach(item.machines) { machine in
        ManagedRow(
          title: machine.displayName,
          detail: "Machine at \(item.gym.name)",
          onRename: { editing = .machine(machine) },
          onArchive: { archiving = .machine(machine, gym: item.gym.name) }
        )
        .padding(.leading, Tokens.Spacing.loose)
      }
    }
  }

  private static func machineCount(_ count: Int) -> String {
    switch count {
    case 0: "Gym · no machines added yet"
    case 1: "Gym · 1 machine"
    default: "Gym · \(count) machines"
    }
  }

  // MARK: - Actions

  private func load() async {
    loadFailed = false
    do {
      inventory = try await store.inventory()
    } catch is CancellationError {
      // A disappearing screen is not a failure, and keeps whatever was showing.
    } catch {
      // A failed refresh keeps the list on screen and says it may be out of date.
      if inventory == nil { loadFailed = true }
      else { failure = "Could not refresh your gyms. The list may be out of date." }
    }
  }

  private func rename(_ edit: EquipmentEdit, name: String, brand: String) -> String? {
    do {
      switch edit {
      case .gym(let gym): try store.renameGym(gym.id, to: name)
      case .machine(let machine): try store.renameMachine(machine.id, name: name, brand: brand)
      }
      editing = nil
      failure = nil
      onChanged()
      Task { await load() }
      return nil
    } catch EquipmentNameError.blank {
      return "A name cannot be blank."
    } catch {
      Task { await load() }
      return "Could not save the new name. It may have been removed. Your changes are still here to retry."
    }
  }

  private func archive(_ request: EquipmentArchive) {
    archiving = nil
    do {
      switch request {
      case .gym(let gym): try store.archiveGym(gym.id)
      case .machine(let machine, _): try store.archiveMachine(machine.id)
      }
      failure = nil
      onChanged()
    } catch {
      failure = "Could not remove it. Nothing was changed."
    }
    Task { await load() }
  }
}

// MARK: - Requests

/// What the rename sheet is editing. Carries the record itself, so the sheet starts from the name
/// as it was when the lifter chose Rename.
///
/// `nonisolated` so its `Identifiable` conformance is an ordinary one: this target defaults to
/// `MainActor`, and a main-actor `id` cannot satisfy a nonisolated requirement.
private nonisolated enum EquipmentEdit: Identifiable {
  case gym(GymRecord)
  case machine(MachineRecord)

  var id: String {
    switch self {
    case .gym(let gym): "gym-\(gym.id.rawValue)"
    case .machine(let machine): "machine-\(machine.id.rawValue)"
    }
  }
}

/// What the removal confirmation is about, with the words it asks in.
///
/// It says what happens and what does not: the row leaves the pickers and the list, nothing brings
/// it back, adding the same name starts a new one (a machine's load history with it), and the sets
/// already logged stay where they were.
private nonisolated enum EquipmentArchive {
  case gym(GymRecord)
  case machine(MachineRecord, gym: String)

  var title: String {
    switch self {
    case .gym(let gym): "Remove \(gym.name)?"
    case .machine(let machine, _): "Remove \(machine.displayName)?"
    }
  }

  var message: String {
    switch self {
    case .gym:
      "It leaves the gym picker and this list, and its machines go with it. Nothing in the app brings it back, and adding a gym with the same name starts a new one. Sets already logged there stay in History."
    case .machine(_, let gym):
      "It leaves the machine picker at \(gym) and this list. Nothing in the app brings it back, and adding a machine with the same name starts a new one with no load history of its own. Sets already logged on it stay in History, and its load chart stays in Progress."
    }
  }
}

// MARK: - Row

/// One gym or machine: its name, and the two things that can be done to it.
///
/// Both actions are visible buttons rather than a swipe or a long press, so they can be found
/// without knowing a gesture, and each names its target for VoiceOver.
private struct ManagedRow: View {
  let title: String
  let detail: String
  let onRename: () -> Void
  let onArchive: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
        Text(title)
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.chalk)
          .fixedSize(horizontal: false, vertical: true)
        Text(detail)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.chalkDim)
      }
      .accessibilityElement(children: .combine)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: Tokens.Spacing.snug) { buttons }
        VStack(spacing: Tokens.Spacing.snug) { buttons }
      }
    }
    .padding(Tokens.Spacing.regular)
    .frame(maxWidth: .infinity, alignment: .leading)
    .hardsetCard()
  }

  @ViewBuilder private var buttons: some View {
    Button("Rename", action: onRename)
      .buttonStyle(HardsetButtonStyle(.secondary))
      .accessibilityLabel("Rename \(title)")
    Button("Remove", action: onArchive)
      .buttonStyle(HardsetButtonStyle(.destructive))
      .accessibilityLabel("Remove \(title) from the pickers")
  }
}

// MARK: - Rename sheet

/// Edits a gym's name, or a machine's name and brand.
///
/// The text is owned here and handed back as arguments, the same shape `NameEntrySheet` uses and
/// for the same reason: a field inside an alert, bound to the presenter's state, once handed back
/// an empty string. Starts from the current name, since a rename is usually a one-letter fix.
private struct EquipmentRenameSheet: View {
  let edit: EquipmentEdit
  let onSave: (_ name: String, _ brand: String) -> String?
  let onCancel: () -> Void

  @State private var name: String
  @State private var brand: String
  @State private var saveFailure: String?
  @FocusState private var focus: Field?

  private nonisolated enum Field: Hashable { case name, brand }

  init(edit: EquipmentEdit, onSave: @escaping (_ name: String, _ brand: String) -> String?, onCancel: @escaping () -> Void) {
    self.edit = edit
    self.onSave = onSave
    self.onCancel = onCancel
    switch edit {
    case .gym(let gym):
      _name = State(initialValue: gym.name)
      _brand = State(initialValue: "")
    case .machine(let machine):
      _name = State(initialValue: machine.name)
      _brand = State(initialValue: machine.brand)
    }
  }

  private var isMachine: Bool {
    if case .machine = edit { return true }
    return false
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Whether either field differs from what the sheet opened with, so a swipe would lose typing.
  private var isEdited: Bool {
    switch edit {
    case .gym(let gym): name != gym.name
    case .machine(let machine): name != machine.name || brand != machine.brand
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
          field("Name", text: $name, focus: .name)
          if isMachine {
            field("Brand", text: $brand, focus: .brand)
            Text("Leave the brand blank if the machine has none.")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.chalkDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          Button("Save", action: save)
            .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
            // Nothing to save is not an error worth explaining; the button simply waits.
            .disabled(trimmedName.isEmpty)
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.top, Tokens.Spacing.loose)
        .padding(.bottom, Tokens.Spacing.section)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(Tokens.Color.canvas)
      .hardsetNavigationTitle(isMachine ? "Rename machine" : "Rename gym")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
      }
      .onAppear { focus = .name }
      .alert(
        "Could not save this name",
        isPresented: Binding(get: { saveFailure != nil }, set: { if !$0 { saveFailure = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(saveFailure ?? "")
      }
    }
    .presentationDetents([.medium, .large])
    // A brushed swipe must not discard an edit in progress; Cancel is the explicit way out.
    .interactiveDismissDisabled(isEdited)
  }

  private func field(_ label: String, text: Binding<String>, focus field: Field) -> some View {
    VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
      Text(label)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .accessibilityHidden(true)
      TextField(text: text, prompt: Text(label).foregroundStyle(Tokens.Color.chalkDim)) {
        Text(label)
      }
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.chalk)
      .tint(Tokens.Color.plateBlue)
      .focused($focus, equals: field)
      .hardsetNameInput()
      .submitLabel(isMachine && field == .name ? .next : .done)
      .onSubmit {
        if isMachine && field == .name { focus = .brand } else { save() }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .padding(.vertical, Tokens.Spacing.snug)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
      // The same outline as the name entry and search fields, focus ring included.
      .hardsetEntryField(isFocused: focus == field)
      .onTapGesture { focus = field }
    }
  }

  private func save() {
    guard !trimmedName.isEmpty else {
      // Return with no name: put the caret back in the name field rather than closing the
      // keyboard beside a disabled Save. Deferred, because the field resigns after submitting.
      Task { focus = .name }
      return
    }
    saveFailure = onSave(trimmedName, brand.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
