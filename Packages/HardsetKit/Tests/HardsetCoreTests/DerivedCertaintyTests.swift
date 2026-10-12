import Foundation
import Testing

@testable import HardsetCore

@Suite("Every derived number carries its own certainty")
struct DerivedCertaintyTests {
  private let day = Date(timeIntervalSince1970: 30_000_000)

  private func report(_ sets: [MuscleKey: Double], unattributed: Int = 0) -> MuscleVolumeReport {
    MuscleVolumeReport(
      fractionalSets: sets, hardSets: 10, unattributedHardSets: unattributed, setsTouchingGroup: [:])
  }

  @Test("Each muscle has its own certainty, not the report's best case")
  func perMuscle() {
    let weekly = report([MuscleKey(.chest): 12, MuscleKey(.forearms): 4, MuscleKey(.quadriceps): 30])
    // Chest is a modelled site: moderate at most.
    #expect(weekly.certainty(for: .chest) == .moderate)
    // Forearms are counted, not modelled: low.
    #expect(weekly.certainty(for: .forearms) == .low)
    // Past the studied range even a modelled site is low.
    #expect(weekly.certainty(for: .quadriceps) == .low)
  }

  @Test("A muscle credited nothing has no figure, so no certainty")
  func nothingCredited() {
    #expect(report([MuscleKey(.chest): 3]).certainty(for: .lats) == nil)
  }

  @Test("A muscle line in the summary carries the same certainty as the volume tab")
  func summaryLineAgrees() {
    let weekly = report([MuscleKey(.chest): 12, MuscleKey(.forearms): 4])
    let lines = WorkoutSummary.muscleLines(from: weekly)
    let chest = lines.first { $0.muscle == MuscleKey(.chest) }
    let forearms = lines.first { $0.muscle == MuscleKey(.forearms) }
    #expect(chest?.certainty == weekly.certainty(for: .chest))
    #expect(forearms?.certainty == weekly.certainty(for: .forearms))
  }

  @Test("A token this version does not know is low, never unevaluated, because a figure is shown")
  func unrecognisedToken() {
    let line = WorkoutSummary.MuscleLine(
      muscle: MuscleKey(stored: "serratus"), fractionalSets: 2, isLowerBound: false)
    #expect(line.certainty == .low)
  }

  @Test("A count reads in the lifter's locale, with its lower bound")
  func countText() {
    let line = WorkoutSummary.MuscleLine(
      muscle: MuscleKey(.chest), fractionalSets: 2.5, isLowerBound: true)
    #expect(line.countText(locale: Locale(identifier: "en_US_POSIX")) == "≥ 2.5")
    #expect(line.countText(locale: Locale(identifier: "de_DE")) == "≥ 2,5")
    let whole = WorkoutSummary.MuscleLine(
      muscle: MuscleKey(.chest), fractionalSets: 12, isLowerBound: false)
    #expect(whole.countText(locale: Locale(identifier: "en_US_POSIX")) == "12")
  }

  private func sample(_ session: SessionID, _ weight: Double, _ reps: Int) -> ProgressionSample {
    ProgressionSample(
      sessionID: session, machineID: nil, weightKg: weight, reps: reps, completedAt: day)
  }

  @Test("A session's best estimate carries the certainty of the set it came from")
  func estimateCertainty() throws {
    let exercise = ExerciseID()
    let tens = SessionID()
    let fours = SessionID()
    let twenties = SessionID()
    let series = ProgressionAnalyzer.series(
      from: [
        sample(tens, 100, 10),
        sample(fours, 110, 4),
        sample(twenties, 60, 20),
      ], exerciseID: exercise)
    let points = try #require(series.first).points
    let byID = Dictionary(uniqueKeysWithValues: points.map { ($0.sessionID, $0) })
    #expect(byID[tens]?.bestEstimateCertainty == .moderate)
    #expect(byID[fours]?.bestEstimateCertainty == .high)
    // Nothing estimable, so neither an estimate nor a certainty.
    #expect(byID[twenties]?.bestEstimatedOneRepMaxKg == nil)
    #expect(byID[twenties]?.bestEstimateCertainty == nil)
  }

  @Test("When two sets estimate the same, the better-supported one speaks for the session")
  func tieGoesToTheBetterSupported() throws {
    // 90 × 10 and 100 × 6 both estimate exactly 120: the first at moderate (7...10 reps), the
    // second at high (2...6). The moderate one comes first, so a value-only maximum would keep it.
    let session = SessionID()
    let series = ProgressionAnalyzer.series(
      from: [sample(session, 90, 10), sample(session, 100, 6)], exerciseID: ExerciseID())
    let point = try #require(series.first?.points.first)
    #expect(point.bestEstimatedOneRepMaxKg == 120)
    #expect(point.bestEstimateCertainty == .high)
  }

  @Test("A point built with no estimate cannot carry a certainty")
  func noEstimateNoCertainty() {
    let point = ProgressionPoint(
      sessionID: SessionID(), machineID: nil, date: day, heaviestLoadKg: 100,
      bestEstimatedOneRepMaxKg: nil, workingSets: 3, bestEstimateCertainty: .high)
    #expect(point.bestEstimateCertainty == nil)
  }

  @Test("An estimated-1RM record carries its estimate's certainty; measured records carry none")
  func recordCertainty() {
    let estimate = PersonalRecord(kind: .estimatedOneRepMax, weightKg: 100, reps: 10)
    #expect(estimate.estimateCertainty == .moderate)
    let low = PersonalRecord(kind: .estimatedOneRepMax, weightKg: 100, reps: 12)
    #expect(low.estimateCertainty == .low)
    #expect(PersonalRecord(kind: .heaviestLoad, weightKg: 100, reps: 10).estimateCertainty == nil)
    #expect(PersonalRecord(kind: .repsAtLoad, weightKg: 100, reps: 10).estimateCertainty == nil)
  }
}
