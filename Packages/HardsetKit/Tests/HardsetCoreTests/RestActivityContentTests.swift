import Foundation
import Testing

@testable import HardsetCore

@Suite("The Lock Screen rest never draws a range it cannot hold, and names what it is resting for")
struct RestActivityContentTests {
  let t = Date(timeIntervalSince1970: 50_000_000)
  let legPress = RestMetadata(
    exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4,
    machineName: "Hammer Strength Leg Press")

  private func range(_ content: RestActivityContent) throws -> ClosedRange<Date> {
    guard case .counting(let range) = content.phase else {
      Issue.record("expected a countdown, got \(content.phase)")
      throw CancellationError()
    }
    return range
  }

  @Test("A fresh countdown runs from its start to its deadline, with Pause and Skip")
  func freshCountdown() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: 120, previouslyElapsed: 0, startDate: t, fireDate: t + 120),
      metadata: legPress)
    #expect(try range(content) == t...(t + 120))
    #expect(content.controls == [.pause, .stop])
    #expect(content.statusText == nil)
  }

  /// Review Focus: the old widget built `Date.now...fireDate`, which traps once the deadline has
  /// passed. Nothing here reads the clock, and a start after the deadline (a clock change, a total
  /// of zero) still yields a valid range that ends at the deadline.
  @Test("A start after the deadline never reverses the range")
  func renderAfterDeadlineNeverReverses() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: 0, previouslyElapsed: 0, startDate: t + 300, fireDate: t),
      metadata: nil)
    let r = try range(content)
    #expect(r.lowerBound <= r.upperBound)
    #expect(r.upperBound == t)
  }

  @Test("A zero-length countdown is a single instant, not a crash")
  func zeroLengthCountdown() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: 0, previouslyElapsed: 0, startDate: t, fireDate: t), metadata: nil)
    #expect(try range(content) == t...t)
  }

  @Test("A total that is not a number falls back to the start date")
  func nonFiniteTotal() throws {
    let content = RestActivityContent.make(
      mode: .countdown(total: .nan, previouslyElapsed: .infinity, startDate: t, fireDate: t + 60),
      metadata: nil)
    #expect(try range(content) == t...(t + 60))
  }

  @Test("After a resume the ring still covers the whole rest, elapsed part included")
  func resumedAlarmRingCoversWholeRest() throws {
    // 120 s rest, paused after 30 s, resumed at t: AlarmKit reports startDate t, fire t + 90.
    let content = RestActivityContent.make(
      mode: .countdown(total: 120, previouslyElapsed: 30, startDate: t, fireDate: t + 90),
      metadata: legPress)
    #expect(try range(content) == (t - 30)...(t + 90))
  }

  @Test("Paused shows what is left and how much of the ring remains, with Resume and Skip")
  func pausedRemainder() {
    let content = RestActivityContent.make(
      mode: .paused(total: 120, previouslyElapsed: 30), metadata: legPress)
    #expect(content.phase == .paused(remaining: .seconds(90), fractionRemaining: 0.75))
    #expect(content.controls == [.resume, .stop])
    #expect(content.statusText == "Paused, 1:30 left")
  }

  @Test("A paused remainder stays between nothing and the whole rest")
  func pausedFractionClamped() {
    let over = RestActivityContent.make(mode: .paused(total: 120, previouslyElapsed: 150), metadata: nil)
    #expect(over.phase == .paused(remaining: .zero, fractionRemaining: 0))
    let under = RestActivityContent.make(mode: .paused(total: 120, previouslyElapsed: -10), metadata: nil)
    #expect(under.phase == .paused(remaining: .seconds(120), fractionRemaining: 1))
    let empty = RestActivityContent.make(mode: .paused(total: 0, previouslyElapsed: 0), metadata: nil)
    #expect(empty.phase == .paused(remaining: .zero, fractionRemaining: 0))
  }

  @Test("An alerting rest is finished and offers nothing; the system's alert has its own stop")
  func alertingIsFinished() {
    let content = RestActivityContent.make(mode: .alerting, metadata: legPress)
    #expect(content.phase == .finished)
    #expect(content.controls.isEmpty)
    #expect(content.statusText == "Rest over")
  }

  @Test("The movement leads, then the set and the machine")
  func namesTheMachine() {
    let content = RestActivityContent.make(mode: .alerting, metadata: legPress)
    #expect(content.title == "Leg Press")
    #expect(content.detail == "Set 2 of 4 · Hammer Strength Leg Press")
  }

  @Test("Without a machine the set alone; without a set at all, just Rest")
  func fallbacks() {
    let free = RestMetadata(exerciseName: "Squat", setOrdinal: 1)
    #expect(RestActivityContent.make(mode: .alerting, metadata: free).detail == "Set 1")
    let bare = RestActivityContent.make(mode: .alerting, metadata: nil)
    #expect(bare.title == "Rest")
    #expect(bare.detail == nil)
    let blank = RestMetadata(exerciseName: "   ", setOrdinal: 3, machineName: " ")
    #expect(RestActivityContent.make(mode: .alerting, metadata: blank).title == "Rest")
    #expect(RestActivityContent.make(mode: .alerting, metadata: blank).detail == "Set 3")
  }

  @Test("Every control has a title, a glyph and words for VoiceOver")
  func controlsAreLabelled() {
    for control in RestActivityContent.Control.allCases {
      #expect(!control.title.isEmpty)
      #expect(!control.symbolName.isEmpty)
      #expect(control.spokenLabel.lowercased().contains("rest"))
    }
    #expect(RestActivityContent.Control.stop.title == "Skip")
  }
}
