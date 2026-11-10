import Foundation
import Testing

@testable import HardsetCore

@Suite("Load history is per machine and never merged")
struct ProgressionTests {
  let exercise = ExerciseID()
  let hammer = MachineID()
  let cybex = MachineID()
  let day0 = Date(timeIntervalSince1970: 13_000_000)

  private func day(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 86_400) }

  private func samples(
    _ rows: [(session: Int, machine: MachineID?, weight: Double, reps: Int, day: Int)]
  ) -> [ProgressionSample] {
    var sessions: [Int: SessionID] = [:]
    return rows.map { row in
      let id = sessions[row.session] ?? SessionID()
      sessions[row.session] = id
      return ProgressionSample(
        sessionID: id, machineID: row.machine,
        weightKg: row.weight, reps: row.reps, completedAt: day(row.day)
      )
    }
  }

  // MARK: - Series

  /// The product's actual claim: the same number on different equipment is not the same effort, so
  /// one line through both would invent progress.
  @Test("Two machines produce two series, never one merged line")
  func twoMachinesTwoSeries() {
    let all = samples([
      (1, hammer, 100, 8, 0), (1, hammer, 100, 8, 0),
      (2, cybex, 70, 8, 7), (2, cybex, 70, 8, 7),
    ])
    let series = ProgressionAnalyzer.series(from: all, exerciseID: exercise)

    #expect(series.count == 2)
    let keys = Set(series.map(\.key.machineID))
    #expect(keys == [hammer, cybex])
    for s in series { #expect(s.points.count == 1) }
  }

  @Test("A point is the session's best work, not its last set")
  func pointIsSessionBest() throws {
    let all = samples([
      (1, hammer, 100, 8, 0), (1, hammer, 110, 5, 0), (1, hammer, 90, 10, 0),
    ])
    let series = try #require(ProgressionAnalyzer.series(from: all, exerciseID: exercise).first)
    let point = try #require(series.points.first)

    #expect(point.heaviestLoadKg == 110)
    #expect(point.workingSets == 3)
    // 110 x 5 estimates highest of the three under Epley.
    let best = try #require(point.bestEstimatedOneRepMaxKg)
    #expect(abs(best - 110 * (1 + 5.0 / 30.0)) < 1e-9)
  }

  /// A high-rep session yields no estimate rather than an extrapolated one. This is the ancestor's
  /// 60 kg x 25 reps -> 110 kg bug, refused.
  @Test("A session with no estimable set has no estimate")
  func noEstimateWhenOutOfRange() throws {
    let all = samples([(1, hammer, 60, 25, 0), (1, hammer, 55, 20, 0)])
    let series = try #require(ProgressionAnalyzer.series(from: all, exerciseID: exercise).first)
    let point = try #require(series.points.first)

    #expect(point.heaviestLoadKg == 60)
    #expect(point.bestEstimatedOneRepMaxKg == nil)
    #expect(series.hasNoEstimates)
  }

  @Test("A mixed session estimates only from the estimable sets")
  func mixedSession() throws {
    let all = samples([(1, hammer, 60, 25, 0), (1, hammer, 100, 6, 0)])
    let series = try #require(ProgressionAnalyzer.series(from: all, exerciseID: exercise).first)
    let point = try #require(series.points.first)
    let best = try #require(point.bestEstimatedOneRepMaxKg)
    #expect(abs(best - 100 * (1 + 6.0 / 30.0)) < 1e-9)
    #expect(!series.hasNoEstimates)
  }

  @Test("Points are oldest first, and the most-trained machine leads")
  func orderingIsStable() throws {
    let all = samples([
      (1, hammer, 100, 8, 0),
      (2, hammer, 105, 8, 7),
      (3, hammer, 110, 8, 14),
      (4, cybex, 70, 8, 3),
    ])
    let series = ProgressionAnalyzer.series(from: all, exerciseID: exercise)
    #expect(series.first?.key.machineID == hammer)
    let dates = try #require(series.first?.points.map(\.date))
    #expect(dates == dates.sorted())
    #expect(series.first?.points.map(\.heaviestLoadKg) == [100, 105, 110])
  }

  @Test("Free-weight work is its own series under a nil machine")
  func freeWeightSeries() {
    let all = samples([(1, nil, 100, 5, 0), (2, hammer, 100, 5, 7)])
    let series = ProgressionAnalyzer.series(from: all, exerciseID: exercise)
    #expect(series.count == 2)
    #expect(series.contains { $0.key.machineID == nil })
  }

  @Test("No samples produce no series")
  func emptyInput() {
    #expect(ProgressionAnalyzer.series(from: [], exerciseID: exercise).isEmpty)
    #expect(ProgressionAnalyzer.machineChanges(from: []).isEmpty)
  }

  // MARK: - Machine changes

  /// The reason this feature exists: a lifter who switches machines and sees the load drop has not
  /// got weaker, and a chart that shows a falling line without saying so is misleading.
  @Test("A machine switch is detected and its load delta reported")
  func machineSwitchDetected() throws {
    let all = samples([
      (1, hammer, 100, 8, 0),
      (2, cybex, 80, 8, 7),
    ])
    let changes = ProgressionAnalyzer.machineChanges(from: all)
    #expect(changes.count == 1)
    let change = try #require(changes.first)
    #expect(change.fromMachineID == hammer)
    #expect(change.toMachineID == cybex)
    #expect(change.heaviestLoadDeltaKg == -20)
    // And it refuses to call the drop a regression.
    #expect(change.explanation.contains("difference between the machines"))
    #expect(!change.explanation.lowercased().contains("weaker"))
  }

  /// The chart and its notes are drawn in the lifter's unit, so the sentence under the chart must
  /// be too. A pound user read "20 kg lower" beneath a line labelled in pounds.
  @Test("The machine-change sentence is stated in the unit the lifter reads")
  func machineChangeExplanationUsesDisplayUnit() throws {
    let all = samples([
      (1, hammer, 100, 8, 0),
      (2, cybex, 80, 8, 7),
    ])
    let change = try #require(ProgressionAnalyzer.machineChanges(from: all).first)
    #expect(change.explanation(in: .pounds).contains("44.1 lb lower"))
    #expect(!change.explanation(in: .pounds).contains("kg"))
    #expect(change.explanation(in: .kilograms).contains("20 kg lower"))
    // The unit-free spelling stays the canonical kilograms sentence it always was.
    #expect(change.explanation == change.explanation(in: .kilograms))
  }

  /// A difference too small to show must not be printed as "0 kg higher", which reads as a
  /// comparison the numbers do not support.
  @Test("A load difference that rounds to nothing is stated as a match")
  func machineChangeRoundingToZero() {
    let change = MachineChange(
      date: day0, fromMachineID: hammer, toMachineID: cybex, heaviestLoadDeltaKg: 0.01
    )
    #expect(change.explanation(in: .kilograms).contains("coincidence, not a comparison"))
    #expect(!change.explanation(in: .pounds).contains("0 lb"))
  }

  @Test("Staying on one machine produces no changes")
  func noChangeWhenStable() {
    let all = samples([
      (1, hammer, 100, 8, 0), (2, hammer, 105, 8, 7), (3, hammer, 110, 8, 14),
    ])
    #expect(ProgressionAnalyzer.machineChanges(from: all).isEmpty)
  }

  @Test("Switching back and forth reports both changes in order")
  func switchingBackAndForth() {
    let all = samples([
      (1, hammer, 100, 8, 0),
      (2, cybex, 80, 8, 7),
      (3, hammer, 105, 8, 14),
    ])
    let changes = ProgressionAnalyzer.machineChanges(from: all)
    #expect(changes.count == 2)
    #expect(changes[0].toMachineID == cybex)
    #expect(changes[1].toMachineID == hammer)
    #expect(changes.map(\.date) == changes.map(\.date).sorted())
  }

  /// A coincidental match must not be presented as a comparison.
  @Test("A switch with an identical load says so rather than implying equivalence")
  func identicalLoadAcrossSwitch() throws {
    let all = samples([(1, hammer, 100, 8, 0), (2, cybex, 100, 8, 7)])
    let change = try #require(ProgressionAnalyzer.machineChanges(from: all).first)
    #expect(change.heaviestLoadDeltaKg == 0)
    #expect(change.explanation.contains("coincidence, not a comparison"))
  }

  @Test("A move to or from free weights is a machine change too")
  func freeWeightTransition() throws {
    let all = samples([(1, nil, 100, 5, 0), (2, hammer, 140, 5, 7)])
    let change = try #require(ProgressionAnalyzer.machineChanges(from: all).first)
    #expect(change.fromMachineID == nil)
    #expect(change.toMachineID == hammer)
    #expect(change.heaviestLoadDeltaKg == 40)
  }

  @Test("Machine switch within the same session reports load delta correctly")
  func intraSessionMachineSwitch() throws {
    let session = SessionID()
    let sample1 = ProgressionSample(
      sessionID: session,
      machineID: hammer,
      weightKg: 100,
      reps: 8,
      completedAt: day(0)
    )
    let sample2 = ProgressionSample(
      sessionID: session,
      machineID: cybex,
      weightKg: 75,
      reps: 10,
      completedAt: day(0).addingTimeInterval(300)
    )
    let changes = ProgressionAnalyzer.machineChanges(from: [sample1, sample2])
    #expect(changes.count == 1)
    let change = try #require(changes.first)
    #expect(change.fromMachineID == hammer)
    #expect(change.toMachineID == cybex)
    #expect(change.heaviestLoadDeltaKg == -25)
  }

  // MARK: - Estimate certainty

  /// The badge beside an estimate must not vouch for more than the rep counts allow. Sets of eleven
  /// and twelve reps are graded low by the estimator, and the point has to carry that.
  @Test("A session of eleven- and twelve-rep sets carries a low-certainty estimate")
  func highRepEstimateIsLow() throws {
    let series = ProgressionAnalyzer.series(
      from: samples([(1, hammer, 60, 11, 0), (1, hammer, 60, 12, 0)]), exerciseID: exercise)
    let point = try #require(series.first?.points.first)
    #expect(point.bestEstimatedOneRepMaxKg != nil)
    #expect(point.bestEstimateCertainty == .low)
  }

  @Test("The winning estimate's certainty is the one recorded", arguments: [
    (5, Certainty.high), (8, Certainty.moderate), (1, Certainty.high),
  ])
  func winningCertainty(reps: Int, expected: Certainty) throws {
    let series = ProgressionAnalyzer.series(
      from: samples([(1, hammer, 100, reps, 0), (1, hammer, 40, 12, 0)]), exerciseID: exercise)
    let point = try #require(series.first?.points.first)
    #expect(point.bestEstimateCertainty == expected)
  }

  @Test("A session with nothing estimable has no estimate and no certainty")
  func noEstimateNoCertainty() throws {
    let series = ProgressionAnalyzer.series(
      from: samples([(1, nil, 0, 8, 0), (1, nil, 60, 20, 0)]), exerciseID: exercise)
    let point = try #require(series.first?.points.first)
    #expect(point.bestEstimatedOneRepMaxKg == nil)
    #expect(point.bestEstimateCertainty == nil)
  }

  /// The chart's badge qualifies the latest figure of each line, so it is the weakest of those.
  @Test("The chart's estimate certainty is the weakest latest estimate across machines")
  func chartCertaintyIsWeakestLatest() {
    let all = samples([
      (1, hammer, 100, 12, 0),  // old and low, superseded below
      (2, hammer, 100, 5, 7),  // latest on the hammer: high
      (3, cybex, 70, 9, 8),  // latest on the cybex: moderate
      (4, cybex, 70, 25, 9),  // newer, but unestimable: does not count
    ])
    let series = ProgressionAnalyzer.series(from: all, exerciseID: exercise)
    #expect(ProgressionAnalyzer.estimateCertainty(latestOf: series.map(\.points)) == .moderate)
  }

  @Test("No estimate anywhere is unevaluated, and a point that hides its certainty counts as low")
  func chartCertaintyEdges() {
    let unestimable = samples([(1, hammer, 0, 8, 0)])
    let series = ProgressionAnalyzer.series(from: unestimable, exerciseID: exercise)
    #expect(ProgressionAnalyzer.estimateCertainty(latestOf: series.map(\.points)) == .unevaluated)
    let silent = ProgressionPoint(
      sessionID: SessionID(), machineID: nil, date: day(0), heaviestLoadKg: 100,
      bestEstimatedOneRepMaxKg: 120, workingSets: 1)
    #expect(silent.bestEstimateCertainty == nil)
    #expect(ProgressionAnalyzer.estimateCertainty(latestOf: [[silent]]) == .low)
  }

  /// Bodyweight work has real sets and no added load. A flat line at zero is not a load history.
  @Test("A history with no added load is recognised as such")
  func noAddedLoad() {
    let bodyweight = ProgressionAnalyzer.series(
      from: samples([(1, nil, 0, 8, 0), (2, nil, 0, 10, 3)]), exerciseID: exercise)
    #expect(ProgressionAnalyzer.hasNoAddedLoad(bodyweight.map(\.points)))
    let weighted = ProgressionAnalyzer.series(
      from: samples([(1, nil, 0, 8, 0), (2, nil, 10, 8, 3)]), exerciseID: exercise)
    #expect(!ProgressionAnalyzer.hasNoAddedLoad(weighted.map(\.points)))
    #expect(!ProgressionAnalyzer.hasNoAddedLoad([]))
  }

  @Test("The disclosure states the estimate's limit and the machine caveat")
  func disclosureIsHonest() {
    let range = ProgressionAnalyzer.source.validRange ?? ""
    #expect(range.contains("twelve reps or fewer"))
    #expect(range.contains("not a change in strength"))
    #expect(ProgressionAnalyzer.source.methodology.contains("never merged"))
  }
}
