import Foundation
import Testing

@testable import HardsetCore

/// "What do I press on each of these?" — the question the app tracks the data for and never
/// answered in words.
@Suite("Each machine's best, next to the one you use most")
struct MachineComparisonTests {
  let exercise = ExerciseID()
  let hammer = MachineID()
  let cybex = MachineID()
  let panatta = MachineID()
  let day = Date(timeIntervalSince1970: 1_700_000_000)

  private func point(_ kg: Double, _ reps: Int, _ estimate: Double?, dayOffset: Int)
    -> ProgressionPoint
  {
    ProgressionPoint(
      sessionID: SessionID(),
      machineID: nil,
      date: day.addingTimeInterval(Double(dayOffset) * 86_400),
      heaviestLoadKg: kg,
      bestEstimatedOneRepMaxKg: estimate,
      workingSets: reps
    )
  }

  private func series(_ machine: MachineID?, _ points: [ProgressionPoint]) -> ProgressionSeries {
    ProgressionSeries(
      key: ProgressionKey(exerciseID: exercise, machineID: machine), points: points
    )
  }

  @Test("Each machine reports its own heaviest load and best estimate")
  func reportsBestPerMachine() {
    let rows = MachineComparison.rows(from: [
      series(hammer, [point(100, 8, 120, dayOffset: 0), point(120, 5, 135, dayOffset: 7)]),
      series(cybex, [point(80, 8, 96, dayOffset: 3)]),
    ])

    let byMachine = Dictionary(uniqueKeysWithValues: rows.map { ($0.key.machineID, $0) })
    #expect(byMachine[hammer]?.heaviestLoadKg == 120)
    #expect(byMachine[hammer]?.bestEstimatedOneRepMaxKg == 135)
    #expect(byMachine[cybex]?.heaviestLoadKg == 80)
    #expect(byMachine[hammer]?.sessionCount == 2)
  }

  /// The number the lifter actually knows is the baseline. Picking the heaviest would make every
  /// other row negative by construction; picking the newest would move the baseline whenever they
  /// tried something once.
  @Test("The machine used most is the reference, not the strongest")
  func referenceIsMostUsed() {
    let rows = MachineComparison.rows(from: [
      // Heavier, but used once.
      series(cybex, [point(200, 5, nil, dayOffset: 1)]),
      series(hammer, [point(100, 8, nil, dayOffset: 0), point(105, 8, nil, dayOffset: 7)]),
    ])

    #expect(rows.first?.key.machineID == hammer)
    #expect(rows.first?.isReference == true)
    #expect(rows.first?.heaviestLoadDeltaKg == nil)
    let other = try? #require(rows.first { $0.key.machineID == cybex })
    #expect(other?.heaviestLoadDeltaKg == 95)
  }

  /// Otherwise the reference — and therefore every delta on screen — depends on the order series
  /// come back in, which is not a fact about the lifter's training.
  @Test("A tie on session count breaks on most recent, deterministically")
  func tiesBreakOnRecency() {
    let older = series(hammer, [point(100, 8, nil, dayOffset: 0)])
    let newer = series(cybex, [point(90, 8, nil, dayOffset: 30)])

    #expect(MachineComparison.rows(from: [older, newer]).first?.key.machineID == cybex)
    // Same answer whichever order they arrive in.
    #expect(MachineComparison.rows(from: [newer, older]).first?.key.machineID == cybex)
  }

  @Test("Rows after the reference are ordered by most recently trained")
  func othersOrderedByRecency() {
    let rows = MachineComparison.rows(from: [
      series(hammer, [point(100, 8, nil, dayOffset: 0), point(100, 8, nil, dayOffset: 1)]),
      series(cybex, [point(90, 8, nil, dayOffset: 2)]),
      series(panatta, [point(95, 8, nil, dayOffset: 40)]),
    ])
    #expect(rows.map(\.key.machineID) == [hammer, panatta, cybex])
  }

  /// A machine only ever used for high-rep work produces no estimate, and inventing one is exactly
  /// the fallback-that-looks-like-a-measurement this codebase refuses.
  @Test("A machine with nothing estimable reports no estimate rather than a guess")
  func noEstimateStaysAbsent() {
    let rows = MachineComparison.rows(from: [
      series(hammer, [point(60, 20, nil, dayOffset: 0)])
    ])
    #expect(rows.first?.bestEstimatedOneRepMaxKg == nil)
    #expect(rows.first?.heaviestLoadKg == 60)
  }

  @Test("Free-weight work is a series like any other and is not dropped")
  func freeWeightIsIncluded() {
    let rows = MachineComparison.rows(from: [
      series(nil, [point(100, 5, nil, dayOffset: 0)]),
      series(hammer, [point(140, 5, nil, dayOffset: 1)]),
    ])
    #expect(rows.contains { $0.key.machineID == nil })
  }

  @Test("An empty history produces no rows rather than a zero")
  func emptyIsEmpty() {
    #expect(MachineComparison.rows(from: []).isEmpty)
    #expect(MachineComparison.rows(from: [series(hammer, [])]).isEmpty)
  }

  /// The load difference between two machines is neither progress nor regression, and the wording
  /// must leave no room for reading it as either. Same stance as `MachineChange.explanation`.
  @Test("The delta is worded as a difference between machines, never as strength")
  func explanationRefusesToImplyProgress() {
    let more = MachineComparison.explanation(
      forDelta: 20, unitAbbreviation: "kg", machineName: "Hammer Leg Press")
    #expect(more.contains("difference between the machines"))
    #expect(more.contains("rather than a change in strength"))
    #expect(more.contains("20 kg more"))

    let less = MachineComparison.explanation(
      forDelta: -12.5, unitAbbreviation: "kg", machineName: "Hammer Leg Press")
    #expect(less.contains("12.5 kg less"))
    #expect(less.contains("rather than a change in strength"))

    // Never the vocabulary of getting better or worse.
    for text in [more, less] {
      for forbidden in ["progress", "stronger", "weaker", "improve", "decline"] {
        #expect(!text.lowercased().contains(forbidden), "\(text) implies strength change.")
      }
    }
  }

  /// The unit is the caller's, because the caller converts. An earlier version hardcoded "kg" and
  /// the view repaired it by replacing " kg " in the finished sentence -- which works right up until
  /// the wording changes, and then quietly tells a lifter reading in pounds that they pressed
  /// "20 kg more".
  @Test("The delta is worded in the unit it was given, not always kilograms")
  func explanationUsesTheGivenUnit() {
    let pounds = MachineComparison.explanation(
      forDelta: 45, unitAbbreviation: "lb", machineName: "Hammer Leg Press")
    #expect(pounds.contains("45 lb more"))
    #expect(!pounds.contains("kg"))
  }

  @Test("An identical load is called a coincidence, not a match")
  func equalLoadIsACoincidence() {
    let text = MachineComparison.explanation(
      forDelta: 0, unitAbbreviation: "kg", machineName: "Cybex Leg Press")
    #expect(text.contains("coincidence"))
  }
}
