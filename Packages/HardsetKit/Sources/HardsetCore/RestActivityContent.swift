import Foundation

/// What the Lock Screen and the Dynamic Island show for a rest, decided where a test can see it.
///
/// A mirror of AlarmKit's presentation state rather than the type itself, because AlarmKit exists
/// only in the iPhoneOS SDK. The widget maps `AlarmPresentationState.Mode` into `Mode` and draws
/// what comes back, so the rules that can crash or mislead live here:
///
/// - A `ClosedRange<Date>` traps when its lower bound is after its upper. The widget used to build
///   `Date.now...fireDate`, which traps whenever the system renders the activity after the
///   deadline. `Phase.counting` never holds a reversed range, and its bounds do not depend on now.
/// - The ring covers the alarm's whole countdown, including time that elapsed before a pause, so a
///   resumed rest does not restart the ring from full.
public struct RestActivityContent: Hashable, Sendable {
  /// AlarmKit's `AlarmPresentationState.Mode`, reduced to plain values.
  public enum Mode: Hashable, Sendable {
    /// `Mode.Countdown`: `totalCountdownDuration`, `previouslyElapsedDuration`, `startDate`,
    /// `fireDate`.
    case countdown(
      total: TimeInterval, previouslyElapsed: TimeInterval, startDate: Date, fireDate: Date)
    /// `Mode.Paused`: `totalCountdownDuration` and `previouslyElapsedDuration`. No dates exist.
    case paused(total: TimeInterval, previouslyElapsed: TimeInterval)
    /// `Mode.Alert`: the rest is over and the system is sounding it.
    case alerting
  }

  public enum Phase: Hashable, Sendable {
    /// Counting down to `range.upperBound`. The ring (`ProgressView(timerInterval:)`) and the
    /// clock (`Text(timerInterval:)`) both take this one range.
    case counting(range: ClosedRange<Date>)
    /// Frozen, with `fractionRemaining` in 0...1 for a still ring.
    case paused(remaining: Duration, fractionRemaining: Double)
    case finished
  }

  /// A button the activity offers. Each one runs a `LiveActivityIntent` in the app's process, so
  /// the app pauses, resumes or ends its own rest and always knows what is left.
  public enum Control: String, Hashable, Sendable, CaseIterable {
    case pause
    case resume
    /// Ends the rest now, as the in-app Skip does. `StopRestIntent` performs it.
    case stop

    public var title: String {
      switch self {
      case .pause: "Pause"
      case .resume: "Resume"
      case .stop: "Skip"
      }
    }

    public var symbolName: String {
      switch self {
      case .pause: "pause.fill"
      case .resume: "play.fill"
      case .stop: "forward.end.fill"
      }
    }

    /// For VoiceOver, which has no countdown beside the button to explain it.
    public var spokenLabel: String {
      switch self {
      case .pause: "Pause rest"
      case .resume: "Resume rest"
      case .stop: "Skip rest"
      }
    }
  }

  /// The movement, or "Rest" for a rest that no set started (Siri, a control).
  public let title: String
  /// "Set 2 of 4 · Hammer Strength Leg Press", or nil when nothing more is known.
  public let detail: String?
  public let phase: Phase
  public let controls: [Control]

  public init(title: String, detail: String?, phase: Phase, controls: [Control]) {
    self.title = title
    self.detail = detail
    self.phase = phase
    self.controls = controls
  }

  /// A line for the paused and finished states, where no system clock speaks for itself.
  public var statusText: String? {
    switch phase {
    case .counting: nil
    case .paused(let remaining, _): "Paused, \(remaining.clockString) left"
    case .finished: "Rest over"
    }
  }

  public static func make(mode: Mode, metadata: RestMetadata?) -> RestActivityContent {
    let phase: Phase
    let controls: [Control]
    switch mode {
    case .countdown(let total, _, let startDate, let fireDate):
      phase = .counting(range: countingRange(total: total, startDate: startDate, fireDate: fireDate))
      controls = [.pause, .stop]
    case .paused(let total, let elapsed):
      let total = max(0, finite(total))
      let remaining = min(total, max(0, total - finite(elapsed)))
      phase = .paused(
        remaining: .seconds(remaining), fractionRemaining: total > 0 ? remaining / total : 0)
      controls = [.resume, .stop]
    case .alerting:
      // The system draws the alert and its own stop button. Nothing here would mean anything.
      phase = .finished
      controls = []
    }
    return RestActivityContent(
      title: title(for: metadata), detail: detail(for: metadata), phase: phase, controls: controls)
  }

  /// From the moment the whole countdown would have begun to the deadline.
  ///
  /// `fireDate - total` rather than `startDate`, because after a system resume `startDate` is the
  /// resume and the elapsed part would vanish from the ring. With no usable total the start date
  /// stands in, and the lower bound is never later than the deadline either way.
  static func countingRange(total: TimeInterval, startDate: Date, fireDate: Date) -> ClosedRange<
    Date
  > {
    let total = finite(total)
    let start = total > 0 ? fireDate.addingTimeInterval(-total) : startDate
    return min(start, fireDate)...fireDate
  }

  private static func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }

  private static func title(for metadata: RestMetadata?) -> String {
    let name = metadata?.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? "Rest" : name
  }

  private static func detail(for metadata: RestMetadata?) -> String? {
    guard let metadata else { return nil }
    let machine = metadata.machineName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return [metadata.setLabel, machine].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: " · ")
  }
}
