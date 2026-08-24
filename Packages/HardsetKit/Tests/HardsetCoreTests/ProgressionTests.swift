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

  @Test("The disclosure states the estimate's limit and the machine caveat")
  func disclosureIsHonest() {
    let range = ProgressionAnalyzer.source.validRange ?? ""
    #expect(range.contains("twelve reps or fewer"))
    #expect(range.contains("not a change in strength"))
    #expect(ProgressionAnalyzer.source.methodology.contains("never merged"))
  }

  // MARK: - Machine changes within one session

  /// The merge this whole design refuses, appearing in the code whose job is to annotate it.
  ///
  /// Keying per session kept whichever machine was seen first and took the heaviest load across all
  /// of them. A lifter who moved equipment mid-exercise had that session attributed to one machine
  /// while carrying a load set on the other, so the delta against the next session compared two
  /// different machines and reported it as one.
  @Test("Moving machines inside one session is a real change, with each machine's own load")
  func withinSessionMoveIsAChange() {
    let input = samples([
      // One session: two sets on the Hammer, then two heavier on the Cybex. Distinct days stand in
      // for distinct set timestamps within the session, which is what real sets have.
      (session: 1, machine: hammer, weight: 80, reps: 8, day: 0),
      (session: 1, machine: hammer, weight: 80, reps: 8, day: 1),
      (session: 1, machine: cybex, weight: 100, reps: 8, day: 2),
      (session: 1, machine: cybex, weight: 105, reps: 6, day: 3),
    ])

    let changes = ProgressionAnalyzer.machineChanges(from: input)

    // Previously invisible: one session collapsed to one entry, so no change could be seen at all.
    #expect(changes.count == 1)
    let change = try! #require(changes.first)
    #expect(change.fromMachineID == hammer)
    #expect(change.toMachineID == cybex)
    // Each side carries its own machine's heaviest load: 105 on the Cybex against 80 on the Hammer.
    #expect(change.heaviestLoadDeltaKg == 25)
  }

  /// The consequence for the *next* session's delta, which is what the chart annotates.
  @Test("A within-session move does not contaminate the next session's delta")
  func withinSessionMoveDoesNotContaminateTheNext() {
    let input = samples([
      // Session 1 starts on the Hammer and finishes on the Cybex at a much heavier load.
      (session: 1, machine: hammer, weight: 80, reps: 8, day: 0),
      (session: 1, machine: cybex, weight: 120, reps: 8, day: 1),
      // Session 2 is back on the Hammer at 85 -- a 5 kg gain on that machine.
      (session: 2, machine: hammer, weight: 85, reps: 8, day: 7),
    ])

    let changes = ProgressionAnalyzer.machineChanges(from: input)

    // Two moves: Hammer to Cybex inside session 1, then Cybex back to Hammer.
    #expect(changes.count == 2)
    let back = try! #require(changes.last)
    #expect(back.fromMachineID == cybex)
    #expect(back.toMachineID == hammer)
    // 85 on the Hammer against 120 on the Cybex. Keying per session compared 85 against the
    // session's max of 120 while calling that session "the Hammer", so the same number came out
    // labelled as a change on one machine rather than between two.
    #expect(back.heaviestLoadDeltaKg == -35)
  }

  @Test("Staying on one machine across sessions reports no change")
  func stayingPutIsNoChange() {
    let input = samples([
      (session: 1, machine: hammer, weight: 80, reps: 8, day: 0),
      (session: 1, machine: hammer, weight: 85, reps: 6, day: 1),
      (session: 2, machine: hammer, weight: 90, reps: 8, day: 7),
    ])
    #expect(ProgressionAnalyzer.machineChanges(from: input).isEmpty)
  }
}
