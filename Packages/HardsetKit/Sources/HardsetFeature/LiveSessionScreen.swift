import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The one sheet this screen presents at a time, so which of them is up is a single value rather
/// than four flags that could each be true at once, and the screen carries one `sheet`
/// presentation instead of four on the same view.
///
/// `nonisolated` so its computed `id` satisfies `Identifiable` without isolated-conformance
/// inference, as `ReceiptSelection` does. The payloads are bare identifiers, so the enum is a plain
/// value the sheet's content looks the live state up from.
private nonisolated enum SessionSheet: Identifiable, Hashable {
  /// The movement picker.
  case addMovement
  /// The machine picker for the exercise with this id.
  case machine(UUID)
  /// The load history for the exercise with this id.
  case history(UUID)
  /// The workout's gym picker.
  case gym

  var id: SessionSheet { self }
}

/// What the machine picker presents over itself. It is its own value because the picker is a sheet,
/// and a sheet that presents another must do so from its own content, on one presentation.
private nonisolated enum MachineSubsheet: Identifiable, Hashable {
  /// The stack-step editor for this machine.
  case loadStep(MachineID)
  /// The name entry for a machine the gym does not have yet.
  case addMachine

  var id: MachineSubsheet { self }
}

/// The name typed for a movement the picker does not list, so `sheet(item:)` has something
/// `Identifiable` to present.
private nonisolated struct NewMovementName: Identifiable {
  let name: String
  var id: String { name }
}

/// The live workout, wired.
///
/// Owns the `SessionCoordinator` and binds it to `SessionView`. Every rule that matters is enforced
/// a layer down — the coordinator marks a row logged only after the write succeeds, decides which
/// rest starts and ends it when the workout closes, and `SetEntryDraft.isLoggable` gates the
/// control — so this type is deliberately thin, and contains no logic worth testing on its own.
@MainActor
public struct LiveSessionScreen: View {
  @State private var coordinator: SessionCoordinator
  @State private var machineSubsheet: MachineSubsheet?
  /// The sheet that is up, or `nil`. The only presentation state this screen holds for its own
  /// sheets; what each sheet reads and the errors it shows are the properties below.
  @State private var presented: SessionSheet?
  /// Why finishing or discarding failed while the session is still open, so the user is told
  /// rather than silently returned to a start screen while their workout is stranded. Cleared by
  /// the next operation, so it can never stand in for a later, different failure.
  @State private var finishError: String?
  /// What the lifter last asked for, so a failure is described as the thing that failed: a
  /// movement that could not be added is not "That set could not be saved".
  @State private var lastOperation: SessionOperation = .log
  /// Counts failed commands. The session's error haptic and announcement follow this rather than
  /// the message, because a retry that fails the same way leaves the message unchanged.
  @State private var failedCommands = 0
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  @State private var pickerRecent: [CatalogEntry] = []
  @State private var pickerError: String?
  /// The name typed in the picker for a movement that is not on the list. Non-nil presents the
  /// editor that asks which body part it trains, in place of adding it untagged on the spot.
  @State private var newMovement: NewMovementName?
  @State private var newMovementError: String?
  @State private var machineOptions: (recent: [MachineOption], others: [MachineOption]) = ([], [])
  @State private var machineError: String?
  /// The gym's machines could not be read, so adding one would risk a duplicate of a machine the
  /// lifter already has.
  @State private var machineLoadFailed = false
  @State private var machineNameError: String?
  @State private var isAddingGym = false
  @State private var gymOptions: [GymOption] = []
  @State private var gymError: String?
  @State private var gymNameError: String?
  /// The set whose records the lifter dismissed, so the card stays gone for those records and comes
  /// back for the next set that earns one.
  @State private var dismissedRecordsSetID: SetID?
  private let unit: WeightUnit
  private let hooks: RestTimerHooks
  private let catalog: CatalogSeeder?
  private let gyms: GymStore?
  private let progression: ProgressionStore?
  private let gymName: String?
  /// What the first-launch tour asks of this screen: the machine picker, open on the first
  /// movement. Asks for nothing in the daily app.
  @Environment(\.tourStaging) private var staging
  private let onShowSettings: (() -> Void)?
  private let onFinished: () -> Void

