#if os(iOS)

  import Foundation
  import HardsetCore
  import HealthKit

  /// The Apple Health seam: one strength-training workout with its start and end, and nothing
  /// else: no energy burned, no ground covered and no heart rate is ever added (spec 4.4,
  /// `DECISIONS.md` §24).
  ///
  /// iOS only: `HKWorkoutBuilder` is "macOS –", so on macOS this module is empty, and the feature
  /// layer, which builds there too, takes these functions as closures (`HealthExportHooks`).
  ///
  /// As with AlarmKit's configuration (`DECISIONS.md` §3), every HealthKit object here is created
  /// and consumed inside one `nonisolated` function and never crosses an isolation boundary.
  /// `HKWorkoutConfiguration` and the metadata dictionary are not `Sendable`. `HKHealthStore` and
  /// `HKWorkoutBuilder` are documented as `Sendable`, but nothing here depends on it: a store is
  /// made per call rather than kept in a static, which would compile only if the SDK agrees.
  /// Apple says one store is enough, not that a second is wrong, and these calls are rare.
  public enum HealthWorkoutWriter {
    public nonisolated static func isAvailable() -> Bool {
      HKHealthStore.isHealthDataAvailable()
    }

    /// Asks to save workouts and to read nothing. True when saving is allowed. Sharing status is
    /// the one Health does report (`authorizationStatus(for:)`), so this is not a guess.
    public nonisolated static func requestAccess() async throws -> Bool {
      let store = HKHealthStore()
      let workouts = HKObjectType.workoutType()
      try await store.requestAuthorization(toShare: [workouts], read: [])
      return store.authorizationStatus(for: workouts) == .sharingAuthorized
    }

    /// Saves one workout and returns the id Health gave it.
    ///
    /// Nil is not a failure: `finishWorkout()` "returns nil if finishing the workout succeeded but
    /// the workout sample is not available because the device is locked". Health then has the
    /// workout, and only its id is unknown.
    public nonisolated static func save(_ plan: HealthWorkoutPlan) async throws -> UUID? {
      let store = HKHealthStore()
      let configuration = HKWorkoutConfiguration()
      switch plan.activity {
      case .traditionalStrengthTraining: configuration.activityType = .traditionalStrengthTraining
      }
      let builder = HKWorkoutBuilder(
        healthStore: store, configuration: configuration, device: .local())
      do {
        try await builder.beginCollection(at: plan.start)
        try await builder.addMetadata([HKMetadataKeyExternalUUID: plan.externalID])
        try await builder.endCollection(at: plan.end)
      } catch {
        // Nothing was finished, so nothing reached Health; the builder is ended without saving.
        builder.discardWorkout()
        throw error
      }
      let workout = try await builder.finishWorkout()
      return workout?.uuid
    }
  }

#endif
