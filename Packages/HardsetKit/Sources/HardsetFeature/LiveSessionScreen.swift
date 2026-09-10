import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Identifies which exercise's machine picker is open.
private struct MachineTarget: Identifiable, Hashable {
  let id: UUID
}

/// What the lifter last asked the coordinator to do.
///
/// The coordinator funnels every failure into one `lastError`, so without this the screen had a
/// single fallback sentence — "It has not been logged" — and said it after a failed *un*-log, when
/// the row is still logged. That is the app stating the opposite of what the database holds.
private enum LiveAction {
  case log
  case unlog
  case removeSlot
  case removeExercise
  case note
  case rename
  case superset
}

/// Hooks the app supplies for the rest timer.
///
/// This exists so the composition root can live in a package target that builds on the host.
/// `RestTimerController` imports AlarmKit, which ships only in the iPhoneOS SDK, so depending
/// on it here would make this target — and therefore the wiring — iOS-only and unverifiable
/// outside a simulator. The app passes the controller's methods in; everything else is testable.
///
/// The default is inert rather than a fake timer: a preview or a host build shows no rest
/// running, which is honest, instead of a countdown that is not backed by an alarm.
@MainActor
public struct RestTimerHooks {
  public var state: () -> RestTimerState
  public var start: (Duration, RestMetadata) -> Void
  public var adjust: (Duration) -> Void
  public var pauseOrResume: () -> Void
  public var cancel: () -> Void
  /// Asks for permission to alert. Called when the lifter chooses a rest length, because that is
  /// when they have just asked for the feature and a prompt makes sense.
  public var requestAuthorization: () async -> Void
  /// True once permission has been refused, so the app can say the timer cannot alert rather than
  /// showing a countdown that will never make a sound.
  public var isDenied: () -> Bool

  public init(
    state: @escaping () -> RestTimerState = { .idle },
    start: @escaping (Duration, RestMetadata) -> Void = { _, _ in },
    adjust: @escaping (Duration) -> Void = { _ in },
    pauseOrResume: @escaping () -> Void = {},
    cancel: @escaping () -> Void = {},
    requestAuthorization: @escaping () async -> Void = {},
    isDenied: @escaping () -> Bool = { false }
  ) {
    self.state = state
    self.start = start
    self.adjust = adjust
    self.pauseOrResume = pauseOrResume
    self.cancel = cancel
    self.requestAuthorization = requestAuthorization
    self.isDenied = isDenied
  }

  public static var inert: RestTimerHooks { RestTimerHooks() }
}

/// The live workout, wired.
///
/// Owns the `SessionCoordinator`, binds it to `SessionView`, and routes rest requests to the
/// hooks. Every rule that matters is enforced a layer down — the coordinator marks a row logged
/// only after the write succeeds, and `SetEntryDraft.isLoggable` gates the control — so this
/// type is deliberately thin, and contains no logic worth testing on its own.
@MainActor
public struct LiveSessionScreen: View {
  @State private var coordinator: SessionCoordinator
  /// Bumped on every accepted machine change, purely to drive the haptic.
  @State private var machineChangeCount = 0
  /// The machine whose name is being repaired.
  @State private var renamingMachine: MachineTarget?
  /// The machine whose stack step is being recorded.
  @State private var incrementMachine: MachineTarget?
  /// Why an equipment edit failed, in the user's words. Separate from the set-logging errors below
  /// because it has a different cause and a different remedy.
  @State private var equipmentError: String?
  /// Whether the name-this-workout sheet is up.
  @State private var isNaming = false
  /// Whether the workout-note sheet is up.
  @State private var isNotingSession = false
  /// Relevance inputs for the picker: the user's own recent movements, and what this gym has
  /// equipment for. Loaded when the picker opens, not per render.
  @State private var recentExercises: [ExerciseID] = []
  @State private var availableHere: Set<ExerciseID> = []
  @State private var gymName: String?
  /// Movements offerable as a template for one the lifter defines. Curated only, and read once per
  /// presentation rather than per render.
  @State private var templates: [CatalogEntry] = []
  /// Machine names already used, for the add-machine sheet.
  @State private var machineNameSuggestions: [MachineNameSheet.MachineNameSuggestionRow] = []
  @State private var isPickerPresented = false
  /// Whether the define-your-own-movement sheet is up.
  @State private var isCreatingExercise = false
  /// Set when finishing failed and the session is still open, so the user is told rather than
  /// silently returned to a start screen while their workout is stranded.
  @State private var finishFailed = false
  /// Which coordinator call is being reported on, so the fallback sentence names the right thing.
  @State private var lastAction: LiveAction?
  /// Set when the machine list could not be read, so an unreadable gym is not drawn as an empty
  /// one. Logging stays possible either way.
  @State private var machineLoadFailed = false
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  @State private var isPickerLoading = false
  /// The exercise whose machine is being chosen. Non-nil presents the picker.
  ///
  /// Wrapped rather than a bare `UUID` because `sheet(item:)` needs `Identifiable`, and retroactively
  /// conforming a Foundation type to get it would leak that conformance to every importer.
  @State private var machineTarget: MachineTarget?
  @State private var machineOptions: (recent: [MachineOption], others: [MachineOption]) = ([], [])
  @State private var isMachinePickerLoading = false
  @State private var isAddingMachine = false
  private let unit: WeightUnit
  private let tracksRPE: Bool
  private let hooks: RestTimerHooks
  @State private var historyTarget: MachineTarget?
  /// Which movement's note is being edited, identified by its `ExerciseLogState` id.
  @State private var noteTarget: MachineTarget?
  private let catalog: CatalogSeeder?
  private let gyms: GymStore?
  private let progression: ProgressionStore?
  /// Creating the lifter's own movements. `nil` hides the affordance, which is correct in previews.
  private let exercises: ExerciseStore?
  private let onFinished: (SessionOutcome) -> Void

