import Foundation
import Testing

@testable import HardsetStore

/// The warning about deleting the app is a set of facts, so the words are held to them.
@Suite("The data-safety copy says the plain facts")
struct DataSafetyCopyTests {
  private func settings(developmentBuild: Bool) -> String {
    DataSafetyCopy.localOnly(developmentBuild: developmentBuild).joined(separator: " ").lowercased()
  }
  private func beforeExporting(developmentBuild: Bool) -> String {
    DataSafetyCopy.beforeExporting(developmentBuild: developmentBuild).lowercased()
  }
  /// Every local-only wording, release and development, for the facts that hold in both.
  private var allSettings: [String] { [false, true].map { settings(developmentBuild: $0) } }
  private var allBeforeExporting: [String] { [false, true].map { beforeExporting(developmentBuild: $0) } }

  @Test("It says history is on this phone only, and that deleting the app deletes it")
  func historyIsOnThisPhone() {
    for text in allSettings + allBeforeExporting {
      #expect(text.contains("this iphone"))
    }
    for text in allSettings {
      #expect(text.contains("nowhere else"))
      #expect(text.contains("deleting hardset deletes it"))
    }
    for text in allBeforeExporting {
      #expect(text.contains("deleting hardset deletes it"))
    }
  }

  @Test("It says exporting is how to keep it, and that JSON and CSV can be read back in, not SQLite")
  func exportingKeepsIt() {
    for text in allSettings {
      #expect(text.contains("exporting is how you keep it"))
      #expect(text.contains("json or csv export is a copy hardset can read back in"))
      #expect(text.contains("sqlite exports are for keeping and inspecting"))
    }
    for text in allBeforeExporting {
      #expect(text.contains("export a json or csv copy"))
    }
    // The copy names JSON and CSV as the restorable formats; if that changes, so must the words.
    let restorable = DataTransferStore.Format.allCases.filter(\.restoresIntoHardset)
    #expect(restorable == [.csv, .json])
  }

  @Test("Every local-only build says updating keeps the history")
  func updatingKeepsIt() {
    for text in allSettings {
      #expect(text.contains("updating hardset keeps your history"))
    }
  }

  /// An App Store or TestFlight install has no developer profile, never expires after 7 days, and
  /// is updated by the App Store, so it is told none of that.
  @Test("A release build says nothing about developer profiles, 7 days or installing over the old app")
  func releaseBuildSaysNothingAboutDevelopmentInstalls() {
    for text in [settings(developmentBuild: false), beforeExporting(developmentBuild: false)] {
      for phrase in ["developer", "profile", "7 days", "seven days", "install new builds", "old app", "expect to do this"] {
        #expect(!text.contains(phrase), Comment(rawValue: phrase))
      }
    }
  }

  /// For a personal-team install the expiry is real and deleting the app is the natural reaction, so
  /// the development wording keeps saying both.
  @Test("A development build says to install over the old app, and why that comes up")
  func developmentBuildSaysToInstallOverTheOldApp() {
    let settings = settings(developmentBuild: true)
    #expect(settings.contains("install new builds over the old app"))
    #expect(settings.contains("don't delete it first"))
    #expect(settings.contains("free developer profile stop opening after 7 days"))
    #expect(beforeExporting(developmentBuild: true).contains("install new builds over the old app"))
  }

  @Test("The development wording is the release wording plus the development install's advice")
  func developmentAddsToReleaseWithoutChangingIt() {
    let release = DataSafetyCopy.localOnly(developmentBuild: false)
    let development = DataSafetyCopy.localOnly(developmentBuild: true)
    #expect(release.count == development.count)
    for (shared, extended) in zip(release, development) {
      #expect(extended.hasPrefix(shared))
    }
    #expect(
      DataSafetyCopy.beforeExporting(developmentBuild: true)
        .hasPrefix(DataSafetyCopy.beforeExporting(developmentBuild: false)))
  }

  @Test("The receipt line is said only where it is true, and says the two facts that matter")
  func receiptNoteIsConditional() throws {
    let note = try #require(DataSafetyCopy.receiptNote(for: .localOnly)).lowercased()
    #expect(note.contains("saved on this iphone only"))
    #expect(note.contains("deleting hardset deletes your history"))
    #expect(note.contains("settings can export a copy"))
    // A build that syncs does not claim its history is on one phone, and an unknown build says nothing.
    #expect(DataSafetyCopy.receiptNote(for: .enabled(containerIdentifier: "iCloud.example")) == nil)
    #expect(DataSafetyCopy.receiptNote(for: nil) == nil)
    // One line, not a paragraph: two sentences at most.
    #expect(note.split(separator: ".").count <= 2)
    for word in ["might", "may ", "could", "should", "probably", "try to"] {
      #expect(!note.contains(word), Comment(rawValue: word))
    }
  }

  @Test("Every sentence is plain: no hedging word where a fact is stated")
  func noHedging() {
    for text in allSettings + allBeforeExporting {
      for word in ["might", "may ", "could", "should", "probably", "try to"] {
        #expect(!text.contains(word), Comment(rawValue: word))
      }
    }
  }
}
