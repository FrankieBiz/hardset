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

  public init(
    state: @escaping () -> RestTimerState = { .idle },
    start: @escaping (Duration, RestMetadata) -> Void = { _, _ in },
    adjust: @escaping (Duration) -> Void = { _ in },
    pauseOrResume: @escaping () -> Void = {},
    cancel: @escaping () -> Void = {}
  ) {
    self.state = state
    self.start = start
    self.adjust = adjust
    self.pauseOrResume = pauseOrResume
    self.cancel = cancel
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
  @State private var restMetadata: RestMetadata?
  @State private var isPickerPresented = false
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
  private let hooks: RestTimerHooks
  @State private var historyTarget: MachineTarget?
  private let catalog: CatalogSeeder?
  private let gyms: GymStore?
  private let progression: ProgressionStore?
  private let onFinished: () -> Void

  /// - Parameter catalog: Supplies the picker. Passing `nil` hides the add-movement affordance
  ///   entirely rather than showing a button that opens an empty list.
  /// - Parameter gyms: Supplies the machine picker. Passing `nil`, or running a session with no
  ///   gym, hides the machine affordance — the same rule as the catalogue.
  public init(
    coordinator: SessionCoordinator,
    unit: WeightUnit,
    hooks: RestTimerHooks = .inert,
    catalog: CatalogSeeder? = nil,
    gyms: GymStore? = nil,
    progression: ProgressionStore? = nil,
    onFinished: @escaping () -> Void = {}
  ) {
    self._coordinator = State(initialValue: coordinator)
    self.unit = unit
    self.hooks = hooks
    self.catalog = catalog
    self.gyms = gyms
    self.progression = progression
    self.onFinished = onFinished
  }

  public var body: some View {
    @Bindable var bindable = coordinator

    SessionView(
      exercises: $bindable.exercises,
      unit: unit,
      restState: hooks.state(),
      restMetadata: restMetadata,
      errorMessage: errorMessage,
      records: coordinator.lastRecords,
      onLogSet: { exerciseStateID, slot in
        coordinator.logSet(slotID: slot.id, inExercise: exerciseStateID)
      },
      onAdjustRest: hooks.adjust,
      onPauseResumeRest: hooks.pauseOrResume,
      onSkipRest: {
        hooks.cancel()
        restMetadata = nil
      },
      onAddExercise: catalog == nil ? nil : { isPickerPresented = true },
      // Offered only when there is a gym to attach equipment to. Machines belong to a gym, so
      // without one there is nothing honest to put in the list.
      onSelectMachine: canPickMachines ? { machineTarget = MachineTarget(id: $0) } : nil,
      onShowHistory: progression == nil ? nil : { historyTarget = MachineTarget(id: $0) },
      onFinish: finish
    )
    .sheet(isPresented: $isPickerPresented) {
      NavigationStack {
        ExercisePickerView(query: $pickerQuery, entries: pickerEntries) { entry in
          coordinator.addExercise(entry)
          isPickerPresented = false
          pickerQuery = ""
        }
        .navigationTitle("Add movement")
      }
      // Searching hits the database, so it happens here rather than inside the picker, which
      // stays free of storage. The query is re-run on change instead of filtering in memory so a
      // user-created movement shows up without reopening the sheet.
      .task(id: pickerQuery) { refreshPicker() }
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
          onAddMachine: { isAddingMachine = true }
        )
        .navigationTitle("Machine")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { machineTarget = nil }
          }
        }
        // Named on the spot rather than in a setup flow, because the lifter is standing at the
        // machine right now and will not be later.
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

  private func selectMachine(_ machineID: MachineID?, forExercise target: UUID) {
    let name =
      machineID.flatMap { id in
        (machineOptions.recent + machineOptions.others).first { $0.id == id }?.displayName
      }
    // The coordinator persists before it mutates memory, and reads the increment from the machines
    // table itself, so nothing here needs to know either.
    _ = coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
  }

  /// Same argument-passing rule as `addGym`: the name arrives as a parameter, because reading it
  /// back out of state across a presentation boundary produced an empty string.
  private func addMachine(named name: String, forExercise target: UUID) {
    guard let gyms, let gymID = coordinator.gymID, !name.isEmpty else { return }
    do {
      let machineID = try gyms.createMachine(at: gymID, name: name)
      // Selected immediately: adding one and then having to find it in a list is a second decision
      // for no reason. The stack step is left unknown rather than guessed — an invented increment
      // would licence progression suggestions the equipment cannot honour.
      refreshMachines(forExercise: target)
      _ = coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
    } catch {
      // Nothing was created, so nothing is selected and the list is unchanged. Silent because the
      // user's next tap is the retry, and a modal error over a modal picker is worse than none.
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
      }
    }
    return "That set could not be saved. It has not been logged — tap to try again."
  }

  private func finish() {
    hooks.cancel()
    restMetadata = nil
    do {
      try coordinator.finish()
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
