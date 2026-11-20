import Foundation
import HardsetCore
import Observation

public nonisolated enum WorkoutRootError: Error, Equatable {
  case notReady
  case workoutAlreadyOpen
  /// "Repeat last workout" was asked before any workout had been finished.
  case nothingToRepeat
}

/// Loads the root once and keeps new-workout creation behind successful recovery.
@MainActor
@Observable
public final class WorkoutRootModel {
  public private(set) var coordinator: SessionCoordinator?
  public private(set) var gymOptions: [GymRecord] = []
  public var selectedGym: GymID?
  /// The lifter's unit, which a recovered workout needs to rebuild its targets: with no machine
  /// step saved, a target adds one plate, and a plate is 2.5 kg or 5 lb. The view keeps it in step
  /// with the stored preference and sets it before `load()`.
  @ObservationIgnored public var weightUnit: WeightUnit = .kilograms
  public private(set) var isReady = false
  public private(set) var isLoading = false
  public private(set) var lastError: (any Error)?

  private let logger: LoggerStore
  private let catalog: CatalogSeeder
  private let gyms: GymStore
  private let now: () -> Date
  private let restAfterSet: Duration?
  private let onStartRest: (Duration, RestMetadata) -> Void
  @ObservationIgnored private var preparation: Task<Void, Never>?

  public init(
    logger: LoggerStore, catalog: CatalogSeeder, gyms: GymStore,
    now: @escaping () -> Date = { Date() }, restAfterSet: Duration? = nil,
    onStartRest: @escaping (Duration, RestMetadata) -> Void = { _, _ in }
  ) {
    self.logger = logger
    self.catalog = catalog
    self.gyms = gyms
    self.now = now
    self.restAfterSet = restAfterSet
    self.onStartRest = onStartRest
  }

  public func load() async {
    guard !isReady, !Task.isCancelled else { return }
    if let preparation {
      await preparation.value
      return
    }
    isLoading = true
    lastError = nil
    let task = Task { await prepare() }
    preparation = task
    await task.value
  }

  /// Initial recovery belongs to the model, so a disappearing appearance cannot
  /// cancel it underneath another caller. Completed input is applied only once.
  private func prepare() async {
    defer {
      preparation = nil
      isLoading = false
    }
    do {
      try await catalog.loadCatalog(now: now())
      let recovered = try await SessionCoordinator.loadResume(
        store: logger, weightUnit: weightUnit, now: now, restAfterSet: restAfterSet,
        onStartRest: onStartRest
      )
      let selection = try await gyms.loadSelection()
      try Task.checkCancellation()
      coordinator = recovered
      apply(selection, learningDefault: true)
      isReady = true
    } catch {
      guard !Task.isCancelled, !(error is CancellationError) else { return }
      lastError = error
    }
  }

  public func startWorkout() throws {
    guard isReady else { throw WorkoutRootError.notReady }
    guard coordinator == nil else { throw WorkoutRootError.workoutAlreadyOpen }
    coordinator = try SessionCoordinator.start(
      store: logger, gymID: selectedGym, plan: [], now: now,
      restAfterSet: restAfterSet, onStartRest: onStartRest
    )
  }

  /// Starts a saved workout in one step: every movement, its machine and its set rows ready.
  ///
  /// Each movement opens on its saved machine only when that machine belongs to the gym the workout
  /// starts at. Otherwise it opens on the machine last used for it here, or on none, so a plan made
  /// at another gym never makes the start fail. The workout's title is the plan's name, and the
  /// session remembers the plan and each rep range itself. A saved rest becomes the movement's
  /// remembered rest, so the existing rest flow starts it after a working set. That happens only
  /// once the workout exists, so a start that fails leaves the lifter's rests as they were.
  public func startWorkout(
    from template: WorkoutTemplate, unit: WeightUnit, rest: RestPreferences
  ) throws {
    guard isReady else { throw WorkoutRootError.notReady }
    guard coordinator == nil else { throw WorkoutRootError.workoutAlreadyOpen }
    let machines = try logger.resolvedMachines(
      for: template.exercises.map { ($0.exerciseID, $0.machineID) }, at: selectedGym)
    let plan = zip(template.exercises, machines).map { exercise, machine in
      PlannedExercise(
        exerciseID: exercise.exerciseID,
        machineID: machine?.id,
        exerciseName: exercise.exerciseName,
        machineName: machine?.displayName,
        machineIncrementKg: machine?.stackIncrementKg,
        plannedSets: exercise.plannedSets,
        repRange: exercise.repRange
      )
    }
    coordinator = try SessionCoordinator.start(
      store: logger, gymID: selectedGym, title: template.name, plan: plan,
      templateID: template.id, weightUnit: unit, now: now,
      restAfterSet: restAfterSet, onStartRest: onStartRest
    )
    for exercise in template.exercises {
      if let seconds = exercise.restSeconds {
        rest.remember(.seconds(seconds), for: exercise.exerciseID)
      }
    }
  }

