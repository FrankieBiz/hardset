import Foundation
import HardsetCore
import Testing

@testable import HardsetStore

@Suite("Failures are told in the lifter's words, never as an error dump")
struct FailureCopyTests {
  private struct Opaque: Error, CustomStringConvertible {
    var description: String { "Error Domain=NSSQLiteErrorDomain Code=19 secret-internal" }
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

  @Test(
    "No action ever leaks the raw error",
    arguments: [
      FailureCopy.Action.logSet, .finishWorkout, .resumeWorkout, .prepareCatalogue, .saveGym,
      .saveMachine, .loadHistory, .loadVolume, .scheduleRest,
    ]
  )
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
}
