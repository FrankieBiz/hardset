import Foundation
import Testing

@testable import HardsetCore

@Suite("Worked from: a record")
struct RecordWorkingTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)  // 14 Nov 2023, 22:13:20 UTC
  let exercise = ExerciseID()
  let hammer = MachineID()
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func sample(
    _ session: SessionID, _ kg: Double, _ reps: Int, day: Int, minute: Int = 0
  ) -> ProgressionSample {
    ProgressionSample(
      sessionID: session, machineID: hammer, weightKg: kg, reps: reps,
      completedAt: epoch.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60))
  }

  private var key: ProgressionKey { ProgressionKey(exerciseID: exercise, machineID: hammer) }

  private func chart(
    _ samples: [ProgressionSample], increment: Double? = nil, estimates: Bool = true
  ) -> RecordWorking {
    RecordWorking.derive(
      keys: [key], samples: samples, estimatesOneRepMax: estimates, incrementKg: { _ in increment },
      label: { _ in "Hammer Strength" })
  }

  // MARK: - The chart's star

  @Test("A known session names the set that set each record, the set it beat, the margin and the rule")
  func knownRecord() throws {
    let first = SessionID()
    let second = SessionID()
    let working = chart([sample(first, 100, 5, day: 0), sample(second, 110, 5, day: 7)])

    #expect(working.groups.count == 1)
    let group = working.groups[0]
    #expect(group.date == epoch.addingTimeInterval(7 * 86_400))
    #expect(group.equipmentLabel == "Hammer Strength")
    #expect(group.entries.map(\.record.kind) == [.heaviestLoad, .estimatedOneRepMax])
    #expect(group.entries.allSatisfy { $0.beaten == PriorSetRecord(weightKg: 100, reps: 5, completedAt: epoch) })

    let account = working.account(title: "Records", caption: "caption", format: format)
    #expect(account.ruleHeading == "What counts as a record")
    #expect(account.rule.contains("at least the greater of 2.5% and one plate step more than the old best"))
    #expect(account.rule.contains("one 5 lb plate when none is saved"))
    #expect(account.rule.contains("a warm-up never is, and a movement's first session only builds history"))

    let section = try #require(account.sections.first)
    #expect(section.heading == "Nov 21, 2023 · Hammer Strength")
    #expect(section.note == "Compared with every earlier working set on this machine.")
    // The estimate's own confidence is the engine's answer for that set, not a figure fixed here.
    let confidence = ScorecardCopy.confidenceWords(
      StrengthMath.estimatedOneRepMax(weightKg: 110, reps: 5).certainty)
    #expect(section.lines.map(\.headline) == ["Heaviest weight", "Best estimated 1RM · \(confidence)"])
    #expect(section.lines.allSatisfy { $0.standing == .produced && $0.standingWord == "Set the record" })
    #expect(section.lines[0].context == "110 kg × 5 · Hammer Strength")
    #expect(
      section.lines[0].detail
        == "Beat your previous heaviest weight, 100 kg × 5 on Nov 14, 2023, by 10 kg (+10%). "
        + "A new heaviest weight needs at least 2.5 kg more: the greater of 2.5% of 100 kg and one plate step.")
    #expect(
      section.lines[1].detail
        == "This set's estimated one-rep max, 128.5 kg, beat your previous best estimate, 116.5 kg, "
        + "from 100 kg × 5 on Nov 14, 2023, by +10%. It needs at least 2.5% more, with an estimate on both sides.")
  }

  @Test("The margin stated is the margin the machine's own step required")
  func marginUsesTheMachineStep() throws {
    let first = SessionID()
    let second = SessionID()
    let samples = [sample(first, 100, 5, day: 0), sample(second, 106, 5, day: 7)]
    // A 5 kg stack needs a real 5 kg: 106 beats 100 by 6 and passes.
    let working = chart(samples, increment: 5)
    let detail = try #require(
      working.account(title: "Records", caption: "", format: format).sections.first?.lines.first?.detail)
    #expect(detail.contains("needs at least 5 kg more"))
    #expect(working.groups[0].entries[0].incrementKg == 5)
    // And a 7.5 kg stack does not: the same set is not a load record there. An estimated record has
    // no plate step, so it is left out of the comparison here.
    #expect(chart(samples, increment: 7.5, estimates: false).groups.isEmpty)
  }

  @Test("When two different earlier sets fit a record's figures, no set is named")
  func ambiguousBeatenSetIsNotGuessed() throws {
    let first = SessionID()
    let second = SessionID()
    let third = SessionID()
    // 100 kg for 3 and 100 kg for 8 both sit at the old heaviest weight.
    let working = chart([
      sample(first, 100, 3, day: 0), sample(second, 100, 8, day: 7), sample(third, 110, 5, day: 14),
    ])
    let heaviest = try #require(working.groups.first?.entries.first { $0.record.kind == .heaviestLoad })
    #expect(heaviest.beaten == nil)
    let detail = try #require(
      working.account(title: "Records", caption: "", format: format).sections.first?.lines.first { $0.headline == "Heaviest weight" }?.detail)
    #expect(detail.hasPrefix("Beat your previous heaviest weight, 100 kg, by 10 kg (+10%)."))
  }

  @Test("A series with no record has no working and nothing is offered")
  func noRecords() {
    let first = SessionID()
    let second = SessionID()
    #expect(chart([sample(first, 100, 5, day: 0), sample(second, 100, 5, day: 7)]).groups.isEmpty)
    #expect(
      RecordWorking.chartAccount(
        keys: [key], samples: [sample(first, 100, 5, day: 0)], estimatesOneRepMax: true,
        incrementKg: { _ in nil }, label: { _ in "Hammer Strength" }, format: format) == nil)
  }

  @Test("Sessions are listed newest first, one group each")
  func newestFirst() {
    let sessions = (0..<4).map { _ in SessionID() }
    let working = chart([
      sample(sessions[0], 100, 5, day: 0), sample(sessions[1], 110, 5, day: 7),
      sample(sessions[2], 110, 5, day: 14), sample(sessions[3], 120, 5, day: 21),
    ])
    #expect(working.groups.count == 2)
    #expect(working.groups.map(\.date) == [epoch.addingTimeInterval(21 * 86_400), epoch.addingTimeInterval(7 * 86_400)])
  }

  // MARK: - The same replay as the stars

  @Test("The sessions that carry a star are exactly the sessions the working explains")
  func sameSessionsAsTheStars() {
    var generator = SplitMix(seed: 23)
    var samples: [ProgressionSample] = []
    for day in 0..<18 {
      let session = SessionID()
      for set in 0..<Int.random(in: 1...4, using: &generator) {
        samples.append(
          sample(
            session, Double(Int.random(in: 20...50, using: &generator)) * 2.5,
            Int.random(in: 1...14, using: &generator), day: day * 4, minute: set * 3))
      }
    }
    for step in [nil, 2.5, 5] as [Double?] {
      for estimates in [true, false] {
        let stars = ProgressTrendAnalyzer.recordSessionIDs(
          samples: samples, incrementKg: step, estimatesOneRepMax: estimates)
        let findings = ProgressTrendAnalyzer.recordFindings(
          samples: samples, incrementKg: step, estimatesOneRepMax: estimates)
        #expect(Set(findings.map(\.sessionID)) == stars)
        #expect(!stars.isEmpty)

        let working = chart(samples, increment: step, estimates: estimates)
        #expect(working.entryCount == findings.count)
        #expect(working.groups.count == stars.count)
      }
    }
  }

  /// The explanation must be true: whatever margin it says was needed, the set met.
  @Test("Every record the working explains met the margin the account states for it")
  func everyMarginWasMet() {
    var generator = SplitMix(seed: 5)
    var samples: [ProgressionSample] = []
    for day in 0..<24 {
      let session = SessionID()
      for set in 0..<Int.random(in: 1...3, using: &generator) {
        samples.append(
          sample(
            session, Double(Int.random(in: 24...60, using: &generator)) * 2.5,
            Int.random(in: 1...12, using: &generator), day: day * 3, minute: set * 3))
      }
    }
    let tolerance = PersonalRecordDetector.loadMatchingTolerance
    for step in [nil, 2.5, 5] as [Double?] {
      let findings = ProgressTrendAnalyzer.recordFindings(
        samples: samples, incrementKg: step, estimatesOneRepMax: true)
      #expect(!findings.isEmpty)
      for finding in findings {
        let record = finding.record
        switch record.kind {
        case .heaviestLoad, .loadAtReps:
          let old = record.previousWeightKg ?? .infinity
          let required = PersonalRecordDetector.requiredMarginKg(over: old, increment: step)
          #expect(record.weightKg + tolerance >= old + required)
        case .repsAtLoad:
          #expect(record.reps > (record.previousReps ?? .max))
        case .estimatedOneRepMax:
          let estimate = StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps).value ?? 0
          #expect(estimate >= (record.previousWeightKg ?? .infinity) * (1 + PersonalRecordDetector.relativeThreshold))
        }
        if let beaten = finding.beaten {
          // A set that is named was done earlier and is the one the figures point to.
          #expect(beaten.completedAt <= finding.sample.completedAt)
        }
      }
    }
  }

  // MARK: - The receipt

  private func receipt(lines: [WorkoutReceipt.Line]) -> WorkoutReceipt {
    WorkoutReceipt(
      id: SessionID(), title: "Push day", startedAt: epoch, finishedAt: epoch.addingTimeInterval(3_600),
      lines: lines)
  }

  private func line(
    _ name: String, _ kg: Double, _ reps: Int, equipment: WorkoutReceipt.Equipment = .machine("Hammer Strength"),
    records: [PersonalRecord] = [], warmup: Bool = false, increment: Double? = nil
  ) -> WorkoutReceipt.Line {
    WorkoutReceipt.Line(
      id: SetID(), exerciseID: nil, exerciseName: name, equipment: equipment, weightKg: kg, reps: reps,
      isWarmup: warmup, records: records, incrementKg: increment)
  }

  @Test("A receipt line's records are explained from what the detector attached to it")
  func receiptRecords() throws {
    let bench = line(
      "Chest press", 105, 5,
      records: [PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)],
      increment: 5)
    let reps = line(
      "Chest press", 100, 9,
      records: [PersonalRecord(kind: .repsAtLoad, weightKg: 100, reps: 9, previousWeightKg: 100, previousReps: 8)])
    let loadAtReps = line(
      "Row", 105, 8, equipment: .unrecorded,
      records: [PersonalRecord(kind: .loadAtReps, weightKg: 105, reps: 8, previousWeightKg: 100, previousReps: 8)])
    let estimate = line(
      "Squat", 100, 8, equipment: .freeWeight,
      records: [PersonalRecord(kind: .estimatedOneRepMax, weightKg: 100, reps: 8, previousWeightKg: 100 * (1 + 5.0 / 30))])
    let plain = line("Chest press", 90, 8)
    let warmup = line("Chest press", 60, 10, warmup: true)
    let workout = receipt(lines: [warmup, bench, plain, reps, loadAtReps, estimate])

    let account = try #require(RecordWorking.receiptAccount(receipt: workout, format: format))
    #expect(account.title == "Records in this workout")
    #expect(account.figure == "4 records")
    #expect(account.figureCaption == "Push day · Nov 14, 2023")
    // Only the sets that earned something have a section; the plain set and the warm-up do not.
    #expect(account.sections.count == 4)
    #expect(account.sections.map(\.heading) == [
      "Chest press, 105 kg × 5", "Chest press, 100 kg × 9", "Row, 105 kg × 8", "Squat, 100 kg × 8",
    ])
    #expect(account.sections[0].note == "Compared with every earlier working set on the same recorded machine.")
    #expect(account.sections[2].note == "Compared with every earlier working set on the same movement with no machine recorded.")

    #expect(
      account.sections[0].lines[0].detail
        == "Beat your previous heaviest weight, 100 kg, by 5 kg (+5%). A new heaviest weight needs at least 5 kg more: "
        + "the greater of 2.5% of 100 kg and one plate step.")
    #expect(
      account.sections[1].lines[0].detail
        == "Beat 8 reps at 100 kg by 1 rep. A reps record needs more reps than you have ever logged at exactly this weight.")
    #expect(
      account.sections[2].lines[0].detail
        == "Beat 100 kg × 8 by 5 kg (+5%). It needs at least 2.5 kg more than the best earlier set of 8 reps or more: "
        + "the greater of 2.5% of 100 kg and one plate step.")
    #expect(
      account.sections[3].lines[0].detail
        == "This set's estimated one-rep max, 126.5 kg, beat your previous best estimate, 116.5 kg, by +8.6%. "
        + "It needs at least 2.5% more, with an estimate on both sides.")
  }

  @Test("One set's records can be asked for alone, and a receipt with none offers nothing")
  func singleLineAndNone() throws {
    let record = PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 5, previousWeightKg: 100)
    let bench = line("Chest press", 105, 5, records: [record])
    let other = line(
      "Row", 80, 8, records: [PersonalRecord(kind: .repsAtLoad, weightKg: 80, reps: 8, previousWeightKg: 80, previousReps: 7)])
    let workout = receipt(lines: [bench, other])

    let one = try #require(RecordWorking.receiptAccount(receipt: workout, line: bench, format: format))
    #expect(one.title == "Records on this set")
    #expect(one.figure == "1 record")
    #expect(one.sections.map(\.heading) == ["Chest press, 105 kg × 5"])

    #expect(RecordWorking.receiptAccount(receipt: receipt(lines: [line("Chest press", 90, 8)]), format: format) == nil)
    #expect(RecordWorking.receiptAccount(receipt: workout, line: line("Row", 1, 1), format: format) == nil)
  }

  @Test("A set with no machine step saved is stated against the 5 lb plate the detector assumed")
  func assumedStepIsStated() throws {
    let bench = line(
      "Chest press", 102, 5,
      records: [PersonalRecord(kind: .heaviestLoad, weightKg: 102, reps: 5, previousWeightKg: 40)])
    let account = try #require(RecordWorking.receiptAccount(receipt: receipt(lines: [bench]), format: format))
    // 2.5% of 40 kg is 1 kg, below one 5 lb plate, so the plate is what was required.
    #expect(account.sections[0].lines[0].detail.contains("needs at least 2.27 kg more"))
    #expect(account.rule.contains("one 5 lb plate when none is saved"))
  }

  // MARK: - Words

  @Test("What is read aloud is sentences: figures spelled out, no multiplication sign")
  func spokenIsProse() throws {
    let first = SessionID()
    let second = SessionID()
    let account = chart([sample(first, 100, 5, day: 0), sample(second, 110, 5, day: 7)])
      .account(title: "Records", caption: "2 sessions", format: format)
    #expect(account.spoken == "Records, 2 records, 2 sessions. Nov 21, 2023: Heaviest weight, Best estimated 1RM.")
    let line = try #require(account.sections.first?.lines.first)
    #expect(
      line.spoken
        == "Heaviest weight. 110 kilograms for 5 reps, Hammer Strength. "
        + "Beat your previous heaviest weight, 100 kilograms for 5 reps on Nov 14, 2023, by 10 kilograms (+10%). "
        + "A new heaviest weight needs at least 2.5 kilograms more: the greater of 2.5% of 100 kilograms and one plate step.")
    for text in account.sections.flatMap(\.lines).map(\.spoken) + [account.spoken] {
      #expect(!text.contains("×") && !text.contains("→"))
    }
  }
}