  /// Starts the last finished workout again: its movements in order, with machines resolved as
  /// `startWorkout(from:unit:rest:)` does, its rep ranges, its title and the saved workout it came
  /// from. Each movement opens with as many sets as were logged, and none for a movement with no
  /// working sets, which falls back to what its history says.
  public func repeatLastWorkout(unit: WeightUnit) throws {
    guard isReady else { throw WorkoutRootError.notReady }
    guard coordinator == nil else { throw WorkoutRootError.workoutAlreadyOpen }
    guard let last = try logger.lastFinishedPlan() else { throw WorkoutRootError.nothingToRepeat }
    let machines = try logger.resolvedMachines(
      for: last.movements.map { ($0.exerciseID, $0.savedMachineID) }, at: selectedGym)
    let plan = zip(last.movements, machines).map { movement, machine in
      PlannedExercise(
        exerciseID: movement.exerciseID,
        machineID: machine?.id,
        exerciseName: movement.exerciseName,
        machineName: machine?.displayName,
        machineIncrementKg: machine?.stackIncrementKg,
        plannedSets: movement.workingSets > 0 ? movement.workingSets : nil,
        repRange: movement.repRange
      )
    }
    coordinator = try SessionCoordinator.start(
      store: logger, gymID: selectedGym, title: last.title, plan: plan,
      templateID: last.templateID, weightUnit: unit, now: now,
      restAfterSet: restAfterSet, onStartRest: onStartRest
    )
  }

  /// Finishing or discarding has already persisted through the coordinator; never drop a live
  /// workout.
  public func clearFinishedWorkout() {
    guard let coordinator, coordinator.isFinished || coordinator.isDiscarded else { return }
    self.coordinator = nil
  }

  /// Re-applies a gym picked on the start screen that no workout has recorded yet, such as one
  /// the view kept across a relaunch after iOS ended the app in the background.
  ///
  /// `nil` re-applies "Not recorded", which is a real pick. A gym that is no longer a saved option
  /// is ignored, so the learned default stands rather than a gym the picker cannot show. Nothing is
  /// stored here: the learned last-used gym (`GymStore.lastUsedGym`) stays the only lasting source.
  /// - Returns: Whether the pick was applied. `false` before the saved gyms have been read.
  @discardableResult
  public func restoreGymPick(_ id: GymID?) -> Bool {
    guard isReady else { return false }
    if let id, !gymOptions.contains(where: { $0.id == id }) { return false }
    selectedGym = id
    return true
  }

  /// Re-reads the options after Settings adds or archives a gym. A pick the lifter already made
  /// stands, including "Not recorded"; only a gym that is no longer offered is dropped. The
  /// learned default is applied by preparation alone, never as a refresh fallback: `nil` here means
  /// the lifter chose "Not recorded", not that no choice exists yet.
  public func refreshGyms() throws {
    apply(try gyms.selection(), learningDefault: false)
  }

  private func apply(_ selection: GymSelection, learningDefault: Bool) {
    gymOptions = selection.options
    if learningDefault, selectedGym == nil { selectedGym = selection.lastUsed }
    if let selectedGym, !gymOptions.contains(where: { $0.id == selectedGym }) {
      self.selectedGym = nil
    }
  }
}
