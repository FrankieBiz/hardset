import Foundation
import Testing

@testable import HardsetCore

@Suite("Worked from: an estimated one-rep max")
struct EstimateWorkingTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)  // 14 Nov 2023, 22:13:20 UTC
  let exercise = ExerciseID()
  let hammer = MachineID()
  let cybex = MachineID()
  let format = WorkedFromFormat(
    unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

  private func at(_ minutes: Int, day: Int = 0) -> Date {
    epoch.addingTimeInterval(Double(day) * 86_400 + Double(minutes) * 60)
  }

  private func sample(
    _ session: SessionID, _ kg: Double, _ reps: Int, minute: Int, day: Int = 0,
    machine: MachineID? = nil, imported: Bool = false
  ) -> ProgressionSample {
    ProgressionSample(
      sessionID: session, machineID: machine, weightKg: kg, reps: reps,
      completedAt: at(minute, day: day), isImported: imported)
  }

  private func label(_ key: ProgressionKey) -> String {
    if key.isImported { return "Imported · machine not recorded" }
    switch key.machineID {
    case hammer: return "Hammer Strength"
    case cybex: return "Cybex"
    default: return "Free weight"
    }
  }

  private func derive(
    _ key: ProgressionKey, _ session: SessionID, _ samples: [ProgressionSample],
    warmups: [ProgressionSample] = [], estimates: Bool = true, addedLoad: Bool = false
  ) -> EstimateWorking? {
    EstimateWorking.derive(
      key: key, sessionID: session, samples: samples, warmups: warmups,
      estimatesOneRepMax: estimates, assumesAddedLoad: addedLoad, label: label)
  }

  // MARK: - Which sets, what credit, what was left out

  @Test("A known session names the set that is the figure, the set below it, and the set it left out")
  func knownSession() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 100, 5, minute: 0, machine: hammer),
          sample(session, 100, 8, minute: 5, machine: hammer),
          sample(session, 60, 15, minute: 10, machine: hammer),
        ]))

    #expect(working.figureKg == StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 8).value)
    #expect(working.certainty == .moderate)
    #expect(working.entries.map(\.standing) == [.counted, .figure, .excluded(.aboveRepLimit(reps: 15))])
    #expect(working.entries.map(\.reps) == [5, 8, 15])
    #expect(working.entries[2].estimateKg == nil)

    let account = working.account(format: format)
    #expect(account.title == "Estimated one-rep max")
    #expect(account.figure == "126.5 kg")
    #expect(account.figureCaption == "Moderate confidence · Hammer Strength · Nov 14, 2023")
    #expect(account.ruleHeading == "Formula")
    #expect(account.rule.contains("weight × (1 + reps ÷ 30)"))
    #expect(account.rule.contains("Sets above 12 reps are not estimated."))
    #expect(account.rule.contains("nearest 0.5 kg"))

    let fed = try #require(account.sections.first { $0.id == "fed" })
    #expect(fed.lines.map(\.headline) == ["100 kg × 5", "100 kg × 8"])
    #expect(fed.lines.map(\.standing) == [.counted, .produced])
    #expect(fed.lines[0].detail == "100 × (1 + 5 ÷ 30) → 116.5 kg. Below the figure.")
    #expect(fed.lines[1].detail == "100 × (1 + 8 ÷ 30) → 126.5 kg. This set is the figure.")
    #expect(fed.lines[1].context == "Nov 14, 2023 · Hammer Strength")

    let left = try #require(account.sections.first { $0.id == "left" })
    #expect(left.lines.count == 1)
    #expect(left.lines[0].headline == "60 kg × 15")
    #expect(left.lines[0].standing == .excluded)
    #expect(left.lines[0].detail == "Left out: 15 reps is above 12, where no one-rep max is estimated.")
  }

  @Test("A set from the same session on another machine is listed as left out, with the machine")
  func otherMachineInSameSession() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 100, 5, minute: 0, machine: hammer),
          sample(session, 140, 3, minute: 20, machine: cybex),
        ]))

    #expect(working.entries.count == 2)
    #expect(working.entries[1].standing == .excluded(.otherSeries(label: "Cybex")))
    #expect(working.entries[1].seriesLabel == "Cybex")
    // The heavier set on the other machine did not move the figure.
    #expect(working.figureKg == StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 5).value)
    let left = try #require(working.account(format: format).sections.first { $0.id == "left" })
    #expect(
      left.lines[0].detail
        == "Left out: logged on Cybex. Each machine has its own line, so this set does not feed this one.")
  }

  @Test("Sets in other sessions on other equipment, or imported, are counted and named, never mixed in")
  func otherSeriesAreCounted() throws {
    let session = SessionID()
    let earlier = SessionID()
    let imported = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 100, 5, minute: 0, machine: hammer),
          sample(earlier, 120, 5, minute: 0, day: -7, machine: cybex),
          sample(earlier, 120, 4, minute: 5, day: -7, machine: cybex),
          sample(imported, 130, 5, minute: 0, day: -30, imported: true),
        ]))

    #expect(working.setsOnOtherSeries == 3)
    let left = try #require(working.account(format: format).sections.first { $0.id == "left" })
    #expect(left.lines.map(\.headline) == ["3 sets on other equipment"])
    #expect(left.lines[0].standing == .excluded)
  }

  @Test("Warm-ups in the session are listed as left out, even the heaviest one")
  func warmupsAreListed() throws {
    let session = SessionID()
    let other = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [sample(session, 100, 5, minute: 10, machine: hammer)],
        warmups: [
          sample(session, 150, 3, minute: 0, machine: hammer),
          sample(other, 60, 10, minute: 0, day: -3, machine: hammer),
        ]))

    #expect(working.entries.map(\.standing) == [.excluded(.warmup), .figure])
    // The warm-up from another session is not this session's to list.
    #expect(working.entries.count == 2)
    #expect(working.figureKg == StrengthMath.estimatedOneRepMax(weightKg: 100, reps: 5).value)
    let left = try #require(working.account(format: format).sections.first { $0.id == "left" })
    #expect(left.lines[0].detail == "Left out: a warm-up. Warm-ups are never counted.")
  }

  @Test("A session with nothing left out says so, and still states what is never mixed in")
  func nothingLeftOut() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(derive(key, session, [sample(session, 100, 5, minute: 0, machine: hammer)]))
    let left = try #require(working.account(format: format).sections.first { $0.id == "left" })
    #expect(left.lines.isEmpty)
    #expect(left.note?.hasPrefix("Nothing in this session was left out.") == true)
    #expect(left.note?.contains("Warm-ups, other machines and imported history") == true)
  }

  @Test("A single is taken as measured, not estimated, and keeps high certainty")
  func measuredSingle() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(derive(key, session, [sample(session, 140, 1, minute: 0, machine: hammer)]))

    #expect(working.figureKg == 140)
    #expect(working.certainty == .high)
    #expect(working.entries[0].isMeasuredSingle)
    let account = working.account(format: format)
    #expect(account.figure == "140 kg")
    #expect(
      account.sections[0].lines[0].detail == "A single is taken as measured: 140 kg. This set is the figure.")
  }

  @Test("Two sets that estimate the same share the figure, and the account says so")
  func tiedSets() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 80, 6, minute: 0, machine: hammer),
          sample(session, 80, 6, minute: 5, machine: hammer),
        ]))
    #expect(working.figureSetCount == 2)
    let fed = try #require(working.account(format: format).sections.first { $0.id == "fed" })
    #expect(fed.note == "2 sets share the highest estimate.")
    #expect(fed.lines.allSatisfy { $0.detail.hasSuffix("This set ties for the figure.") })
  }

  @Test("A session of high-rep sets has no figure, and every set is listed as left out with why")
  func noEstimate() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 50, 15, minute: 0, machine: hammer),
          sample(session, 50, 20, minute: 5, machine: hammer),
        ]))
    #expect(working.figureKg == nil)
    #expect(working.certainty == .unevaluated)
    let account = working.account(format: format)
    #expect(account.figure == "No estimate")
    #expect(account.sections.map(\.id) == ["left"])
    #expect(account.sections[0].lines.count == 2)
    #expect(account.spoken.contains("no estimate"))
    #expect(account.spoken.contains("No set in this session could be estimated."))
  }

  @Test("A load of zero, or one no lift reaches, is left out as a load and not blamed on the reps")
  func implausibleLoads() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 0, 8, minute: 0, machine: hammer),
          sample(session, 1_500, 5, minute: 5, machine: hammer),
          sample(session, 100, 5, minute: 10, machine: hammer),
        ]))
    #expect(working.entries.map(\.standing) == [.excluded(.implausibleLoad), .excluded(.implausibleLoad), .figure])
    let left = try #require(working.account(format: format).sections.first { $0.id == "left" })
    #expect(left.lines[0].detail == "Left out: a load of zero, or above 1000 kg, is not estimated.")
  }

  @Test("A movement that is not estimated lists every set as left out and says which kind of movement")
  func movementNotEstimated() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: nil)
    let sets = [sample(session, 20, 8, minute: 0)]

    let bodyweight = try #require(derive(key, session, sets, estimates: false))
    #expect(bodyweight.figureKg == nil)
    #expect(bodyweight.entries[0].standing == .excluded(.movementNotEstimated(assumesAddedLoad: false)))
    #expect(
      bodyweight.account(format: format).sections[0].lines[0].detail
        == "Left out: body mass is not recorded with each set, so a one-rep max is not estimated for bodyweight movements.")

    let unknown = try #require(derive(key, session, sets, estimates: false, addedLoad: true))
    #expect(unknown.entries[0].standing == .excluded(.movementNotEstimated(assumesAddedLoad: true)))
    #expect(
      unknown.account(format: format).sections[0].lines[0].detail.contains("this movement's type is unknown"))
  }

  @Test("A session the series does not have has no working")
  func unknownSession() {
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    #expect(derive(key, SessionID(), [sample(SessionID(), 100, 5, minute: 0, machine: hammer)]) == nil)
  }

  // MARK: - The same calculation as the chart

  /// The point of the design: the figure in the account is the point on the chart, set for set.
  @Test("Every point the analyser draws has a working with the same figure and the same certainty")
  func parityWithTheChart() throws {
    var generator = SplitMix(seed: 7)
    let machines: [MachineID?] = [hammer, cybex, nil]
    let sessions = (0..<14).map { _ in SessionID() }
    var samples: [ProgressionSample] = []
    for (index, session) in sessions.enumerated() {
      let machine = machines[index % 3]
      for setIndex in 0..<Int.random(in: 2...5, using: &generator) {
        samples.append(
          sample(
            session, Double(Int.random(in: 8...60, using: &generator)) * 2.5,
            Int.random(in: 1...20, using: &generator), minute: setIndex * 4, day: index * 3,
            machine: machine, imported: index == 13))
      }
    }

    let series = ProgressionAnalyzer.series(from: samples, exerciseID: exercise)
    #expect(!series.isEmpty)
    var compared = 0
    for one in series {
      for point in one.points {
        let working = try #require(derive(one.key, point.sessionID, samples))
        #expect(working.figureKg == point.bestEstimatedOneRepMaxKg)
        #expect(working.date == point.date)
        if point.bestEstimatedOneRepMaxKg != nil {
          #expect(working.certainty == point.bestEstimateCertainty)
          #expect(working.figureSetCount >= 1)
        } else {
          #expect(working.figureSetCount == 0)
        }
        compared += 1
      }
    }
    #expect(compared == series.reduce(0) { $0 + $1.points.count })
  }

  @Test("The working behind a legend's latest figure is the latest session that has an estimate")
  func latestMatchesTheLegend() throws {
    let older = SessionID()
    let newest = SessionID()
    let noEstimate = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let samples = [
      sample(older, 100, 5, minute: 0, day: -14, machine: hammer),
      sample(newest, 105, 5, minute: 0, day: -7, machine: hammer),
      // A later session with only high-rep work draws no point, so it is not the latest figure.
      sample(noEstimate, 50, 20, minute: 0, machine: hammer),
    ]
    let working = try #require(
      EstimateWorking.deriveLatest(
        key: key, samples: samples, estimatesOneRepMax: true, label: label))
    #expect(working.sessionID == newest)

    let series = ProgressionAnalyzer.series(from: samples, exerciseID: exercise)
    let lastWithEstimate = series[0].points.last { $0.bestEstimatedOneRepMaxKg != nil }
    #expect(working.sessionID == lastWithEstimate?.sessionID)
    #expect(working.figureKg == lastWithEstimate?.bestEstimatedOneRepMaxKg)
  }

  // MARK: - Words

  @Test("Pounds are shown in pounds and the estimate rounds to a pound")
  func pounds() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(derive(key, session, [sample(session, 100, 5, minute: 0, machine: hammer)]))
    let lb = WorkedFromFormat(
      unit: .pounds, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
    let account = working.account(format: lb)
    #expect(account.figure == "257 lb")
    #expect(account.rule.contains("nearest 1 lb"))
    #expect(account.sections[0].lines[0].headline == "220.46 lb × 5")
  }

  @Test("The day is the day in the lifter's own time zone")
  func dayInTheLiftersTimeZone() {
    let late = Date(timeIntervalSince1970: 1_700_000_000)  // 22:13 UTC on 14 Nov
    let auckland = WorkedFromFormat(
      unit: .kilograms, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "Pacific/Auckland")!)
    #expect(format.day(late) == "Nov 14, 2023")
    #expect(auckland.day(late) == "Nov 15, 2023")
  }

  @Test("What is read aloud is sentences: no multiplication sign, no arrow, no table")
  func spokenIsProse() throws {
    let session = SessionID()
    let key = ProgressionKey(exerciseID: exercise, machineID: hammer)
    let working = try #require(
      derive(
        key, session,
        [
          sample(session, 100, 5, minute: 0, machine: hammer),
          sample(session, 100, 8, minute: 5, machine: hammer),
          sample(session, 60, 15, minute: 10, machine: hammer),
        ],
        warmups: [sample(session, 40, 10, minute: -5, machine: hammer)]))
    let account = working.account(format: format)

    #expect(
      account.spoken
        == "Estimated one-rep max, 126.5 kilograms, Moderate confidence, Hammer Strength, Nov 14, 2023. "
        + "It comes from 100 kilograms for 8 reps. 2 sets counted, 2 left out.")
    let spoken = account.sections.flatMap(\.lines).map(\.spoken)
    for text in spoken + [account.spoken] {
      #expect(!text.contains("×") && !text.contains("÷") && !text.contains("→"))
    }
    #expect(
      spoken.contains(
        "100 kilograms for 8 reps on Nov 14, 2023, Hammer Strength. "
          + "100 times one plus 8 over 30 comes to 126.5 kilograms. This set is the figure."))
  }

  @Test("The rounding the account states is the rounding the figure gets")
  func roundingIsStatedTruthfully() {
    #expect(StrengthMath.displayRounded(116.67, in: .kilograms) == 116.5)
    #expect(StrengthMath.displayRounded(116.67, in: .pounds) == 257)
    #expect(StrengthMath.epleyRepsDivisor == 30)
    #expect(
      StrengthMath.estimatedOneRepMax(weightKg: 90, reps: 6).value == 90 * (1 + 6 / StrengthMath.epleyRepsDivisor))
  }
}

/// A seeded generator, so the parity test sees the same sets on every run and every platform.
struct SplitMix: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
