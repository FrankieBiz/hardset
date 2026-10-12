import AppIntents
import HardsetAlarm

/// Hands the app's live objects to its App Intents.
///
/// A file of its own so `HardsetApp.swift` need not import AppIntents: that file's
/// `@Dependency(\.defaultDatabase)` is swift-dependencies' (through SQLiteData), and AppIntents
/// brings a dependency property wrapper of its own.
enum IntentDependencies {
  /// Called from `HardsetApp.init()`, which runs on every launch, including the background
  /// launch a Lock Screen button causes, before any intent is performed.
  @MainActor
  static func register(restTimer: RestTimerController) {
    AppDependencyManager.shared.add(dependency: restTimer)
  }
}
