import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// `MachineLibraryView` wired to storage.
///
/// Machines could only ever be created inside a workout, which is the right primary path and was
/// never the whole story: there was no way to review what you had named, fix a typo outside a
/// session, set a stack step you learned later, or find the duplicate a mistyped name created. This
/// is that surface, and nothing more — it prompts for nothing and blocks nothing.
@MainActor
public struct MachineLibraryScreen: View {
  private let gyms: GymStore
  private let unit: WeightUnit

  @State private var choices: [MachineLibraryView.GymChoice] = []
  @State private var selectedGym: GymID?
  @State private var rows: [MachineLibraryView.Row] = []
  @State private var prompt: Prompt?
  /// Machine names already used anywhere, for the add sheet.
  @State private var nameSuggestions: [MachineNameSheet.MachineNameSuggestionRow] = []
  @State private var failure: String?
  @State private var isLoading = true
  @State private var isLoadingMachines = false
  @State private var loadFailed = false

  public init(gyms: GymStore, unit: WeightUnit = .kilograms) {
    self.gyms = gyms
    self.unit = unit
  }

  /// One optional drives one sheet. Two `.sheet` modifiers on a single anchor silently drop the
  /// second, which has already cost this codebase a screen that never presented.
  private enum Prompt: Identifiable {
    case addMachine
    case addGym
    case rename(MachineLibraryView.Row)
    case step(MachineLibraryView.Row)

    var id: String {
      switch self {
      case .addMachine: "add"
      case .addGym: "add-gym"
      case .rename(let row): "rename-\(row.id.rawValue)"
      case .step(let row): "step-\(row.id.rawValue)"
      }
    }
  }

