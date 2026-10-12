import HardsetAlarm
import HardsetCore
import HardsetFeature
import HardsetStore
import SQLiteData
import SwiftUI
import UserNotifications

/// The app target, deliberately thin.
///
/// Everything with behaviour worth testing lives in `Packages/HardsetKit`, which builds and tests
/// on the host with `swift test`. This file cannot be compiled from a sandboxed command line — the
/// Swift macro plugin server does not survive it — so it is kept to wiring that has no logic to
/// get wrong: open the database, install the account-change delegate, hand `RestTimerController`'s
/// methods to the feature layer, install the foreground notification presenter, and show the root
/// view. It also registers the rest timer for App Intents, so the Lock Screen's buttons and Siri
/// act on this same controller.
///
/// Anything added here that a test could cover belongs in the package instead.
@main
struct HardsetApp: App {
  /// Held for the process lifetime. `SyncEngine` retains its delegate strongly and the delegate
  /// deliberately holds no reference back, so ownership lives here.
  @State private var syncDelegate = HardsetSyncDelegate()
  /// The AlarmKit-backed rest timer. iOS-only, which is exactly why the feature layer takes its
  /// methods as closures rather than importing it. Built in `init()`, because it writes the rest
  /// down in the database opened there.
  @State private var restTimer: RestTimerController
  /// Shows the rest notification while Hardset is in front. Held for the process lifetime because
  /// `UNUserNotificationCenter.delegate` is `weak`.
  @State private var notificationPresenter: RestNotificationPresenter

  init() {
    // Exactly once per process. `prepareDependencies` is the supported place to install the
    // default database, and calling it more than once is a programmer error.
    let database: (any DatabaseWriter)? = prepareDependencies { dependencies in
      do {
        let opened = try HardsetDatabase.open()
        dependencies.defaultDatabase = opened
        return opened
      } catch {
        // Deliberately not a `fatalError`. A launch that cannot open the store should still start
        // so the user can be told, rather than shown a crash.
        assertionFailure("Could not open the Hardset database: \(error)")
        return nil
      }
    }
    // Without a database there is nowhere to write the rest down, so the timer still runs but a
    // relaunch cannot find its alarm.
    let timer = RestTimerController(persistence: database.map { RestTimerStore(database: $0) })
    _restTimer = State(initialValue: timer)
    // Before any intent can run: a Lock Screen button can launch the app in the background, and
    // its intent asks for this controller.
    IntentDependencies.register(restTimer: timer)

    // Here, not in a view: Apple asks for the delegate to be set before the app finishes
    // launching, and `init()` runs before any scene exists.
    let presenter = RestNotificationPresenter()
    UNUserNotificationCenter.current().delegate = presenter
    _notificationPresenter = State(initialValue: presenter)
  }

  var body: some Scene {
    WindowGroup {
      RootView(syncDelegate: syncDelegate, restTimer: restTimer)
    }
  }
}

private struct RootView: View {
  let syncDelegate: HardsetSyncDelegate
  let restTimer: RestTimerController

  /// Retained for the process lifetime, and that is load-bearing rather than tidy.
  ///
  /// `SyncEngine` installs triggers on every synchronized table that call an instance method of
  /// its own, held weakly. Letting it deallocate leaves those triggers in place with nothing
  /// behind them, and every subsequent write to a synchronized table throws
  /// `_DatabaseFunctionDeallocated` -- no gyms, no machines, no sessions, no sets.
  @State private var syncEngine: SyncEngine?

  @Dependency(\.defaultDatabase) private var database

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
        authorizationDenied: { restTimer.authorization == .denied },
        lastErrorMessage: {
          restTimer.lastError.map { FailureCopy.message(for: $0, during: .scheduleRest) }
        }
      ),
      // Device-local and keyed by exercise. Without it every choice was forgotten on relaunch.
      restPreferences: UserDefaultsRestPreferences()
    )
    .task {
      // Launch first: a force-quit relaunches the app idle while its alarm still counts down.
      // Then follow AlarmKit for as long as the app runs; this does not return.
      await restTimer.reconcile()
      await restTimer.observeAlarms()
    }
    .task {
      // Sync starts after the UI exists, so a CloudKit hiccup cannot block launch.
      do {
        syncEngine = try HardsetDatabase.makeSyncEngine(for: database, delegate: syncDelegate)
      } catch {
        // A schema the SyncEngine rejects is a programmer error caught by `SchemaTests`, not
        // something a user can act on — so run local-only rather than crash.
        assertionFailure("SyncEngine rejected the schema: \(String(describing: error))")
      }
    }
  }
}

/// One line, because `HardsetAlarm` takes a protocol so it can keep depending on `HardsetCore`
/// alone, and the store's methods already match it. `@retroactive` because both sides are imported:
/// neither module can declare this without depending on the other.
extension RestTimerStore: @retroactive RestTimerPersistence {}
