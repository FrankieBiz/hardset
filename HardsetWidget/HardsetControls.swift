import AppIntents
import HardsetCore
import SwiftUI
import WidgetKit

/// Start workout, in Control Center, on the Lock Screen or the Action button. Opens Hardset,
/// which starts an empty workout or shows the open one (`StartWorkoutPolicy`).
struct StartWorkoutControl: ControlWidget {
  static let kind = "com.hardset.app.control.start-workout"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: StartWorkoutControlIntent()) {
        Label("Start workout", systemImage: "figure.strengthtraining.traditional")
      }
    }
    .displayName("Start workout")
    .description("Opens Hardset and starts an empty workout.")
  }
}

/// The length the lifter picks when adding the Rest control. Optional, with no default: a rest
/// exists only once someone chooses it (`HANDOFF.md` §6).
struct RestControlConfiguration: ControlConfigurationIntent {
  static let title: LocalizedStringResource = "Rest"

  @Parameter(title: "Length", defaultUnit: .minutes, supportsNegativeNumbers: false)
  var length: Measurement<UnitDuration>?

  init() {}
}

/// A rest of the configured length, started without opening the app. Until a valid length is
/// chosen it reads "Rest · Choose" and a tap starts nothing (`RestControlState`). It is always one
/// button over one intent: the control template builder has no `if`/`else`.
struct RestControl: ControlWidget {
  static let kind = "com.hardset.app.control.rest"

  var body: some ControlWidgetConfiguration {
    AppIntentControlConfiguration(kind: Self.kind, intent: RestControlConfiguration.self) {
      configuration in
      let state = RestControlState.make(
        configuredSeconds: configuration.length?.converted(to: .seconds).value)
      let seconds: Double? =
        switch state {
        case .ready(let rest): rest.seconds
        case .needsChoice: nil
        }
      ControlWidgetButton(action: RestControlIntent(seconds: seconds)) {
        Label(state.title, systemImage: "timer")
      }
    }
    .displayName("Rest")
    .description("Starts a rest of the length you choose. It logs nothing.")
    .promptsForUserConfiguration()
  }
}
