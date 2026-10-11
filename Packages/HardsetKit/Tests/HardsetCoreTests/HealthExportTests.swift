import Foundation
import Testing

@testable import HardsetCore

@Suite("A workout reaches Apple Health only when asked, with its own times, and nothing invented")
struct HealthExportTests {
  let start = Date(timeIntervalSince1970: 70_000_000)
  let id = SessionID()

  private func decide(
    finishedAfter seconds: Double?, sets: Int = 6, enabled: Bool = true, exported: Bool = false,
    now: Date? = nil
  ) -> HealthExportDecision {
    let timeline = SessionTimeline(
      startedAt: start, finishedAt: seconds.map { start.addingTimeInterval($0) })
    return HealthExportPolicy.decide(
      sessionID: id, timeline: timeline, loggedSets: sets, isEnabled: enabled,
      alreadyExported: exported, now: now ?? start.addingTimeInterval(86_400))
  }

  @Test("A finished workout goes as strength training, from its start to its finish")
  func exportsTimeline() {
    let expected = HealthWorkoutPlan(
      sessionID: id, activity: .traditionalStrengthTraining, start: start,
      end: start.addingTimeInterval(3_000))
    #expect(decide(finishedAfter: 3_000) == .export(expected))
    #expect(expected.externalID == id.description)
  }

  /// When the lifter has not opted in, nothing else is examined, so no reason leaks.
  @Test("Off means off, whatever the workout")
  func offBeatsEverything() {
    #expect(decide(finishedAfter: nil, sets: 0, enabled: false, exported: true) == .skip(.notEnabled))
  }

  @Test("Never twice")
  func neverTwice() {
    #expect(decide(finishedAfter: 3_000, exported: true) == .skip(.alreadyExported))
  }

  @Test("An open workout, or one with nothing logged, is not a workout to record")
  func openOrEmpty() {
    #expect(decide(finishedAfter: nil) == .skip(.stillOpen))
    #expect(decide(finishedAfter: 3_000, sets: 0) == .skip(.nothingLogged))
  }

  /// Review Focus: a session left open overnight and finished in the morning is the ancestor's
  /// 9,749-minute workout. Health must not receive it, nor a zero-length one.
  @Test("An implausibly long or zero-length workout is skipped")
  func implausiblyLongIsSkipped() {
    #expect(decide(finishedAfter: 7 * 3_600) == .skip(.implausiblyLong))
    #expect(decide(finishedAfter: 6 * 3_600) != .skip(.implausiblyLong))
    #expect(decide(finishedAfter: 0) == .skip(.lengthUnknown))
  }

  /// Review Focus: the clock moved backwards after the workout, so its end is "in the future".
  @Test("A workout that ends after now is skipped")
  func endsInFutureIsSkipped() {
    #expect(decide(finishedAfter: 3_000, now: start.addingTimeInterval(1_000)) == .skip(.endsInFuture))
    #expect(decide(finishedAfter: 3_000, now: start.addingTimeInterval(3_000)) != .skip(.endsInFuture))
  }

  @Test("The setting says what is sent and what is not, and that nothing is read")
  func settingCopy() {
    #expect(HealthExportCopy.settingFooter.contains("strength training"))
    #expect(HealthExportCopy.settingFooter.contains("no calories"))
    #expect(HealthExportCopy.settingFooter.contains("never reads"))
  }

  @Test("The summary says saved only when it was, and stays quiet about skips nobody needs")
  func summaryLines() {
    #expect(HealthExportCopy.summaryLine(for: .saved) == "Saved to Apple Health as strength training.")
    #expect(HealthExportCopy.summaryLine(for: .failed)?.contains("still saved here") == true)
    #expect(HealthExportCopy.summaryLine(for: .skipped(.notEnabled)) == nil)
    #expect(HealthExportCopy.summaryLine(for: .skipped(.alreadyExported)) == nil)
    #expect(HealthExportCopy.summaryLine(for: .skipped(.implausiblyLong))?.contains("length is unknown") == true)
  }
}
