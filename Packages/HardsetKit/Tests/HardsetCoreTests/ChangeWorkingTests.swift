import Foundation
import Testing

@testable import HardsetCore

/// A change the lifter reads as a percentage must be able to say which sets produced it. These pin
/// that the account's figure is the figure on screen, because it is taken from the same function,
/// and that every set that took no part is a line under "Left out" with its reason.
@Suite("Worked from: a six-week change and a scorecard gain")
struct ChangeWorkingTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)  // 14 Nov 2023, 22:13:20 UTC
  let exercise = ExerciseID()
  let hammer = MachineID()
  let cybex = MachineID()
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func at(_ minutes: Int, day: Int) -> Date {
    epoch.addingTimeInterval(Double(day) * 86_400 + Double(minutes) * 60)
  }

  private func sample(
    _ session: SessionID, _ kg: Double, _ reps: Int, day: Int, minute: Int = 0,
    machine: MachineID? = nil
  ) -> ProgressionSample {
    ProgressionSample(
      sessionID: session, machineID: machine, weightKg: kg, reps: reps,
      completedAt: at(minute, day: day))
  }

  private func label(_ key: ProgressionKey) -> String {
    switch key.machineID {
    case hammer: "Hammer Strength"
    case cybex: "Cybex"
    default: "Free weight"
    }
  }

  private func sixWeek(
    _ key: ProgressionKey, _ samples: [ProgressionSample], warmups: [ProgressionSample] = [],
    estimates: Bool = true, addedLoad: Bool = false
  ) -> ChangeWorking? {
    ChangeWorking.sixWeek(
      key: key, samples: samples, warmups: warmups, estimatesOneRepMax: estimates,
      assumesAddedLoad: addedLoad, label: label)
  }

  /// The row's own figure, from the function the board calls.
  private func trend(
    _ key: ProgressionKey, _ samples: [ProgressionSample], estimates: Bool = true, addedLoad: Bool = false
  ) -> MovementTrend? {
    ProgressTrendAnalyzer.trend(
      key: key, samples: samples.filter { key.contains($0) }, incrementKg: nil,
      estimatesOneRepMax: estimates, assumesAddedLoad: addedLoad)
  }

  // MARK: - The Progress row's six-week change

  @Test("A six-week change names both sessions, the set that decided each, and every set left out")
  func sixWeekEstimatedMax() throws {
    let older = SessionID()
    let latest = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let samples = [
      sample(older, 100, 5, day: 0, machine: hammer),
      sample(older, 100, 8, day: 0, minute: 5, machine: hammer),
      sample(older, 60, 15, day: 0, minute: 10, machine: hammer),
      sample(older, 90, 8, day: 0, minute: 15, machine: cybex),
      sample(latest, 120, 5, day: 42, machine: hammer),
    ]
    let warmups = [sample(older, 40, 10, day: 0, minute: -5, machine: hammer)]
    let working = try #require(sixWeek(key, samples, warmups: warmups))

    // The figure is the row's own: the same function produced both.
    let row = try #require(trend(key, samples))
    #expect(working.fraction == row.sixWeekChange)
    #expect(working.certainty == row.certainty)
    #expect(working.metric == row.metric)
    #expect(working.metric == .estimatedMax)

    let account = working.account(format: format)
    #expect(account.title == "Estimated max over six weeks")
    #expect(account.figure == "+11%")
    #expect(account.figure == ProgressCopy.signedPercent(try #require(row.sixWeekChange)))
    #expect(
      account.figureCaption == "Moderate confidence · Hammer Strength · Nov 14, 2023 to Dec 26, 2023")
    #expect(account.ruleHeading == "Formula")
    // Names the formula, the cap and the band, from the constants the arithmetic uses.
    #expect(account.rule.contains("weight × (1 + reps ÷ 30)"))
    #expect(account.rule.contains("Sets above 12 reps are not estimated."))
    #expect(account.rule.contains("5 to 7 weeks before the latest session"))
    #expect(account.rule.contains("weaker confidence of its two estimates"))
    #expect(account.rule.hasSuffix("11 to 12 reps is low."))

    #expect(account.sections.map(\.id) == ["current", "baseline", "left"])
    let current = account.sections[0]
    #expect(current.heading == "Latest session · Dec 26, 2023")
    #expect(current.lines.map(\.headline) == ["120 kg × 5"])
    #expect(current.lines.map(\.standing) == [.produced])
    #expect(current.lines[0].detail == "120 × (1 + 5 ÷ 30) → 140 kg. This set is the figure.")

    let baseline = account.sections[1]
    #expect(baseline.heading == "Baseline · Nov 14, 2023")
    #expect(baseline.lines.map(\.headline) == ["100 kg × 5", "100 kg × 8"])
    #expect(baseline.lines.map(\.standing) == [.counted, .produced])
    #expect(baseline.lines[1].detail == "100 × (1 + 8 ÷ 30) → 126.5 kg. This set is the figure.")

    // Every set that took no part is a line with its reason.
    let left = account.sections[2]
    #expect(left.lines.map(\.id) == ["baseline-left-0", "baseline-warmups", "baseline-elsewhere"])
    #expect(left.lines.allSatisfy { $0.standing == .excluded })
    #expect(left.lines[0].headline == "60 kg × 15")
    #expect(left.lines[0].detail == "Left out: 15 reps is above 12, where no one-rep max is estimated.")
    #expect(left.lines[1].headline == "1 warm-up set")
    #expect(left.lines[1].detail.hasPrefix("Left out: warm-ups"))
    #expect(left.lines[2].headline == "1 set on other equipment")
    #expect(left.lines[2].detail.hasPrefix("Left out: each machine has its own line"))
    #expect(account.spoken.contains("Estimated max over six weeks, +11%"))
    #expect(account.spoken.contains("3 sets counted, 3 sets left out"))
  }

  @Test("Sessions looked at and not used are named: passed over in the band, outside it, or with no estimate")
  func sessionsNotUsed() throws {
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let baseline = SessionID()
    let below = SessionID()
    let tooRecent = SessionID()
    let allHighReps = SessionID()
    let latest = SessionID()
    let samples = [
      sample(baseline, 100, 8, day: 0, machine: hammer),
      sample(below, 90, 8, day: 3, machine: hammer),
      sample(tooRecent, 95, 8, day: 10, machine: hammer),
      sample(tooRecent, 95, 8, day: 10, minute: 5, machine: hammer),
      sample(allHighReps, 50, 15, day: -20, machine: hammer),
      sample(allHighReps, 50, 15, day: -20, minute: 5, machine: hammer),
      sample(latest, 120, 5, day: 42, machine: hammer),
    ]
    let working = try #require(sixWeek(key, samples))
    #expect(working.fraction == trend(key, samples)?.sixWeekChange)

    #expect(working.passedOver.map(\.reason) == [.belowBaseline])
    #expect(working.outsideBand == ChangeWorking.Tally(sessions: 1, sets: 2))
    #expect(working.withoutFigure == ChangeWorking.Tally(sessions: 1, sets: 2))

    let account = working.account(format: format)
    #expect(account.sections.map(\.id) == ["current", "baseline", "passed", "left"])
    let passed = account.sections[2]
    #expect(passed.lines.count == 1)
    #expect(passed.lines[0].headline == "Nov 17, 2023")
    #expect(passed.lines[0].detail == "Estimated max 114 kg. Below the baseline, so it was not used.")

    let left = account.sections[3]
    #expect(left.lines.map(\.id) == ["outside-band", "without-figure"])
    #expect(left.lines[0].headline == "1 session outside the band")
    #expect(left.lines[0].context == "2 sets")
    #expect(left.lines[0].detail.contains("5 to 7 weeks before the latest"))
    #expect(left.lines[1].headline == "1 session with no estimate")
    #expect(left.lines[1].detail == "Left out: every set in it is above 12 reps, where no one-rep max is estimated.")
  }

  @Test("A movement with no session in the band has no change, and so nothing to open")
  func noBaselineNoWorking() {
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let a = SessionID()
    let b = SessionID()
    let samples = [sample(a, 100, 5, day: 0, machine: hammer), sample(b, 105, 5, day: 20, machine: hammer)]
    #expect(trend(key, samples)?.sixWeekChange == nil)
    #expect(sixWeek(key, samples) == nil)
  }

  @Test("A measured change says it is measured, and names the heaviest load as the figure")
  func sixWeekHeaviestLoad() throws {
    let key = ProgressionKey(exerciseID: exercise)
    let older = SessionID()
    let latest = SessionID()
    // Every set above the estimable rep limit, so the row's metric is the heaviest load.
    let samples = [
      sample(older, 50, 15, day: 0), sample(older, 60, 15, day: 0, minute: 5),
      sample(latest, 70, 15, day: 42),
    ]
    let working = try #require(sixWeek(key, samples))
    #expect(working.metric == .heaviestLoad)
    #expect(working.certainty == nil)
    #expect(working.fraction == trend(key, samples)?.sixWeekChange)

    let account = working.account(format: format)
    #expect(account.title == "Heaviest weight over six weeks")
    #expect(account.figure == "+17%")
    #expect(account.figureCaption == "Measured, not estimated · Free weight · Nov 14, 2023 to Dec 26, 2023")
    #expect(account.ruleHeading == "Rule")
    #expect(account.rule.contains("heaviest load it logged"))
    #expect(!account.rule.contains("Epley"))
    let baseline = account.sections[1]
    #expect(baseline.lines.map(\.standing) == [.counted, .produced])
    #expect(baseline.lines[0].detail == "Lighter than the heaviest load. Below the figure.")
  }

  @Test("An added load whose body mass is unknown is rated Low and says why")
  func sixWeekAddedLoad() throws {
    let key = ProgressionKey(exerciseID: exercise)
    let older = SessionID()
    let latest = SessionID()
    let samples = [sample(older, 20, 8, day: 0), sample(latest, 30, 8, day: 42)]
    let working = try #require(sixWeek(key, samples, estimates: false, addedLoad: true))
    #expect(working.metric == .addedLoad)
    #expect(working.certainty == .low)
    #expect(working.fraction == trend(key, samples, estimates: false, addedLoad: true)?.sixWeekChange)
    let account = working.account(format: format)
    #expect(account.figureCaption.hasPrefix("Low confidence · "))
    #expect(account.rule.contains(ExerciseModality.unknownLoadAssumption))
    #expect(account.rule.contains("Nothing is estimated, and the change is rated Low confidence."))
  }

  @Test("Reps at the top weight are only compared at the same top weight, and a session that differs is named")
  func sixWeekRepsAtTopLoad() throws {
    let key = ProgressionKey(exerciseID: exercise)
    let sameTop = SessionID()
    let otherTop = SessionID()
    let latest = SessionID()
    // A bodyweight movement the app does not estimate: reps at the heaviest weight, bodyweight (0).
    let samples = [
      sample(sameTop, 0, 8, day: 0),
      sample(otherTop, 20, 12, day: 2),
      sample(latest, 0, 10, day: 42),
    ]
    let working = try #require(sixWeek(key, samples, estimates: false))
    #expect(working.metric == .repsAtTopLoad)
    #expect(working.fraction == trend(key, samples, estimates: false)?.sixWeekChange)
    #expect(working.passedOver.map(\.reason) == [.differentTopLoad])
    let account = working.account(format: format)
    #expect(account.sections[2].lines[0].detail.contains("only compared at the same top weight"))
    #expect(account.rule.contains("only compared at the same top weight"))
  }

  // MARK: - The scorecard's biggest gain

  private func prior(_ kg: Double, _ reps: Int, day: Int, minute: Int = 0) -> PriorSetRecord {
    PriorSetRecord(weightKg: kg, reps: reps, completedAt: at(minute, day: day))
  }

  @Test("A gain names this workout's sets, last time's sets, and everything the comparison passed over")
  func lastTimeGain() throws {
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let input = ScorecardInput(
      key: key, exerciseName: "Chest press",
      currentSets: [prior(100, 8, day: 7), prior(100, 6, day: 7, minute: 5)],
      previousSets: [prior(100, 5, day: 0), prior(100, 4, day: 0, minute: 5)],
      leftOut: ScorecardInput.LeftOut(
        currentWarmups: 2, currentOtherEquipment: 1, previousWarmups: 1, previousOtherEquipment: 0,
        olderSessions: 3, olderSets: 11))
    let card = WorkoutScorecard.make([input])
    let gain = try #require(card.biggestGain)
    let working = try #require(ChangeWorking.lastTime(gain: gain))

    #expect(working.fraction == gain.fraction)
    #expect(working.certainty == gain.certainty)
    #expect(working.metric == gain.metric)

    let account = working.account(format: format)
    #expect(account.title == "Estimated max since last time")
    #expect(account.figure == ProgressCopy.signedPercent(gain.fraction))
    #expect(account.figure == "+9%")
    #expect(
      account.figureCaption == "Moderate confidence · Chest press · Nov 14, 2023 to Nov 21, 2023")
    #expect(account.rule.contains("most recent earlier session that trained the same movement on the same machine"))
    #expect(account.rule.contains("weight × (1 + reps ÷ 30)"))
    #expect(account.sections.map(\.id) == ["current", "baseline", "left"])
    #expect(account.sections[0].heading == "This workout · Nov 21, 2023")
    #expect(account.sections[1].heading == "Last time · Nov 14, 2023")
    #expect(account.sections[0].lines.map(\.standing) == [.produced, .counted])

    let left = account.sections[2]
    #expect(left.lines.map(\.id) == ["current-warmups", "current-elsewhere", "baseline-warmups", "older"])
    #expect(left.lines.map(\.headline) == [
      "2 warm-up sets", "1 set on other equipment", "1 warm-up set", "3 sessions before last time",
    ])
    #expect(left.lines[3].context == "11 sets")
    #expect(left.lines[3].detail == "Left out: only the most recent earlier session on this machine is compared.")
  }

  @Test("A gain in the heaviest load is measured, and the account says so")
  func lastTimeMeasuredGain() throws {
    let key = ProgressionKey(exerciseID: exercise)
    // Above the rep limit on both sides, so no estimate exists and the scorecard falls back to load.
    let input = ScorecardInput(
      key: key, exerciseName: "Cable curl", currentSets: [prior(45, 15, day: 7)],
      previousSets: [prior(40, 15, day: 0)])
    let gain = try #require(WorkoutScorecard.make([input]).biggestGain)
    #expect(gain.metric == .heaviestLoad)
    let working = try #require(ChangeWorking.lastTime(gain: gain))
    #expect(working.fraction == gain.fraction)
    let account = working.account(format: format)
    #expect(account.figureCaption.hasPrefix("Measured, not estimated · Cable curl"))
    #expect(account.ruleHeading == "Rule")
  }

  @Test("A gain built without the sets it came from has nothing to open")
  func gainWithoutBasis() {
    let gain = WorkoutScorecard.Gain(
      key: ProgressionKey(exerciseID: exercise), exerciseName: "Chest press", fraction: 0.06,
      metric: .estimatedMax, certainty: .moderate)
    #expect(ChangeWorking.lastTime(gain: gain) == nil)
  }

  @Test("The scorecard's gain carries the sets it was computed from")
  func gainCarriesItsBasis() throws {
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let input = ScorecardInput(
      key: key, exerciseName: "Chest press", currentSets: [prior(105, 5, day: 7)],
      previousSets: [prior(100, 5, day: 0)])
    let gain = try #require(WorkoutScorecard.make([input]).biggestGain)
    #expect(gain.basis == input)
  }
}