  public var body: some View {
    content
      .task { await reload() }
      .refreshable { await reload() }
      .sheet(item: $prompt) { prompt in sheet(for: prompt) }
      .alert(
        "Could not complete that",
        isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
      ) {
        Button("OK") { failure = nil }
      } message: {
        Text(failure ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    if isLoading, choices.isEmpty {
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if loadFailed, choices.isEmpty {
      ContentUnavailableView {
        Label("Could not read your machines", systemImage: "exclamationmark.triangle")
      } description: {
        Text("Your equipment and workout history are safe.")
      } actions: {
        Button("Try again") { Task { await reload() } }
      }
    } else if choices.isEmpty {
      // No gym at all is a different state from a gym with no machines, and conflating them would
      // offer "Add a machine" with nowhere to put it.
      ContentUnavailableView {
        Label("No gyms yet", systemImage: "building.2")
      } description: {
        Text(
          "A gym is created the first time you record where you trained. You can add one here if "
            + "you would rather set it up in advance."
        )
      } actions: {
        Button("Add a gym") { prompt = .addGym }
      }
    } else {
      MachineLibraryView(
        gyms: choices,
        selectedGym: $selectedGym,
        rows: rows,
        unit: unit,
        onAddMachine: { prompt = .addMachine },
        onRename: { prompt = .rename($0) },
        onSetStep: { prompt = .step($0) },
        onSetArchived: setArchived
      )
      .onChange(of: selectedGym) { _, _ in Task { await reloadMachines() } }
      .overlay {
        if isLoadingMachines {
          ProgressView("Loading machines…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Tokens.Color.ground.opacity(0.92))
        }
      }
    }
  }

  @ViewBuilder private func sheet(for prompt: Prompt) -> some View {
    switch prompt {
    case .addGym:
      NameEntrySheet(
        title: "Add a gym",
        prompt: "Gym name",
        confirmLabel: "Add",
        onConfirm: { name in
          self.prompt = nil
          write { let id = try gyms.createGym(name: name); selectedGym = id }
        },
        onCancel: { self.prompt = nil }
      )

    case .addMachine:
      MachineNameSheet(
        suggestions: nameSuggestions,
        onConfirm: { name in
          self.prompt = nil
          guard let gym = selectedGym else { return }
          // `resolveMachine`, not `createMachine`. The sheet offers names back, so re-picking one
          // already at this gym is a likely input -- and inserting unconditionally would answer
          // "that one" with a second machine holding none of its history.
          write { _ = try gyms.resolveMachine(at: gym, named: name) }
        },
        onCancel: { self.prompt = nil }
      )

    case .rename(let row):
      NameEntrySheet(
        title: "Rename machine",
        prompt: "Name or brand",
        confirmLabel: "Save",
        // Prefilled. A rename sheet that opens blank makes the lifter retype a name the app is
        // already holding.
        initialValue: row.name,
        onConfirm: { name in
          self.prompt = nil
          write { try gyms.renameMachine(row.id, to: name) }
        },
        onCancel: { self.prompt = nil }
      )

    case .step(let row):
      NameEntrySheet(
        title: "Stack step",
        prompt: "Smallest step in \(unit.abbreviation)",
        footnote: "The smallest jump this stack actually moves in. Left unset the app will not "
          + "round a load to a step this machine cannot make.",
        confirmLabel: "Save",
        initialValue: row.stackIncrementKg
          .map { MachineLibraryView.trimmed(unit.displayValue(fromKilograms: $0)) } ?? "",
        // Empty clears it, which has to be possible: a step entered by mistake would otherwise be
        // permanent, and an unknown step is an honest state the rest of the app already handles.
        allowsEmpty: true,
        isDecimal: true,
        onConfirm: { text in
          self.prompt = nil
          setStep(text, for: row)
        },
        onCancel: { self.prompt = nil }
      )
    }
  }

  // MARK: - Writes

  private func setArchived(_ row: MachineLibraryView.Row, _ archived: Bool) {
    write { try gyms.setMachineArchived(archived, for: row.id) }
  }

  /// Stores the step in kilograms, converting at the boundary. Kilograms are canonical everywhere
  /// in this app; a pounds value reaching the column would make one machine's step mean something
  /// different from another's.
  private func setStep(_ text: String, for row: MachineLibraryView.Row) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      write { try gyms.setStackIncrement(nil, for: row.id) }
      return
    }
    // Locale-aware: a comma decimal separator is what a large part of the world types, and
    // `Double(_:)` rejects it outright.
    guard let value = Self.number(from: trimmed), value > 0 else {
      failure = "That is not a weight this app can read. Nothing was changed."
      return
    }
    write { try gyms.setStackIncrement(unit.toKilograms(value), for: row.id) }
  }

  static func number(from text: String) -> Double? {
    if let value = Double(text) { return value }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.number(from: text)?.doubleValue
  }

  /// Runs a write and surfaces its failure instead of swallowing it. A `try?` here would leave a
  /// button that appears to do nothing, which is a failure mode this codebase has already shipped.
  private func write(_ work: () throws -> Void) {
    do {
      try work()
      failure = nil
      Task { await reload() }
    } catch {
      failure = error.localizedDescription
    }
  }

  // MARK: - Reads

  private func reload() async {
    isLoading = true
    loadFailed = false
    let gyms = gyms
    let result = await readOffMain {
      let records = try gyms.gyms()
      // Failure to infer recency must not turn a readable gym list into an error.
      return (records, try? gyms.lastUsedGym())
    }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      let records = loaded.0
      choices = records.map { MachineLibraryView.GymChoice(id: $0.id, name: $0.name) }
      if selectedGym == nil || !records.contains(where: { $0.id == selectedGym }) {
        // Where they last trained, falling back to the first gym. Learned rather than stored, so
        // there is no preference to go stale.
        selectedGym = loaded.1 ?? records.first?.id
      }
      isLoading = false
      await reloadMachines()
    case .failure:
      choices = []
      rows = []
      nameSuggestions = []
      loadFailed = true
      isLoading = false
    }
  }

  private func reloadMachines() async {
    guard let gym = selectedGym else {
      rows = []
      nameSuggestions = []
      isLoadingMachines = false
      return
    }
    isLoadingMachines = true
    let gyms = gyms
    let result = await readOffMain {
      (try gyms.machineNameSuggestions(at: gym), try gyms.machineLibrary(at: gym))
    }
    guard !Task.isCancelled, gym == selectedGym else { return }
    switch result {
    case .success(let loaded):
      nameSuggestions = loaded.0.map {
        MachineNameSheet.MachineNameSuggestionRow(
          name: $0.name, isAlreadyHere: $0.existingHere != nil, otherGymNames: $0.otherGymNames
        )
      }
      rows = loaded.1.map {
        MachineLibraryView.Row(
          id: $0.id,
          name: $0.name,
          stackIncrementKg: $0.stackIncrementKg,
          isArchived: $0.isArchived,
          linkedExerciseNames: $0.linkedExerciseNames,
          lastUsed: $0.lastUsed,
          heaviestKg: $0.heaviestKg,
          heaviestReps: $0.heaviestReps,
          workingSetCount: $0.workingSetCount
        )
      }
    case .failure:
      rows = []
      nameSuggestions = []
      failure = "Your machines could not be read. Your workout history is safe; try again."
    }
    isLoadingMachines = false
  }
}
