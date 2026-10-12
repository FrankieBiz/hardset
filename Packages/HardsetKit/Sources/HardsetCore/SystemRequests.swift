import Foundation
// Explicit: on Apple platforms `@Observable` arrives transitively, on Linux it does not.
import Observation

// What Siri, Shortcuts, Spotlight, the Action button, Control Center and the Lock Screen may ask
// of Hardset, and what each request does. None of them can log a set: the lifter must see the
// numbers being saved (spec §4). They can start a workout (in the app, on screen), and start,
// pause, resume or end a rest. Nothing here takes a weight or a rep count.

/// Why a rest asked for from outside the app was refused.
public enum RestRequestError: Error, Hashable, Sendable {
  case notANumber
  case notPositive
  case outOfRange
}

/// Turns a duration a person said or configured into a rest, or refuses it.
public enum RestRequest {
  /// The rest asked for, in whole seconds, if it lies in `RestPlan.allowedRange`.
  ///
  /// Required, never defaulted: there is no rest the app may assume (`HANDOFF.md` §6). Rounded to
  /// the nearest second only to absorb floating-point noise from unit conversion (0.1 h is
  /// 360.00000000000006 s); outside the range it is refused, not clamped, as a typed rest is.
  public static func duration(seconds: Double) -> Result<Duration, RestRequestError> {
    guard seconds.isFinite else { return .failure(.notANumber) }
    let whole = seconds.rounded()
    guard whole > 0 else { return .failure(.notPositive) }
    let range = RestPlan.allowedRange
    // Compared as Doubles first, so a huge value never reaches an integer conversion.
    guard whole >= range.lowerBound.seconds, whole <= range.upperBound.seconds,
      let rest = RestPlan.validated(.seconds(Int64(whole)))
    else { return .failure(.outOfRange) }
    return .success(rest)
  }

  /// What Siri says, or a shortcut shows, when a rest is refused.
  public static var refusal: String {
    "A rest can be from \(RestPlan.allowedRange.lowerBound.clockString) "
      + "to \(RestPlan.allowedRange.upperBound.clockString)."
  }
}

/// Something done to the rest timer from outside the app.
public enum RestCommand: Hashable, Sendable {
  case start(Duration)
  case pause
  case resume
  /// Ends the rest now, as the in-app Skip does.
  case stop
}

public enum RestCommandOutcome: Hashable, Sendable {
  case perform(RestCommand)
  /// Nothing to do, and the sentence that says why.
  case nothing(String)
}

/// Decides what a rest command does to the rest that is really running.
///
/// The caller must have reconciled the timer first: an intent can launch the app in the
/// background, where the controller reads idle until it has looked at AlarmKit.
public enum RestCommandPlan {
  public static let noRest = "No rest is running."
  /// Said instead of `noRest` when AlarmKit could not be read, so "idle" may be wrong.
  public static let couldNotCheck =
    "The rest timer could not be checked. Open Hardset and try again."

  /// - Parameter alarmsUnreadable: The timer's last look at AlarmKit failed. An idle state is
  ///   then not known to be idle (a cold launch reads idle until it has looked), so nothing is
  ///   done and the sentence says so. A rest the timer already holds is still planned against.
  public static func outcome(
    for command: RestCommand, state: RestTimerState, now: Date, alarmsUnreadable: Bool = false
  ) -> RestCommandOutcome {
    if alarmsUnreadable, state == .idle { return .nothing(couldNotCheck) }
    switch command {
    case .start(let duration):
      // A new rest replaces the current one: the lifter asked for it by name.
      return RestPlan.validated(duration) == nil ? .nothing(RestRequest.refusal) : .perform(command)
    case .pause:
      switch state {
      case .idle: return .nothing(noRest)
      case .paused: return .nothing("The rest is already paused.")
      case .running: return state.hasElapsed(at: now) ? .nothing("That rest is already over.") : .perform(command)
      }
    case .resume:
      switch state {
      case .idle: return .nothing(noRest)
      case .running: return .nothing("The rest is already running.")
      case .paused: return .perform(command)
      }
    case .stop:
      return state == .idle ? .nothing(noRest) : .perform(command)
    }
  }

  /// What Siri says once a command has been carried out.
  public static func confirmation(for command: RestCommand) -> String {
    switch command {
    case .start(let duration): "Resting for \(duration.clockString)."
    case .pause: "Rest paused."
    case .resume: "Rest resumed."
    case .stop: "Rest skipped."
    }
  }
}

/// What the app knows, at the moment a "Start workout" request arrives.
public struct WorkoutLaunchState: Hashable, Sendable {
  /// The launch read (resume an open workout) has run. Before it, nothing is known.
  public var isReady: Bool
  public var hasOpenWorkout: Bool
  /// A workout may be open but could not be read.
  public var resumeFailed: Bool
  public var showsFirstRun: Bool

  public init(isReady: Bool, hasOpenWorkout: Bool, resumeFailed: Bool, showsFirstRun: Bool) {
    self.isReady = isReady
    self.hasOpenWorkout = hasOpenWorkout
    self.resumeFailed = resumeFailed
    self.showsFirstRun = showsFirstRun
  }
}

public enum StartWorkoutAction: Hashable, Sendable {
  /// Keep the request until the app can act on it.
  case wait
  case startEmptyWorkout
  case showOpenWorkout
  case showResumeFailure
}

/// "Start a workout" from Siri, Spotlight, the Action button or Control Center.
///
/// It never starts a second workout over the first. A workout that could not be reopened blocks it
/// exactly as it blocks the Start button (Phase 1: an open session must never look like "no
/// workout"), and the first-run screen is seen before anything starts.
public enum StartWorkoutPolicy {
  public static func action(for state: WorkoutLaunchState) -> StartWorkoutAction {
    guard state.isReady else { return .wait }
    if state.resumeFailed { return .showResumeFailure }
    if state.hasOpenWorkout { return .showOpenWorkout }
    if state.showsFirstRun { return .wait }
    return .startEmptyWorkout
  }
}

/// A request that needs the app's screen.
///
/// One case on purpose. Rest commands go straight to the timer; nothing that logs, edits or
/// finishes a workout may arrive from outside the app.
public enum SystemRequest: Hashable, Sendable {
  case startWorkout
}

/// Holds a request from outside the app until the root view can act on it.
///
/// An intent can run before any view exists (a cold launch), so the request waits here rather than
/// being handed to a view that is not there. One slot: asking twice starts one workout.
@MainActor
@Observable
public final class SystemRequestInbox {
  public private(set) var pending: SystemRequest?

  public init() {}

  public func post(_ request: SystemRequest) {
    pending = request
  }

  /// The pending request, removed. Call only when acting on it; a request the app must wait on
  /// stays where it is.
  public func take() -> SystemRequest? {
    defer { pending = nil }
    return pending
  }
}

/// The Rest control in Control Center, from the duration the lifter configured when adding it.
public enum RestControlState: Hashable, Sendable {
  case ready(Duration)
  /// Not configured, or configured with a duration that is no longer allowed. Tapping it starts
  /// nothing: it never starts a rest of a length nobody chose.
  case needsChoice

  public static func make(configuredSeconds: Double?) -> RestControlState {
    guard let configuredSeconds,
      case .success(let rest) = RestRequest.duration(seconds: configuredSeconds)
    else { return .needsChoice }
    return .ready(rest)
  }

  /// The control's label, in the same words as the rest chip.
  public var title: String {
    switch self {
    case .ready(let rest): "Rest · \(rest.clockString)"
    case .needsChoice: "Rest · Choose"
    }
  }
}
