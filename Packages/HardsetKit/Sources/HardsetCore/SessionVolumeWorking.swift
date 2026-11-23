import Foundation

/// Which sets produced a workout's volume, set by set, and what was left out.
///
/// Volume leads the Train screen's last workout as its monument, 72 pt, because it is a sum of loads
/// and reps the lifter logged and not an estimate. A large number the lifter cannot inspect is
/// exactly what the product refuses, so it opens "Worked from", where every set that fed it is a line
/// of weight × reps and every set that did not is a line with its reason.
///
/// It applies `SessionVolume`'s three rules, the same ones `HistoryStore` applies to the rows it reads
/// for the summary: only logged sets count (a receipt holds nothing else), warm-ups are left out of
/// volume, working sets and reps, and a working set with no load adds nothing to volume while still
/// counting as a working set and as its reps. `volume` is the summary's `SessionVolume`, and a Store
/// test holds the two equal on a real database.
public struct SessionVolumeWorking: Hashable, Sendable {
  /// One set of the workout, in the order it was performed.
  public struct Entry: Hashable, Sendable, Identifiable {
    public let id: Int
    public let exerciseName: String
    /// The machine's display name, or what the receipt says the set was done on.
    public let equipment: String
    public let weightKg: Double
    public let reps: Int
    public let isWarmup: Bool

    /// What the set adds to volume: weight × reps, and nothing for a warm-up.
    public var volumeKg: Double { isWarmup ? 0 : weightKg * Double(reps) }
  }

  /// Every set of the workout, in the order performed.
  public let entries: [Entry]

  /// The summary figures, by `SessionVolume`'s own rules.
  public var volume: SessionVolume {
    var workingSets = 0
    var warmupSets = 0
    var volumeKg = 0.0
    var reps = 0
    for entry in entries {
      if entry.isWarmup {
        warmupSets += 1
      } else {
        workingSets += 1
        volumeKg += entry.weightKg * Double(entry.reps)
        reps += entry.reps
      }
    }
    return SessionVolume(
      workingSets: workingSets, warmupSets: warmupSets, volumeKg: volumeKg, reps: reps)
  }

  public static func derive(lines: [WorkoutReceipt.Line]) -> SessionVolumeWorking {
    SessionVolumeWorking(
      entries: lines.enumerated().map { offset, line in
        Entry(
          id: offset, exerciseName: line.exerciseName, equipment: line.equipmentLabel,
          weightKg: line.weightKg, reps: line.reps, isWarmup: line.isWarmup)
      })
  }

  // MARK: - Words

  static func rule(format: WorkedFromFormat) -> String {
    let nearest = format.unit == .kilograms ? "kilogram" : "pound"
    return "Volume is the sum of weight × reps over the working sets of the workout. Warm-ups are left "
      + "out, and a set with no load adds nothing to it. It is a sum of what you logged, so it carries "
      + "no confidence rating. It is shown to the nearest \(nearest); each line below is exact."
  }

  /// The volume as the Train screen writes it: whole units, no grouping surprises.
  static func shownVolume(_ kilograms: Double, format: WorkedFromFormat) -> String {
    format.unit.fromKilograms(kilograms).rounded()
      .formatted(.number.precision(.fractionLength(0)).locale(format.locale))
  }

  /// What the account says, built from this derivation and nothing else.
  ///
  /// - Parameter title: What the workout is called, or its date, for the heading.
  public func account(title: String, format: WorkedFromFormat) -> WorkedFromAccount {
    let summary = volume
    let figure = "\(Self.shownVolume(summary.volumeKg, format: format)) \(format.unit.abbreviation)"
    let working = entries.filter { !$0.isWarmup }
    let warmups = entries.filter(\.isWarmup)

    let fed = working.map { entry -> WorkedFromAccount.Line in
      let set = format.set(weightKg: entry.weightKg, reps: entry.reps)
      let adds = entry.weightKg > 0
        ? "= \(format.load(entry.volumeKg))"
        : "No load, so it adds nothing to volume. It still counts as a working set and as its reps."
      return WorkedFromAccount.Line(
        id: "set-\(entry.id)", standing: .counted, headline: set, context: "\(entry.exerciseName) · \(entry.equipment)",
        detail: adds,
        spoken: "\(entry.exerciseName), \(format.setSpoken(weightKg: entry.weightKg, reps: entry.reps))"
          + (entry.weightKg > 0 ? ", \(format.loadSpoken(entry.volumeKg))" : ", no load, adds nothing") + ".")
    }
    let left = warmups.map { entry -> WorkedFromAccount.Line in
      WorkedFromAccount.Line(
        id: "warmup-\(entry.id)", standing: .excluded,
        headline: format.set(weightKg: entry.weightKg, reps: entry.reps),
        context: "\(entry.exerciseName) · \(entry.equipment) · warm-up",
        detail: "Left out: warm-ups never count toward volume.",
        spoken: "\(entry.exerciseName), \(format.setSpoken(weightKg: entry.weightKg, reps: entry.reps)), "
          + "warm-up. Left out: warm-ups never count toward volume.")
    }

    let sections = [
      WorkedFromAccount.Section(
        id: "fed", heading: "Sets that fed this figure",
        note: working.isEmpty
          ? "No working set was logged."
          : "\(working.count == 1 ? "1 working set" : "\(working.count) working sets") · "
            + "\(summary.reps == 1 ? "1 rep" : "\(summary.reps) reps"), in the order you did them.",
        lines: fed),
      WorkedFromAccount.Section(
        id: "left", heading: "Left out",
        note: left.isEmpty ? "Nothing was left out." : "Warm-ups never count toward volume.",
        lines: left),
    ]

    let leftSentence = warmups.isEmpty
      ? "Nothing was left out."
      : "Left out: \(warmups.count == 1 ? "1 warm-up set" : "\(warmups.count) warm-up sets")."
    return WorkedFromAccount(
      title: "Volume", figure: figure,
      figureCaption: "\(title) · counted from sets you logged, not estimated",
      ruleHeading: "How volume is summed", rule: Self.rule(format: format), sections: sections,
      spoken: "Volume, \(figure), \(title), counted from sets you logged, not estimated. "
        + "\(working.count == 1 ? "1 working set" : "\(working.count) working sets"), "
        + "\(summary.reps == 1 ? "1 rep" : "\(summary.reps) reps"). \(leftSentence)")
  }
}
