import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

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
  /// What the running rest is for, as the timer was told. Nil for a rest no set started (Siri, a
  /// control), so the bar never captions such a rest with an older set.
  public var metadata: () -> RestMetadata?
  public var start: (Duration, RestMetadata) -> Void
  public var adjust: (Duration) -> Void
  public var pauseOrResume: () -> Void
  public var cancel: () -> Void
  /// Whether the lifter has turned alarms off for Hardset. A choice, not a failure: the countdown
  /// still runs, so the screen says what it means rather than reporting an error.
  public var authorizationDenied: () -> Bool
  /// The timer's latest failure, already in the lifter's words. The app maps the error, so this
  /// target never sees AlarmKit's error types.
  public var lastErrorMessage: () -> String?

  public init(
    state: @escaping () -> RestTimerState = { .idle },
    metadata: @escaping () -> RestMetadata? = { nil },
    start: @escaping (Duration, RestMetadata) -> Void = { _, _ in },
    adjust: @escaping (Duration) -> Void = { _ in },
    pauseOrResume: @escaping () -> Void = {},
    cancel: @escaping () -> Void = {},
    authorizationDenied: @escaping () -> Bool = { false },
    lastErrorMessage: @escaping () -> String? = { nil }
  ) {
    self.state = state
    self.metadata = metadata
    self.start = start
    self.adjust = adjust
    self.pauseOrResume = pauseOrResume
    self.cancel = cancel
    self.authorizationDenied = authorizationDenied
    self.lastErrorMessage = lastErrorMessage
  }

  public static var inert: RestTimerHooks { RestTimerHooks() }
}

/// How a live workout ended, reported only after the write that ended it succeeded.
///
/// The root needs to know which: a finished workout has a summary to read back from the database
/// by its id, and a discarded one no longer exists, so there is nothing to show for it.
public enum SessionExit: Hashable, Sendable {
  case finished(SessionID)
  case discarded
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
  @State private var isPickerPresented = false
  /// Why finishing failed, set while the session is still open, so the user is told rather than
  /// silently returned to a start screen while their workout is stranded. The error rather than a
  /// flag, so only a clock problem is told to check the clock.
  @State private var finishError: (any Error)?
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  /// The movements logged most recently, newest first and each once (the store dedupes). Read when
  /// the picker opens, never in `body`.
  @State private var recentEntries: [CatalogEntry] = []
  /// What Finish asks when the rows say it must (`FinishFlow`). One flag per dialog rather than a
  /// binding derived from one optional decision: clearing that as the dialog closed would change
  /// the count in its title while it animated away. The count stays until the next Finish.
  @State private var isConfirmingUnlogged = false
  @State private var unloggedCount = 0
  @State private var isConfirmingDiscard = false
  /// The action the coordinator's `lastError` belongs to, so a failed edit is not described as a
  /// failed log. Set by `attempt(_:_:)`, around every coordinator write.
  @State private var lastAction: FailureCopy.Action = .logSet
  /// The exercise whose machine is being chosen. Non-nil presents the picker.
  ///
  /// Wrapped rather than a bare `UUID` because `sheet(item:)` needs `Identifiable`, and retroactively
  /// conforming a Foundation type to get it would leak that conformance to every importer.
  @State private var machineTarget: MachineTarget?
  @State private var machineOptions: (recent: [MachineOption], others: [MachineOption]) = ([], [])
  @State private var isAddingMachine = false
  /// Why the last machine could not be added, in the user's words. Shown in the picker, which is
  /// where the lifter is looking when it fails.
  @State private var machineError: String?
  @Environment(\.openURL) private var openURL
  private let unit: WeightUnit
  private let hooks: RestTimerHooks
  @State private var historyTarget: MachineTarget?
  private let catalog: CatalogSeeder?
  private let gyms: GymStore?
  private let progression: ProgressionStore?
  private let shortcuts: WorkoutShortcutsStore?
  private let onFinished: (SessionExit) -> Void

