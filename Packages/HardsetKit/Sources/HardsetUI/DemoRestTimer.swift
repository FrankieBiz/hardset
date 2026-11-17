import HardsetCore
import Observation
import SwiftUI

/// A rest countdown that lives only in memory, for the places that show the real rest bar without
/// a workout behind it: the pitch page and the guided tour.
///
/// It uses the same `RestTimerState` the real timer does, so `RestBarView` draws it exactly as it
/// draws the real one, but it schedules no alarm and writes nothing, and it never touches the
/// lifter's own rest. It restarts itself when it runs out, or when skipped, so a demo that is left
/// alone keeps showing a countdown rather than an empty bar.
@MainActor
@Observable
public final class DemoRestTimer {
  public private(set) var state: RestTimerState
  /// Counts every command the lifter gives, so a view can play a haptic for each one.
  public private(set) var commands = 0

  private let startingDuration: Duration

  /// - Parameters:
  ///   - startingDuration: How long each demo rest runs. 90 seconds, as the pitch copy says.
  ///   - initialState: Defaults to a rest just started; a capture passes a paused state so its text
  ///     does not change while the image is taken.
  public init(startingDuration: Duration = .seconds(90), initialState: RestTimerState? = nil) {
    self.startingDuration = startingDuration
    self.state = initialState ?? .running(endsAt: Date().addingTimeInterval(startingDuration.seconds))
  }

  /// Starts a fresh rest.
  public func restart() {
    state = .running(endsAt: Date().addingTimeInterval(startingDuration.seconds))
  }

  /// Nudges the rest by `delta` with the engine's own rule, so −15 and +15 behave as they do on
  /// the real timer.
  public func adjust(by delta: Duration) {
    commands += 1
    state = state.adjusted(by: delta, at: Date())
  }

  public func pauseOrResume() {
    commands += 1
    switch state {
    case .running: state = state.paused(at: Date())
    case .paused: state = state.resumed(at: Date())
    case .idle: restart()
    }
  }

  /// Skipping a demo rest starts the next one, so the bar is never left empty.
  public func skip() {
    commands += 1
    restart()
  }

  /// Starts again if a running rest has run out. Called on a slow tick by the view that shows it.
  public func restartIfElapsed() {
    if state.hasElapsed(at: Date()) { restart() }
  }
}
