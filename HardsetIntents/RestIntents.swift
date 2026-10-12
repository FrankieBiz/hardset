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

/// "Start a rest" from Siri, Shortcuts, the Action button or the Rest control. The length is
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

  /// For the Rest control, which already knows its configured length.
  init(seconds: Double) {
    self.length = Measurement(value: seconds, unit: .seconds)
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    switch RestRequest.duration(seconds: length.converted(to: .seconds).value) {
    case .failure:
      return .result(
        dialog: IntentDialog(LocalizedStringResource(stringLiteral: RestRequest.refusal)))
    case .success(let rest):
      return .result(dialog: await restReply(.start(rest), on: restTimer))
    }
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
