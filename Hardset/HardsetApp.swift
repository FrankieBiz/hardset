import HardsetStore
import HardsetUI
import SQLiteData
import SwiftUI

@main
struct HardsetApp: App {
  /// Held for the process lifetime. `SyncEngine` retains its delegate strongly, and the
  /// delegate deliberately holds no reference back, so ownership lives here.
  @State private var syncDelegate = HardsetSyncDelegate()

  init() {
    // Exactly once per process. `prepareDependencies` is the supported place to install the
    // default database, and calling it more than once is a programmer error.
    prepareDependencies { dependencies in
      do {
        let database = try HardsetDatabase.open()
        dependencies.defaultDatabase = database
      } catch {
        // Deliberately not a `fatalError`. A launch that cannot open the store should still
        // start, so the user can be told rather than shown a crash.
        assertionFailure("Could not open the Hardset database: \(error)")
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .task {
          // Sync is started after the UI exists so a CloudKit hiccup cannot block launch.
          await startSyncing()
        }
    }
  }

  private func startSyncing() async {
    @Dependency(\.defaultDatabase) var database
    do {
      try HardsetDatabase.makeSyncEngine(for: database, delegate: syncDelegate)
    } catch {
      // A schema the SyncEngine rejects is a programmer error caught by `SchemaTests`, not
      // something the user can act on -- so log and run local-only rather than crash.
      assertionFailure("SyncEngine rejected the schema: \(String(describing: error))")
    }
  }
}

/// Placeholder root. Phase 0 ships the target graph, store and timer; screens come next.
struct RootView: View {
  var body: some View {
    VStack(spacing: Tokens.Spacing.section) {
      Text("Hardset")
        .font(.largeTitle.weight(.semibold))
      UnevaluatedReadout(
        explanation: "No sets logged yet, so there is nothing to estimate."
      )
    }
    .padding(Tokens.Spacing.section)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Tokens.Color.background)
  }
}
