import Foundation
import Testing

@testable import HardsetCore

@Suite("Movement trends, records per session and stalls")
struct ProgressTrendTests {
  let epoch = Date(timeIntervalSince1970: 1_700_000_000)
  let exercise = ExerciseID()

  private func day(_ n: Int) -> Date { epoch.addingTimeInterval(Double(n) * 86_400) }

  private func s(day dayNumber: Int, session: Int, kg: Double, reps: Int) -> ProgressionSample {
    ProgressionSample(
      sessionID: SessionID(rawValue: sessionUUID(session)),
      machineID: nil,
      weightKg: kg,
      reps: reps,
      completedAt: day(dayNumber).addingTimeInterval(Double(session))
    )
  }

  private func sessionUUID(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
  }

  private func key() -> ProgressionKey { ProgressionKey(exerciseID: exercise) }

  @Test func estimatedMaxChangeOverSixWeeks() {
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: [s(day: 0, session: 0, kg: 40, reps: 10), s(day: 42, session: 1, kg: 45, reps: 10)],
      incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.metric == .estimatedMax)
    #expect(abs((trend?.sixWeekChange ?? 0) - 0.125) < 1e-9)
  }

  @Test func noSessionInWindowMeansNoChange() {
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: [s(day: 0, session: 0, kg: 40, reps: 10), s(day: 20, session: 1, kg: 42.5, reps: 10)],
      incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.sixWeekChange == nil)
  }

  @Test func highRepWorkTrendsOnHeaviestLoad() {
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: [s(day: 0, session: 0, kg: 40, reps: 15), s(day: 7, session: 1, kg: 42.5, reps: 15)],
      incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.metric == .heaviestLoad)
  }

  @Test func bodyweightTrendsOnReps() {
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: [s(day: 0, session: 0, kg: 0, reps: 10), s(day: 7, session: 1, kg: 0, reps: 12)],
      incrementKg: nil, estimatesOneRepMax: false
    )
    #expect(trend?.metric == .repsAtTopLoad)
    #expect(trend?.sparkline == [10, 12])
  }

  @Test func sparklineKeepsTwelveNewest() {
    let samples = (0..<15).map { index in
      s(day: index * 7, session: index, kg: 40 + Double(index), reps: 10)
    }
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.sparkline.count == 12)
    #expect(abs((trend?.sparkline.last ?? 0) - 72) < 1e-9)
  }

  @Test func flatFourSessionsStall() {
    let samples = (0..<4).map { index in
      s(day: index * 7, session: index, kg: 40, reps: 10)
    }
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.stalledSessions == 3)
  }

  @Test func aLongFlatHistoryReportsTheThreeSessionsThatDecideIt() {
    // Only the last three sessions decide a stall, so the label never claims a longer run than
    // the sessions that were actually checked.
    let samples = (0..<10).map { index in
      s(day: index * 7, session: index, kg: 40, reps: 10)
    }
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.stalledSessions == ProgressTrendAnalyzer.stallRun)
  }

  @Test func aRecordFourSessionsBackDoesNotHideAStall() {
    var samples = (0..<6).map { index in
      s(day: index * 7, session: index, kg: 40, reps: 10)
    }
    samples.append(s(day: 42, session: 6, kg: 42.5, reps: 10))
    samples.append(contentsOf: (7..<10).map { index in
      s(day: index * 7, session: index, kg: 42.5, reps: 10)
    })
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.stalledSessions == ProgressTrendAnalyzer.stallRun)
  }

  @Test func aRecordInTheLastThreeIsNotAStall() {
    var samples = (0..<3).map { index in
      s(day: index * 7, session: index, kg: 40, reps: 10)
    }
    samples.append(s(day: 21, session: 3, kg: 42.5, reps: 10))
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.stalledSessions == nil)
  }

  @Test func threeSessionsCannotStall() {
    let samples = (0..<3).map { index in
      s(day: index * 7, session: index, kg: 40, reps: 10)
    }
    let trend = ProgressTrendAnalyzer.trend(
      key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(trend?.stalledSessions == nil)
  }

  @Test func firstSessionIsNeverARecord() {
    let records = ProgressTrendAnalyzer.recordSessionIDs(
      samples: [s(day: 0, session: 0, kg: 40, reps: 10)],
      incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(records.isEmpty)
  }

  @Test func recordSessionsFound() {
    let samples = [
      s(day: 0, session: 0, kg: 40, reps: 10),
      s(day: 7, session: 1, kg: 40, reps: 11),
      s(day: 14, session: 2, kg: 40, reps: 11),
    ]
    let records = ProgressTrendAnalyzer.recordSessionIDs(
      samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
    )
    #expect(records == [SessionID(rawValue: sessionUUID(1))])
  }

  @Test func trendOfALongHistoryStaysFast() {
    // The progress board computes a trend for every movement on open. A lifter's busiest movement
    // is 400 sessions of five sets, so the record replay must not grow with the square of that.
    var samples: [ProgressionSample] = []
    for session in 0..<400 {
      for position in 0..<5 {
        samples.append(
          ProgressionSample(
            sessionID: SessionID(rawValue: sessionUUID(session)),
            machineID: nil,
            weightKg: 40 + Double(session / 40) * 2.5,
            reps: 8 + (session + position) % 5,
            completedAt: day(session * 2).addingTimeInterval(Double(position))
          )
        )
      }
    }
    #expect(samples.count == 2_000)

    var trend: MovementTrend?
    let elapsed = ContinuousClock().measure {
      trend = ProgressTrendAnalyzer.trend(
        key: key(), samples: samples, incrementKg: 2.5, estimatesOneRepMax: true
      )
    }

    #expect(trend?.sessionCount == 400)
    #expect(elapsed < .milliseconds(50), "trend over 2,000 sets took \(elapsed)")
  }

  @Test func bodyweightRepsAreOnlyComparedAtTheSameAddedLoad() {
    // Pull-ups with +20 kg for 5 six weeks ago, then bodyweight for 10: not 100% better, because the
    // two numbers are reps at different loads.
    let dropped = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [s(day: 0, session: 0, kg: 20, reps: 5), s(day: 42, session: 1, kg: 0, reps: 10)],
      incrementKg: nil, estimatesOneRepMax: false
    )
    // Adding load: 12 reps at bodyweight, then 6 at +10 kg, is not 50% worse.
    let added = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [s(day: 0, session: 0, kg: 0, reps: 12), s(day: 42, session: 1, kg: 10, reps: 6)],
      incrementKg: nil, estimatesOneRepMax: false
    )
    // The same load both times is a fair comparison.
    let same = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [s(day: 0, session: 0, kg: 0, reps: 8), s(day: 42, session: 1, kg: 0, reps: 10)],
      incrementKg: nil, estimatesOneRepMax: false
    )
    // A load within tolerance is the same load.
    let noisy = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [s(day: 0, session: 0, kg: 10, reps: 8), s(day: 42, session: 1, kg: 10.004, reps: 10)],
      incrementKg: nil, estimatesOneRepMax: false
    )

    #expect(dropped?.sixWeekChange == nil)
    #expect(added?.sixWeekChange == nil)
    #expect(abs((same?.sixWeekChange ?? 0) - 0.25) < 1e-9)
    #expect(abs((noisy?.sixWeekChange ?? 0) - 0.25) < 1e-9)
  }

  @Test func estimatedMaxTrendCarriesTheCertaintyOfItsLatestEstimate() {
    // Ten reps is moderate, five is high, twelve is low: certainty follows the reps behind it.
    func certainty(reps: Int) -> Certainty? {
      ProgressTrendAnalyzer.trend(
        key: key(),
        samples: [s(day: 0, session: 0, kg: 40, reps: reps), s(day: 7, session: 1, kg: 42.5, reps: reps)],
        incrementKg: 2.5, estimatesOneRepMax: true
      )?.certainty
    }

    #expect(certainty(reps: 5) == .high)
    #expect(certainty(reps: 10) == .moderate)
    #expect(certainty(reps: 12) == .low)
  }

  @Test func theCertaintyBelongsToTheSetThatMadeTheEstimate() {
    // Ten reps at 40 estimates 53.3; three reps at 45 estimates 49.5, so the ten-rep set is best.
    let trend = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [
        s(day: 0, session: 0, kg: 40, reps: 8),
        s(day: 7, session: 1, kg: 40, reps: 10),
        s(day: 7, session: 1, kg: 45, reps: 3),
      ],
      incrementKg: 2.5, estimatesOneRepMax: true
    )

    #expect(trend?.metric == .estimatedMax)
    #expect(trend?.certainty == .moderate)
  }

  @Test("Six-week change and scorecard both report the weaker estimate", arguments: [true, false])
  func changeCarriesWeakerCertainty(priorIsLow: Bool) throws {
    let prior = s(day: 0, session: 0, kg: 40, reps: priorIsLow ? 12 : 5)
    let current = s(day: 42, session: 1, kg: 60, reps: priorIsLow ? 5 : 12)
    let trend = try #require(ProgressTrendAnalyzer.trend(key: key(), samples: [prior, current],
      incrementKg: 2.5, estimatesOneRepMax: true))
    let scorecard = WorkoutScorecard.make([ScorecardInput(key: key(), exerciseName: "Press",
      currentSets: [PriorSetRecord(weightKg: current.weightKg, reps: current.reps, completedAt: current.completedAt)],
      previousSets: [PriorSetRecord(weightKg: prior.weightKg, reps: prior.reps, completedAt: prior.completedAt)],
      repRange: nil, setRecord: false)])
    #expect(trend.certainty == .low)
    #expect(trend.certainty == scorecard.biggestGain?.certainty)
  }

  @Test func onlyAnEstimateHasACertainty() {
    let heaviest = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [s(day: 0, session: 0, kg: 40, reps: 15), s(day: 7, session: 1, kg: 42.5, reps: 15)],
      incrementKg: 2.5, estimatesOneRepMax: true
    )
    let bodyweight = ProgressTrendAnalyzer.trend(
      key: key(),
      samples: [s(day: 0, session: 0, kg: 0, reps: 10), s(day: 7, session: 1, kg: 0, reps: 12)],
      incrementKg: nil, estimatesOneRepMax: false
    )

    #expect(heaviest?.metric == .heaviestLoad)
    #expect(heaviest?.certainty == nil)
    #expect(bodyweight?.certainty == nil)
  }

  @Test func mostImprovedOrdersByChange() {
    let changes: [Double?] = [0.05, 0.2, nil, -0.1, 0.1]
    let trends = changes.enumerated().map { index, change in
      MovementTrend(
        key: ProgressionKey(exerciseID: index == 0 ? exercise : ExerciseID()),
        metric: .estimatedMax,
        sparkline: [1],
        sixWeekChange: change,
        sessionCount: 2,
        stalledSessions: nil,
        latestDate: day(index)
      )
    }
    #expect(ProgressTrendAnalyzer.mostImproved(trends).compactMap(\.sixWeekChange) == [0.2, 0.1, 0.05])
  }
  @Test("Incremental replay preserves the full detector at tolerance edges and arbitrary rep counts",
    arguments: [true, false])
  func replayMatchesFullHistory(estimates: Bool) {
    let loads = [0.0, 40, 40.009, 40.01, 40.011, 42.5, 50, 100, 105, 1001]
    let reps = [1, 5, 8, 12, 13, 20, 999]
    let samples = (0..<350).map { index in
      s(day: index / 5, session: index / 5, kg: loads[(index * 7) % loads.count],
        reps: reps[(index * 11) % reps.count])
    }
    var index = RecordReplayIndex(samples: samples)
    var full: [PriorSetRecord] = []
    for sample in samples {
      let candidate = PersonalRecordDetector.Candidate(weightKg: sample.weightKg, reps: sample.reps)
      let expected = PersonalRecordDetector.records(for: candidate, history: full,
        increment: 5, estimatesOneRepMax: estimates)
      let actual = PersonalRecordDetector.records(for: candidate, history: index.comparisons(for: sample),
        increment: 5, estimatesOneRepMax: estimates)
      #expect(actual == expected)
      index.append(sample)
      full.append(PriorSetRecord(weightKg: sample.weightKg, reps: sample.reps, completedAt: sample.completedAt))
    }
  }

}
