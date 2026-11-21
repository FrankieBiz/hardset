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

  @Test("It says exporting is how to keep it, and only a CSV can be read back in")
  func exportingKeepsIt() {
    #expect(settings.contains("exporting is how you keep it"))
    #expect(settings.contains("csv export is a copy hardset can read back in"))
    #expect(beforeExporting.contains("export a csv"))
    // The copy names CSV as the one restorable format; if that changes, so must the words.
    let restorable = DataTransferStore.Format.allCases.filter(\.restoresIntoHardset)
    #expect(restorable == [.csv])
    #expect(settings.contains("json and sqlite exports are for keeping and inspecting"))
  }

  @Test("It says to install over the old app, not after deleting it, and why that comes up")
  func installOverTheOldApp() {
    #expect(settings.contains("install new builds over the old app"))
    #expect(settings.contains("don't delete it first"))
    #expect(settings.contains("updating keeps your history"))
    #expect(settings.contains("free developer profile stop opening after 7 days"))
    #expect(beforeExporting.contains("install new builds over the old app"))
  }

  @Test("Every sentence is plain: no hedging word where a fact is stated")
  func noHedging() {
    for word in ["might", "may ", "could", "should", "probably", "try to"] {
      #expect(!settings.contains(word), Comment(rawValue: word))
      #expect(!beforeExporting.contains(word), Comment(rawValue: word))
    }
  }
}
