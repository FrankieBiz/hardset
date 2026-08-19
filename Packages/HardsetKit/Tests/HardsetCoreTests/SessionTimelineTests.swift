import Foundation
import Testing

@testable import HardsetCore

/// Invariant 1: duration is derived from two immutable instants, never stored and never
/// recomputed against the wall clock.
@Suite("Session duration is derived, never stored")
struct SessionTimelineTests {
  let start = Date(timeIntervalSince1970: 1_000_000)

  @Test("An open session has no duration at all")
  func openSessionHasNoDuration() {
    let timeline = SessionTimeline(startedAt: start)
    #expect(timeline.duration == nil)
    #expect(timeline.isOpen)
  }

  /// The regression that produced 9,749-minute workouts: elapsed time was read against
  /// `Date()` while rendering, so an abandoned session grew forever. Here the value cannot
  /// depend on when it is asked, because there is nothing to ask.
  @Test("Duration of an open session does not drift as time passes")
  func openSessionDoesNotDrift() {
    let timeline = SessionTimeline(startedAt: start)
    let first = timeline.duration
    let later = timeline.duration
    #expect(first == nil)
    #expect(later == nil)
    #expect(first == later)
  }

  @Test("A finished session's duration is exactly the span between the two instants")
  func finishedDuration() throws {
    var timeline = SessionTimeline(startedAt: start)
    try timeline.finish(at: start.addingTimeInterval(3_600))
    #expect(timeline.duration == .seconds(3_600))
    #expect(!timeline.isOpen)
  }

  @Test("The same timeline reports the same duration every time it is asked")
  func durationIsStable() throws {
    var timeline = SessionTimeline(startedAt: start)
    try timeline.finish(at: start.addingTimeInterval(1_800))
    #expect(timeline.duration == timeline.duration)
  }

  @Test("Finishing twice is refused, so finishedAt cannot drift")
  func cannotFinishTwice() throws {
    var timeline = SessionTimeline(startedAt: start)
    try timeline.finish(at: start.addingTimeInterval(60))
    #expect(throws: SessionTimelineError.alreadyFinished) {
      try timeline.finish(at: start.addingTimeInterval(120))
    }
  }

  @Test("Finishing before starting is refused")
  func cannotFinishBeforeStart() {
    var timeline = SessionTimeline(startedAt: start)
    #expect(throws: SessionTimelineError.finishedBeforeStart) {
      try timeline.finish(at: start.addingTimeInterval(-1))
    }
  }

  @Test("A session longer than any real workout is flagged rather than displayed")
  func implausibleIsFlagged() throws {
    var absurd = SessionTimeline(startedAt: start)
    try absurd.finish(at: start.addingTimeInterval(9_749 * 60))
    #expect(absurd.isImplausible)

    var normal = SessionTimeline(startedAt: start)
    try normal.finish(at: start.addingTimeInterval(75 * 60))
    #expect(!normal.isImplausible)
  }
}