  /// - Parameter catalog: Supplies the picker. Passing `nil` hides the add-movement affordance
  ///   entirely rather than showing a button that opens an empty list.
  /// - Parameter gyms: Supplies the machine picker and the workout's gym. Passing `nil` hides
  ///   both; a session with no gym hides the machine chips until one is set.
  /// - Parameter gymName: Shown in the screen's header, so the lifter can see which gym's
  ///   machines the chips are offering. `nil` reads "No gym recorded".
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
      restMetadata: hooks.metadata() ?? coordinator.restMetadata,
      errorMessage: errorMessage,
      errorEvent: failedCommands,
      // Without a working alarm nothing else marks the end of a rest, so the screen does.
      restEndsSilently: hooks.issue() != nil,
      records: recordsAreDismissed ? [] : coordinator.lastRecords,
      recordsExerciseName: coordinator.lastRecordsExerciseName,
      lastRest: coordinator.lastRestByCard,
      restExerciseID: coordinator.restExerciseID,
      onChooseNextRest: { exerciseStateID, duration in
        coordinator.rememberRest(duration, forExercise: exerciseStateID)
      },
      onLogSet: { exerciseStateID, slot in
        logSet(slot, inExercise: exerciseStateID)
      },
      onStartRest: { exerciseStateID, duration in
        coordinator.startRest(duration, afterExercise: exerciseStateID)
      },
      onAdjustRest: hooks.adjust,
      onPauseResumeRest: hooks.pauseOrResume,
      onSkipRest: { coordinator.endRest() },
      onAddExercise: catalog == nil ? nil : { presented = .addMovement },
      // Offered only when there is a gym to attach equipment to. Machines belong to a gym, so
      // without one there is nothing honest to put in the list.
      onSelectMachine: canPickMachines ? { presented = .machine($0) } : nil,
      onShowHistory: progression == nil ? nil : { presented = .history($0) },
      onShowSettings: onShowSettings,
      onChangeGym: gyms == nil ? nil : { presented = .gym },
      onUndoSet: { exerciseStateID, slot in
        begin(.undoSet)
        return noteOutcome(coordinator.undoSet(slotID: slot.id, inExercise: exerciseStateID))
      },
      onRemoveSet: { exerciseStateID, slot in
        begin(.removeSet)
        noteOutcome(coordinator.removeSlot(slotID: slot.id, inExercise: exerciseStateID))
      },
      onRemoveExercise: { exerciseStateID in
        begin(.removeMovement)
        noteOutcome(coordinator.removeExercise(exerciseStateID))
      },
      onMoveExercise: { exerciseStateID, offset in
        begin(.moveMovement)
        noteOutcome(coordinator.moveExercise(exerciseStateID, by: offset))
      },
      onDismissError: dismissError,
      onDismissRecords: { dismissedRecordsSetID = coordinator.lastRecordsSetID },
      onFinish: { finish() },
      onFinishAt: coordinator.lastLoggedAt == nil ? nil : { finish(at: $0) },
      onDiscard: discard
    )
    // The tour opens the machine picker on the first movement, and closes it when its step ends.
    .onChange(of: staging.opensMachinePicker, initial: true) { _, opens in
      if opens {
        guard canPickMachines, let first = coordinator.exercises.first else { return }
        presented = .machine(first.id)
      } else if case .machine = presented {
        presented = nil
      }
    }
    // One presentation for every sheet this screen opens. The four of them sat side by side on this
    // view, each driven by its own flag; now which one is up is `presented`, so two can never be
    // requested at once and SwiftUI is never asked to choose between sibling modifiers.
    .stagedSheet(item: $presented, onDismiss: sheetDismissed) { sheet in
      switch sheet {
      case .addMovement: addMovementSheet
      case .machine(let target): machineSheet(forExercise: target)
      case .history(let target): historySheet(forExercise: target)
      case .gym: gymSheet
      }
    }
  }

  /// Clears what the sheet that just closed left behind, so a failure belongs to the visit it
  /// happened in and reopening starts clean. One callback serves every sheet, so each reset is safe
  /// to run when another sheet closed: only one sheet is ever up, and each reset touches only state
  /// that sheet reads.
  private func sheetDismissed() {
    // A swipe-down dismissal used to leave the last search behind for the next visit.
    pickerQuery = ""
    pickerError = nil
    clearError(from: .addMovement)
    machineError = nil
    machineLoadFailed = false
    clearError(from: .changeMachine)
    gymError = nil
    clearError(from: .setGym)
  }

  // MARK: - Sheets

  private var addMovementSheet: some View {
    NavigationStack {
      ExercisePickerView(
        query: $pickerQuery,
        entries: pickerEntries,
        recent: pickerRecent,
        errorMessage: pickerError,
        onCancel: { presented = nil },
        onCreate: catalog == nil ? nil : { name in newMovement = NewMovementName(name: name) },
        onSelect: { entry in addMovement(entry) }
      )
      .hardsetNavigationTitle("Add movement")
      // Asks which body part the movement trains before saving it, so a movement the lifter makes
      // mid-workout counts toward a muscle from its first set, and there is one way to make one.
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
    // Searching hits the database, so it happens here rather than inside the picker, which
    // stays free of storage. The query is re-run on change instead of filtering in memory so a
    // user-created movement shows up without reopening the sheet.
    .task(id: pickerQuery) { refreshPicker() }
  }

  private func machineSheet(forExercise target: UUID) -> some View {
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
            presented = nil
          }
        },
        // Not offered while the gym's machines cannot be read: a lifter who cannot see the
        // machines they have would add a second one of each.
        onAddMachine: machineLoadFailed ? nil : { machineSubsheet = .addMachine },
        onEditIncrement: { id in machineSubsheet = .loadStep(id) },
        onArchive: { id in archiveMachine(id, forExercise: target) },
        onCancel: { presented = nil }
      )
      .hardsetNavigationTitle("Machine")
      // Inside the machine sheet, not beside it, and one presentation for both of its own sheets.
      .sheet(item: $machineSubsheet, onDismiss: { machineNameError = nil }) { subsheet in
        switch subsheet {
        case .loadStep(let id):
          if let machine = (machineOptions.recent + machineOptions.others).first(where: { $0.id == id }) {
            LoadStepSheet(machineName: machine.displayName, incrementKg: machine.stackIncrementKg, unit: unit,
              onSave: { increment in
                guard let gyms, let gymID = coordinator.gymID else { return false }
                do {
                  try gyms.setStackIncrement(increment, for: machine.id, at: gymID)
                  for index in coordinator.exercises.indices where coordinator.exercises[index].machineID == machine.id {
                    coordinator.exercises[index].updateMachineIncrement(increment)
                  }
                  refreshMachines(forExercise: target)
                  machineSubsheet = nil
                  return true
                } catch { return false }
              }, onCancel: { machineSubsheet = nil })
            .hardsetSheet()
          }
        case .addMachine:
          // Named on the spot rather than in a setup flow, because the lifter is standing at the
          // machine right now and will not be later.
          NameEntrySheet(
            title: "Add a machine",
            prompt: "Name or brand",
            footnote:
              "Whatever you'd recognise it by — \"Hammer Strength\" or \"the one by the window\".",
            errorMessage: machineNameError,
            onConfirm: { name in
              addMachine(named: name, forExercise: target)
            },
            onCancel: { machineSubsheet = nil }
          )
          .hardsetSheet()
        }
      }
    }
    .hardsetSheet()
    // Reloaded per presentation: what the lifter used most recently changes as they log.
    .task(id: target) { refreshMachines(forExercise: target) }
  }

  @ViewBuilder
  private func historySheet(forExercise target: UUID) -> some View {
    if let progression, let exercise = coordinator.exercises.first(where: { $0.id == target }) {
      NavigationStack {
        ExerciseProgressScreen(
          store: progression,
          exerciseID: exercise.exerciseID,
          exerciseName: exercise.exerciseName,
          unit: unit
        )
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { presented = nil }
          }
        }
      }
      .hardsetSheet()
    }
  }

  /// The workout's gym, settable after Start. Machines belong to a gym, so this is what turns
  /// the machine chips on for a workout that began without one.
  private var gymSheet: some View {
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
          Button("Cancel") { presented = nil }
        }
      }
      // Inside the gym sheet, not beside it: a sheet presented from the anchor that is already
      // presenting one never appears.
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

  /// Counts a command that did not succeed, and passes its result through.
  @discardableResult
  private func noteOutcome(_ succeeded: Bool) -> Bool {
    if !succeeded { failedCommands += 1 }
    return succeeded
  }

  // MARK: - Logging

  /// The record card stays dismissed for the records the lifter dismissed. A later set that earns
  /// records has a set of its own, so the card returns for it.
  private var recordsAreDismissed: Bool {
    coordinator.lastRecordsSetID != nil && coordinator.lastRecordsSetID == dismissedRecordsSetID
  }

  /// Logging is the coordinator's: it writes the set, claims any records, and starts the rest the
  /// lifter chose for the movement, all only once the write has succeeded.
  private func logSet(_ slot: SetSlot, inExercise exerciseStateID: UUID) {
    begin(.log)
    noteOutcome(coordinator.logSet(slotID: slot.id, inExercise: exerciseStateID))
  }

  // MARK: - Movements

  private func addMovement(_ entry: CatalogEntry) {
    begin(.addMovement)
    if noteOutcome(coordinator.addExercise(entry)) {
      presented = nil
    } else {
      // The picker stays open with the reason, rather than closing as if the movement had been
      // added and leaving the explanation somewhere behind it.
      pickerError = failureMessage(for: .addMovement)
    }
  }

  /// A movement outside the catalogue, named and tagged by the lifter and added in one step.
  ///
  /// A failure keeps the editor up with everything typed and says why, so trying again is one tap.
  private func createMovement(named name: String, attribution: CustomAttribution) {
    guard let catalog else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    begin(.addMovement)
    let entry: CatalogEntry
    do {
      // Refuses a name that is already there, so a second "Pendulum Squat" is never created by
      // retyping it. Handing back the existing one would throw away the muscles just chosen.
      entry = try catalog.createNewCustomExercise(named: trimmed, attribution: attribution)
    } catch CatalogSeederError.blankName {
      newMovementError = "Type the movement's name first."
      return
    } catch CatalogSeederError.duplicateName {
      newMovementError = MovementEditorDraft.nameTakenMessage(trimmed)
      return
    } catch {
      newMovementError = "“\(trimmed)” could not be added. Try again."
      noteOutcome(false)
      return
    }
    if noteOutcome(coordinator.addExercise(entry)) {
      newMovement = nil
      presented = nil
    } else {
      newMovementError = failureMessage(for: .addMovement)
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
    if noteOutcome(
      coordinator.changeMachine(to: machineID, machineName: resolvedName, inExercise: target)
    ) {
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
      noteOutcome(false)
      return
    }
    machineSubsheet = nil
    // Selected immediately: adding one and then having to find it in a list is a second decision
    // for no reason. The stack step is left unknown rather than guessed — an invented increment
    // would licence progression suggestions the equipment cannot honour.
    refreshMachines(forExercise: target)
    if selectMachine(machineID, forExercise: target, name: name) {
      // Dismissed, like choosing an existing machine does. Leaving the picker open after the
      // decision has been made asks the lifter to confirm something twice.
      presented = nil
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
      presented = nil
      return
    }
    begin(.setGym)
    if noteOutcome(coordinator.setGym(id)) {
      gymError = nil
      presented = nil
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
    // The clock is blamed only when the clock is the cause. A full disk used to be reported as a
    // date-and-time problem, sending the lifter to the wrong setting.
    if let timelineError = error as? SessionTimelineError, timelineError == .finishedBeforeStart {
      return "This workout could not be finished, because your device's clock reads earlier than "
        + "its start. It is still open, and your logged sets are saved. Check your device's date "
        + "and time, then try again."
    }
    return operation.failure
  }

  // MARK: - Finishing

  /// Finishes now, or at `endedAt` when the lifter chose the last set's time for a workout left
  /// open. The coordinator stops the rest timer once the workout really is closed: a failed finish
  /// leaves the lifter mid-workout, and mid-rest.
  private func finish(at endedAt: Date? = nil) {
    begin(.finish)
    do {
      if let endedAt {
        try coordinator.finish(at: endedAt)
      } else {
        try coordinator.finish()
      }
      onFinished()
    } catch SessionTimelineError.alreadyFinished {
      // Genuinely closed already — a double tap, or a finish that raced a recovery. Moving on is
      // correct here because the session really is finished.
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
      noteOutcome(false)
    }
  }

  /// Deletes the open workout and everything logged in it. Reached only through a confirmation.
  private func discard() {
    begin(.discard)
    do {
      try coordinator.discard()
      onFinished()
    } catch {
      // Finished on another device in the meantime: it is closed, and saved, so the screen moves
      // on rather than offering to discard it again.
      if coordinator.isFinished {
        onFinished()
        return
      }
      finishError = Self.message(for: error, during: .discard)
      noteOutcome(false)
    }
  }
}

extension SessionCoordinator {
  /// Builds a coordinator whose rest requests, and their end, are routed to `hooks`.
  ///
  /// A convenience with a purpose: the `onStartRest` and `onCancelRest` closures have to be supplied
  /// at construction, before the view exists, which is easy to forget and silently produces a
  /// session that never rests, or one whose rest outlives it.
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
      onStartRest: { duration, metadata in hooks.start(duration, metadata) },
      onCancelRest: { hooks.cancel() }
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
        + "Try again."
    case .discard:
      "This workout could not be discarded. It is still open, and its sets are saved."
    }
  }
}
