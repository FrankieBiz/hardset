import Foundation

/// What one movement on one machine actually did at each rep count.
///
/// This is the inverse of `RepMaxLedger`'s "best at each weight": for each count from one to
/// twelve, the heaviest working set completed with exactly that many reps. It is a table of sets
/// the lifter logged, not an estimate, so no rung is worked out with Epley and a rep count with no
/// set is absent rather than dashed, interpolated or filled in.
///
/// Loads within `PersonalRecordDetector.loadMatchingTolerance` are one load, as they are for a
/// record, so a typed 40 and a typed 40.004 do not produce two rungs. The first set at that load
/// names the rung and its date, as `RepMaxLedger` names a weight, so the cell always opens a set
/// that exists.
public struct RepLadder: Hashable, Sendable {
  /// The counts a ladder covers. Thirteen reps and above are a different kind of work and get no
  /// rung, which is the same ceiling an estimate is held to.
  public static let repCounts = 1...12

  /// One rep count and the set that holds it.
  public struct Rung: Hashable, Sendable, Identifiable {
    public let reps: Int
    public let weightKg: Double
    public let sessionID: SessionID
    public let completedAt: Date

    public var id: Int { reps }

    public init(reps: Int, weightKg: Double, sessionID: SessionID, completedAt: Date) {
      self.reps = reps
      self.weightKg = weightKg
      self.sessionID = sessionID
      self.completedAt = completedAt
    }
  }

  public let key: ProgressionKey
  /// Ascending by rep count. A count with no set is not in this array.
  public let rungs: [Rung]

  public init(key: ProgressionKey, rungs: [Rung]) {
    self.key = key
    self.rungs = rungs
      .filter { Self.repCounts.contains($0.reps) }
      .sorted { $0.reps < $1.reps }
  }

  public var isEmpty: Bool { rungs.isEmpty }

  /// The rung at `reps`, or `nil` when no set was completed at that count.
  public func rung(reps: Int) -> Rung? {
    rungs.first { $0.reps == reps }
  }

  // MARK: - Derivation

  /// One movement-on-one-machine's ladder from its working sets.
  ///
  /// `samples` may carry other machines and imported history; only the sets matching `key` are
  /// read. Warm-ups never reach here, because the history reads working sets only, so a warm-up
  /// cannot become a rung.
  public static func ladder(
    for key: ProgressionKey, from samples: [ProgressionSample]
  ) -> RepLadder {
    RepLadder(key: key, rungs: rungs(from: samples.filter { key.contains($0) }))
  }

  /// Every key in `samples`, each with its own ladder. Two machines remain two ladders; nothing is
  /// ever combined into one line.
  public static func ladders(
    for exerciseID: ExerciseID, from samples: [ProgressionSample]
  ) -> [ProgressionKey: RepLadder] {
    var ladders: [ProgressionKey: RepLadder] = [:]
    for sample in samples {
      let key = ProgressionKey(
        exerciseID: exerciseID, machineID: sample.machineID, isImported: sample.isImported)
      if ladders[key] == nil {
        ladders[key] = ladder(for: key, from: samples)
      }
    }
    return ladders
  }

  private static func rungs(from samples: [ProgressionSample]) -> [Rung] {
    var rungs: [Rung] = []
    for sample in samples.sorted(by: chronologically) {
      guard repCounts.contains(sample.reps) else { continue }
      let candidate = Rung(
        reps: sample.reps, weightKg: sample.weightKg, sessionID: sample.sessionID,
        completedAt: sample.completedAt)
      guard let index = rungs.firstIndex(where: { $0.reps == sample.reps }) else {
        rungs.append(candidate)
        continue
      }
      // A load within the detector's tolerance is the same load, and the first set at it names the
      // rung. Only a load genuinely above it replaces the set, so a later 40.004 does not overwrite
      // the 40 that reached the same load first.
      let existing = rungs[index]
      if sample.weightKg >= existing.weightKg + PersonalRecordDetector.loadMatchingTolerance {
        rungs[index] = candidate
      }
    }
    return rungs.sorted { $0.reps < $1.reps }
  }

  /// A total order, not just by date, so equal timestamps do not reorder between launches.
  private static func chronologically(
    _ lhs: ProgressionSample, _ rhs: ProgressionSample
  ) -> Bool {
    if lhs.completedAt != rhs.completedAt { return lhs.completedAt < rhs.completedAt }
    if lhs.sessionID != rhs.sessionID {
      return lhs.sessionID.rawValue.uuidString < rhs.sessionID.rawValue.uuidString
    }
    if lhs.weightKg != rhs.weightKg { return lhs.weightKg < rhs.weightKg }
    return lhs.reps < rhs.reps
  }

  // MARK: - Working

