import Foundation
import Testing

@testable import HardsetCore

/// Invariant 2: rest is an absolute deadline or a frozen remainder, never a countdown, and
/// never both at once.
@Suite("Rest state is a date, never a countdown")
struct RestTimerStateTests {
  let now = Date(timeIntervalSince1970: 2_000_000)

  @Test("A row with both a deadline and a remainder is rejected as corruption")
  func bothSetIsRejected() {
    #expect(throws: RestTimerStateError.bothDeadlineAndRemainingSet) {
      try RestTimerState(endsAt: now, pausedRemainingSeconds: 30)
    }
  }

  @Test("Each state round-trips through its two-column storage form")
  func storageRoundTrip() throws {
    let cases: [RestTimerState] = [
      .idle,
      .running(endsAt: now.addingTimeInterval(90)),
      .paused(remaining: .seconds(45)),
    ]
    for state in cases {
      let (endsAt, paused) = state.storage
      let restored = try RestTimerState(endsAt: endsAt, pausedRemainingSeconds: paused)
      #expect(restored == state, "\(state) did not survive the round trip")
    }
  }

  @Test("Storage never emits both columns at once, for any state")
  func storageNeverEmitsBoth() {
    let cases: [RestTimerState] = [
      .idle, .running(endsAt: now), .paused(remaining: .seconds(10)),
    ]
    for state in cases {
      let (endsAt, paused) = state.storage
      #expect(!(endsAt != nil && paused != nil))
    }
  }

  @Test("A negative stored remainder is rejected")
  func negativeRemainderRejected() {
    #expect(throws: RestTimerStateError.negativeRemaining) {
      try RestTimerState(endsAt: nil, pausedRemainingSeconds: -5)
    }
  }

  @Test("Remaining time is measured against the clock, not stored and decremented")
  func remainingIsComputed() {
    let state = RestTimerState.running(endsAt: now.addingTimeInterval(60))
    #expect(state.remaining(at: now) == .seconds(60))
    #expect(state.remaining(at: now.addingTimeInterval(30)) == .seconds(30))
    // Clamped, never negative -- an overdue timer reads zero, not -12.
    #expect(state.remaining(at: now.addingTimeInterval(90)) == .seconds(0))
  }

  @Test("Pausing then resuming preserves the remaining time")
  func pauseResumePreservesRemaining() {
    let running = RestTimerState.running(endsAt: now.addingTimeInterval(100))
    let paused = running.paused(at: now.addingTimeInterval(40))
    #expect(paused == .paused(remaining: .seconds(60)))

    let resumed = paused.resumed(at: now.addingTimeInterval(500))
    #expect(resumed.remaining(at: now.addingTimeInterval(500)) == .seconds(60))
  }

  /// AlarmKit cannot alter a running countdown, so +/-15 s is cancel-and-reschedule. The
  /// state maths still has to be right, including at the clamp.
  @Test("Adjusting a deadline never lands it in the past")
  func adjustmentClampsToNow() {
    let state = RestTimerState.running(endsAt: now.addingTimeInterval(10))
    let shrunk = state.adjusted(by: .seconds(-15), at: now)
    #expect(shrunk == .running(endsAt: now))
  }

  @Test("Adjusting a paused timer moves the remainder, not a deadline")
  func adjustPaused() {
    let paused = RestTimerState.paused(remaining: .seconds(30))
    #expect(paused.adjusted(by: .seconds(15), at: now) == .paused(remaining: .seconds(45)))
    #expect(paused.adjusted(by: .seconds(-60), at: now) == .paused(remaining: .seconds(0)))
  }

  @Test("An idle timer ignores adjustment")
  func idleIgnoresAdjustment() {
    #expect(RestTimerState.idle.adjusted(by: .seconds(15), at: now) == .idle)
  }

  /// A paused timer can reach zero -- pause with a second left and adjust it down, or pause exactly
  /// at the end. Resuming that used to produce a running timer whose deadline had already passed:
  /// nothing would schedule an alarm for it and nothing would end it, so the bar sat at zero
  /// claiming to be running.
  @Test("Resuming a paused timer with nothing left ends it rather than running it at zero")
  func resumingAnExhaustedPauseGoesIdle() {
    let exhausted = RestTimerState.paused(remaining: .seconds(0))
    #expect(exhausted.resumed(at: now) == .idle)

    // And a negative remainder, which `adjusted` clamps but a stored row could still hold.
    #expect(RestTimerState.paused(remaining: .seconds(-5)).resumed(at: now) == .idle)
  }

  @Test("Resuming a paused timer with time left still runs")
  func resumingALivePauseRuns() {
    let paused = RestTimerState.paused(remaining: .seconds(30))
    let resumed = paused.resumed(at: now)
    #expect(resumed.isRunning)
    #expect(resumed.remaining(at: now)?.seconds == 30)
  }
}
