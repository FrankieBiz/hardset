import Foundation

/// The best reps ever performed at one weight, and when they were first reached.
public struct BestAtWeight: Hashable, Sendable, Identifiable {
  public let weightKg: Double
  public let reps: Int
  public let achievedAt: Date

  public var id: Double { weightKg }

  public init(weightKg: Double, reps: Int, achievedAt: Date) {
    self.weightKg = weightKg
    self.reps = reps
    self.achievedAt = achievedAt
  }
}

/// Builds the "best at each weight" table shown under a movement's graph.
///
/// Loads within the record detector's 0.01 kg tolerance are one weight, so 40 and a typed 40.004
/// do not become two rows. The first-seen value names the weight, and only the most reps and the
/// earliest date that reached them are kept.
public enum RepMaxLedger {
  /// `samples` must be one exercise-on-one-machine's history.
  public static func bests(from samples: [ProgressionSample]) -> [BestAtWeight] {
    var rows: [BestAtWeight] = []
    for sample in samples.sorted(by: { $0.completedAt < $1.completedAt }) {
      if let index = rows.firstIndex(where: {
        abs($0.weightKg - sample.weightKg) < PersonalRecordDetector.loadMatchingTolerance
      }) {
        let existing = rows[index]
        if sample.reps > existing.reps {
          rows[index] = BestAtWeight(
            weightKg: existing.weightKg, reps: sample.reps, achievedAt: sample.completedAt
          )
        }
      } else {
        rows.append(
          BestAtWeight(weightKg: sample.weightKg, reps: sample.reps, achievedAt: sample.completedAt)
        )
      }
    }
    return rows.sorted { $0.weightKg > $1.weightKg }
  }
}
