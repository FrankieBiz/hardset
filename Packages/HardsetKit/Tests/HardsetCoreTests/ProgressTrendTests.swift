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
}
