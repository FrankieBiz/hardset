import HardsetAlarm
import HardsetCore
import HardsetFeature
import HardsetStore
import HardsetUI
import SQLiteData
import SwiftUI

/// The app target, deliberately thin.
///
/// Everything with behaviour worth testing lives in `Packages/HardsetKit`, which builds and tests
/// on the host with `swift test`. This file cannot be compiled from a sandboxed command line — the
/// Swift macro plugin server does not survive it — so it is kept to wiring that has no logic to
/// get wrong: open the database, install the account-change delegate, hand `RestTimerController`'s
/// methods to the feature layer, and show the root view.
///
/// Anything added here that a test could cover belongs in the package instead.
@main
struct HardsetApp: App {
  /// Held for the process lifetime. `SyncEngine` retains its delegate strongly and the delegate
  /// deliberately holds no reference back, so ownership lives here.
  @State private var syncDelegate = HardsetSyncDelegate()
  /// The AlarmKit-backed rest timer. iOS-only, which is exactly why the feature layer takes its
  /// methods as closures rather than importing it.
  @State private var restTimer = RestTimerController()

  /// Why the store could not be opened, or `nil` when it opened.
  ///
  /// Load-bearing. Previously the failure path was `assertionFailure`, which does nothing in a
  /// release build, and `defaultDatabase` was left unassigned -- so the app launched against an
  /// empty fallback store and rendered a perfectly normal, completely blank logger. A lifter with
  /// two years of history would see a fresh install, train into a store discarded on quit, and be
  /// told nothing. Recording the failure is what makes it possible to say so instead.
  private let storeFailure: String?
  /// UI tests get a fresh migrated store on every launch. Release builds can never enable this.
  private let runsUITests: Bool

  init() {
    #if DEBUG
      let runsUITests = ProcessInfo.processInfo.arguments.contains("--hardset-ui-testing")
    #else
      let runsUITests = false
    #endif

    #if DEBUG
      if runsUITests, let bundleID = Bundle.main.bundleIdentifier {
        // `@AppStorage` is process-global. Reset only Hardset's own test container so a previous UI
        // run cannot skip the first-use rest choice or change the unit under a later assertion.
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
      }
    #endif

    var failure: String?
    // Exactly once per process. `prepareDependencies` is the supported place to install the
    // default database, and calling it more than once is a programmer error.
    prepareDependencies { dependencies in
      do {
        dependencies.defaultDatabase =
          try runsUITests
          ? HardsetDatabase.ephemeral()
          : HardsetDatabase.open()
      } catch {
        // Not a `fatalError`: a crash tells the user less than the screen does, and it removes
        // their chance to read the reason. Not swallowed either -- see `storeFailure`.
        failure = String(describing: error)
      }
    }
    self.storeFailure = failure
    self.runsUITests = runsUITests
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if let storeFailure {
          // Deliberately terminal. There is no "start fresh" affordance, because a store that failed
          // to open once may well open on the next launch, and erasing it is not reversible.
          StoreUnavailableView(detail: storeFailure)
        } else {
          RootView(
            syncDelegate: syncDelegate,
            restTimer: restTimer,
            startsSyncEngine: !runsUITests
          )
        }
      }
      // Applied here so both branches inherit them. `HardsetRootView` sets the same two inside its
      // own body — and keeps them, since the package previews and the host suite render that view
      // without this target — so only the store-failure screen was missing them: on a device in Light
      // Mode the status bar, scroll indicators and the selection handles on the one text that screen
      // exists to have copied were all drawn light, in stock blue. DECISIONS #22 makes dark-only the
      // rule for the whole app, not for one view.
      .preferredColorScheme(.dark)
      .tint(Tokens.Color.accent)
    }
  }
}

private struct RootView: View {
  let syncDelegate: HardsetSyncDelegate
  let restTimer: RestTimerController
  let startsSyncEngine: Bool

  /// Retained for the process lifetime, and that is load-bearing rather than tidy.
  ///
  /// `SyncEngine` installs triggers on every synchronized table that call an instance method of
  /// its own, held weakly. Letting it deallocate leaves those triggers in place with nothing
  /// behind them, and every subsequent write to a synchronized table throws
  /// `_DatabaseFunctionDeallocated` -- no gyms, no machines, no sessions, no sets.
  @State private var syncEngine: SyncEngine?

  @Dependency(\.defaultDatabase) private var database

  /// Persists the rest timer so it survives the app being killed.
  ///
  /// `deviceRestTimer` had no reader and no writer while Settings promised the timer keeps running
  /// through a force-quit. AlarmKit's alert did survive; the app's own state did not, so on relaunch
  /// the bar was gone and the alarm's id was lost with it -- leaving an alert scheduled that nothing
  /// could cancel.
  private var restStore: RestTimerStore { RestTimerStore(database: database) }

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
        cancel: { restTimer.cancel() },
        // Nothing requested AlarmKit permission anywhere in the app, so every schedule on a fresh
        // install was refused and the rest timer counted down without ever alerting.
        requestAuthorization: { await restTimer.requestAuthorizationIfNeeded() },
        isDenied: { restTimer.isDenied }
      ),
      // No default rest prescription. A rest duration is a training decision, and inventing 90
      // seconds here would be the app asserting something it has no basis for. This becomes a
      // per-exercise setting; until then the timer is started explicitly or not at all.
      restAfterSet: nil
    )
    .task {
      // Restored before anything else, so a rest still running when the app was killed comes back
      // instead of silently continuing as an alarm with no visible countdown.
      restTimer.persist = { state, alarmID in
        try? restStore.save(state: state, alarmID: alarmID, sessionID: nil)
      }
      if let stored = try? restStore.load() {
        restTimer.restore(state: stored.state, alarmID: stored.alarmID)
      }

      // Sync starts after the UI exists, so a CloudKit hiccup cannot block launch. A UI-test store
      // is intentionally process-local and has nothing to synchronize.
      guard startsSyncEngine else { return }
      do {
        syncEngine = try HardsetDatabase.makeSyncEngine(for: database, delegate: syncDelegate)
      } catch {
        // Run local-only rather than crash. Everything a workout touches — logging, the rest
        // timer, history, plans — is local, so a sync engine that cannot start costs sync and
        // nothing else.
        //
        // Deliberately NOT `assertionFailure`. That reads as "this can only be a schema bug caught
        // by `SchemaTests`", and it is not: iCloud and push are **paid**-membership capabilities,
        // so a build signed with a free personal team reaches here every single launch. An
        // assertion would turn the one build configuration a developer runs by default into a
        // crash on launch, on the day they were trying to test the app in a gym.
        //
        // A schema mistake still fails loudly where it should — in `SchemaTests`, on the host,
        // before anything is installed.
        print("Hardset: running local-only, sync unavailable — \(String(describing: error))")
      }
    }
  }
}
