import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

@Suite("Failures are told in the lifter's words, never as an error dump")
struct FailureCopyTests {
  private struct Opaque: Error, CustomStringConvertible {
    var description: String { "Error Domain=NSSQLiteErrorDomain Code=19 secret-internal" }
  }

  /// One row of the copy table: what `error` raised during `action` must say, exactly.
  struct CopyRow: Sendable {
    let error: any Error
    let action: FailureCopy.Action
    let expected: String
  }

  @Test("Known logging errors keep their specific copy")
  func knownLoggingErrors() {
    #expect(
      FailureCopy.message(for: LoggerStoreError.incompleteSet, during: .logSet)
        == "Enter a weight and reps before logging this set.")
    #expect(
      FailureCopy.message(for: LoggerStoreError.sessionNotFound, during: .logSet)
        == "This workout could not be found. Your logged sets are safe.")
  }

  @Test("A clock that went backwards is named as the cause")
  func clockCause() {
    #expect(
      FailureCopy.message(for: SessionTimelineError.finishedBeforeStart, during: .finishWorkout)
        .contains("Check your device's date and time"))
  }

  @Test("No action ever leaks the raw error", arguments: FailureCopy.Action.allCases)
  func neverLeaks(action: FailureCopy.Action) {
    let text = FailureCopy.message(for: Opaque(), during: action)
    #expect(!text.isEmpty)
    #expect(!text.contains("Domain"))
    #expect(!text.contains("secret-internal"))
  }

  @Test("A stranded workout is never described as gone")
  func resumeReassures() {
    let text = FailureCopy.message(for: Opaque(), during: .resumeWorkout)
    #expect(text.contains("sets are saved"))
  }

  @Test(
    "Every message is the table's exact copy",
    arguments: [
      CopyRow(
        error: LoggerStoreError.incompleteSet, action: .logSet,
        expected: "Enter a weight and reps before logging this set."),
      CopyRow(
        error: LoggerStoreError.sessionNotFound, action: .logSet,
        expected: "This workout could not be found. Your logged sets are safe."),
      CopyRow(
        error: Opaque(), action: .logSet,
        expected: "That set could not be saved. It has not been logged — tap to try again."),
      CopyRow(
        error: Opaque(), action: .loadSummary,
        expected: "Your workout is saved, but its summary could not be read. Try again."),
      CopyRow(
        error: SessionTimelineError.finishedBeforeStart, action: .finishWorkout,
        expected: "This workout could not be finished, so it is still open. Your sets are saved. "
          + "Check your device's date and time, then try again."),
      CopyRow(
        error: Opaque(), action: .finishWorkout,
        expected: "This workout could not be finished, so it is still open. Your sets are saved. "
          + "Try again."),
      CopyRow(
        error: Opaque(), action: .resumeWorkout,
        expected: "Your unfinished workout could not be reopened. Its sets are saved. Try again."),
      CopyRow(
        error: Opaque(), action: .prepareCatalogue,
        expected: "The movement list could not be prepared. Try again."),
      CopyRow(
        error: Opaque(), action: .saveGym,
        expected: "That gym could not be saved. Try again."),
      CopyRow(
        error: Opaque(), action: .saveMachine,
        expected: "That machine could not be saved. Try again."),
      CopyRow(
        error: Opaque(), action: .loadHistory,
        expected: "Your history could not be read. Your sets are safe. Try again."),
      CopyRow(
        error: Opaque(), action: .loadVolume,
        expected: "The last 7 days could not be read. Your sets are safe. Try again."),
      CopyRow(
        error: Opaque(), action: .scheduleRest,
        expected: "The rest alarm could not be set. The countdown on screen still runs."),
      CopyRow(
        error: LoggerStoreError.incompleteSet, action: .editSet,
        expected: "Enter a weight and reps to save this change."),
      CopyRow(
        error: LoggerStoreError.setNotFound, action: .editSet,
        expected: "That set is no longer in this workout."),
      CopyRow(
        error: Opaque(), action: .editSet,
        expected: "That change could not be saved. The set still shows what was saved — try again."),
      CopyRow(
        error: LoggerStoreError.setNotFound, action: .deleteSet,
        expected: "That set is no longer in this workout."),
      CopyRow(
        error: Opaque(), action: .deleteSet,
        expected: "That set could not be deleted. It is still saved — try again."),
      CopyRow(
        error: Opaque(), action: .undoDelete,
        expected: "That set could not be put back. Tap Undo to try again."),
      CopyRow(
        error: LoggerStoreError.sessionNotEmpty, action: .discardWorkout,
        expected: "This workout has logged sets, so it was not discarded. Finish it to keep them."),
      CopyRow(
        error: Opaque(), action: .discardWorkout,
        expected: "This workout could not be discarded. It is still open — try again."),
      CopyRow(
        error: LoggerStoreError.setNotFound, action: .logSet,
        expected: "That set could not be saved. It has not been logged — tap to try again."),
      CopyRow(
        error: GymStoreError.blankName, action: .renameGym,
        expected: "Enter a name for this gym."),
      CopyRow(
        error: Opaque(), action: .renameGym,
        expected: "That gym could not be renamed. Try again."),
      CopyRow(
        error: Opaque(), action: .archiveGym,
        expected: "That gym could not be archived. It is still in your list — try again."),
      CopyRow(
        error: GymStoreError.blankName, action: .renameMachine,
        expected: "Enter a name for this machine."),
      CopyRow(
        error: Opaque(), action: .renameMachine,
        expected: "That machine could not be renamed. Try again."),
      CopyRow(
        error: Opaque(), action: .archiveMachine,
        expected: "That machine could not be archived. It is still in your list — try again."),
    ]
  )
  func copyMatchesTable(row: CopyRow) {
    #expect(FailureCopy.message(for: row.error, during: row.action) == row.expected)
  }

  @Test("A finish failure that is not a clock problem never blames the clock")
  func genericFinishDoesNotBlameClock() {
    let text = FailureCopy.message(for: Opaque(), during: .finishWorkout)
    #expect(!text.contains("date and time"))
  }
}
