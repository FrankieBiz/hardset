import Foundation

@main struct RecordStarBenchmark {
  static func main() {
    let machine = MachineID()
    let sessions = (0..<400).map { _ in SessionID() }
    let samples: [ProgressionSample] = (0..<2_000).map { index in
      let load = 40.0 + Double((index / 5) % 30) * 2.5
      let date = Date(timeIntervalSince1970: Double(index) * 60)
      return ProgressionSample(sessionID: sessions[index / 5], machineID: machine,
        weightKg: load, reps: 6 + index % 7, completedAt: date)
    }
    var times: [Double] = []
    var count = 0
    for _ in 0..<5 {
      let start = ContinuousClock.now
      count = ProgressTrendAnalyzer.recordSessionIDs(samples: samples, incrementKg: 2.5,
        estimatesOneRepMax: true).count
      let duration = start.duration(to: .now).components
      times.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
    }
    print("2,000 sets, 400 sessions, debug median ms: \(times.sorted()[2]); record sessions: \(count); samples ms: \(times)")
  }
}