  /// - Parameter catalog: Supplies the picker. Passing `nil` hides the add-movement affordance
  ///   entirely rather than showing a button that opens an empty list.
  /// - Parameter gyms: Supplies the machine picker. Passing `nil`, or running a session with no
  ///   gym, hides the machine affordance — the same rule as the catalogue.
  /// - Parameter shortcuts: Supplies the picker's Recent section. Passing `nil` leaves it out; the
  ///   full list is unaffected.
  /// - Parameter onFinished: Called once the session has been finished or discarded, after the
  ///   write. Never called while the session is still open.
  public init(
    coordinator: SessionCoordinator,
    unit: WeightUnit,
    hooks: RestTimerHooks = .inert,
    catalog: CatalogSeeder? = nil,
    gyms: GymStore? = nil,
    progression: ProgressionStore? = nil,
    shortcuts: WorkoutShortcutsStore? = nil,
    onFinished: @escaping (SessionExit) -> Void = { _ in }
  ) {
    self._coordinator = State(initialValue: coordinator)
    self.unit = unit
    self.hooks = hooks
    self.catalog = catalog
    self.gyms = gyms
    self.progression = progression
    self.shortcuts = shortcuts
    self.onFinished = onFinished
  }

  public var body: some View {
    @Bindable var bindable = coordinator

    SessionView(
      exercises: $bindable.exercises,
      unit: unit,
      restState: hooks.state(),
      // The timer's own record of what its rest is for, so the bar names the set that actually
      // started it, and names none for a rest started from Siri or a control.
      restMetadata: hooks.metadata(),
      errorMessage: errorMessage,
      onLogSet: { exerciseStateID, slot in
        attempt(.logSet) { coordinator.logSet(slotID: slot.id, inExercise: exerciseStateID) }
      },
      onAdjustRest: hooks.adjust,
      onPauseResumeRest: hooks.pauseOrResume,
      onSkipRest: {
        hooks.cancel()
        coordinator.endRest()
      },
      onAddExercise: addExerciseAction,
      onSelectMachine: selectMachineAction,
      onShowHistory: showHistoryAction,
      restChoices: coordinator.restChoices,
      // The view reports (state id, rest); the coordinator takes them the other way round.
      onChooseRest: { stateID, rest in coordinator.setRestChoice(rest, forExercise: stateID) },
      // No choice means nothing to start, which the chip already reflects by not offering it.
      onStartRest: { stateID in _ = coordinator.startRest(forExercise: stateID) },
      // Trophies and pulses are the coordinator's, set only after the write they describe.
      recordsBySlot: coordinator.recordsBySlot,
      feedback: coordinator.feedback,
      pendingUndo: pendingUndo,
      onEditSet: { exerciseStateID, slotID, draft in
        attempt(.editSet) {
          coordinator.editSet(slotID: slotID, inExercise: exerciseStateID, to: draft)
        }
      },
      onDeleteSet: { exerciseStateID, slotID in
        attempt(.deleteSet) { coordinator.deleteSet(slotID: slotID, inExercise: exerciseStateID) }
      },
      onUndoDelete: {
        attempt(.undoDelete) {
          // Too late is not a failure: the coordinator drops the deletion and reports nothing, so
          // an earlier failure keeps its own copy. A failed Undo keeps the deletion for a retry.
          coordinator.undoDelete() || coordinator.undoableDeletion == nil
        }
      },
      // The coordinator holds the real window and refuses an Undo after it either way; this only
      // tells it the bar has gone.
      onExpireUndo: { coordinator.expireUndo() }
      // Finish is the toolbar's prominent action, so the list is given no Finish of its own.
    )
    // At the bottom edge, beneath anything `SessionView` insets there itself. On iOS the rest bar
    // is the tab accessory, so this sits directly above it (and under the keypad when the keypad is
    // open); on macOS, where `SessionView` draws the bar, it sits under the bar.
    .safeAreaInset(edge: .bottom, spacing: 0) { restNotice }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        // `ButtonRole.confirm` is iOS 26 and macOS 26, and this target also builds for macOS 15.
        if #available(macOS 26.0, *) {
          Button("Finish", role: .confirm, action: requestFinish)
        } else {
          Button("Finish", action: requestFinish)
        }
      }
    }
    // Two dialogs rather than one that switches, so each keeps a fixed shape: only the empty
    // workout has a message.
    .confirmationDialog(
      FinishFlow.unloggedTitle(count: unloggedCount),
      isPresented: $isConfirmingUnlogged,
      titleVisibility: .visible
    ) {
      Button("Finish workout", action: finish)
      Button("Keep logging", role: .cancel) {}
    }
    .confirmationDialog(
      FinishFlow.discardTitle,
      isPresented: $isConfirmingDiscard,
      titleVisibility: .visible
    ) {
      Button("Discard workout", role: .destructive, action: discard)
      Button("Keep logging", role: .cancel) {}
    } message: {
      Text(FinishFlow.discardMessage)
    }
    .sheet(isPresented: $isPickerPresented) {
      NavigationStack {
        ExercisePickerView(
          query: $pickerQuery,
          entries: pickerEntries,
          recent: recentEntries,
          onCancel: {
            isPickerPresented = false
            pickerQuery = ""
          }
        ) { entry in
          attempt(.addMovement) { coordinator.addExercise(entry) }
          isPickerPresented = false
          pickerQuery = ""
        }
        .navigationTitle("Add movement")
      }
      // Searching hits the database, so it happens here rather than inside the picker, which
      // stays free of storage. The query is re-run on change instead of filtering in memory so a
      // user-created movement shows up without reopening the sheet.
      .task(id: pickerQuery) { refreshPicker() }
      // Once per presentation: what was logged most recently changes as the workout goes on.
      .task { refreshRecent() }
    }
    // A failure belongs to the attempt the lifter just made, so it goes when the picker does.
    .sheet(item: $machineTarget, onDismiss: { machineError = nil }) { wrapped in
      let target = wrapped.id
      NavigationStack {
        MachinePickerView(
          recent: machineOptions.recent,
          others: machineOptions.others,
          selected: coordinator.exercises.first { $0.id == target }?.machineID,
          unit: unit,
          onSelect: { machineID in
            selectMachine(machineID, forExercise: target)
            machineTarget = nil
          },
          onAddMachine: { isAddingMachine = true }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { machineErrorFooter }
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

  // The optional actions and the Undo are named here rather than written inline: `SessionView`
  // takes twenty-two arguments, and conditional closures inside that call are what makes the type
  // checker give up on `body`.

  private var addExerciseAction: (() -> Void)? {
    guard catalog != nil else { return nil }
    return { isPickerPresented = true }
  }

  /// Offered only when there is a gym to attach equipment to. Machines belong to a gym, so without
  /// one there is nothing honest to put in the list.
  private var selectMachineAction: ((UUID) -> Void)? {
    guard canPickMachines else { return nil }
    return { machineTarget = MachineTarget(id: $0) }
  }

  private var showHistoryAction: ((UUID) -> Void)? {
    guard progression != nil else { return nil }
    return { historyTarget = MachineTarget(id: $0) }
  }

  /// Keyed by the deleted row's id, which is stable for that deletion: an id made here would be new
  /// on every render, restarting the bar's timer so it never closed.
  private var pendingUndo: PendingUndo? {
    guard let deletion = coordinator.undoableDeletion else { return nil }
    return PendingUndo(id: deletion.slot.id, label: "Set deleted")
  }

  /// Why the rest may not sound, shown only while a rest is running or paused. The timer is the
  /// truth here, not the coordinator's record of the rest it last asked for, which outlives a rest
  /// that ended on its own.
  ///
  /// A refusal and a failure can both be true (alarms off, and the stand-in notification failed),
  /// so each gets its own line rather than one hiding the other.
  @ViewBuilder private var restNotice: some View {
    if hooks.state() != .idle {
      let alarmsOff = hooks.authorizationDenied()
      let failure = hooks.lastErrorMessage()
      if alarmsOff || failure != nil {
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
          if alarmsOff {
            HStack(spacing: Tokens.Spacing.snug) {
              Text("Alarms are off for Hardset, so rest won't sound when the phone is locked.")
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
              settingsButton
            }
          }
          if let failure {
            Text(failure)
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.critical)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.horizontal, Tokens.Spacing.regular)
        .padding(.vertical, Tokens.Spacing.snug)
        .background(Tokens.Color.surface)
      }
    }
  }

  /// Opens Hardset's page in the Settings app, where alarms can be turned back on. UIKit only:
  /// this target also builds for macOS, which has no such URL.
  @ViewBuilder private var settingsButton: some View {
    #if canImport(UIKit)
      if let url = URL(string: UIApplication.openSettingsURLString) {
        Button {
          openURL(url)
        } label: {
          Text("Settings")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.accent)
            .frame(minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    #else
      EmptyView()
    #endif
  }

  /// The machine picker's footer. Empty unless adding a machine just failed.
  @ViewBuilder private var machineErrorFooter: some View {
    if let machineError {
      Text(machineError)
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.critical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Spacing.section)
        .padding(.vertical, Tokens.Spacing.snug)
        .background(Tokens.Color.background)
    }
  }

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
    attempt(.changeMachine) {
      coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
    }
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
      attempt(.changeMachine) {
        coordinator.changeMachine(to: machineID, machineName: name, inExercise: target)
      }
      machineError = nil
      // Dismissed, like choosing an existing machine does. Leaving the picker open after the
      // decision has been made asks the lifter to confirm something twice.
      machineTarget = nil
    } catch {
      // Nothing was created, so nothing is selected and the list is unchanged. Stated in the
      // picker's footer rather than in a modal over a modal, and never as the error itself, which
      // can carry database internals. The picker stays open, so "Add a machine" is the retry.
      machineError = FailureCopy.message(for: error, during: .saveMachine)
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

  /// Loads the picker's Recent section.
  private func refreshRecent() {
    guard let shortcuts else { return }
    do {
      recentEntries = try shortcuts.recentExercises()
    } catch {
      // Recent is a convenience, and the full list below is unaffected, so an unreadable history
      // leaves the section out rather than blocking the picker.
      recentEntries = []
    }
  }

  /// A failed write is stated in the user's words, not as an error dump. The wording lives in
  /// `FailureCopy`, where it is tested; this only says which action failed.
  private var errorMessage: String? {
    if let finishError {
      return FailureCopy.message(for: finishError, during: .finishWorkout)
    }
    // A failed Undo says "Tap Undo to try again", which is true only while the deletion can still
    // be undone. Once its window closes the bar is gone and the set stays deleted, as the lifter
    // first asked, so the instruction would point at a button that no longer exists. The
    // coordinator keeps `lastError` until the next write, so the screen stops showing it here.
    if lastAction == .undoDelete && coordinator.undoableDeletion == nil { return nil }
    return coordinator.lastError.map { FailureCopy.message(for: $0, during: lastAction) }
  }

  /// Runs one coordinator write and, when it fails, records which action the coordinator's
  /// `lastError` now belongs to.
  ///
  /// Labelled after the call rather than before it, so a call that did nothing (logging a row that
  /// is already logged, an Undo after its window) cannot relabel an earlier failure as its own. A
  /// finish failure is retired first: it described an earlier attempt, and left in place it would
  /// stand in front of this one's copy.
  @discardableResult
  private func attempt(_ action: FailureCopy.Action, _ write: () -> Bool) -> Bool {
    finishError = nil
    let succeeded = write()
    if !succeeded { lastAction = action }
    return succeeded
  }

  // MARK: - Finishing

  /// The toolbar's Finish. The coordinator decides from the rows (`FinishFlow`): finish at once,
  /// confirm with the count of sets that will not be saved, or offer Discard when nothing was
  /// logged. An empty workout is never finished into history.
  private func requestFinish() {
    switch coordinator.finishDecision {
    case .finish:
      finish()
    case .confirmUnlogged(let count):
      unloggedCount = count
      isConfirmingUnlogged = true
    case .discardEmpty:
      isConfirmingDiscard = true
    }
  }

  private func finish() {
    hooks.cancel()
    // Ended together with the timer. `coordinator.finish()` also ends it, but only once its write
    // succeeds, and the timer is already gone either way.
    coordinator.endRest()
    do {
      try coordinator.finish()
      onFinished(.finished(coordinator.sessionID))
    } catch SessionTimelineError.alreadyFinished {
      // Genuinely closed already — a double tap, or a finish that raced a recovery. Moving on is
      // correct here because the session really is finished.
      onFinished(.finished(coordinator.sessionID))
    } catch {
      // Anything else and the session is STILL OPEN. Reporting it finished here was a bug: the
      // root view dropped the coordinator, the user started a new workout, and because
      // openSession() returns only the newest and history shows finished sessions only, the first
      // session's sets became unreachable from every screen. The earlier comment claimed "nothing
      // is lost", which was wrong.
      //
      // `finishedBeforeStart` is the realistic trigger: the device clock moving backwards, from a
      // timezone or NTP correction, makes `now()` precede `startedAt`. Kept, so only that case is
      // told to check the clock.
      finishError = error
    }
  }

  /// Deletes a workout with nothing logged. The screen leaves only after the store has deleted it;
  /// a refusal (a set the screen never saw) or a failure keeps the workout open and says why.
  private func discard() {
    if attempt(.discardWorkout, { coordinator.discard() }) {
      hooks.cancel()
      onFinished(.discarded)
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
    restPreferences: any RestPreferenceStore,
    hooks: RestTimerHooks,
    now: @escaping () -> Date = { Date() }
  ) throws -> SessionCoordinator {
    try SessionCoordinator.start(
      store: store,
      gymID: gymID,
      title: title,
      plan: plan,
      now: now,
      restPreferences: restPreferences,
      onStartRest: { duration, metadata in hooks.start(duration, metadata) }
    )
  }
}
