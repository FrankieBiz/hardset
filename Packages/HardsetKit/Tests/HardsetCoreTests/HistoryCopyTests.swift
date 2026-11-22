import Foundation
import Testing

@testable import HardsetCore

@Suite("History's search words say what was searched and what was found")
struct HistoryCopyTests {
  @Test("The subtitle counts matches, and says when it shows a page of them")
  func subtitle() {
    #expect(HistoryCopy.searchSubtitle(query: "bench", shown: 1, total: 1) == "1 workout matches “bench”")
    #expect(HistoryCopy.searchSubtitle(query: "bench", shown: 7, total: 7)
      == "7 workouts match “bench”, newest first")
    #expect(HistoryCopy.searchSubtitle(query: "bench", shown: 50, total: 120)
      == "Latest 50 of 120 workouts match “bench”")
  }

  @Test("No match is a statement that names the words searched, not a blank screen")
  func noMatch() {
    #expect(HistoryCopy.noMatchTitle(for: "deadlift") == "No workouts match “deadlift”")
    #expect(HistoryCopy.noMatchDetail.contains("movement, machine and gym"))
  }

  @Test("A failed search says history is safe")
  func failure() {
    #expect(HistoryCopy.searchFailedDetail.contains("safe"))
  }

  /// The prompt names what search reads, so a lifter does not type a workout title and wonder why
  /// nothing is found.
  @Test("The prompt names the three things search reads")
  func prompt() {
    for word in ["movement", "machine", "gym"] {
      #expect(HistoryCopy.searchPrompt.contains(word))
    }
  }
}
