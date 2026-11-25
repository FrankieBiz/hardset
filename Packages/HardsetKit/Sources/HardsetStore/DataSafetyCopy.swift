import Foundation

/// What the app says about where a lifter's history lives, how to keep it, and what not to do.
///
/// Kept here, beside the export and restore it describes, so a test can hold the words to the
/// facts: a build with no iCloud sync keeps history on one phone, an export is how it is kept,
/// deleting the app deletes the history, and updating keeps it. Those are true of every
/// local-only build, an App Store or TestFlight install included.
///
/// One fact is true only of a development install: a build installed with a free developer profile
/// stops opening after 7 days, so a reinstall is routine and the first instinct on seeing the app
/// refuse to open is to delete it. That sentence is private, and the only way to draw it is to say
/// `developmentBuild: true`, so no caller can show it to a customer without having decided the
/// build is a development one. The decision belongs to the caller because this module cannot see
/// how the app was signed.
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

  public static let updatingKeepsIt = "Updating Hardset keeps your history."

  /// True only of a development install: personal-team and ad hoc builds expire, App Store and
  /// TestFlight installs do not. Private so it is reached only through a `developmentBuild:` answer.
  private static let developmentInstall =
    "Install new builds over the old app, and don't delete it first. "
    + "Builds installed with a free developer profile stop opening after 7 days, so expect to do this."

  /// The Settings card for a build with no iCloud sync, one short paragraph per fact.
  ///
  /// - Parameter developmentBuild: Whether this install carries a development provisioning profile
  ///   (the simulator, a personal-team or an ad hoc build). Only then does the card say how to
  ///   install over the old app and that the profile expires.
  public static func localOnly(developmentBuild: Bool) -> [String] {
    [
      historyStaysOnThisPhone,
      exportingKeepsIt,
      developmentBuild ? updatingKeepsIt + " " + developmentInstall : updatingKeepsIt,
    ]
  }

  /// The facts above the export buttons, in one place: on this iPhone only, deleting the app
  /// deletes it, and an export keeps it.
  static let beforeExportingFacts =
    "Your history is saved on this iPhone only, and deleting Hardset deletes it. "
    + "Export a JSON or CSV copy to keep it."

  /// The same facts above the export buttons, with the development install's advice only where it
  /// is true.
  ///
  /// - Parameter developmentBuild: As for `localOnly(developmentBuild:)`.
  public static func beforeExporting(developmentBuild: Bool) -> String {
    developmentBuild
      ? beforeExportingFacts + " Install new builds over the old app, not after deleting it."
      : beforeExportingFacts
  }

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
