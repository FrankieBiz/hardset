import Foundation

/// The two things worth pointing out, once, and nothing else (spec 4.7).
///
/// Each names a control and what it does. None says what to lift, how much, or how often: a tip
/// that coaches is a target in disguise (`HANDOFF.md` §6), and a test holds the copy to that.
public enum FeatureTip: String, CaseIterable, Hashable, Sendable {
  /// The machine chip on a movement: loads are kept per machine.
  case machineChip
  /// A movement's name: it opens that movement's load history.
  case movementHistory

  public var title: String {
    switch self {
    case .machineChip: "Which machine?"
    case .movementHistory: "Its history"
    }
  }

  public var message: String {
    switch self {
    case .machineChip:
      "Tap the machine chip to pick the one you're on. Loads are kept per machine."
    case .movementHistory:
      "Tap a movement's name to see every load you've logged on it, machine by machine."
    }
  }

  public var symbolName: String {
    switch self {
    case .machineChip: "dumbbell"
    case .movementHistory: "chart.xyaxis.line"
    }
  }
}

/// What the live workout shows right now, as far as tips are concerned.
public struct FeatureTipFacts: Hashable, Sendable {
  /// A machine chip exists only when the workout has a gym.
  public var sessionHasGym: Bool
  public var hasMovementOnScreen: Bool
  /// A movement on screen has history to open.
  public var movementWithHistoryOnScreen: Bool
  /// The keypad is up. Nothing may cover the numbers being typed.
  public var isEnteringNumbers: Bool

  public init(
    sessionHasGym: Bool, hasMovementOnScreen: Bool, movementWithHistoryOnScreen: Bool,
    isEnteringNumbers: Bool
  ) {
    self.sessionHasGym = sessionHasGym
    self.hasMovementOnScreen = hasMovementOnScreen
    self.movementWithHistoryOnScreen = movementWithHistoryOnScreen
    self.isEnteringNumbers = isEnteringNumbers
  }
}

/// When a tip may appear. TipKit then shows each at most once, ends it when the feature is used,
/// and shows no more than one a day (`Tips.configure([.displayFrequency(.daily)])`).
public enum FeatureTipPlan {
  public static func isEligible(_ tip: FeatureTip, facts: FeatureTipFacts) -> Bool {
    guard !facts.isEnteringNumbers else { return false }
    switch tip {
    case .machineChip: return facts.sessionHasGym && facts.hasMovementOnScreen
    case .movementHistory: return facts.movementWithHistoryOnScreen
    }
  }
}
