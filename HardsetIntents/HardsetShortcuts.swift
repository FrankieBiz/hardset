import AppIntents

/// Phrases for Siri, and the entries Spotlight and the Action button list. A workout and a
/// rest, started and ended; nothing that logs (DECISIONS.md §26). Every phrase names the app,
/// as App Shortcuts require.
///
/// App target only: the system reads App Shortcuts from the app bundle. They appear in Spotlight
/// and Shortcuts, and in Settings › Action Button › Shortcut, with no further work.
struct HardsetShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartWorkoutIntent(),
      phrases: [
        "Start a workout in \(.applicationName)",
        "Begin a workout in \(.applicationName)",
      ],
      shortTitle: "Start workout",
      systemImageName: "figure.strengthtraining.traditional")
    AppShortcut(
      intent: StartRestIntent(),
      phrases: [
        "Start a rest in \(.applicationName)",
        "Rest in \(.applicationName)",
      ],
      shortTitle: "Start rest",
      systemImageName: "timer")
    AppShortcut(
      intent: StopRestIntent(),
      phrases: [
        "Skip my rest in \(.applicationName)",
        "End my rest in \(.applicationName)",
      ],
      shortTitle: "Skip rest",
      systemImageName: "forward.end")
  }
}
