import Foundation

/// What the app says about where a lifter's history lives, how to keep it, and what not to do.
///
/// Kept here, beside the export and restore it describes, so a test can hold the words to the
/// facts: a build with no iCloud sync keeps history on one phone, an export is how it is kept,
/// and a new build goes over the old app, because deleting the app deletes the history. A free
/// developer profile stops opening after 7 days, so a reinstall is routine for a local-only
/// build and the first instinct on seeing the app refuse to open is to delete it.
///
/// These are shown only where they are true. A build with iCloud sync does not say its history is
/// on one phone.
public nonisolated enum DataSafetyCopy {
  public static let historyStaysOnThisPhone =
    "This build can't use iCloud sync, so your history lives on this iPhone and nowhere else. "
    + "Deleting Hardset deletes it."

  public static let exportingKeepsIt =
    "Exporting is how you keep it: a JSON or CSV export is a copy Hardset can read back in, and "
    + "JSON also brings back saved workouts and body mass. SQLite exports are for keeping and inspecting."

  public static let installOverTheOldApp =
    "Install new builds over the old app, and don't delete it first: updating keeps your history. "
    + "Builds installed with a free developer profile stop opening after 7 days, so expect to do this."

  /// The Settings card for a build with no iCloud sync, one short paragraph per fact.
  public static let localOnly = [historyStaysOnThisPhone, exportingKeepsIt, installOverTheOldApp]

  /// The same three facts in one place, above the export buttons.
  public static let beforeExporting =
    "Your history is saved on this iPhone only. Export a JSON or CSV copy to keep it, "
    + "and install new builds over the old app; deleting it first deletes your history."

  /// One quiet line for where a lifter meets their history early, under a finished workout. Settings
  /// holds the whole warning, but a lifter who never opens Settings would never learn that their
  /// history has no copy off this phone, so the receipt says the two facts that matter and where to
  /// act on them.
  ///
  /// `nil` unless the build is known to have no iCloud sync: a build that syncs does not say its
  /// history is on one phone, and a surface that does not know says nothing rather than guess.
  public static func receiptNote(for sync: SyncStatus?) -> String? {
    guard sync == .localOnly else { return nil }
    return "Saved on this iPhone only. Deleting Hardset deletes your history, and Settings can export a copy."
  }
}
