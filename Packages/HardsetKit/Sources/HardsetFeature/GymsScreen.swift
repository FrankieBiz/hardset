import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Gyms and their machines, with rename and archive.
///
/// Nothing here deletes: archiving takes a gym or machine out of the pickers and leaves every set
/// logged on it in history (`GymStore.archiveGym`). A write goes through the store first and the
/// list is reloaded from it afterwards, so a rename is only ever shown once it is saved; a failure
/// says so in `FailureCopy`'s words and leaves the old name on screen.
struct GymsScreen: View {
  /// A gym or a machine, the thing a rename or an archive acts on.
  fileprivate enum Target: Identifiable, Equatable {
    case gym(GymRecord)
    case machine(MachineRecord)

    var id: String {
      switch self {
      case .gym(let gym): "gym-\(gym.id.rawValue)"
      case .machine(let machine): "machine-\(machine.id.rawValue)"
      }
    }

    /// What the lifter sees the thing called.
    var name: String {
      switch self {
      case .gym(let gym): gym.name
      case .machine(let machine): machine.displayName
      }
    }
  }

  private struct GymSection: Identifiable {
    let gym: GymRecord
    let machines: [MachineRecord]
    var id: GymID { gym.id }
  }

  let store: GymStore

  @State private var sections: [GymSection] = []
  @State private var renaming: Target?
  @State private var archiving: Target?
  /// The gym whose section footer carries the failure, with the words to show.
  @State private var failure: (gym: GymID, message: String)?

  init(store: GymStore) {
    self.store = store
  }

  var body: some View {
    List {
      ForEach(sections) { section in
        Section {
          gymRow(section.gym)
          if section.machines.isEmpty {
            Text("No machines yet. Add them from a movement's machine chip during a workout.")
              .font(.callout)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
          ForEach(section.machines) { machine in
            machineRow(machine)
          }
        } footer: {
          if let failure, failure.gym == section.gym.id {
            Text(failure.message)
              .foregroundStyle(Tokens.Color.critical)
          }
        }
      }
    }
    .navigationTitle("Gyms and machines")
    .task { reload() }
    .sheet(item: $renaming) { target in
      RenameSheet(target: target) { name, brand in
        rename(target, to: name, brand: brand)
      }
    }
    .confirmationDialog(
      archiveTitle,
      isPresented: isConfirmingArchive,
      titleVisibility: .visible
    ) {
      if let target = archiving {
        Button("Archive", role: .destructive) { archive(target) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("It leaves your pickers. Every set logged on it stays in your history.")
    }
  }

  /// A `Text` built from a string literal, so the title is a localisation key ("Archive “%@”?").
  /// The `String` it replaced went through the verbatim overload and could never be translated.
  private var archiveTitle: Text {
    guard let archiving else { return Text("Archive?") }
    return Text("Archive “\(archiving.name)”?")
  }

  private var isConfirmingArchive: Binding<Bool> {
    Binding(
      get: { archiving != nil },
      set: { if !$0 { archiving = nil } }
    )
  }

  // MARK: - Rows

  private func gymRow(_ gym: GymRecord) -> some View {
    Text(gym.name)
      .font(.headline)
      .accessibilityAddTraits(.isHeader)
      .modifier(Actions(target: .gym(gym), rename: { renaming = $0 }, archive: { archiving = $0 }))
  }

  private func machineRow(_ machine: MachineRecord) -> some View {
    Text(machine.displayName)
      .modifier(
        Actions(target: .machine(machine), rename: { renaming = $0 }, archive: { archiving = $0 })
      )
  }

  /// Rename and Archive three ways, so neither needs a swipe: swipe, long press, and as
  /// VoiceOver actions.
  private struct Actions: ViewModifier {
    let target: Target
    let rename: (Target) -> Void
    let archive: (Target) -> Void

    func body(content: Content) -> some View {
      content
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button("Archive", role: .destructive) { archive(target) }
          Button("Rename") { rename(target) }
        }
        .contextMenu {
          Button("Rename") { rename(target) }
          Button("Archive", role: .destructive) { archive(target) }
        }
        .accessibilityActions {
          Button("Rename") { rename(target) }
          Button("Archive") { archive(target) }
        }
    }
  }

  // MARK: - Store

  private func reload() {
    do {
      sections = try store.gyms().map { gym in
        GymSection(gym: gym, machines: try store.machines(at: gym.id))
      }
    } catch {
      // The list stays as it was; there is no action to blame, so nothing is claimed.
    }
  }

  private func rename(_ target: Target, to name: String, brand: String) {
    do {
      switch target {
      case .gym(let gym):
        try store.renameGym(gym.id, to: name)
      case .machine(let machine):
        try store.renameMachine(machine.id, name: name, brand: brand)
      }
      failure = nil
      reload()
    } catch {
      fail(error, target: target, action: isGym(target) ? .renameGym : .renameMachine)
    }
  }

  private func archive(_ target: Target) {
    do {
      switch target {
      case .gym(let gym): try store.archiveGym(gym.id)
      case .machine(let machine): try store.archiveMachine(machine.id)
      }
      failure = nil
      reload()
    } catch {
      fail(error, target: target, action: isGym(target) ? .archiveGym : .archiveMachine)
    }
  }

  private func isGym(_ target: Target) -> Bool {
    if case .gym = target { return true }
    return false
  }

  private func fail(_ error: any Error, target: Target, action: FailureCopy.Action) {
    let gymID: GymID
    switch target {
    case .gym(let gym): gymID = gym.id
    case .machine(let machine): gymID = machine.gymID
    }
    failure = (gymID, FailureCopy.message(for: error, during: action))
  }
}

/// Rename with the current name already in the field. `NameEntrySheet` starts empty and is shared,
/// so a rename gets its own.
private struct RenameSheet: View {
  let title: String
  let isMachine: Bool
  let onSave: (String, String) -> Void

  @State private var name: String
  @State private var brand: String
  @FocusState private var isFocused: Bool
  @Environment(\.dismiss) private var dismiss

  fileprivate init(target: GymsScreen.Target, onSave: @escaping (String, String) -> Void) {
    switch target {
    case .gym(let gym):
      self.title = "Rename gym"
      self.isMachine = false
      _name = State(initialValue: gym.name)
      _brand = State(initialValue: "")
    case .machine(let machine):
      self.title = "Rename machine"
      self.isMachine = true
      _name = State(initialValue: machine.name)
      _brand = State(initialValue: machine.brand)
    }
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .focused($isFocused)
          if isMachine {
            TextField("Brand (optional)", text: $brand)
          }
        }
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            onSave(name, brand)
            dismiss()
          }
          .disabled(EquipmentName.normalized(name) == nil)
        }
      }
      .onAppear { isFocused = true }
    }
    .presentationDetents([.medium])
  }
}
