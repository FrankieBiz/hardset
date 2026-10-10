import Foundation
import HardsetCore

/// Plain-language copy for every failure the lifter can see.
///
/// Copy that used to live in a view (`LiveSessionScreen.errorMessage`) is moved here so it is
/// tested, and later UI tasks read it from this type. A raw `\(error)` must never reach the screen:
/// these messages say what happened to the user's sets and what to do next, and they never include
/// the underlying error's description, which can carry database or device internals.
public nonisolated enum FailureCopy {
  /// Each user-visible action that can fail.
  public enum Action: Sendable, CaseIterable {
    case logSet
    case finishWorkout
    case resumeWorkout
    case prepareCatalogue
    case saveGym
    case saveMachine
    case loadHistory
    case loadVolume
    case scheduleRest
  }

  /// The message for `error` raised while performing `action`.
  ///
  /// Known errors get their specific wording. Any other error gets the action's generic message.
  public static func message(for error: any Error, during action: Action) -> String {
    switch action {
    case .logSet:
      if let storeError = error as? LoggerStoreError {
        switch storeError {
        case .incompleteSet:
          return "Enter a weight and reps before logging this set."
        case .sessionNotFound:
          return "This workout could not be found. Your logged sets are safe."
        }
      }
      return "That set could not be saved. It has not been logged — tap to try again."

    case .finishWorkout:
      if let timelineError = error as? SessionTimelineError, timelineError == .finishedBeforeStart {
        return "This workout could not be finished, so it is still open. Your sets are saved. "
          + "Check your device's date and time, then try again."
      }
      return "This workout could not be finished, so it is still open. Your sets are saved. "
        + "Try again."

    case .resumeWorkout:
      return "Your unfinished workout could not be reopened. Its sets are saved. Try again."

    case .prepareCatalogue:
      return "The movement list could not be prepared. Try again."

    case .saveGym:
      return "That gym could not be saved. Try again."

    case .saveMachine:
      return "That machine could not be saved. Try again."

    case .loadHistory:
      return "Your history could not be read. Your sets are safe. Try again."

    case .loadVolume:
      return "The last 7 days could not be read. Your sets are safe. Try again."

    case .scheduleRest:
      return "The rest alarm could not be set. The countdown on screen still runs."
    }
  }
}