  /// - Parameter catalog: Supplies the picker. Passing `nil` hides the add-movement affordance
  ///   entirely rather than showing a button that opens an empty list.
  /// - Parameter gyms: Supplies the machine picker. Passing `nil`, or running a session with no
  ///   gym, hides the machine affordance — the same rule as the catalogue.
  public init(
    coordinator: SessionCoordinator,
    unit: WeightUnit,
    tracksRPE: Bool = false,
    hooks: RestTimerHooks = .inert,
    catalog: CatalogSeeder? = nil,
    gyms: GymStore? = nil,
    progression: ProgressionStore? = nil,
    exercises: ExerciseStore? = nil,
    onFinished: @escaping (SessionOutcome) -> Void = { _ in }
  ) {
    self._coordinator = State(initialValue: coordinator)
    self.unit = unit
    self.tracksRPE = tracksRPE
    self.hooks = hooks
    self.catalog = catalog
    self.gyms = gyms
    self.progression = progression
    self.exercises = exercises
    self.onFinished = onFinished
  }

  public var body: some View {
    @Bindable var bindable = coordinator

    SessionView(
      exercises: $bindable.exercises,
      unit: unit,
      tracksRPE: tracksRPE,
      restState: hooks.state(),
      restMetadata: coordinator.lastRestMetadata,
      restTotal: coordinator.restAfterSet,
      errorMessage: errorMessage,
      records: coordinator.lastRecords,
      onLogSet: { exerciseStateID, slot in
        lastAction = .log
        coordinator.logSet(slotID: slot.id, inExercise: exerciseStateID)
      },
      onUnlogSet: { exerciseStateID, slot in
        lastAction = .unlog
        coordinator.unlogSet(slotID: slot.id, inExercise: exerciseStateID)
      },
      onRemoveSlot: { exerciseStateID, slot in
        lastAction = .removeSlot
        coordinator.removeSlot(slotID: slot.id, inExercise: exerciseStateID)
      },
      onRemoveExercise: { exerciseStateID in
        lastAction = .removeExercise
        coordinator.removeExercise(exerciseStateID)
      },
      onAdjustRest: hooks.adjust,
      onPauseResumeRest: hooks.pauseOrResume,
      onSkipRest: {
        hooks.cancel()
        coordinator.clearRestMetadata()
      },
      onAddExercise: catalog == nil ? nil : { isPickerPresented = true },
      // Offered only when there is a gym to attach equipment to. Machines belong to a gym, so
      // without one there is nothing honest to put in the list.
      onSelectMachine: canPickMachines ? { machineTarget = MachineTarget(id: $0) } : nil,
      onShowHistory: progression == nil ? nil : { historyTarget = MachineTarget(id: $0) },
      onEditNote: { noteTarget = MachineTarget(id: $0) },
      onJoinSuperset: {
        lastAction = .superset
        coordinator.joinSupersetWithNext(exerciseStateID: $0)
      },
      onLeaveSuperset: {
        lastAction = .superset
        coordinator.leaveSuperset(exerciseStateID: $0)
      },
      onFinish: finish
    )
    .toolbar {
      ToolbarItem(placement: .principal) {
        Button { isNaming = true } label: {
          // The name, or an invitation. Not a required step: a workout with no name is fine and
          // reads as its date everywhere.
          Text(coordinator.title.isEmpty ? "Name this workout" : coordinator.title)
            .font(Tokens.Text.label.weight(.semibold))
            .foregroundStyle(
              coordinator.title.isEmpty ? Tokens.Color.textSecondary : Tokens.Color.textPrimary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          coordinator.title.isEmpty
            ? "Name this workout"
            : "Workout name, \(coordinator.title). Double tap to rename."
        )
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isNotingSession = true
        } label: {
          Label(
            coordinator.notes.isEmpty ? "Add a note" : "Edit note",
            systemImage: coordinator.notes.isEmpty ? "square.and.pencil" : "note.text"
          )
        }
      }
    }
    .sheet(isPresented: $isNotingSession) {
      NameEntrySheet(
        title: coordinator.notes.isEmpty ? "Note on this workout" : "Edit note",
        prompt: "Slept badly, first session back, felt strong\u{2026}",
        footnote:
          "About the session rather than a movement \u{2014} how it went, how you felt, anything you "
          + "will want to know when you read this back. Clear it to remove it.",
        confirmLabel: "Save",
        initialValue: coordinator.notes,
        allowsEmpty: true,
        isMultiline: true,
        onConfirm: { text in
          isNotingSession = false
          lastAction = .note
          _ = coordinator.setSessionNotes(text)
        },
        onCancel: { isNotingSession = false }
      )
    }
    .sheet(isPresented: $isNaming) {
      NameEntrySheet(
        title: coordinator.title.isEmpty ? "Name this workout" : "Rename workout",
        prompt: "Name",
        footnote: "Optional. Without one, this workout is listed by its date.",
        confirmLabel: "Save",
        initialValue: coordinator.title,
        // "Optional" has to mean it: a workout that was named can go back to being unnamed.
        allowsEmpty: true,
        onConfirm: { name in
          isNaming = false
          lastAction = .rename
          _ = coordinator.rename(to: name)
        },
        onCancel: { isNaming = false }
      )
    }
    .sheet(item: $noteTarget) { wrapped in
      let exercise = coordinator.exercises.first { $0.id == wrapped.id }
      NameEntrySheet(
        // The movement names the sheet; the placeholder shows what to type. The other way
        // round, the field read "Barbell Bench Press" and invited the user to type a name.
        title: exercise?.exerciseName ?? "Note",
        prompt: "Seat 4, pin 3, wide grip",
        footnote: "Seat height, pin, grip \u{2014} whatever you will not remember next week. Kept with the movement, so it is here every time you do it. Clear it to remove it.",
        confirmLabel: "Save",
        initialValue: exercise?.notes ?? "",
        // Clearing the field is how a note is deleted; there is no separate destructive control.
        allowsEmpty: true,
        isMultiline: true,
        onConfirm: { text in
          noteTarget = nil
          lastAction = .note
          if let exerciseID = exercise?.exerciseID {
            _ = coordinator.setNotes(text, for: exerciseID)
          }
        },
        onCancel: { noteTarget = nil }
      )
    }
    // Changing equipment mid-exercise re-prefills every unlogged row from the new machine's
    // history, which is a big enough change to confirm by feel.
    .sensoryFeedback(.selection, trigger: machineChangeCount)
    // Each sheet owns its own error and its own search. Neither was cleared on an interactive
    // dismissal, so the picker reopened pre-filtered -- hiding Recent and "At your gym", which are
    // both gated on an empty query -- and a stale equipment message outranked every later error
    // for the rest of the session, then fired as an alert about a failure from an hour ago.
    .onChange(of: isPickerPresented) { _, shown in
      if !shown {
        pickerQuery = ""
        equipmentError = nil
      }
    }
    .onChange(of: machineTarget) { _, target in
      if target == nil { equipmentError = nil }
    }
    .sheet(isPresented: $isPickerPresented) {
      NavigationStack {
        ExercisePickerView(
          query: $pickerQuery,
          entries: pickerEntries,
          isLoading: isPickerLoading,
          recent: recentExercises,
          availableHere: availableHere,
          gymName: gymName,
          onSelect: { entry in
            guard coordinator.addExercise(entry) else {
              // Keep the picker open. Dismissing it made a failed add look successful until the
              // lifter returned to the workout and discovered that no row had appeared.
              equipmentError = "That movement could not be added. Nothing was changed."
              return
            }
            isPickerPresented = false
            pickerQuery = ""
            equipmentError = nil
          },
          // The catalogue is knowingly a third of its intended size, so "nothing matches" is a
          // routine outcome. It used to be a dead end.
          onCreate: exercises == nil ? nil : { isCreatingExercise = true }
        )
        .sheet(isPresented: $isCreatingExercise) {
          NewExerciseSheet(
            // Prefilled from the search that found nothing, so the name is not typed twice.
            initialName: pickerQuery,
            templates: templates,
            gymName: gymName,
            onCreate: { draft in
              isCreatingExercise = false
              createExercise(draft)
            },
            onCancel: { isCreatingExercise = false }
          )
        }
        // The picker stays up on a failed add, so it has to own the message too. Without this the
        // only renderers were the logger's own banner -- underneath this sheet -- and the machine
        // picker's alert, which is a different, unpresented sheet. A failed add was a silent tap.
        .alert(
          "Could not add that movement",
          isPresented: Binding(
            get: { equipmentError != nil },
            set: { if !$0 { equipmentError = nil } }
          )
        ) {
          Button("OK") { equipmentError = nil }
        } message: {
          Text(equipmentError ?? "Nothing was changed.")
        }
        .navigationTitle("Add movement")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isPickerPresented = false }
          }
        }
        // Inline rather than large. A large title truncates instead of wrapping, so at
        // accessibility text sizes this sheet was headed "Add movem...". Inline also stops a
        // modal picker from spending a third of its height on its own name.
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
      }
      // Searching hits the database, so it happens here rather than inside the picker, which
      // stays free of storage. The query is re-run on change instead of filtering in memory so a
      // user-created movement shows up without reopening the sheet.
      .task(id: pickerQuery) { await refreshPicker() }
      // Once per presentation. Relevance does not change while the sheet is open.
      .task { await refreshRelevance() }
    }
    .sheet(item: $machineTarget) { wrapped in
      let target = wrapped.id
      NavigationStack {
        VStack(spacing: 0) {
          // A read that failed and a gym with no equipment produced exactly the same screen: two
          // empty sections and "Not recorded". DECISIONS #53 is explicit that a failed read says so
          // rather than presenting a convincing empty list. The picker below stays usable, because
          // an unreadable gym must never block logging.
          if machineLoadFailed {
            VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
              Text("Your machines could not be read")
                .font(Tokens.Text.label.weight(.semibold))
                .foregroundStyle(Tokens.Color.textPrimary)
              Text("Your equipment and workout history are safe.")
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
              Button("Try again") { refreshMachines(forExercise: target) }
                .font(Tokens.Text.label)
                .foregroundStyle(Tokens.Color.accent)
                .frame(minHeight: Tokens.minimumTapTarget, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Spacing.regular)
            .background(Tokens.Color.surface)
            .accessibilityElement(children: .combine)
          }

          MachinePickerView(
            recent: machineOptions.recent,
            others: machineOptions.others,
            selected: coordinator.exercises.first { $0.id == target }?.machineID,
            unit: unit,
            onSelect: { machineID in
              selectMachine(machineID, forExercise: target)
              machineTarget = nil
            },
            onAddMachine: { isAddingMachine = true },
            onRename: { renamingMachine = MachineTarget(id: $0.rawValue) },
            onArchive: { archive($0, forExercise: target) },
            onSetIncrement: { incrementMachine = MachineTarget(id: $0.rawValue) }
          )
        }
        .navigationTitle("Machine")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { machineTarget = nil }
          }
        }
        // Named on the spot rather than in a setup flow, because the lifter is standing at the
        // machine right now and will not be later.
        .sheet(item: $renamingMachine) { wrapped in
          let id = MachineID(rawValue: wrapped.id)
          // Opened with the name the app already knows, like the stack-step sheet below and the
          // sibling call site in the machine library. Blank, it made the lifter retype a name
          // mid-workout to correct one character of it.
          let current = (machineOptions.recent + machineOptions.others)
            .first { $0.id == id }?.displayName ?? ""
          NameEntrySheet(
            title: "Rename machine",
            prompt: "Name or brand",
            footnote:
              "Only the label changes. Everything logged on this machine keeps its history.",
            confirmLabel: "Save",
            initialValue: current,
            onConfirm: { newName in
              renamingMachine = nil
              rename(id, to: newName, forExercise: target)
            },
            onCancel: { renamingMachine = nil }
          )
        }
        // The step a stack moves in, recorded from the machine list because that is where the
        // lifter is looking at the machine. Nothing could write this column before, so its label,
        // its readers, and the keypad's use of it were all unreachable.
        .sheet(item: $incrementMachine) { wrapped in
          let id = MachineID(rawValue: wrapped.id)
          let current = machineOptions.recent.first { $0.id == id }?.stackIncrementKg
            ?? machineOptions.others.first { $0.id == id }?.stackIncrementKg
          NameEntrySheet(
            title: "Stack step",
            prompt: "Smallest change in \(unit.abbreviation)",
            footnote:
              "The smallest jump this stack can make \u{2014} often 5 kg or 10 lb. Suggested loads "
              + "and the +/- buttons stay on steps the machine can actually hit. Leave it empty if "
              + "you are not sure; a guess would be worse than not knowing.",
            confirmLabel: "Save",
            initialValue: current.map { Self.format(unit.fromKilograms($0)) } ?? "",
            allowsEmpty: true,
            isDecimal: true,
            onConfirm: { text in
              incrementMachine = nil
              setIncrement(text, for: id, forExercise: target)
            },
            onCancel: { incrementMachine = nil }
          )
        }
        .sheet(isPresented: $isAddingMachine) {
          MachineNameSheet(
            // Offers names already used, so the same machine at a second gym is not retyped and
            // mistyped into a third empty history.
            suggestions: machineNameSuggestions,
            onConfirm: { name in
              isAddingMachine = false
              addMachine(named: name, forExercise: target)
            },
            onCancel: { isAddingMachine = false }
          )
        }
        .alert(
          "Could not update that machine",
          isPresented: Binding(
            get: { equipmentError != nil },
            set: { if !$0 { equipmentError = nil } }
          )
        ) {
          Button("OK") { equipmentError = nil }
        } message: {
          Text(equipmentError ?? "Nothing was changed.")
        }
        .overlay {
          if isMachinePickerLoading {
            ProgressView("Loading machines…")
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Tokens.Color.ground.opacity(0.92))
          }
        }
      }
      // Reloaded per presentation: what the lifter used most recently changes as they log.
      .task(id: wrapped) { await loadMachines(forExercise: target) }
    }
    .sheet(item: $historyTarget) { wrapped in
      if let progression, let exercise = coordinator.exercises.first(where: { $0.id == wrapped.id })
      {
        NavigationStack {
          ExerciseProgressScreen(
            store: progression,
            exerciseID: exercise.exerciseID,
            exerciseName: exercise.exerciseName,
            unit: unit
          )
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { historyTarget = nil }
            }
          }
        }
      }
    }
  }

  private var canPickMachines: Bool { gyms != nil && coordinator.gymID != nil }

  /// Loads the picker's two lists, recency first.
  ///
  /// Split here rather than in the view so `MachinePickerView` keeps no storage dependency, and so
  /// the ordering rule — the machine you last used this movement on is the one you are standing at
  /// — lives in one place.
  private func refreshMachines(forExercise target: UUID) {
    Task { await loadMachines(forExercise: target) }
  }

  private func loadMachines(forExercise target: UUID) async {
    guard let gyms, let gymID = coordinator.gymID,
      let exercise = coordinator.exercises.first(where: { $0.id == target })
    else {
      isMachinePickerLoading = false
      return
    }
    isMachinePickerLoading = true
    let exerciseID = exercise.exerciseID
    let result = await readOffMain {
      let recent = try gyms.recentMachines(for: exerciseID, at: gymID)
      let recentIDs = Set(recent.map(\.id))
      let others = try gyms.machines(at: gymID).filter { !recentIDs.contains($0.id) }
      let suggestions = try gyms.machineNameSuggestions(at: gymID)
      return (recent, others, suggestions)
    }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      machineOptions = (loaded.0.map(Self.option(for:)), loaded.1.map(Self.option(for:)))
      // Loaded here rather than with the exercise picker's relevance, because this is the flow
      // that reaches "Add a machine".
      machineNameSuggestions = loaded.2.map {
        MachineNameSheet.MachineNameSuggestionRow(
          name: $0.name, isAlreadyHere: $0.existingHere != nil, otherGymNames: $0.otherGymNames
        )
      }
    case .failure:
      // An unreadable gym must not block logging. The picker shows only "Not recorded", which is
      // a true statement about what can be offered rather than a fabricated list.
      machineOptions = ([], [])
      machineNameSuggestions = []
    }
    isMachinePickerLoading = false
  }

  private static func option(for record: MachineRecord) -> MachineOption {
    MachineOption(
      id: record.id, displayName: record.displayName, stackIncrementKg: record.stackIncrementKg
    )
  }

  /// Retires a machine. If the exercise was pointing at it, the pointer is cleared -- a row
  /// referencing equipment that is no longer offered is a dead end.
  private func archive(_ machineID: MachineID, forExercise target: UUID) {
    guard let gyms else { return }
    do {
      try gyms.archiveMachine(machineID)
      equipmentError = nil
      if coordinator.exercises.first(where: { $0.id == target })?.machineID == machineID {
        _ = coordinator.changeMachine(to: nil, machineName: nil, inExercise: target)
      }
      refreshMachines(forExercise: target)
    } catch {
      equipmentError = "That machine could not be retired. \(error)"
    }
  }

  private func rename(_ machineID: MachineID, to name: String, forExercise target: UUID) {
    guard let gyms else { return }
    do {
      try gyms.renameMachine(machineID, to: name)
      equipmentError = nil
      // The name is denormalised onto the log state for the Lock Screen, so it is refreshed too.
      if coordinator.exercises.first(where: { $0.id == target })?.machineID == machineID {
        _ = coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
      }
      refreshMachines(forExercise: target)
    } catch {
      equipmentError = "That machine could not be renamed. \(error)"
    }
  }

  private func selectMachine(_ machineID: MachineID?, forExercise target: UUID) {
    let name =
      machineID.flatMap { id in
        (machineOptions.recent + machineOptions.others).first { $0.id == id }?.displayName
      }
    // The coordinator persists before it mutates memory, and reads the increment from the machines
    // table itself, so nothing here needs to know either.
    if coordinator.changeMachine(to: machineID, machineName: name, inExercise: target) {
      // Only on a change that actually took. A failed write must not feel like a success.
      machineChangeCount += 1
    }
  }

  /// Same argument-passing rule as `addGym`: the name arrives as a parameter, because reading it
  /// back out of state across a presentation boundary produced an empty string.
  /// Writes the stack step, in the unit on screen, converted to kilograms like every other load.
  ///
  /// An empty field clears it back to unknown, which is a real answer rather than a failure: better
  /// no step than a guessed one, because a wrong step makes every suggestion unreachable on the
  /// equipment.
  private func setIncrement(_ text: String, for machineID: MachineID, forExercise target: UUID) {
    guard let gyms else { return }
    let entered = TypedNumber.parse(text)
    do {
      try gyms.setStackIncrement(entered.map { unit.toKilograms($0) }, for: machineID)
      refreshMachines(forExercise: target)
      // Re-selected so the exercise picks up the new increment without the lifter reselecting it.
      _ = coordinator.changeMachine(
        to: machineID,
        machineName: machineOptions.recent.first { $0.id == machineID }?.displayName
          ?? machineOptions.others.first { $0.id == machineID }?.displayName,
        inExercise: target
      )
      equipmentError = nil
    } catch {
      equipmentError = "That step could not be saved. The machine is unchanged."
    }
  }

  static func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
  }

  /// Records a movement the lifter defined, then adds it to the workout in progress.
  ///
  /// Added immediately rather than returned to the list: they described it in order to log it, and
  /// making them find it again afterwards is a second decision for no reason.
  private func createExercise(_ draft: NewExerciseDraft) {
    guard let exercises else { return }
    do {
      let id = try exercises.createExercise(
        name: draft.name,
        modality: draft.modality,
        primaryMuscle: draft.primaryMuscle,
        inheriting: draft.inheriting
      )
      let machineID: MachineID?
      if let machineName = draft.machineName, let gyms, let gymID = coordinator.gymID {
        machineID = try gyms.resolveMachine(
          at: gymID, named: machineName, forExercise: id
        ).id
      } else {
        machineID = nil
      }
      guard coordinator.addExercise(
        exerciseID: id,
        exerciseName: draft.name,
        modality: draft.modality,
        machineID: machineID,
        machineName: machineID == nil ? nil : draft.machineName
      ) else {
        equipmentError = "That movement was saved, but it could not be added to this workout."
        return
      }
      isPickerPresented = false
      pickerQuery = ""
      equipmentError = nil
    } catch {
      equipmentError = "That movement could not be saved. Nothing was added."
    }
  }

  private func addMachine(named name: String, forExercise target: UUID) {
    guard let gyms, let gymID = coordinator.gymID, !name.isEmpty else { return }
    do {
      let exerciseID = coordinator.exercises.first { $0.id == target }?.exerciseID
      // Recorded here because this is the only moment the association is known for free: a machine
      // is named from inside an exercise's picker, and nothing later can recover what it was for
      // without guessing.
      //
      // `resolveMachine`, not `createMachine`: the sheet now offers names back, so a name that is
      // already at THIS gym is a likely input rather than a rare one, and inserting unconditionally
      // would answer "that one" with a second machine holding no history. Never matches across
      // gyms -- that would be the merge invariant #10 forbids.
      let machineID = try gyms.resolveMachine(
        at: gymID, named: name, forExercise: exerciseID
      ).id
      // Selected immediately: adding one and then having to find it in a list is a second decision
      // for no reason. The stack step is left unknown rather than guessed — an invented increment
      // would licence progression suggestions the equipment cannot honour.
      refreshMachines(forExercise: target)
      _ = coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
      // Dismissed, like choosing an existing machine does. Leaving the picker open after the
      // decision has been made asks the lifter to confirm something twice.
      machineTarget = nil
    } catch {
      // The picker remains open and owns the alert, so the failure is visible without throwing the
      // lifter out of the equipment flow.
      equipmentError = "That machine could not be saved. Nothing was changed."
    }
  }

  /// What to surface above the alphabet. Both inputs are facts -- history and inventory -- so
  /// neither turns the picker into a recommendation.
  private func refreshRelevance() async {
    let catalog = catalog
    let gyms = gyms
    let gymID = coordinator.gymID
    let result = await readOffMain {
      let templates = try catalog?.selectableExercises().filter(\.isCurated) ?? []
      guard let gyms else {
        return (templates, [ExerciseID](), Set<ExerciseID>(), String?.none)
      }
      let recent = try gyms.recentlyLoggedExercises()
      guard let gymID else { return (templates, recent, Set<ExerciseID>(), String?.none) }
      let available = try gyms.exercisesWithEquipment(at: gymID)
      let name = try gyms.gyms().first { $0.id == gymID }?.name
      return (templates, recent, available, name)
    }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let loaded):
      templates = loaded.0
      recentExercises = loaded.1
      availableHere = loaded.2
      gymName = loaded.3
    case .failure:
      // Creation remains available even if relevance could not be assembled.
      templates = []
      recentExercises = []
      availableHere = []
      gymName = nil
    }
  }

  private func refreshPicker() async {
    guard let catalog else {
      pickerEntries = []
      isPickerLoading = false
      return
    }
    let query = pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    isPickerLoading = true
    // A short debounce avoids a table scan for every intermediate character without making the
    // keyboard feel detached from the results. Empty-query presentation still loads immediately.
    if !query.isEmpty {
      try? await Task.sleep(for: .milliseconds(120))
    }
    guard !Task.isCancelled else { return }
    let result = await readOffMain { try catalog.search(query) }
    guard !Task.isCancelled, query == pickerQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    else { return }
    switch result {
    case .success(let entries):
      pickerEntries = entries
    case .failure:
      // An unreadable catalogue is not worth blocking a workout over: the list is empty and the
      // picker says so, and the user can still log what is already on the plan.
      pickerEntries = []
    }
    isPickerLoading = false
  }

  /// A failed write is stated in the user's words, not as an error dump. The row stays
  /// unlogged, so the correct instruction is to try again.
  private var errorMessage: String? {
    // Stated, never swallowed: a rename or retire that failed must not look like it worked.
    if let equipmentError { return equipmentError }
    if finishFailed {
      return "This workout could not be finished, so it is still open. Your sets are saved. "
        + "Check your device's date and time, then try again."
    }
    guard let error = coordinator.lastError else { return nil }
    if let storeError = error as? LoggerStoreError {
      switch storeError {
      case .incompleteSet:
        return "Enter a weight and reps before logging this set."
      case .sessionNotFound:
        return "This workout could not be found. Your logged sets are safe."
      case .sessionAlreadyOpen:
        // Not reachable from inside a live session -- this screen only exists because one is open
        // -- but stated rather than left to the generic fallback, which would blame the set.
        return "A workout is already open. Finish it before starting another."
      }
    }
    return "That set could not be saved. It has not been logged — tap to try again."
  }

  private func finish() {
    hooks.cancel()
    coordinator.clearRestMetadata()
    do {
      try coordinator.finish()
      // Read after the finish, so the timeline is closed and the summary has a duration.
      onFinished(coordinator.outcome)
    } catch SessionTimelineError.alreadyFinished {
      // Genuinely closed already — a double tap, or a finish that raced a recovery. Moving on is
      // correct here because the session really is finished. The outcome may carry no duration in
      // that case, and "Unknown" is the honest thing to show.
      onFinished(coordinator.outcome)
    } catch {
      // Anything else and the session is STILL OPEN. Calling onFinished() here was a bug: the root
      // view dropped the coordinator, the user started a new workout, and because openSession()
      // returns only the newest and history shows finished sessions only, the first session's sets
      // became unreachable from every screen. The earlier comment claimed "nothing is lost", which
      // was wrong.
      //
      // `finishedBeforeStart` is the realistic trigger: the device clock moving backwards, from a
      // timezone or NTP correction, makes `now()` precede `startedAt`.
      finishFailed = true
    }
  }
}

