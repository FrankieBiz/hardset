import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Identifies which exercise's machine picker is open.
private struct MachineTarget: Identifiable, Hashable {
  let id: UUID
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
  @State private var isPickerPresented = false
  /// Whether the define-your-own-movement sheet is up.
  @State private var isCreatingExercise = false
  /// Set when finishing failed and the session is still open, so the user is told rather than
  /// silently returned to a start screen while their workout is stranded.
  @State private var finishFailed = false
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  /// The exercise whose machine is being chosen. Non-nil presents the picker.
  ///
  /// Wrapped rather than a bare `UUID` because `sheet(item:)` needs `Identifiable`, and retroactively
  /// conforming a Foundation type to get it would leak that conformance to every importer.
  @State private var machineTarget: MachineTarget?
  @State private var machineOptions: (recent: [MachineOption], others: [MachineOption]) = ([], [])
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
        coordinator.logSet(slotID: slot.id, inExercise: exerciseStateID)
      },
      onUnlogSet: { exerciseStateID, slot in
        coordinator.unlogSet(slotID: slot.id, inExercise: exerciseStateID)
      },
      onRemoveSlot: { exerciseStateID, slot in
        coordinator.removeSlot(slotID: slot.id, inExercise: exerciseStateID)
      },
      onRemoveExercise: { exerciseStateID in
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
    .sheet(isPresented: $isPickerPresented) {
      NavigationStack {
        ExercisePickerView(
          query: $pickerQuery,
          entries: pickerEntries,
          recent: recentExercises,
          availableHere: availableHere,
          gymName: gymName,
          onSelect: { entry in
            coordinator.addExercise(entry)
            isPickerPresented = false
            pickerQuery = ""
          },
          // The catalogue is knowingly a third of its intended size, so "nothing matches" is a
          // routine outcome. It used to be a dead end.
          onCreate: exercises == nil ? nil : { isCreatingExercise = true }
        )
        .sheet(isPresented: $isCreatingExercise) {
          NewExerciseSheet(
            // Prefilled from the search that found nothing, so the name is not typed twice.
            initialName: pickerQuery,
            onCreate: { name, modality, muscle in
              isCreatingExercise = false
              createExercise(name: name, modality: modality, muscle: muscle)
            },
            onCancel: { isCreatingExercise = false }
          )
        }
        .navigationTitle("Add movement")
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
      .task(id: pickerQuery) { refreshPicker() }
      // Once per presentation. Relevance does not change while the sheet is open.
      .task { refreshRelevance() }
    }
    .sheet(item: $machineTarget) { wrapped in
      let target = wrapped.id
      NavigationStack {
        MachinePickerView(
          recent: machineOptions.recent,
          others: machineOptions.others,
          selected: coordinator.exercises.first { $0.id == target }?.machineID,
          onSelect: { machineID in
            selectMachine(machineID, forExercise: target)
            machineTarget = nil
          },
          onAddMachine: { isAddingMachine = true },
          onRename: { renamingMachine = MachineTarget(id: $0.rawValue) },
          onArchive: { archive($0, forExercise: target) },
          onSetIncrement: { incrementMachine = MachineTarget(id: $0.rawValue) }
        )
        .navigationTitle("Machine")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { machineTarget = nil }
          }
        }
        // Named on the spot rather than in a setup flow, because the lifter is standing at the
        // machine right now and will not be later.
        .sheet(item: $renamingMachine) { wrapped in
          NameEntrySheet(
            title: "Rename machine",
            prompt: "Name or brand",
            footnote:
              "Only the label changes. Everything logged on this machine keeps its history.",
            onConfirm: { newName in
              let id = MachineID(rawValue: wrapped.id)
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
          NameEntrySheet(
            title: "Add a machine",
            prompt: "Name or brand",
            footnote:
              "Whatever you'd recognise it by — \"Hammer Strength\" or \"the one by the window\".",
            onConfirm: { name in
              isAddingMachine = false
              addMachine(named: name, forExercise: target)
            },
            onCancel: { isAddingMachine = false }
          )
        }
      }
      // Reloaded per presentation: what the lifter used most recently changes as they log.
      .task(id: wrapped) { refreshMachines(forExercise: target) }
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
    guard let gyms, let gymID = coordinator.gymID,
      let exercise = coordinator.exercises.first(where: { $0.id == target })
    else { return }
    do {
      let recent = try gyms.recentMachines(for: exercise.exerciseID, at: gymID)
      let recentIDs = Set(recent.map(\.id))
      let others = try gyms.machines(at: gymID).filter { !recentIDs.contains($0.id) }
      machineOptions = (recent.map(Self.option(for:)), others.map(Self.option(for:)))
    } catch {
      // An unreadable gym must not block logging. The picker shows only "Not recorded", which is
      // a true statement about what can be offered rather than a fabricated list.
      machineOptions = ([], [])
    }
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
  private func createExercise(name: String, modality: ExerciseModality?, muscle: Muscle) {
    guard let exercises else { return }
    do {
      let id = try exercises.createExercise(
        name: name, modality: modality, primaryMuscle: muscle
      )
      coordinator.addExercise(exerciseID: id, exerciseName: name, modality: modality)
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
      let machineID = try gyms.createMachine(
        at: gymID, name: name, forExercise: exerciseID
      )
      // Selected immediately: adding one and then having to find it in a list is a second decision
      // for no reason. The stack step is left unknown rather than guessed — an invented increment
      // would licence progression suggestions the equipment cannot honour.
      refreshMachines(forExercise: target)
      _ = coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
      // Dismissed, like choosing an existing machine does. Leaving the picker open after the
      // decision has been made asks the lifter to confirm something twice.
      machineTarget = nil
    } catch {
      // Nothing was created, so nothing is selected and the list is unchanged. Silent because the
      // user's next tap is the retry, and a modal error over a modal picker is worse than none.
    }
  }

  /// What to surface above the alphabet. Both inputs are facts -- history and inventory -- so
  /// neither turns the picker into a recommendation.
  private func refreshRelevance() {
    guard let gyms else { return }
    recentExercises = (try? gyms.recentlyLoggedExercises()) ?? []
    if let gymID = coordinator.gymID {
      availableHere = (try? gyms.exercisesWithEquipment(at: gymID)) ?? []
      gymName = (try? gyms.gyms())?.first { $0.id == gymID }?.name
    } else {
      availableHere = []
      gymName = nil
    }
  }

  private func refreshPicker() {
    guard let catalog else { return }
    do {
      pickerEntries = try catalog.search(pickerQuery)
    } catch {
      // An unreadable catalogue is not worth blocking a workout over: the list is empty and the
      // picker says so, and the user can still log what is already on the plan.
      pickerEntries = []
    }
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
    plan: [PlannedExercise],
    restAfterSet: Duration?,
    hooks: RestTimerHooks,
    now: @escaping () -> Date = { Date() }
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      gymID: gymID,
      title: title,
      plan: plan,
      now: now,
      restAfterSet: restAfterSet,
      onStartRest: { duration, metadata in hooks.start(duration, metadata) }
    )
  }
}
