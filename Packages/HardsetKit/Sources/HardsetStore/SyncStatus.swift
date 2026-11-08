import Foundation

/// Whether this launch replicates the workout database to iCloud, and if not, why.
///
/// Sync is an addition to a local-first app, never a precondition for opening it. A build signed
/// without an iCloud container -- a personal development team cannot sign one -- still opens the
/// lifter's workouts. It keeps them on this device and says so, rather than refusing to start.
// `nonisolated` is deliberate. This module defaults to MainActor isolation, and this value is
// produced on the startup queue and read by views alike.
public nonisolated enum SyncStatus: Hashable, Sendable {
  /// The sync engine was constructed against this private container. That means replication is
  /// set up, not that an iCloud account is signed in or that anything has uploaded yet.
  case enabled(containerIdentifier: String)
  /// This build carries no iCloud container entitlement, so nothing leaves the device.
  case localOnly

  /// The container this launch syncs to, or `nil` for a local-only launch.
  ///
  /// An explicit identifier wins (tests pass one per suite); otherwise the one the build is
  /// entitled to. A blank identifier is treated as absent: handing SQLiteData an empty container
  /// name would fail at engine construction and strand the app on its startup failure screen,
  /// which is the exact outcome local-only mode exists to prevent.
  public static func container(explicit: String?, entitled: String?) -> String? {
    for candidate in [explicit, entitled] {
      if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return candidate
      }
    }
    return nil
  }

  public var isSyncing: Bool {
    if case .enabled = self { return true }
    return false
  }
}