extension SessionCoordinator {
  /// Builds a coordinator whose rest requests are routed to `hooks`.
  ///
  /// A convenience with a purpose: the `onStartRest` closure has to be supplied at
  /// construction, before the view exists, which is easy to forget and silently produces a
  /// session that never rests.
  public static func start(
    store: LoggerStore,
    gymID: GymID? = nil,
    title: String = "",
    splitDayID: SplitDayID? = nil,
    plan: [PlannedExercise],
    restAfterSet: Duration?,
    hooks: RestTimerHooks,
    now: @escaping () -> Date = { Date() }
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      gymID: gymID,
      title: title,
      splitDayID: splitDayID,
      plan: plan,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: { duration, metadata in hooks.start(duration, metadata) }
    )
  }

  /// Keeps the database work for a new workout off the UI actor while preserving the same rest
  /// routing as the synchronous convenience above.
  public static func startAsync(
    store: LoggerStore,
    gymID: GymID? = nil,
    title: String = "",
    splitDayID: SplitDayID? = nil,
    plan: [PlannedExercise],
    restAfterSet: Duration?,
    hooks: RestTimerHooks,
    now: @escaping () -> Date = { Date() }
  ) async throws -> SessionCoordinator {
    try await SessionCoordinator.startAsync(
      store: store,
      gymID: gymID,
      title: title,
      splitDayID: splitDayID,
      plan: plan,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: { duration, metadata in hooks.start(duration, metadata) }
    )
  }
}
