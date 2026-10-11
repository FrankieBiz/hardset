import Foundation
import Testing

@testable import HardsetCore

@Suite("Requests from outside the app start timers and workouts, never sets, and never guess")
struct SystemRequestsTests {
  let now = Date(timeIntervalSince1970: 60_000_000)

  private func rest(_ seconds: Double) -> Duration? {
    try? RestRequest.duration(seconds: seconds).get()
  }

  @Test("A rest in range comes back in whole seconds")
  func inRange() {
    #expect(rest(90) == .seconds(90))
    #expect(rest(15) == .seconds(15))
    #expect(rest(1800) == .seconds(1800))
  }

  /// 0.1 h is 360.00000000000006 s and 1.5 min is 90 s after conversion; neither may be refused.
  @Test("Floating-point noise from a unit conversion is whole seconds")
  func floatingNoiseIsWholeSeconds() {
    #expect(rest(0.1 * 3600) == .seconds(360))
    #expect(rest(1.5 * 60) == .seconds(90))
  }

  /// Review Focus: Siri hears "a ten second rest", a shortcut is given 45 minutes, a control
  /// carries a stale value. Each is refused with a sentence, never clamped to the nearest limit
  /// and never replaced by a default.
  @Test("Out of range, zero, negative or not a number is refused, not clamped")
  func outOfRangeRefusedNotClamped() {
    #expect(RestRequest.duration(seconds: 10) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 14.4) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 1801) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 1e300) == .failure(.outOfRange))
    #expect(RestRequest.duration(seconds: 0) == .failure(.notPositive))
    #expect(RestRequest.duration(seconds: -60) == .failure(.notPositive))
    #expect(RestRequest.duration(seconds: .nan) == .failure(.notANumber))
    #expect(RestRequest.duration(seconds: .infinity) == .failure(.notANumber))
    #expect(RestRequest.refusal == "A rest can be from 0:15 to 30:00.")
  }

  @Test("Start always replaces the rest, if its length is allowed")
  func startReplaces() {
    let running = RestTimerState.running(endsAt: now + 60)
    #expect(RestCommandPlan.outcome(for: .start(.seconds(120)), state: running, now: now)
      == .perform(.start(.seconds(120))))
    #expect(RestCommandPlan.outcome(for: .start(.seconds(5)), state: .idle, now: now)
      == .nothing(RestRequest.refusal))
  }

  @Test("Pause needs a rest that is still counting")
  func pause() {
    #expect(RestCommandPlan.outcome(for: .pause, state: .running(endsAt: now + 60), now: now)
      == .perform(.pause))
    #expect(RestCommandPlan.outcome(for: .pause, state: .running(endsAt: now - 1), now: now)
      == .nothing("That rest is already over."))
    #expect(RestCommandPlan.outcome(for: .pause, state: .paused(remaining: .seconds(30)), now: now)
      == .nothing("The rest is already paused."))
    #expect(RestCommandPlan.outcome(for: .pause, state: .idle, now: now) == .nothing("No rest is running."))
  }

  @Test("Resume needs a paused rest")
  func resume() {
    #expect(RestCommandPlan.outcome(for: .resume, state: .paused(remaining: .seconds(30)), now: now)
      == .perform(.resume))
    #expect(RestCommandPlan.outcome(for: .resume, state: .running(endsAt: now + 9), now: now)
      == .nothing("The rest is already running."))
    #expect(RestCommandPlan.outcome(for: .resume, state: .idle, now: now) == .nothing("No rest is running."))
  }

  @Test("Stop ends any rest, even one whose deadline just passed, and says so when there is none")
  func stop() {
    #expect(RestCommandPlan.outcome(for: .stop, state: .running(endsAt: now - 1), now: now) == .perform(.stop))
    #expect(RestCommandPlan.outcome(for: .stop, state: .paused(remaining: .seconds(5)), now: now) == .perform(.stop))
    #expect(RestCommandPlan.outcome(for: .stop, state: .idle, now: now) == .nothing("No rest is running."))
  }

  @Test("Siri confirms in plain words")
  func confirmations() {
    #expect(RestCommandPlan.confirmation(for: .start(.seconds(150))) == "Resting for 2:30.")
    #expect(RestCommandPlan.confirmation(for: .pause) == "Rest paused.")
    #expect(RestCommandPlan.confirmation(for: .resume) == "Rest resumed.")
    #expect(RestCommandPlan.confirmation(for: .stop) == "Rest skipped.")
  }

  private func state(
    ready: Bool = true, open: Bool = false, failed: Bool = false, firstRun: Bool = false
  ) -> WorkoutLaunchState {
    WorkoutLaunchState(isReady: ready, hasOpenWorkout: open, resumeFailed: failed, showsFirstRun: firstRun)
  }

  @Test("With nothing open, Start workout starts an empty one")
  func startsEmpty() {
    #expect(StartWorkoutPolicy.action(for: state()) == .startEmptyWorkout)
  }

  /// Review Focus: "Start a workout" said mid-workout, or with a workout that failed to reopen,
  /// must never put a second session on top of the first.
  @Test("An open workout is shown, never replaced")
  func openWorkoutIsShownNotReplaced() {
    #expect(StartWorkoutPolicy.action(for: state(open: true)) == .showOpenWorkout)
    #expect(StartWorkoutPolicy.action(for: state(open: true, firstRun: true)) == .showOpenWorkout)
  }

  @Test("A workout that could not be reopened blocks the start, as the Start button is blocked")
  func resumeFailureBlocksStart() {
    #expect(StartWorkoutPolicy.action(for: state(failed: true)) == .showResumeFailure)
    #expect(StartWorkoutPolicy.action(for: state(open: true, failed: true)) == .showResumeFailure)
  }

  /// Review Focus: on a cold launch the intent runs before the open workout has been read. The
  /// request waits in the inbox, and is acted on once, after the read.
  @Test("Before the launch read, the request waits; it is taken once")
  @MainActor
  func requestWaitsForLaunch() {
    let inbox = SystemRequestInbox()
    inbox.post(.startWorkout)
    inbox.post(.startWorkout)
    #expect(StartWorkoutPolicy.action(for: state(ready: false)) == .wait)
    #expect(inbox.pending == .startWorkout)
    #expect(StartWorkoutPolicy.action(for: state(open: true)) == .showOpenWorkout)
    #expect(inbox.take() == .startWorkout)
    #expect(inbox.take() == nil)
  }

  @Test("The first-run screen is seen before a requested workout starts")
  func firstRunFirst() {
    #expect(StartWorkoutPolicy.action(for: state(firstRun: true)) == .wait)
  }

  /// Review Focus: a control added without choosing a length starts nothing.
  @Test("An unconfigured or stale Rest control asks for a choice instead of starting a rest")
  func unconfiguredControlStartsNothing() {
    #expect(RestControlState.make(configuredSeconds: nil) == .needsChoice)
    #expect(RestControlState.make(configuredSeconds: 5) == .needsChoice)
    #expect(RestControlState.make(configuredSeconds: 3600) == .needsChoice)
    #expect(RestControlState.make(configuredSeconds: 120) == .ready(.seconds(120)))
    #expect(RestControlState.make(configuredSeconds: 120).title == "Rest · 2:00")
    #expect(RestControlState.needsChoice.title == "Rest · Choose")
  }
}
