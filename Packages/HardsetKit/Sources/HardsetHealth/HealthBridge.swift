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
  /// Access has been requested for everything Hardset uses. HealthKit never says whether it was
  /// granted -- read permission in particular is private -- so this means "asked", not "allowed".
  public private(set) var connected = false
  /// The most recent body mass this device holds, read from or sent to Apple Health.
  public private(set) var latestBodyMass: DeviceHealthStore.BodyMass?
  private let health = HKHealthStore()
  private let store: DeviceHealthStore
  public init(store: DeviceHealthStore) { self.store = store }

  /// Body masses Hardset will send to Apple Health. Outside this, a value is far more likely a
  /// typo (a dropped decimal point, the wrong unit) than a reading, and Health would keep it.
  public static let plausibleBodyMassKilograms: ClosedRange<Double> = 20...400

  private static var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType(), HKQuantityType(.bodyMass)] }
  private static var readTypes: Set<HKObjectType> { [HKObjectType.workoutType(), HKQuantityType(.bodyMass)] }

  public func connect() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      guard HKHealthStore.isHealthDataAvailable() else { throw HealthBridgeError.unavailable }
      try await health.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
      connected = true
      lastError = nil
      message = "Permissions requested. You control access in Apple Health; read permission is private to you."
    } catch { lastError = error; message = nil }
  }

  /// Restores `connected` from HealthKit, so a lifter who already chose Connect is not asked to
  /// again every time Settings opens. Asking for the status shows no prompt, so authorization is
  /// still requested only from Connect.
  public func refreshConnection() async {
    guard HKHealthStore.isHealthDataAvailable(),
      let status = try? await health.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
    else { return }
    connected = status == .unnecessary
  }

  /// Reads the latest stored body mass for display. A failed read shows nothing rather than a
  /// stale or invented figure.
  public func loadLatestBodyMass() async {
    latestBodyMass = try? await store.latestBodyMass()
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
        DeviceHealthStore.Sample(id: $0.uuid, kind: DeviceHealthStore.bodyMassKind, value: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)),
          unit: "kg", startedAt: $0.startDate, endedAt: $0.endDate)
      } + workouts.map {
        DeviceHealthStore.Sample(id: $0.uuid, kind: "apple.workout.\($0.workoutActivityType.rawValue)", value: 0,
          unit: "", startedAt: $0.startDate, endedAt: $0.endDate)
      }
      try await store.save(samples)
      await loadLatestBodyMass()
      lastError = nil
      message = "Copied \(weights.count) body-mass samples and \(workouts.count) workout summaries from the last year (up to 1,000 each) onto this iPhone, where JSON and SQLite exports include them. Empty results can mean access is denied. No machine identity or sets are inferred."
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
      // Every finished workout is offered each time; the count is what was offered, not what was
      // new to Health, which matches a repeat by its sync identifier and keeps one copy.
      message = "Offered \(written) completed strength workouts to Apple Health. Any it already had keep a single copy, matched by a stable identifier. No calories, heart rate or machine identity were estimated."
    } catch { lastError = error; message = nil }
  }

  /// Saves the entered body mass to Apple Health and this device. Returns whether it was saved,
  /// so the entry can be cleared only once it really was.
  @discardableResult
  public func writeBodyMass(kilograms: Double) async -> Bool {
    guard connected, !isWorking, kilograms.isFinite, Self.plausibleBodyMassKilograms.contains(kilograms) else {
      return false
    }
    isWorking = true
    defer { isWorking = false }
    do {
      let now = Date()
      let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms), start: now, end: now)
      try await health.save(sample)
      try await store.save([.init(id: sample.uuid, kind: DeviceHealthStore.bodyMassKind, value: kilograms, unit: "kg", startedAt: now, endedAt: now)])
      await loadLatestBodyMass()
      lastError = nil
      message = "Saved your entered body mass to Apple Health and this device."
      return true
    } catch {
      lastError = error
      message = nil
      return false
    }
  }
}

private enum HealthBridgeError: Error { case unavailable }
#endif
