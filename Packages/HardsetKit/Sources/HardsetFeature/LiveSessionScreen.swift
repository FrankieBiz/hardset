import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Identifies which exercise's machine picker is open.
private struct MachineTarget: Identifiable, Hashable {
  let id: UUID
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
  @State private var editingIncrement: MachineOption?
  @State private var restMetadata: RestMetadata?
  @State private var isPickerPresented = false
  /// Why finishing or discarding failed while the session is still open, so the user is told
  /// rather than silently returned to a start screen while their workout is stranded. Cleared by
  /// the next operation, so it can never stand in for a later, different failure.
  @State private var finishError: String?
  /// What the lifter last asked for, so a failure is described as the thing that failed: a
  /// movement that could not be added is not "That set could not be saved".
  @State private var lastOperation: SessionOperation = .log
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  @State private var pickerRecent: [CatalogEntry] = []
  @State private var pickerError: String?
  /// The exercise whose machine is being chosen. Non-nil presents the picker.
  ///
  /// Wrapped rather than a bare `UUID` because `sheet(item:)` needs `Identifiable`, and retroactively
  /// conforming a Foundation type to get it would leak that conformance to every importer.
  @State private var machineTarget: MachineTarget?
  @State private var machineOptions: (recent: [MachineOption], others: [MachineOption]) = ([], [])
  @State private var machineError: String?
  /// The gym's machines could not be read, so adding one would risk a duplicate of a machine the
  /// lifter already has.
  @State private var machineLoadFailed = false
  @State private var isAddingMachine = false
  @State private var machineNameError: String?
  @State private var isChoosingGym = false
  @State private var isAddingGym = false
  @State private var gymOptions: [GymOption] = []
  @State private var gymError: String?
  @State private var gymNameError: String?
  /// The movement whose set produced `coordinator.lastRecords`, so the records name it.
  @State private var recordsExerciseName: String?
  @State private var recordsDismissed = false
  /// The rest each movement was last given, read once per movement rather than on every render.
  @State private var rememberedRest: [ExerciseID: Duration] = [:]
  private let unit: WeightUnit
  private let hooks: RestTimerHooks
  @State private var historyTarget: MachineTarget?
  private let catalog: CatalogSeeder?
  private let gyms: GymStore?
  private let progression: ProgressionStore?
  private let gymName: String?
  private let restPreferences: RestPreferences
  private let onShowSettings: (() -> Void)?
  private let onFinished: () -> Void

  /// - Parameter catalog: Supplies the picker. Passing `nil` hides the add-movement affordance
  ///   entirely rather than showing a button that opens an empty list.
  /// - Parameter gyms: Supplies the machine picker and the workout's gym. Passing `nil` hides
  ///   both; a session with no gym hides the machine chips until one is set.
  /// - Parameter gymName: Shown in the screen's header, so the lifter can see which gym's
  ///   machines the chips are offering. `nil` reads "No gym recorded".
  /// - Parameter restPreferences: Where each movement's last chosen rest is remembered.
  /// - Parameter onShowSettings: Puts the settings button in the header, so the unit can be
  ///   changed mid-workout as it could be from the start screen.
  /// - Parameter onFinished: Called once the workout is finished or discarded, and no longer open.
  public init(
    coordinator: SessionCoordinator,
    unit: WeightUnit,
    hooks: RestTimerHooks = .inert,
    catalog: CatalogSeeder? = nil,
    gyms: GymStore? = nil,
    progression: ProgressionStore? = nil,
    gymName: String? = nil,
    restPreferences: RestPreferences? = nil,
    onShowSettings: (() -> Void)? = nil,
    onFinished: @escaping () -> Void = {}
  ) {
    self._coordinator = State(initialValue: coordinator)
    self.unit = unit
    self.hooks = hooks
    self.catalog = catalog
    self.gyms = gyms
    self.progression = progression
    self.gymName = gymName
    self.restPreferences = restPreferences ?? RestPreferences()
    self.onShowSettings = onShowSettings
    self.onFinished = onFinished
  }

