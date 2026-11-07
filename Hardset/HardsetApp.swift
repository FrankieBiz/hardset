import HardsetAlarm
import HardsetCore
import HardsetFeature
import HardsetStore
import HardsetUI
import SQLiteData
import SwiftUI

/// The app owns startup resources across all scenes. Database failures keep the
/// workout UI behind an explicit retry state instead of an unintended fallback.
@main
@MainActor
struct HardsetApp: App {
  @State private var startup = AppStartup {
    try HardsetDatabase.prepareForLaunch()
  }
  /// The AlarmKit-backed rest timer. iOS-only, which is exactly why the feature layer takes its
  /// methods as closures rather than importing it.
  @State private var restTimer = RestTimerController()

  var body: some Scene {
    WindowGroup {
      StartupView(startup: startup, restTimer: restTimer)
    }
  }
}

@MainActor
private struct StartupView: View {
  let startup: AppStartup<HardsetDatabase.Resources>
  let restTimer: RestTimerController

  var body: some View {
    Group {
      if let resources = startup.resources {
        RootView(database: resources.database, restTimer: restTimer)
      } else if startup.lastError != nil {
        VStack(spacing: Tokens.Spacing.section) {
          HardsetEmptyState(
            title: "Could not open Hardset",
            detail: "Try again to open your workouts.",
            systemImage: "exclamationmark.triangle"
          )
          Button {
            Task { await startup.retry() }
          } label: {
            Text("Try again")
              .frame(minHeight: Tokens.minimumTapTarget)
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(Tokens.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.background)
      } else {
        ProgressView("Opening your workouts")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.background)
      }
    }
    .task { await startup.start() }
  }
}

@MainActor
private struct RootView: View {
  let database: any DatabaseWriter
  let restTimer: RestTimerController

  var body: some View {
    HardsetRootView(
      environment: HardsetEnvironment(database: database),
      // No unit passed: the root view infers it from the device locale on first launch and then
      // honours whatever the user chose in Settings. Hardcoding `.kilograms` here meant a US
      // lifter had no way to see pounds at all, though the engine supported it throughout.
      unit: nil,
      hooks: RestTimerHooks(
        state: { restTimer.state },
        start: { duration, metadata in
          restTimer.start(duration: duration, metadata: metadata)
        },
        adjust: { delta in restTimer.adjust(by: delta) },
        pauseOrResume: {
          // The controller owns the running/paused distinction; asking it is the only way to
          // avoid a second copy of that state here.
          if restTimer.state.isRunning { restTimer.pause() } else { restTimer.resume() }
        },
        cancel: { restTimer.cancel() }
      ),
      // No default rest prescription. A rest duration is a training decision, and inventing 90
      // seconds here would be the app asserting something it has no basis for. This becomes a
      // per-exercise setting; until then the timer is started explicitly or not at all.
      restAfterSet: nil
    )
  }
}
