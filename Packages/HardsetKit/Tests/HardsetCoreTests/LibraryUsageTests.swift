import Foundation
import Testing

@testable import HardsetCore

@Suite("The Library says how much was logged, never how much should be")
struct LibraryUsageTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private let now = Date(timeIntervalSince1970: 1_700_000_000 + 12 * 3_600)

  private func ago(days: Int) -> Date {
    now.addingTimeInterval(Double(-days) * 86_400)
  }

  private func line(_ usage: LibraryUsage) -> String? {
    usage.line(now: now, calendar: calendar)
  }

  private func spoken(_ usage: LibraryUsage) -> String? {
    usage.spokenLine(now: now, calendar: calendar)
  }

  @Test("Native sets read as a count and a last-done phrase in LastDoneText's words")
  func nativeOnly() {
    #expect(
      line(LibraryUsage(workingSets: 38, importedSets: 0, lastDoneAt: ago(days: 12)))
        == "38 working sets · last done 12 days ago")
    #expect(
      line(LibraryUsage(workingSets: 1, importedSets: 0, lastDoneAt: now))
        == "1 working set · last done today")
    #expect(
      line(LibraryUsage(workingSets: 2, importedSets: 0, lastDoneAt: ago(days: 1)))
        == "2 working sets · last done yesterday")
    #expect(
      line(LibraryUsage(workingSets: 5, importedSets: 0, lastDoneAt: ago(days: 21)))
        == "5 working sets · last done 3 weeks ago")
  }

  @Test("Imported sets are a separate count, never added to the native one")
  func nativeAndImported() {
    #expect(
      line(LibraryUsage(workingSets: 38, importedSets: 42, lastDoneAt: ago(days: 12)))
        == "38 working sets · last done 12 days ago · 42 imported sets")
    #expect(
      spoken(LibraryUsage(workingSets: 1, importedSets: 1, lastDoneAt: now))
        == "1 working set, last done today, 1 imported set")
  }

  @Test("Imported-only history is a count with no last-done claim")
  func importedOnly() {
    let usage = LibraryUsage(workingSets: 0, importedSets: 42, lastDoneAt: nil)
    #expect(line(usage) == "42 imported sets")
    #expect(spoken(usage) == "42 imported sets")
    #expect(line(LibraryUsage(workingSets: 0, importedSets: 1, lastDoneAt: nil))
      == "1 imported set")
    #expect(line(usage)?.contains("last done") == false)
    #expect(line(usage)?.contains("today") == false)
  }

  @Test("Nothing logged draws nothing at all")
  func bothCountsZero() {
    let usage = LibraryUsage(workingSets: 0, importedSets: 0, lastDoneAt: nil)
    #expect(line(usage) == nil)
    #expect(spoken(usage) == nil)
  }

  @Test("A future-only movement is a count with no timing claim, never today and never negative")
  func futureOnly() {
    let upcoming = LibraryUsage(workingSets: 38, importedSets: 0, lastDoneAt: nil)
    #expect(line(upcoming) == "38 working sets")
    #expect(spoken(upcoming) == "38 working sets")
    #expect(line(upcoming)?.contains("today") == false)
    #expect(line(upcoming)?.contains("last done") == false)
    #expect(line(upcoming)?.contains("-") == false)

    // The store never hands over a future last-done (D31), but the line must not clamp one to
    // "today" if it ever did.
    let future = LibraryUsage(
      workingSets: 38, importedSets: 0, lastDoneAt: now.addingTimeInterval(86_400))
    #expect(line(future) == "38 working sets")
    #expect(line(future)?.contains("today") == false)
  }

  @Test("The spoken form turns the middle dots into commas and keeps every phrase")
  func spokenForm() {
    #expect(
      spoken(LibraryUsage(workingSets: 38, importedSets: 42, lastDoneAt: ago(days: 12)))
        == "38 working sets, last done 12 days ago, 42 imported sets")
    #expect(
      spoken(LibraryUsage(workingSets: 38, importedSets: 0, lastDoneAt: ago(days: 12)))
        == "38 working sets, last done 12 days ago")
    #expect(spoken(LibraryUsage(workingSets: 0, importedSets: 0, lastDoneAt: ago(days: 12))) == nil)
  }

  @Test("No line can carry a word that judges the lifter")
  func forbiddenWords() {
    let usages = [
      LibraryUsage(workingSets: 38, importedSets: 0, lastDoneAt: ago(days: 12)),
      LibraryUsage(workingSets: 1, importedSets: 0, lastDoneAt: now),
      LibraryUsage(workingSets: 38, importedSets: 42, lastDoneAt: ago(days: 12)),
      LibraryUsage(workingSets: 0, importedSets: 42, lastDoneAt: nil),
      LibraryUsage(workingSets: 38, importedSets: 0, lastDoneAt: nil),
      LibraryUsage(workingSets: 0, importedSets: 0, lastDoneAt: nil),
    ]
    let forbidden = [
      "should", "recommend", "aim for", "ideal", "goal", "target", "neglect", "missed",
      "behind", "catch up", "enough", "streak",
    ]
    for usage in usages {
      for text in [line(usage), spoken(usage)].compactMap({ $0 }) {
        let lowered = text.lowercased()
        for word in forbidden {
          #expect(!lowered.contains(word), "\(text) must not contain \(word)")
        }
      }
    }
  }
}