  public var body: some View {
    @Bindable var bindable = coordinator

    SessionView(
      exercises: $bindable.exercises,
      unit: unit,
      title: "Workout",
      gymName: displayedGymName,
      startedAt: coordinator.startedAt,
      lastLoggedAt: coordinator.lastLoggedAt,
      isStale: isStale,
      restState: hooks.state(),
      restMetadata: hooks.metadata() ?? restMetadata,
      errorMessage: errorMessage,
      records: recordsDismissed ? [] : coordinator.lastRecords,
      recordsExerciseName: recordsExerciseName,
      lastRest: lastRestByCard,
      onLogSet: { exerciseStateID, slot in
        logSet(slot, inExercise: exerciseStateID)
      },
      onStartRest: { exerciseStateID, duration in
        startRest(duration, afterExercise: exerciseStateID)
      },
      onAdjustRest: hooks.adjust,
      onPauseResumeRest: hooks.pauseOrResume,
      onSkipRest: endRest,
      onAddExercise: catalog == nil ? nil : { isPickerPresented = true },
      // Offered only when there is a gym to attach equipment to. Machines belong to a gym, so
      // without one there is nothing honest to put in the list.
      onSelectMachine: canPickMachines ? { machineTarget = MachineTarget(id: $0) } : nil,
      onShowHistory: progression == nil ? nil : { historyTarget = MachineTarget(id: $0) },
      onShowSettings: onShowSettings,
      onChangeGym: gyms == nil ? nil : { isChoosingGym = true },
      onUndoSet: { exerciseStateID, slot in
        begin(.undoSet)
        return coordinator.undoSet(slotID: slot.id, inExercise: exerciseStateID)
      },
      onRemoveSet: { exerciseStateID, slot in
        begin(.removeSet)
        coordinator.removeSlot(slotID: slot.id, inExercise: exerciseStateID)
      },
      onRemoveExercise: { exerciseStateID in
        begin(.removeMovement)
        coordinator.removeExercise(exerciseStateID)
      },
      onMoveExercise: { exerciseStateID, offset in
        begin(.moveMovement)
        coordinator.moveExercise(exerciseStateID, by: offset)
      },
      onDismissError: dismissError,
      onDismissRecords: { recordsDismissed = true },
      onFinish: { finish() },
      onFinishAt: coordinator.lastLoggedAt == nil ? nil : { finish(at: $0) },
      onDiscard: discard
    )
    .onAppear { loadRememberedRest() }
    .onChange(of: coordinator.exercises.map(\.exerciseID)) { loadRememberedRest() }
    .sheet(isPresented: $isPickerPresented, onDismiss: {
      // A swipe-down dismissal used to leave the last search behind for the next visit.
      pickerQuery = ""
      pickerError = nil
      clearError(from: .addMovement)
    }) {
      NavigationStack {
        ExercisePickerView(
          query: $pickerQuery,
          entries: pickerEntries,
          recent: pickerRecent,
          errorMessage: pickerError,
          onCancel: { isPickerPresented = false },
          onCreate: catalog == nil ? nil : { name in createMovement(named: name) },
          onSelect: { entry in addMovement(entry) }
        )
        .hardsetNavigationTitle("Add movement")
      }
      .hardsetSheet()
      // Searching hits the database, so it happens here rather than inside the picker, which
      // stays free of storage. The query is re-run on change instead of filtering in memory so a
      // user-created movement shows up without reopening the sheet.
      .task(id: pickerQuery) { refreshPicker() }
    }
    .sheet(item: $machineTarget, onDismiss: {
      machineError = nil
      machineLoadFailed = false
      clearError(from: .changeMachine)
    }) { wrapped in
      let target = wrapped.id
      NavigationStack {
        MachinePickerView(
          recent: machineOptions.recent,
          others: machineOptions.others,
          selected: coordinator.exercises.first { $0.id == target }?.machineID,
          unit: unit,
          errorMessage: machineError,
          onSelect: { machineID in
            // Closed only when the change was saved. On a failure the picker stays, saying why,
            // and the lifter's next tap is the retry.
            if selectMachine(machineID, forExercise: target) {
              machineTarget = nil
            }
          },
          // Not offered while the gym's machines cannot be read: a lifter who cannot see the
          // machines they have would add a second one of each.
          onAddMachine: machineLoadFailed ? nil : { isAddingMachine = true },
          onEditIncrement: { id in
            editingIncrement = (machineOptions.recent + machineOptions.others).first { $0.id == id }
          },
          onArchive: { id in archiveMachine(id, forExercise: target) },
          onCancel: { machineTarget = nil }
        )
        .hardsetNavigationTitle("Machine")
        .sheet(item: $editingIncrement) { machine in
          LoadStepSheet(machineName: machine.displayName, incrementKg: machine.stackIncrementKg, unit: unit,
            onSave: { increment in
              guard let gyms, let gymID = coordinator.gymID else { return false }
              do {
                try gyms.setStackIncrement(increment, for: machine.id, at: gymID)
                for index in coordinator.exercises.indices where coordinator.exercises[index].machineID == machine.id {
                  coordinator.exercises[index].updateMachineIncrement(increment)
                }
                refreshMachines(forExercise: target)
                editingIncrement = nil
                return true
              } catch { return false }
            }, onCancel: { editingIncrement = nil })
          .hardsetSheet()
        }
        // Named on the spot rather than in a setup flow, because the lifter is standing at the
        // machine right now and will not be later.
        .sheet(isPresented: $isAddingMachine, onDismiss: { machineNameError = nil }) {
          NameEntrySheet(
            title: "Add a machine",
            prompt: "Name or brand",
            footnote:
              "Whatever you'd recognise it by — \"Hammer Strength\" or \"the one by the window\".",
            errorMessage: machineNameError,
            onConfirm: { name in
              addMachine(named: name, forExercise: target)
            },
            onCancel: { isAddingMachine = false }
          )
          .hardsetSheet()
        }
      }
      .hardsetSheet()
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
        .hardsetSheet()
      }
    }
    // The workout's gym, settable after Start. Machines belong to a gym, so this is what turns
    // the machine chips on for a workout that began without one.
    .sheet(isPresented: $isChoosingGym, onDismiss: {
      gymError = nil
      clearError(from: .setGym)
    }) {
      NavigationStack {
        GymPickerView(
          gyms: gymOptions,
          selected: coordinator.gymID,
          errorMessage: gymError,
          onSelect: { id in chooseGym(id) },
          onAddGym: { isAddingGym = true }
        )
        .hardsetNavigationTitle("Workout gym")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isChoosingGym = false }
          }
        }
        // Inside the gym sheet, not beside it: two sheets on one anchor and the second never
        // presents.
        .sheet(isPresented: $isAddingGym, onDismiss: { gymNameError = nil }) {
          NameEntrySheet(
            title: "Add a gym",
            prompt: "Name",
            footnote: "Machines are recorded per gym, so this is what groups them.",
            errorMessage: gymNameError,
            onConfirm: { name in addGym(named: name) },
            onCancel: { isAddingGym = false }
          )
          .hardsetSheet()
        }
      }
      .hardsetSheet()
      .task { refreshGyms() }
    }
  }

  private var canPickMachines: Bool { gyms != nil && coordinator.gymID != nil }

  /// The session's own gym, by the name this screen last read, else the caller's. A gym added
  /// from this screen is named here before the caller's list knows it.
  private var displayedGymName: String? {
    guard let id = coordinator.gymID else { return nil }
    return gymOptions.first { $0.id == id }?.name ?? gymName
  }

  /// A workout open longer than any real session: finishing it now would record a length the app
  /// already refuses to show. The same documented limit history uses, not a new threshold, and
  /// the app still never closes the workout itself.
  private var isStale: Bool {
    Date().timeIntervalSince(coordinator.startedAt) > SessionTimeline.plausibleLimit.seconds
  }

  /// Clears what the last operation left behind before the next one, so an old failure is never
  /// relabelled as the new operation's, and a stale finish message never outlives the attempt.
  private func begin(_ operation: SessionOperation) {
    coordinator.clearError()
    finishError = nil
    lastOperation = operation
  }

  /// Drops an error that belongs to a sheet the lifter has just closed.
  private func clearError(from operation: SessionOperation) {
    if lastOperation == operation { coordinator.clearError() }
  }

  private func dismissError() {
    coordinator.clearError()
    finishError = nil
  }

  // MARK: - Logging and rest

  private func logSet(_ slot: SetSlot, inExercise exerciseStateID: UUID) {
    begin(.log)
    recordsDismissed = false
    if coordinator.logSet(slotID: slot.id, inExercise: exerciseStateID) {
      recordsExerciseName = coordinator.exercises.first { $0.id == exerciseStateID }?.exerciseName
    }
  }

  /// Starts a rest the lifter chose, and remembers it for this movement so it is one tap next
  /// time. Remembering their own choice is not a default: a movement with none still asks.
  private func startRest(_ duration: Duration, afterExercise exerciseStateID: UUID) {
    guard let exercise = coordinator.exercises.first(where: { $0.id == exerciseStateID }) else { return }
    restPreferences.remember(duration, for: exercise.exerciseID)
    rememberedRest[exercise.exerciseID] = duration
    let completed = exercise.slots.filter { $0.isLogged && !$0.isWarmup }.count
    let metadata = RestMetadata(exerciseName: exercise.exerciseName, setOrdinal: completed,
      plannedSets: exercise.workingSetCount, machineName: exercise.machineName)
    restMetadata = metadata
    hooks.start(duration, metadata)
  }

  private func endRest() {
    hooks.cancel()
    restMetadata = nil
  }

  private func loadRememberedRest() {
    for exercise in coordinator.exercises where rememberedRest[exercise.exerciseID] == nil {
      if let duration = restPreferences.lastRest(for: exercise.exerciseID) {
        rememberedRest[exercise.exerciseID] = duration
      }
    }
  }

  private var lastRestByCard: [UUID: Duration] {
    var byCard: [UUID: Duration] = [:]
    for exercise in coordinator.exercises {
      if let duration = rememberedRest[exercise.exerciseID] {
        byCard[exercise.id] = duration
      }
    }
    return byCard
  }

  // MARK: - Movements

  private func addMovement(_ entry: CatalogEntry) {
    begin(.addMovement)
    if coordinator.addExercise(entry) {
      isPickerPresented = false
    } else {
      // The picker stays open with the reason, rather than closing as if the movement had been
      // added and leaving the explanation somewhere behind it.
      pickerError = failureMessage(for: .addMovement)
    }
  }

  /// A movement outside the catalogue, named by the lifter and added in one step.
  private func createMovement(named name: String) {
    guard let catalog else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    begin(.addMovement)
    let entry: CatalogEntry
    do {
      // Returns the existing movement for a name that is already there, so a second "Pendulum
      // Squat" is never created by retyping it.
      entry = try catalog.createCustomExercise(named: trimmed)
    } catch CatalogSeederError.blankName {
      pickerError = "Type the movement's name first."
      return
    } catch {
      pickerError = "“\(trimmed)” could not be added. Try again."
      return
    }
    if coordinator.addExercise(entry) {
      isPickerPresented = false
    } else {
      pickerError = failureMessage(for: .addMovement)
    }
  }

  private func refreshPicker() {
    guard let catalog else { return }
    do {
      let entries = try catalog.search(pickerQuery)
      // Recents only before a search: once the lifter types, the matches are the answer.
      let recent = try pickerQuery.isEmpty ? catalog.recent(limit: 8) : []
      pickerEntries = entries
      pickerRecent = recent
      pickerError = nil
    } catch {
      // An unreadable catalogue is not worth blocking a workout over, and it is not an empty
      // one either: the lists are left as they were and the picker says what happened. The
      // lifter can still log what is already on the plan.
      pickerError = "Your movements could not be read. Close this and try again."
    }
  }

  // MARK: - Machines

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
      machineLoadFailed = false
      machineError = nil
    } catch {
      // An unreadable gym must not block logging. The picker offers "Not recorded", which is a
      // true statement about what can be offered, and says the list could not be read rather
      // than presenting an empty one as the lifter's machines.
      machineOptions = ([], [])
      machineLoadFailed = true
      machineError = "This gym’s machines could not be read. You can still log without one."
    }
  }

  private static func option(for record: MachineRecord) -> MachineOption {
    MachineOption(
      id: record.id, displayName: record.displayName, stackIncrementKg: record.stackIncrementKg
    )
  }

  /// `true` when the movement's machine was changed. `name` is passed when the caller has it,
  /// because a machine created a moment ago may not be in the loaded lists yet.
  private func selectMachine(
    _ machineID: MachineID?, forExercise target: UUID, name: String? = nil
  ) -> Bool {
    let resolvedName =
      name
      ?? machineID.flatMap { id in
        (machineOptions.recent + machineOptions.others).first { $0.id == id }?.displayName
      }
    begin(.changeMachine)
    // The coordinator persists before it mutates memory, and reads the increment from the machines
    // table itself, so nothing here needs to know either.
    if coordinator.changeMachine(to: machineID, machineName: resolvedName, inExercise: target) {
      machineError = nil
      return true
    }
    machineError = failureMessage(for: .changeMachine)
    return false
  }

  /// Same argument-passing rule as `addGym`: the name arrives as a parameter, because reading it
  /// back out of state across a presentation boundary produced an empty string.
  private func addMachine(named name: String, forExercise target: UUID) {
    guard let gyms, let gymID = coordinator.gymID, !name.isEmpty else { return }
    let machineID: MachineID
    do {
      machineID = try gyms.createMachine(at: gymID, name: name)
    } catch {
      // Nothing was created, so nothing is selected and the list is unchanged. The name sheet
      // stays up with the name still typed and says so; closing it silently made the tap look
      // like it had worked.
      machineNameError = "“\(name)” could not be saved. Try again."
      return
    }
    isAddingMachine = false
    // Selected immediately: adding one and then having to find it in a list is a second decision
    // for no reason. The stack step is left unknown rather than guessed — an invented increment
    // would licence progression suggestions the equipment cannot honour.
    refreshMachines(forExercise: target)
    if selectMachine(machineID, forExercise: target, name: name) {
      // Dismissed, like choosing an existing machine does. Leaving the picker open after the
      // decision has been made asks the lifter to confirm something twice.
      machineTarget = nil
    }
  }

  private func archiveMachine(_ id: MachineID, forExercise target: UUID) {
    guard let gyms else { return }
    do {
      try gyms.archiveMachine(id)
      refreshMachines(forExercise: target)
    } catch {
      machineError = "That machine could not be archived. Try again."
    }
  }

  // MARK: - Gym

  private func refreshGyms() {
    guard let gyms else { return }
    do {
      gymOptions = try gyms.gyms().map { GymOption(id: $0.id, name: $0.name) }
    } catch {
      gymError = "Your gyms could not be read. Close this and try again."
    }
  }

  private func chooseGym(_ id: GymID?) {
    guard id != coordinator.gymID else {
      isChoosingGym = false
      return
    }
    begin(.setGym)
    if coordinator.setGym(id) {
      gymError = nil
      isChoosingGym = false
    } else {
      gymError = failureMessage(for: .setGym)
    }
  }

  /// Takes the name as an argument, for the reason `addMachine` gives.
  private func addGym(named name: String) {
    guard let gyms, !name.isEmpty else { return }
    let id: GymID
    do {
      id = try gyms.createGym(name: name)
    } catch {
      gymNameError = "“\(name)” could not be saved. Try again."
      return
    }
    isAddingGym = false
    refreshGyms()
    chooseGym(id)
  }

  // MARK: - Messages

  /// A failed write is stated in the user's words, not as an error dump, and as the thing that
  /// failed. A newer failure always wins over an older finish message.
  private var errorMessage: String? {
    if let error = coordinator.lastError {
      return Self.message(for: error, during: failedOperation)
    }
    return finishError
  }

  /// The coordinator's own record of which command failed, when it has one: a write that was not
  /// applied can come from an undo, a move or a removal, not only from logging a set.
  private var failedOperation: SessionOperation {
    switch coordinator.lastFailedCommand {
    case .some(.addExercise): .addMovement
    case .some(.logSet): .log
    case .some(.undoSet): .undoSet
    case .some(.addSet): .addSet
    case .some(.removeSlot): .removeSet
    case .some(.removeExercise): .removeMovement
    case .some(.moveExercise): .moveMovement
    case .some(.changeMachine): .changeMachine
    case .some(.setGym): .setGym
    case .none: lastOperation
    }
  }

  private func failureMessage(for operation: SessionOperation) -> String {
    coordinator.lastError.map { Self.message(for: $0, during: operation) } ?? operation.failure
  }

  private static func message(for error: any Error, during operation: SessionOperation) -> String {
    if let storeError = error as? LoggerStoreError {
      // Exhaustive on purpose, with no `default`: a new failure added to the store must arrive
      // here as a compile error and get its own sentence, not slip into a generic one.
      switch storeError {
      case .incompleteSet:
        return "Enter a weight and reps before logging this set."
      case .sessionNotFound:
        return "This workout could not be found. Your logged sets are safe."
      case .sessionClosed:
        return "This workout has already been finished, so nothing was changed in it. "
          + "Your logged sets are safe."
      case .exerciseNotFound:
        return "That movement is no longer in the catalogue, so nothing was saved for it."
      case .sessionExerciseNotFound:
        return "That movement is no longer part of this workout, so nothing was saved for it."
      case .sessionExerciseMismatch:
        return "That movement's details changed while you were logging, so the set was not "
          + "saved. Try again."
      case .gymNotFound:
        return "That gym could not be found, so nothing was changed."
      case .machineNotFound:
        return "That machine could not be found, so nothing was changed. Choose it again or "
          + "pick another."
      case .machineGymMismatch:
        return "That machine belongs to a different gym, so nothing was changed."
      case .writeNotApplied:
        return operation.failure
      }
    }
    if let coordinatorError = error as? SessionCoordinatorError {
      switch coordinatorError {
      case .slotIsLogged:
        return "That set is already saved. Undo it first to change or remove it."
      case .gymChangeConflictsWithMachines:
        return "Movements in this workout already have machines recorded, so the gym was not "
          + "changed. Set them to “Not recorded” first."
      case .invalidFinishTime:
        return "A workout can only finish after its last set and not in the future, so this one "
          + "is still open. Your logged sets are saved. Check your device's date and time."
      default:
        return operation.failure
      }
    }
    return operation.failure
  }

  // MARK: - Finishing

  /// Finishes now, or at `endedAt` when the lifter chose the last set's time for a workout left
  /// open. The rest timer is stopped only once the workout really is closed: a failed finish
  /// leaves the lifter mid-workout, and mid-rest.
  private func finish(at endedAt: Date? = nil) {
    begin(.finish)
    do {
      if let endedAt {
        try coordinator.finish(at: endedAt)
      } else {
        try coordinator.finish()
      }
      endRest()
      onFinished()
    } catch SessionTimelineError.alreadyFinished {
      // Genuinely closed already — a double tap, or a finish that raced a recovery. Moving on is
      // correct here because the session really is finished.
      endRest()
      onFinished()
    } catch {
      // Anything else and the session is STILL OPEN. Calling onFinished() here was a bug: the root
      // view dropped the coordinator, the user started a new workout, and because openSession()
      // returns only the newest and history shows finished sessions only, the first session's sets
      // became unreachable from every screen. The earlier comment claimed "nothing is lost", which
      // was wrong.
      //
      // `finishedBeforeStart` is the realistic trigger: the device clock moving backwards, from a
      // timezone or NTP correction, makes `now()` precede `startedAt`.
      finishError = Self.message(for: error, during: .finish)
    }
  }

  /// Deletes the open workout and everything logged in it. Reached only through a confirmation.
  private func discard() {
    begin(.discard)
    do {
      try coordinator.discard()
      endRest()
      onFinished()
    } catch {
      // Finished on another device in the meantime: it is closed, and saved, so the screen moves
      // on rather than offering to discard it again.
      if coordinator.isFinished {
        endRest()
        onFinished()
        return
      }
      finishError = Self.message(for: error, during: .discard)
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

/// What the lifter last asked the live session to do, so a failure is described as the thing
/// that failed.
private enum SessionOperation {
  case log
  case addMovement
  case addSet
  case changeMachine
  case undoSet
  case removeSet
  case removeMovement
  case moveMovement
  case setGym
  case finish
  case discard

  /// The sentence for a failure with no more specific explanation. Each says what did not
  /// happen and what is still true, because the lifter's first question is whether anything was
  /// lost.
  var failure: String {
    switch self {
    case .log:
      "That set could not be saved, so it is not logged. Tap the check again to retry."
    case .addMovement:
      "That movement could not be added. Nothing was changed."
    case .addSet:
      "Another set could not be added. Nothing was changed."
    case .changeMachine:
      "The machine could not be changed. The movement keeps its previous machine."
    case .undoSet:
      "That set could not be undone. It is still saved."
    case .removeSet:
      "That row could not be removed."
    case .removeMovement:
      "That movement could not be removed. Its sets are still saved."
    case .moveMovement:
      "The movements could not be reordered. Nothing was changed."
    case .setGym:
      "The workout's gym could not be changed. Nothing was changed."
    case .finish:
      "This workout could not be finished, so it is still open. Your logged sets are saved. "
        + "Check your device's date and time, then try again."
    case .discard:
      "This workout could not be discarded. It is still open, and its sets are saved."
    }
  }
}
