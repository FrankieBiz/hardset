import AppIntents
import HardsetCore

// Compiled into the app AND the widget extension (Tools/generate_project.py), so the Control
// Center buttons (Task 11) can name these types. Both declare `supportedModes = .foreground`:
// the system brings Hardset forward and performs them in the app's process, so the inbox is the
// app's own. Neither takes a weight or a rep count.

/// "Start a workout": opens Hardset and starts an empty one, or shows the one already open
/// (`StartWorkoutPolicy`). It never logs anything (DECISIONS.md §26).
///
/// It only posts the request. The root view acts on it once the launch read has run and the
/// first-run screen is done, so asking twice, or asking mid-workout, never starts a second one.
struct StartWorkoutIntent: AppIntent {
  static let title: LocalizedStringResource = "Start a workout"
  static let description = IntentDescription(
    "Opens Hardset and starts an empty workout. If one is already open, it shows that one.")
  static let supportedModes: IntentModes = .foreground

  @AppDependency private var systemRequests: SystemRequestInbox

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    systemRequests.post(.startWorkout)
    return .result()
  }
}

/// Opens Hardset and does nothing else: the Rest control's action until a length is chosen.
struct OpenHardsetIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Hardset"
  static let isDiscoverable = false
  static let supportedModes: IntentModes = .foreground

  init() {}

  func perform() async throws -> some IntentResult { .result() }
}
