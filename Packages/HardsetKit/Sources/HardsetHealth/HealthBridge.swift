#if os(iOS)
import Foundation
import HealthKit
import HardsetCore
import HardsetStore
import Observation

/// Authorization is requested only after the user chooses Connect in Settings.
/// Denied reads look like empty data in HealthKit; the UI never calls that proof of no data.
@MainActor
@Observable
public final class HealthBridge {
  public private(set) var isWorking = false
  public private(set) var message: String?
  public private(set) var lastError: (any Error)?
  public private(set) var connected = false
  private let health = HKHealthStore()
  private let store: DeviceHealthStore
  public init(store: DeviceHealthStore) { self.store = store }

  public func connect() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      guard HKHealthStore.isHealthDataAvailable() else { throw HealthBridgeError.unavailable }
      let bodyMass = HKQuantityType(.bodyMass)
      try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), bodyMass],
        read: [HKObjectType.workoutType(), bodyMass])
      connected = true
      lastError = nil
      message = "Permissions requested. You control access in Apple Health; read permission is private to you."
    } catch { lastError = error; message = nil }
  }

  public func readRecent() async {
    guard connected, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date())!
      let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: nil)
      let weights = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1000).result(for: health)
      let workouts = try await HKSampleQueryDescriptor(predicates: [.workout(predicate)],
        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1000).result(for: health)
      let samples = weights.map {
        DeviceHealthStore.Sample(id: $0.uuid, kind: "apple.bodyMass", value: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)),
          unit: "kg", startedAt: $0.startDate, endedAt: $0.endDate)
      } + workouts.map {
        DeviceHealthStore.Sample(id: $0.uuid, kind: "apple.workout.\($0.workoutActivityType.rawValue)", value: 0,
          unit: "", startedAt: $0.startDate, endedAt: $0.endDate)
      }
      try await store.save(samples)
      lastError = nil
      message = "Read \(weights.count) body-mass samples and \(workouts.count) workout summaries from the last year (up to 1,000 each). Empty results can mean access is denied. Saved on this device only; no machine identity or sets are inferred."
    } catch { lastError = error; message = nil }
  }

  public func writeWorkouts() async {
    guard connected, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let workouts = try await store.workoutsToExport()
      var written = 0
      for workout in workouts {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: nil)
        try await builder.beginCollection(at: workout.start)
        try await builder.addMetadata([
          HKMetadataKeySyncIdentifier: "hardset.workout.\(workout.id)",
          HKMetadataKeySyncVersion: 1,
        ])
        try await builder.endCollection(at: workout.end)
        _ = try await builder.finishWorkout()
        written += 1
      }
      lastError = nil
      message = "Sent \(written) completed strength workouts to Apple Health. Stable sync identifiers prevent retry duplicates. No calories, heart rate or machine identity were estimated."
    } catch { lastError = error; message = nil }
  }

  public func writeBodyMass(kilograms: Double) async {
    guard connected, !isWorking, kilograms.isFinite, kilograms > 0 else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let now = Date()
      let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms), start: now, end: now)
      try await health.save(sample)
      try await store.save([.init(id: sample.uuid, kind: "apple.bodyMass", value: kilograms, unit: "kg", startedAt: now, endedAt: now)])
      lastError = nil
      message = "Saved your entered body mass to Apple Health and this device."
    } catch { lastError = error; message = nil }
  }
}

private enum HealthBridgeError: Error { case unavailable }
#endif
