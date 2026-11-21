import Foundation
import Testing

@testable import HardsetStore

/// The warning about deleting the app is a set of facts, so the words are held to them.
@Suite("The data-safety copy says the plain facts")
struct DataSafetyCopyTests {
  private var settings: String { DataSafetyCopy.localOnly.joined(separator: " ").lowercased() }
  private var beforeExporting: String { DataSafetyCopy.beforeExporting.lowercased() }

  @Test("It says history is on this phone only, and that deleting the app deletes it")
  func historyIsOnThisPhone() {
    for text in [settings, beforeExporting] {
      #expect(text.contains("this iphone"))
    }
    #expect(settings.contains("nowhere else"))
    #expect(settings.contains("deleting hardset deletes it"))
    #expect(beforeExporting.contains("deleting it first deletes your history"))
  }

  @Test("It says exporting is how to keep it, and that JSON and CSV can be read back in, not SQLite")
  func exportingKeepsIt() {
    #expect(settings.contains("exporting is how you keep it"))
    #expect(settings.contains("json or csv export is a copy hardset can read back in"))
    #expect(beforeExporting.contains("export a json or csv copy"))
    // The copy names JSON and CSV as the restorable formats; if that changes, so must the words.
    let restorable = DataTransferStore.Format.allCases.filter(\.restoresIntoHardset)
    #expect(restorable == [.csv, .json])
    #expect(settings.contains("sqlite exports are for keeping and inspecting"))
  }

  @Test("It says to install over the old app, not after deleting it, and why that comes up")
  func installOverTheOldApp() {
    #expect(settings.contains("install new builds over the old app"))
    #expect(settings.contains("don't delete it first"))
    #expect(settings.contains("updating keeps your history"))
    #expect(settings.contains("free developer profile stop opening after 7 days"))
    #expect(beforeExporting.contains("install new builds over the old app"))
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
    for word in ["might", "may ", "could", "should", "probably", "try to"] {
      #expect(!settings.contains(word), Comment(rawValue: word))
      #expect(!beforeExporting.contains(word), Comment(rawValue: word))
    }
  }
}
