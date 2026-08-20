import HardsetAlarm
import HardsetCore
import HardsetFeature
import HardsetStore
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

  init() {
    // Exactly once per process. `prepareDependencies` is the supported place to install the
    // default database, and calling it more than once is a programmer error.
    prepareDependencies { dependencies in
      do {
        dependencies.defaultDatabase = try HardsetDatabase.open()
      } catch {
        // Deliberately not a `fatalError`. A launch that cannot open the store should still start
        // so the user can be told, rather than shown a crash.
        assertionFailure("Could not open the Hardset database: \(error)")
      }
    }
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

  @Dependency(\.defaultDatabase) private var database

  var body: some View {
    HardsetRootView(
      environment: HardsetEnvironment(database: database),
      unit: .kilograms,
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
        try HardsetDatabase.makeSyncEngine(for: database, delegate: syncDelegate)
      } catch {
        // A schema the SyncEngine rejects is a programmer error caught by `SchemaTests`, not
        // something a user can act on — so run local-only rather than crash.
        assertionFailure("SyncEngine rejected the schema: \(String(describing: error))")
      }
    }
  }
}
