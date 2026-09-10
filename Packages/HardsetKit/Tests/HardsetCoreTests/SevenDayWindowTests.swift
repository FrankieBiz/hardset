import Foundation
import Testing

@testable import HardsetCore

@Suite("A seven-day volume window has one unambiguous boundary")
struct SevenDayWindowTests {
  private let ending = Date(timeIntervalSince1970: 12_000_000)

  @Test("The lower boundary is exactly seven days before the exclusive upper boundary")
  func hasSevenDaySpan() {
    let window = SevenDayWindow(endingAt: ending)
    #expect(window.startingAt.timeIntervalSince(window.endingAt) == -SevenDayWindow.duration)
  }

  @Test("Neighbouring windows touch but never overlap")
  func neighbouringWindowsShareOneBoundary() {
    let current = SevenDayWindow(endingAt: ending)
    let previous = current.shifted(byWeeks: -1)

    #expect(previous.endingAt == current.startingAt)
    #expect(previous.startingAt < previous.endingAt)
    #expect(current.startingAt < current.endingAt)
  }

  @Test("Moving back and forward returns to the exact captured window")
  func roundTrips() {
    let current = SevenDayWindow(endingAt: ending)
    #expect(current.shifted(byWeeks: -3).shifted(byWeeks: 3) == current)
  }
}
