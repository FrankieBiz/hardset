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

  init() {
    var failure: String?
    // Exactly once per process. `prepareDependencies` is the supported place to install the
    // default database, and calling it more than once is a programmer error.
    prepareDependencies { dependencies in
      do {
        dependencies.defaultDatabase = try HardsetDatabase.open()
      } catch {
        // Not a `fatalError`: a crash tells the user less than the screen does, and it removes
        // their chance to read the reason. Not swallowed either -- see `storeFailure`.
        failure = String(describing: error)
      }
    }
    self.storeFailure = failure
  }

  var body: some Scene {
    WindowGroup {
      if let storeFailure {
        // Deliberately terminal. There is no "start fresh" affordance, because a store that failed
        // to open once may well open on the next launch, and erasing it is not reversible.
        StoreUnavailableView(detail: storeFailure)
      } else {
        RootView(syncDelegate: syncDelegate, restTimer: restTimer)
      }
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
        cancel: { restTimer.cancel() }
      ),
      // No default rest prescription. A rest duration is a training decision, and inventing 90
      // seconds here would be the app asserting something it has no basis for. This becomes a
      // per-exercise setting; until then the timer is started explicitly or not at all.
      restAfterSet: nil
    )
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
