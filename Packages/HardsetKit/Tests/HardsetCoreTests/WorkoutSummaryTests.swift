import Foundation
import Testing

@testable import HardsetCore

@Suite("The summary states what was done, and withholds what it cannot know")
struct WorkoutSummaryTests {
  let posix = Locale(identifier: "en_US_POSIX")
  let start = Date(timeIntervalSince1970: 2_000_000)

  private func summary(finishedAfter seconds: Double?) -> WorkoutSummary {
    WorkoutSummary(
      sessionID: SessionID(),
      timeline: SessionTimeline(
        startedAt: start, finishedAt: seconds.map { start.addingTimeInterval($0) }),
      volume: SessionVolume(workingSets: 0, warmupSets: 0, volumeKg: 0, reps: 0),
      records: [], muscles: [], unattributedSets: 0, machinesUsed: []
    )
  }

  @Test("A closed workout's length comes from its timeline")
  func closedLength() {
    #expect(summary(finishedAfter: 2_700).lengthText == "45:00")
    #expect(summary(finishedAfter: 3_900).length == .seconds(3_900))
  }

  @Test(
    "Open, backwards or implausibly long: the length is unknown, not a number",
    arguments: [nil, -60, 7 * 3_600] as [Double?]
  )
  func unknownLength(seconds: Double?) {
    let result = summary(finishedAfter: seconds)
    #expect(result.length == nil)
    #expect(result.lengthText == "Length unknown")
  }

  @Test("Muscle lines: most credited first, then vocabulary order; nothing at zero")
  func muscleOrder() {
    let report = MuscleVolumeReport(
      fractionalSets: [
        MuscleKey(.triceps): 2, MuscleKey(.chest): 4, MuscleKey(.frontDelts): 2,
        MuscleKey(.biceps): 0,
      ],
      hardSets: 4, unattributedHardSets: 0, setsTouchingGroup: [:])
    let lines = WorkoutSummary.muscleLines(from: report)
    #expect(lines.map(\.muscle) == [MuscleKey(.chest), MuscleKey(.frontDelts), MuscleKey(.triceps)])
    #expect(lines.allSatisfy { !$0.isLowerBound })
  }

  @Test("Any unattributed set makes every line a lower bound")
  func lowerBound() {
    let report = MuscleVolumeReport(
      fractionalSets: [MuscleKey(.chest): 2.5], hardSets: 5, unattributedHardSets: 2,
      setsTouchingGroup: [:])
    let line = WorkoutSummary.muscleLines(from: report)[0]
    #expect(line.isLowerBound)
    #expect(line.setsText(locale: posix) == "≥ 2.5 sets")
    #expect(line.spokenSetsText(locale: posix) == "at least 2.5 sets")
    #expect(line.setsText(locale: Locale(identifier: "de_DE")) == "≥ 2,5 sets")
  }

  @Test("Set counts agree with their noun")
  func nouns() {
    let one = WorkoutSummary.MuscleLine(muscle: MuscleKey(.chest), fractionalSets: 1, isLowerBound: false)
    let half = WorkoutSummary.MuscleLine(muscle: MuscleKey(.chest), fractionalSets: 0.5, isLowerBound: false)
    let four = WorkoutSummary.MuscleLine(muscle: MuscleKey(.chest), fractionalSets: 4, isLowerBound: false)
    #expect(one.setsText(locale: posix) == "1 set")
    #expect(half.setsText(locale: posix) == "0.5 sets")
    #expect(four.setsText(locale: posix) == "4 sets")
  }
}
