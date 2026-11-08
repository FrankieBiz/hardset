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
      apply(selection)
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

  /// Finishing has already persisted through the coordinator; never discard a live workout.
  public func clearFinishedWorkout() {
    guard coordinator?.isFinished == true else { return }
    coordinator = nil
  }

  public func refreshGyms() throws {
    apply(try gyms.selection())
  }

  private func apply(_ selection: GymSelection) {
    gymOptions = selection.options
    if selectedGym == nil { selectedGym = selection.lastUsed }
    if let selectedGym, !gymOptions.contains(where: { $0.id == selectedGym }) {
      self.selectedGym = nil
    }
  }
}
