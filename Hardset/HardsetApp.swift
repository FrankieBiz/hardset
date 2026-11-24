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

  init() {
    #if DEBUG
      // For the UI tests only: a Swift runtime trap prints its reason to stderr, which a launched
      // app does not keep. With this set, stderr goes to a file in the app's own temporary
      // directory, where CI collects it. Absent in release builds.
      if ProcessInfo.processInfo.environment["HARDSET_CAPTURE_STDERR"] == "1" {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("stderr.log").path
        let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if descriptor >= 0 { dup2(descriptor, STDERR_FILENO) }
      }
      // For the UI tests only: every journey must start from the same empty store, or the order the
      // journeys run in decides what each one finds. "reset" removes the database files and the
      // app's preferences before anything opens them; anything else keeps what is there, which the
      // one journey that relaunches mid-test needs. Done before the onboarding marker below, which is
      // one of the preferences it clears. Absent in release builds, so nothing can erase a lifter's
      // data through it.
      if ProcessInfo.processInfo.environment["HARDSET_STORE"] == "reset" {
        Self.resetStoreForUITests()
      }
      // For the UI tests only: the first-launch sequence is stored state, and a launch argument
      // cannot stand in for it, because an argument shadows the stored value and the app's own
      // write on finishing would never be read back. "skip" marks it seen; "reset" clears it so a
      // fresh-install journey can run.
      switch ProcessInfo.processInfo.environment["HARDSET_ONBOARDING"] {
      case "skip":
        UserDefaults.standard.set(OnboardingVersion.current, forKey: "hardset.onboardingVersion")
      case "reset":
        UserDefaults.standard.removeObject(forKey: "hardset.onboardingVersion")
      default:
        break
      }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      StartupView(startup: startup, restTimer: restTimer)
    }
  }

  #if DEBUG
    /// Deletes the database SQLiteData opens by default (`SQLiteData.db` and its write-ahead log
    /// files, in Application Support) and the app's preferences, so the next launch is a fresh
    /// install of the store. The path is the library's own default, which `HardsetDatabase.open`
    /// does not override; the journeys check for the empty start screen, so a path that ever
    /// drifted would fail them rather than isolate nothing.
    private static func resetStoreForUITests() {
      let files = FileManager.default
      if let support = try? files.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
      {
        for name in ["SQLiteData.db", "SQLiteData.db-wal", "SQLiteData.db-shm"] {
          try? files.removeItem(at: support.appendingPathComponent(name))
        }
      }
      if let domain = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: domain)
      }
    }
  #endif
}

@MainActor
private struct StartupView: View {
  let startup: AppStartup<HardsetDatabase.Resources>
  let restTimer: RestTimerController
  @State private var timerReady = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if let resources = startup.resources, timerReady {
        RootView(database: resources.database, sync: resources.sync, restTimer: restTimer)
      } else if let error = startup.lastError {
        // The design system's empty state and primary button, not the stock bordered one, so the
        // first screen a lifter might ever see already looks like the rest of the app. A build
        // without iCloud no longer lands here: it opens local-only. What remains is a database
        // that genuinely could not open or migrate, or a sync engine that could not start.
        // Scrolls, because at an accessibility text size the explanation and the share control
        // are taller than one screen, and the share control is the way out of a repeated failure.
        ScrollView {
          VStack(spacing: Tokens.Spacing.regular) {
            HardsetEmptyState(
              title: "Could not open Hardset",
              detail: "Your workouts are still saved on this phone, and nothing has been erased. "
                + "Do not delete the app: deleting it is what deletes them. Try again; if it keeps "
                + "happening, share the error below so it can be looked at.",
              systemImage: "exclamationmark.triangle",
              actionTitle: "Try again",
              actionSystemImage: "arrow.clockwise",
              action: { Task { await startup.retry() } }
            )
            // The way out of a repeated failure. Without it, a lifter who cannot open the database
            // cannot export or reach Settings, and the only words are a retry that keeps failing.
            ShareLink(item: Self.errorReport(error)) {
              Label("Share error details", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(HardsetButtonStyle(.secondary, fullWidth: false))
            .accessibilityHint("Shares the error text so it can be sent for help")
            // The error itself, small and selectable. On a phone with no debugger attached this
            // screen is the only place the cause can be read, and "try again" alone gave nothing
            // to report when retrying failed the same way.
            Text(verbatim: String(describing: error))
              .font(Tokens.Text.provenance)
              .foregroundStyle(Tokens.Color.chalkDim)
              .multilineTextAlignment(.center)
              .lineLimit(6)
              .textSelection(.enabled)
              .padding(.horizontal, Tokens.Spacing.section)
              .accessibilityLabel("Error details: \(String(describing: error))")
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Tokens.Spacing.section)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.canvas)
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
    // A rest that ended, or was stopped on the Lock Screen, while the app was away clears as soon
    // as the lifter is back, rather than waiting for the next alarm update.
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { restTimer.refresh() }
    }
  }

  /// The text a lifter can send for help: what failed, and the error itself. A version and build
  /// are included because the same error on a different build may have a different cause.
  static func errorReport(_ error: any Error) -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return "Hardset could not open its database on version \(version ?? "unknown") "
      + "(\(build ?? "unknown")).\n\n\(String(describing: error))"
  }
}

@MainActor
private struct RootView: View {
  let database: any DatabaseWriter
  let sync: SyncStatus
  let restTimer: RestTimerController

  var body: some View {
    HardsetLaunchView(
      environment: HardsetEnvironment(database: database, sync: sync),
      // No unit passed: the root view infers it from the device locale on first launch and then
      // honours whatever the user chose in Settings. Hardcoding `.kilograms` here meant a US
      // lifter had no way to see pounds at all, though the engine supported it throughout.
      unit: nil,
      hooks: RestTimerHooks(
        state: { restTimer.state },
        metadata: { restTimer.metadata },
        issue: { restTimer.issue.map { RestTimerIssue($0) } },
        retry: { restTimer.retry() },
        resetRestTimer: { restTimer.resetAfterRecoveryFailure() },
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

extension RestTimerIssue {
  /// The controller's issue in the feature layer's terms. The feature layer cannot import the
  /// AlarmKit-backed module, so the translation lives here with the rest of the wiring.
  fileprivate init(_ issue: RestTimerController.Issue) {
    switch issue {
    case .alarmsDenied: self = .alarmsDenied
    case .recoveryFailed: self = .recoveryFailed
    case .failed: self = .unavailable
    }
  }
}
