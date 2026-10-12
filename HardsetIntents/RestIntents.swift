import AppIntents
import Foundation
import HardsetAlarm
import HardsetCore

// Compiled into the app AND the widget extension (Tools/generate_project.py). The Live
// Activity's buttons and the Rest control name these types from the widget, and a
// `LiveActivityIntent` is performed in the app's process, launched in the background if need
// be, so `RestTimerController` is the app's own. None of them logs anything (DECISIONS.md §26).

/// Carries out a command and says what happened, in Core's words.
@MainActor
func restReply(_ command: RestCommand, on timer: RestTimerController) async -> IntentDialog {
  switch await timer.perform(command) {
  case .perform(let done):
    IntentDialog(LocalizedStringResource(stringLiteral: RestCommandPlan.confirmation(for: done)))
  case .nothing(let why):
    IntentDialog(LocalizedStringResource(stringLiteral: why))
  }
}

/// Validates a length and starts the rest, saying what happened. Shared by `StartRestIntent` and
/// the Rest control.
@MainActor
func startRestReply(seconds: Double, on timer: RestTimerController) async -> IntentDialog {
  switch RestRequest.duration(seconds: seconds) {
  case .failure:
    IntentDialog(LocalizedStringResource(stringLiteral: RestRequest.refusal))
  case .success(let rest):
    await restReply(.start(rest), on: timer)
  }
}

/// "Start a rest" from Siri, Shortcuts or the Action button. The length is
/// required and has no default: Siri asks for it.
struct StartRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Start a rest"
  static let description = IntentDescription(
    "Starts a rest timer of the length you say. It logs nothing.")

  @Parameter(
    title: "Length", defaultUnit: .minutes, supportsNegativeNumbers: false,
    requestValueDialog: IntentDialog("How long a rest?"))
  var length: Measurement<UnitDuration>

  @AppDependency private var restTimer: RestTimerController

  init() {}

  /// For a caller that already knows the length.
  init(seconds: Double) {
    self.length = Measurement(value: seconds, unit: .seconds)
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let seconds = length.converted(to: .seconds).value
    return .result(dialog: await startRestReply(seconds: seconds, on: restTimer))
  }
}

/// The Rest control's action. A control's button takes one action type, so this one covers both
/// states: with a length (the lifter chose one) it starts that rest exactly as `StartRestIntent`
/// does; with none it does nothing and starts nothing -- there is no default rest
/// (`RestControlState`). It stays in the background, so a configured tap never opens the app.
struct RestControlIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Start a rest"
  static let isDiscoverable = false

  @Parameter(title: "Seconds")
  var seconds: Double?

  @AppDependency private var restTimer: RestTimerController

  init() {}

  init(seconds: Double?) {
    self.seconds = seconds
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    if let seconds {
      _ = await startRestReply(seconds: seconds, on: restTimer)
    }
    return .result()
  }
}

/// "Skip my rest": the Lock Screen's Skip, and a Siri phrase (Task 10).
struct StopRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Skip the rest"
  static let description = IntentDescription("Ends the rest timer now.")
  @AppDependency private var restTimer: RestTimerController
  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    .result(dialog: await restReply(.stop, on: restTimer))
  }
}

/// The Lock Screen's Pause. Not offered to Siri or Shortcuts.
struct PauseRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Pause the rest"
  static let isDiscoverable = false
  @AppDependency private var restTimer: RestTimerController
  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    .result(dialog: await restReply(.pause, on: restTimer))
  }
}

/// The Lock Screen's Resume. Not offered to Siri or Shortcuts.
struct ResumeRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Resume the rest"
  static let isDiscoverable = false
  @AppDependency private var restTimer: RestTimerController
  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    .result(dialog: await restReply(.resume, on: restTimer))
  }
}
