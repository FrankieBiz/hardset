import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

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
  @State private var pickerQuery = ""
  @State private var pickerEntries: [CatalogEntry] = []
  private let unit: WeightUnit
  private let hooks: RestTimerHooks
  private let catalog: CatalogSeeder?
  private let onFinished: () -> Void

  /// - Parameter catalog: Supplies the picker. Passing `nil` hides the add-movement affordance
  ///   entirely rather than showing a button that opens an empty list.
  public init(
    coordinator: SessionCoordinator,
    unit: WeightUnit,
    hooks: RestTimerHooks = .inert,
    catalog: CatalogSeeder? = nil,
    onFinished: @escaping () -> Void = {}
  ) {
    self._coordinator = State(initialValue: coordinator)
    self.unit = unit
    self.hooks = hooks
    self.catalog = catalog
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
    } catch {
      // Already finished, or finishing before it started. Either way the session is closed and
      // nothing is lost, so the user is moved on rather than trapped on a dead screen.
      onFinished()
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
