import Foundation
import Testing

@testable import HardsetCore

@Suite("The scorecard's words, and the share text that opens with them")
struct ScorecardCopyTests {
  private func card(
    entries: [(String, WorkoutScorecard.Outcome)], beaten: Int, compared: Int, records: Int,
    gain: (String, Double, TrendMetric)? = nil, certainty: Certainty? = nil
  ) -> WorkoutScorecard {
    WorkoutScorecard(
      entries: entries.map {
        WorkoutScorecard.Entry(key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: $0.0, outcome: $0.1)
      },
      beatenCount: beaten, comparedCount: compared, recordMovementCount: records,
      biggestGain: gain.map {
        WorkoutScorecard.Gain(
          key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: $0.0, fraction: $0.1,
          metric: $0.2, certainty: certainty)
      })
  }

  @Test("The records line counts movements, not sets, and is absent when there are none")
  func recordsLine() {
    #expect(ScorecardCopy.recordsText(card(entries: [], beaten: 0, compared: 0, records: 0)) == nil)
    #expect(ScorecardCopy.recordsText(card(entries: [], beaten: 1, compared: 1, records: 1))
      == "A record on 1 movement")
    #expect(ScorecardCopy.recordsText(card(entries: [], beaten: 3, compared: 4, records: 3))
      == "Records on 3 movements")
  }

  @Test("The biggest gain names the movement, the metric and the percentage")
  func gainLine() {
    #expect(ScorecardCopy.gainText(card(
      entries: [], beaten: 1, compared: 1, records: 0, gain: ("Chest press", 0.0625, .estimatedMax)))
      == "Biggest gain: Chest press, estimated max +6%")
    #expect(ScorecardCopy.gainText(card(
      entries: [], beaten: 1, compared: 1, records: 0, gain: ("Row", 0.125, .heaviestLoad)))
      == "Biggest gain: Row, heaviest weight +13%")
    #expect(ScorecardCopy.gainText(card(entries: [], beaten: 0, compared: 1, records: 0)) == nil)
  }

  @Test("A movement's mark is what grew, 'Record' when only a record applies, or its plain status")
  func entryMarks() {
    let beat = WorkoutScorecard.Outcome.beat(.beat(addedKg: 0, addedReps: 1))
    let load = WorkoutScorecard.Outcome.beat(.beat(addedKg: 2.5, addedReps: 1))
    func mark(
      _ outcome: WorkoutScorecard.Outcome, equipment: WorkoutReceipt.Equipment? = nil
    ) -> String? {
      ScorecardCopy.markText(
        WorkoutScorecard.Entry(
          key: ProgressionKey(exerciseID: ExerciseID()), exerciseName: "Lift", outcome: outcome,
          equipment: equipment),
        unit: .kilograms)
    }

    #expect(mark(beat) == "+1 rep")
    #expect(mark(load) == "+2.5 kg · +1 rep")
    #expect(mark(.beat(nil)) == "Record")
    #expect(mark(.matched) == "Matched")
    // A first time names what it is a first time on. Only a recorded machine earns "on this
    // machine"; a barbell has none, so claiming one was the bug.
    #expect(mark(.firstTime, equipment: .machine("Hammer Strength Chest Press"))
      == "First time on this machine")
    #expect(mark(.firstTime, equipment: .freeWeight) == "First time")
    #expect(mark(.firstTime, equipment: .bodyweight) == "First time")
    #expect(mark(.firstTime, equipment: .unrecorded) == "First time")
    #expect(mark(.firstTime) == "First time")
    // Falling short is carried by the headline's count, not drawn as a mark on the movement.
    #expect(mark(.notBeaten) == nil)
  }

  @Test("The share text opens with the headline, then the records and the biggest gain")
  func shareTextOpensWithTheHeadline() {
    let scored = card(
      entries: [("Chest press", .beat(.beat(addedKg: 0, addedReps: 1)))], beaten: 1, compared: 1,
      records: 1, gain: ("Chest press", 0.0625, .estimatedMax))
    let receipt = WorkoutReceipt(
      id: SessionID(), title: "Upper A", startedAt: Date(timeIntervalSince1970: 1_793_527_200),
      finishedAt: Date(timeIntervalSince1970: 1_793_530_800), lines: [], scorecard: scored)

    let lines = receipt.text(unit: .kilograms).components(separatedBy: "\n")

    #expect(lines[0] == "Beat last time on 1 of 1")
    #expect(lines[1] == "A record on 1 movement")
    #expect(lines[2] == "Biggest gain: Chest press, estimated max +6%")
    #expect(lines[3] == "HARDSET · Workout receipt")
  }

  @Test("An estimated gain says how far to trust it in the share text, a measured one says nothing")
  func shareTextStatesTheCertaintyOfAnEstimatedGain() {
    func gainLine(_ metric: TrendMetric, certainty: Certainty?) -> String? {
      let scored = card(
        entries: [], beaten: 1, compared: 1, records: 0, gain: ("Chest press", 0.0625, metric),
        certainty: certainty)
      return ScorecardCopy.gainShareText(scored)
    }

    #expect(gainLine(.estimatedMax, certainty: .moderate)
      == "Biggest gain: Chest press, estimated max +6% · Moderate confidence")
    #expect(gainLine(.estimatedMax, certainty: .high)
      == "Biggest gain: Chest press, estimated max +6% · High confidence")
    #expect(gainLine(.estimatedMax, certainty: .low)
      == "Biggest gain: Chest press, estimated max +6% · Low confidence")
    #expect(gainLine(.heaviestLoad, certainty: nil) == "Biggest gain: Chest press, heaviest weight +6%")
    #expect(ScorecardCopy.gainShareText(card(entries: [], beaten: 0, compared: 1, records: 0)) == nil)
  }

  @Test("The share text carries the certainty beside the estimated gain")
  func shareTextCarriesTheCertainty() {
    let scored = card(
      entries: [], beaten: 1, compared: 1, records: 0, gain: ("Chest press", 0.0625, .estimatedMax),
      certainty: .moderate)
    let receipt = WorkoutReceipt(
      id: SessionID(), title: "Upper A", startedAt: Date(timeIntervalSince1970: 1_793_527_200),
      finishedAt: Date(timeIntervalSince1970: 1_793_530_800), lines: [], scorecard: scored)

    let lines = receipt.text(unit: .kilograms).components(separatedBy: "\n")

    #expect(lines[1] == "Biggest gain: Chest press, estimated max +6% · Moderate confidence")
  }

  @Test("Without a scorecard the share text is what it always was")
  func shareTextWithoutAScorecard() {
    let receipt = WorkoutReceipt(
      id: SessionID(), title: "Upper A", startedAt: Date(timeIntervalSince1970: 1_793_527_200),
      finishedAt: Date(timeIntervalSince1970: 1_793_530_800), lines: [])

    #expect(receipt.text(unit: .kilograms).components(separatedBy: "\n")[0] == "HARDSET · Workout receipt")
  }
}
