import Foundation
import HardsetCore
import Synchronization

/// Where the lifter's rest choice for each exercise is remembered.
///
/// Device-local on purpose. A rest preference is not training data, so it does not justify a
/// permanent synced column (`DECISIONS.md` §4: the schema is additive-only forever). And
/// `UserDefaults` is already declared in the privacy manifest (CA92.1).
public nonisolated protocol RestPreferenceStore: AnyObject, Sendable {
  func rest(for exercise: ExerciseID) -> Duration?
  func setRest(_ rest: Duration?, for exercise: ExerciseID)
}

/// `UserDefaults` is documented as thread-safe, which is what makes `@unchecked` honest here.
public nonisolated final class UserDefaultsRestPreferences: RestPreferenceStore, @unchecked Sendable {
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func rest(for exercise: ExerciseID) -> Duration? {
    let seconds = defaults.integer(forKey: Self.key(exercise))
    // `integer(forKey:)` returns 0 for a missing key, and 0 is never a valid rest.
    return seconds > 0 ? .seconds(seconds) : nil
  }

  public func setRest(_ rest: Duration?, for exercise: ExerciseID) {
    if let rest {
      defaults.set(Int(rest.components.seconds), forKey: Self.key(exercise))
    } else {
      defaults.removeObject(forKey: Self.key(exercise))
    }
  }

  private static func key(_ exercise: ExerciseID) -> String {
    "hardset.rest.\(exercise.rawValue.uuidString)"
  }
}

/// For tests and previews.
public nonisolated final class InMemoryRestPreferences: RestPreferenceStore {
  private let storage: Mutex<[ExerciseID: Duration]>

  public init(_ initial: [ExerciseID: Duration] = [:]) {
    storage = Mutex(initial)
  }

  public func rest(for exercise: ExerciseID) -> Duration? {
    storage.withLock { $0[exercise] }
  }

  public func setRest(_ rest: Duration?, for exercise: ExerciseID) {
    storage.withLock { $0[exercise] = rest }
  }
}
