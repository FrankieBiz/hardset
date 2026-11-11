import Foundation
import HardsetCore
import Observation

public nonisolated enum WorkoutRootError: Error, Equatable {
  case notReady
  case workoutAlreadyOpen
}

/// Loads the root once and keeps new-workout creation behind successful recovery.
@MainActor
@Observable
public final class WorkoutRootModel {
  public private(set) var coordinator: SessionCoordinator?
  public private(set) var gymOptions: [GymRecord] = []
  public var selectedGym: GymID?
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
        store: logger, now: now, restAfterSet: restAfterSet, onStartRest: onStartRest
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
