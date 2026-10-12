import AppIntents
import HardsetAlarm
import HardsetCore

/// Hands the app's live objects to its App Intents.
///
/// A file of its own so `HardsetApp.swift` need not import AppIntents: that file's
/// `@Dependency(\.defaultDatabase)` is swift-dependencies' (through SQLiteData), and AppIntents
/// brings a dependency property wrapper of its own.
enum IntentDependencies {
  /// Called from `HardsetApp.init()`, which runs on every launch, including the background
  /// launch a Lock Screen button causes, before any intent is performed. The inbox is the one the
  /// root view reads, so a Start workout request reaches the screen.
  @MainActor
  static func register(restTimer: RestTimerController, systemRequests: SystemRequestInbox) {
    AppDependencyManager.shared.add(dependency: restTimer)
    AppDependencyManager.shared.add(dependency: systemRequests)
  }
}
