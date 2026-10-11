import Foundation
import HardsetCore
import SQLiteData
import Synchronization

/// Whether the lifter has been through the first screen. Device-local, like rest choices: it is
/// not training data, and `UserDefaults` is already declared in the privacy manifest (CA92.1).
public nonisolated protocol FirstRunFlag: AnyObject, Sendable {
  var isComplete: Bool { get }
  func markComplete()
}

/// `UserDefaults` is documented as thread-safe, which is what makes `@unchecked` honest here.
public nonisolated final class UserDefaultsFirstRunFlag: FirstRunFlag, @unchecked Sendable {
  static let key = "hardset.firstRunComplete"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var isComplete: Bool { defaults.bool(forKey: Self.key) }

  public func markComplete() {
    defaults.set(true, forKey: Self.key)
  }
}

/// For tests and previews.
public nonisolated final class InMemoryFirstRunFlag: FirstRunFlag {
  private let storage: Mutex<Bool>

  public init(isComplete: Bool = false) {
    storage = Mutex(isComplete)
  }

  public var isComplete: Bool { storage.withLock { $0 } }

  public func markComplete() {
    storage.withLock { $0 = true }
  }
}

/// Decides whether the first screen shows, and ends it (spec 3.5).
public nonisolated struct FirstRunStore {
  private let database: any DatabaseWriter
  private let flag: any FirstRunFlag

  public init(database: any DatabaseWriter, flag: any FirstRunFlag) {
    self.database = database
    self.flag = flag
  }

  /// True only for someone who has never finished the first screen and has no workout at all,
  /// open or finished.
  ///
  /// Someone updating with history has the flag unset, because it is new, and must not be greeted
  /// as a stranger. A workout left open must be offered back, not hidden behind a welcome.
  public func shouldShow() throws -> Bool {
    guard !flag.isComplete else { return false }
    let anySession = try database.read { db in
      try Session.order { $0.startedAt.desc() }.fetchOne(db)
    }
    return anySession == nil
  }

  /// Ends the first screen: creates the gym when a name was given, then marks it done.
  ///
  /// The name goes through `EquipmentName`, so "   " creates nothing. The flag is set only after
  /// the gym is written: if that write fails the screen stays, with the name still typed, rather
  /// than claiming a gym that does not exist.
  @discardableResult
  public func complete(gymName: String, now: Date = Date()) throws -> GymID? {
    let gym = try EquipmentName.normalized(gymName).map {
      try GymStore(database: database).createGym(name: $0, now: now)
    }
    flag.markComplete()
    return gym
  }
}