  /// The set a rung came from and the other sets at that same rep count, as a "Worked from"
  /// account. `nil` when this ladder has no rung at `reps`, so nothing is offered that would
  /// explain an absence.
  ///
  /// `samples` is the history the ladder was built from; it is passed rather than carried on the
  /// ladder so the value a view holds stays small.
  public func working(
    reps: Int, from samples: [ProgressionSample], label: String, format: WorkedFromFormat
  ) -> WorkedFromAccount? {
    guard let rung = rung(reps: reps) else { return nil }
    let atReps = samples
      .filter { key.contains($0) && $0.reps == reps }
      .sorted(by: Self.chronologically)
    let context = "\(format.day(rung.completedAt)) · \(label)"
    let produced = WorkedFromAccount.Line(
      id: "produced-\(reps)",
      standing: .produced,
      headline: format.set(weightKg: rung.weightKg, reps: reps),
      context: context,
      detail: RepLadderCopy.producedDetail(reps: reps),
      spoken: "\(format.setSpoken(weightKg: rung.weightKg, reps: reps)). \(context). "
        + RepLadderCopy.producedDetail(reps: reps),
      standingWord: RepLadderCopy.producedStandingWord)

    var others: [WorkedFromAccount.Line] = []
    for (index, sample) in atReps.enumerated() where !Self.isTheRung(sample, rung) {
      let detail =
        abs(sample.weightKg - rung.weightKg) < PersonalRecordDetector.loadMatchingTolerance
        ? RepLadderCopy.sameLoadDetail
        : RepLadderCopy.lighterDetail(reps: reps)
      let otherContext = "\(format.day(sample.completedAt)) · \(label)"
      others.append(
        WorkedFromAccount.Line(
          id: "other-\(index)", standing: .counted,
          headline: format.set(weightKg: sample.weightKg, reps: sample.reps),
          context: otherContext, detail: detail,
          spoken: "\(format.setSpoken(weightKg: sample.weightKg, reps: sample.reps)). "
            + "\(otherContext). \(detail)"))
    }

    var sections = [
      WorkedFromAccount.Section(
        id: "produced", heading: RepLadderCopy.producedHeading, note: nil, lines: [produced])
    ]
    if !others.isEmpty {
      sections.append(
        WorkedFromAccount.Section(
          id: "others", heading: RepLadderCopy.otherSetsHeading(reps: reps),
          note: RepLadderCopy.otherSetsNote, lines: others))
    }

    return WorkedFromAccount(
      title: RepLadderCopy.rungName(reps: reps),
      figure: format.load(rung.weightKg),
      figureCaption: context,
      ruleHeading: RepLadderCopy.ruleHeading,
      rule: RepLadderCopy.rule(reps: reps),
      sections: sections,
      spoken: "\(RepLadderCopy.rungName(reps: reps)), \(format.loadSpoken(rung.weightKg)). "
        + "\(label), \(format.day(rung.completedAt)).")
  }

  private static func isTheRung(_ sample: ProgressionSample, _ rung: Rung) -> Bool {
    sample.reps == rung.reps && sample.sessionID == rung.sessionID
      && sample.completedAt == rung.completedAt && sample.weightKg == rung.weightKg
  }
}

/// The words the rep ladder uses.
///
/// They say what the number is — "your heaviest 8" — and never what the lifter could do today,
/// what to attempt next, or how it compares to a target. Kept in Core so a test can read every
/// string without a screen.
public enum RepLadderCopy {
  public static let sectionTitle = "Your heaviest at each rep count"
  public static let sectionDetail =
    "The heaviest set you completed at each rep count on this machine. "
    + "A rep count with no set is left out."
  public static let openHint = "Shows the set this came from."
  public static let ruleHeading = "How this is read"
  public static let producedHeading = "The set it came from"
  public static let producedStandingWord = "The set it came from"
  public static let otherSetsNote =
    "Other sets at this rep count, each below the figure or at the same load."
  public static let sameLoadDetail = "The same load, reached later."

  public static func repsText(_ reps: Int) -> String {
    "\(reps) \(reps == 1 ? "rep" : "reps")"
  }

  /// "Your heaviest 8": the figure named by the rep count that produced it.
  public static func rungName(reps: Int) -> String {
    "Your heaviest \(reps)"
  }

  public static func producedDetail(reps: Int) -> String {
    "The heaviest set at \(repsText(reps))."
  }

  public static func lighterDetail(reps: Int) -> String {
    "Lighter than your heaviest \(reps)."
  }

  public static func otherSetsHeading(reps: Int) -> String {
    "Other sets at \(repsText(reps))"
  }

  public static func rule(reps: Int) -> String {
    "This is the heaviest working set you completed with exactly \(repsText(reps)) "
      + "on this machine. Loads that differ by less than \(tolerance) kg count as one load. "
      + "A rep count with no set is not shown."
  }

  /// What a row reads aloud: the figure, then where and when it was reached.
  public static func rowLabel(
    reps: Int, weightKg: Double, date: Date, machine: String, format: WorkedFromFormat
  ) -> String {
    "Your heaviest \(repsText(reps)): \(format.loadSpoken(weightKg)), first reached "
      + "\(format.day(date)), \(machine)."
  }

  private static var tolerance: String {
    "\(PersonalRecordDetector.loadMatchingTolerance)"
  }
}
