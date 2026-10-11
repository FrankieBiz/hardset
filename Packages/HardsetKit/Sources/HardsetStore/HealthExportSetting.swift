import Foundation
import Synchronization

/// Whether the lifter has asked for finished workouts to be saved to Apple Health. Off until they
/// turn it on.
///
/// Device-local, like rest choices: Health permission is granted per device, so the choice is too.
/// `UserDefaults` is already declared in the privacy manifest (CA92.1).
public nonisolated protocol HealthExportSetting: AnyObject, Sendable {
  var isEnabled: Bool { get }
  func setEnabled(_ enabled: Bool)
}

/// `UserDefaults` is documented as thread-safe, which is what makes `@unchecked` honest here.
public nonisolated final class UserDefaultsHealthExportSetting: HealthExportSetting, @unchecked Sendable {
  static let key = "hardset.healthExport.enabled"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// `bool(forKey:)` is false for a missing key, which is the opt-in default.
  public var isEnabled: Bool { defaults.bool(forKey: Self.key) }

  public func setEnabled(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.key)
  }
}

/// For tests and previews.
public nonisolated final class InMemoryHealthExportSetting: HealthExportSetting {
  private let storage: Mutex<Bool>

  public init(isEnabled: Bool = false) {
    storage = Mutex(isEnabled)
  }

  public var isEnabled: Bool { storage.withLock { $0 } }

  public func setEnabled(_ enabled: Bool) {
    storage.withLock { $0 = enabled }
  }
}
