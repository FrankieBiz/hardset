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
    case editSet
    case deleteSet
    case undoDelete
    case discardWorkout
    case loadSummary
    case renameGym
    case archiveGym
    case renameMachine
    case archiveMachine
    case addMovement
    case changeMachine
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
        case .setNotFound, .sessionNotEmpty, .sessionNotOpen:
          break
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

    case .editSet:
      if let storeError = error as? LoggerStoreError {
        if storeError == .incompleteSet { return "Enter a weight and reps to save this change." }
        if storeError == .setNotFound { return "That set is no longer in this workout." }
      }
      return "That change could not be saved. The set still shows what was saved — try again."

    case .deleteSet:
      if let storeError = error as? LoggerStoreError, storeError == .setNotFound {
        return "That set is no longer in this workout."
      }
      return "That set could not be deleted. It is still saved — try again."

    case .undoDelete:
      return "That set could not be put back. Tap Undo to try again."

    case .discardWorkout:
      if let storeError = error as? LoggerStoreError {
        if storeError == .sessionNotEmpty {
          return "This workout has logged sets, so it was not discarded. Finish it to keep them."
        }
        // Deleted on another device first. "Still open — try again" would be untrue, and a retry
        // could only fail the same way.
        if storeError == .sessionNotFound {
          return "This workout has already been deleted, so there is nothing left to discard."
        }
      }
      return "This workout could not be discarded. It is still open — try again."

    case .loadSummary:
      return "Your workout is saved, but its summary could not be read. Try again."

    case .renameGym:
      if let gymError = error as? GymStoreError, gymError == .blankName {
        return "Enter a name for this gym."
      }
      return "That gym could not be renamed. Try again."

    case .archiveGym:
      return "That gym could not be archived. It is still in your list — try again."

    case .renameMachine:
      if let gymError = error as? GymStoreError, gymError == .blankName {
        return "Enter a name for this machine."
      }
      return "That machine could not be renamed. Try again."

    case .archiveMachine:
      return "That machine could not be archived. It is still in your list — try again."

    case .addMovement:
      return "That movement could not be added. Try again."

    case .changeMachine:
      return "The machine could not be changed. Your logged sets are safe. Try again."
    }
  }
}
