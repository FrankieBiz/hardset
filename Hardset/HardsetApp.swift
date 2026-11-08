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
  @State private var timerReady = false

  var body: some View {
    Group {
      if let resources = startup.resources, timerReady {
        RootView(database: resources.database, restTimer: restTimer)
      } else if startup.lastError != nil {
        // The design system's empty state and primary button, not the stock bordered one, so the
        // first screen a lifter might ever see already looks like the rest of the app.
        HardsetEmptyState(
          title: "Could not open Hardset",
          detail: "Try again to open your workouts.",
          systemImage: "exclamationmark.triangle",
          actionTitle: "Try again",
          actionSystemImage: "arrow.clockwise",
          action: { Task { await startup.retry() } }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.background)
      } else {
        // A quiet line on the launch canvas rather than a spinner: opening usually takes a moment,
        // and the screen should not flash a busy indicator on every launch.
        HardsetLoadingState("Opening your workouts…")
      }
    }
    .task { await startup.start() }
    .onChange(of: startup.resources != nil, initial: true) {
      guard let resources = startup.resources else { return }
      let journal = RestJournal(database: resources.database)
      switch resources.restCheckpoint {
      case .success(let checkpoint): restTimer.configure(checkpoint: checkpoint, save: journal.save)
      case .failure(let error): restTimer.configureRecoveryFailure(error, restore: journal.load, save: journal.save)
      }
      timerReady = true
    }
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
        metadata: { restTimer.metadata },
        hasError: { restTimer.lastError != nil },
        retry: { restTimer.retry() },
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
