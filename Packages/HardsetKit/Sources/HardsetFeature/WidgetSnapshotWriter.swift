import Foundation
import HardsetCore
import HardsetStore
import OSLog

#if os(iOS)
  import WidgetKit
#endif

/// Writes the widgets' file and asks WidgetKit to redraw (`DECISIONS.md` §25).
///
/// WidgetKit is asked only after the file is written, so a widget is never told to redraw from a
/// write that failed. With no App Group container (off iOS, or the group missing from the
/// entitlements) nothing is written, and the widget keeps saying "nothing yet".
@MainActor
struct WidgetSnapshotWriter {
  let store: WidgetSnapshotStore

  /// Throws when the finished workouts cannot be read or the file cannot be written. The caller
  /// keeps the error and does not show it: a widget one workout behind is not worth interrupting
  /// a lifter over, and it still shows its last file or "nothing yet".
  func refresh(unit: WeightUnit) throws {
    #if os(iOS)
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: WidgetSnapshotFile.appGroupIdentifier)
      guard let file = WidgetSnapshotFile(containerURL: container) else { return }
      try file.write(store.snapshot(unit: unit))
      WidgetCenter.shared.reloadAllTimelines()
    #endif
  }

  /// Puts a failed refresh in the unified log, so a Release build keeps a trace of it too. Only
  /// the error's type is public: its description can carry file paths, so it stays private.
  static func log(_ error: any Error) {
    let kind = String(reflecting: type(of: error))
    let detail = String(describing: error)
    logger.error(
      "The widget snapshot was not written: \(kind, privacy: .public) \(detail, privacy: .private)")
  }

  private static let logger = Logger(subsystem: "com.hardset.app", category: "widget")
}
