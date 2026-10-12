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
    postStartWorkout(to: systemRequests)
    return .result()
  }
}

/// Asks the app to start a workout (or show the open one). Shared by both start-workout intents.
@MainActor
func postStartWorkout(to inbox: SystemRequestInbox) {
  inbox.post(.startWorkout)
}

/// The one place the Start workout control can open. `OpenIntent` needs a `target` of an app
/// value type, so this is a single-case enum.
enum HardsetScreen: String, AppEnum {
  case train

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
  static let caseDisplayRepresentations: [HardsetScreen: DisplayRepresentation] = [
    .train: "Train"
  ]
}

/// The Start workout control's action. Apple's controls article opens an app from a control with
/// an `OpenIntent`, which the system brings forward on its own. The Siri, Spotlight and Action
/// button path stays `StartWorkoutIntent`. Like it, this only posts the request.
struct StartWorkoutControlIntent: OpenIntent {
  static let title: LocalizedStringResource = "Start a workout"
  static let isDiscoverable = false

  @Parameter(title: "Screen")
  var target: HardsetScreen

  @AppDependency private var systemRequests: SystemRequestInbox

  init() {
    target = .train
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    postStartWorkout(to: systemRequests)
    return .result()
  }
}
