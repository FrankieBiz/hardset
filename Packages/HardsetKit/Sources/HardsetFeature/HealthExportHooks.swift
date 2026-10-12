import Foundation
import HardsetCore

/// Apple Health, as closures the app supplies. HealthKit's workout builder is iOS-only and this
/// target also builds for macOS, so, like `RestTimerHooks`, the feature layer never imports it.
/// The default is unavailable: a preview or a host build offers no Health setting at all.
@MainActor
public struct HealthExportHooks {
  /// Whether this device has Apple Health. False hides the setting and sends nothing.
  public var isAvailable: () -> Bool
  /// Asks once; true when saving is allowed.
  public var requestAccess: () async -> Bool
  /// Saves one workout. Its Health id, or nil when Health saved it without handing it back (the
  /// phone locked as it finished), so there is no id to record.
  public var save: (HealthWorkoutPlan) async throws -> UUID?

  public init(
    isAvailable: @escaping () -> Bool = { false },
    requestAccess: @escaping () async -> Bool = { false },
    save: @escaping (HealthWorkoutPlan) async throws -> UUID? = { _ in throw CancellationError() }
  ) {
    self.isAvailable = isAvailable
    self.requestAccess = requestAccess
    self.save = save
  }

  public static var unavailable: HealthExportHooks { HealthExportHooks() }
}
