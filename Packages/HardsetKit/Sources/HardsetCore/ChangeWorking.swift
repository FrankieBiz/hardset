import Foundation

/// Which sets produced a change between two sessions, by what arithmetic, and what was left out.
///
/// This is the working behind two figures a lifter reads as a percentage: a Progress row's six-week
/// change and a finished workout's biggest gain. Both are the ratio of one session's value to
/// another's, and for an estimated max each value is itself an estimate, so neither can be taken on
/// trust. It does not decide anything: the six-week change is rebuilt from
/// `ProgressTrendAnalyzer.comparison`, the very function the row's figure came from, and a gain is
/// rebuilt from the sets the scorecard compared, through the same `ProgressTrendAnalyzer.value`.
/// `ChangeWorkingTests` and a Store test hold the figure here equal to the figure on screen.
///
/// Every set that took no part is left out in words, not left missing: warm-ups, sets on other
/// equipment, sessions outside the comparison band and a session where no set could be estimated
/// are each a line under "Left out" with a reason, counted where a whole session was passed over.
public struct ChangeWorking: Hashable, Sendable {
  /// How the baseline was chosen.
  public enum Basis: Hashable, Sendable {
    /// A Progress row: the session with the highest value five to seven weeks before the latest.
    case sixWeek
    /// The scorecard: the most recent earlier session on the same machine.
    case lastTime
  }

  /// One end of the comparison: a session's sets and what was left out beside them.
  public struct Side: Hashable, Sendable {
    /// The session's date: when its first set was completed.
    public let date: Date
    /// The working sets on this series, in the order performed. These are what the value is made of.
    public let sets: [PriorSetRecord]
    /// Warm-ups in the session, left out.
    public let warmupSets: Int
    /// Working sets in the session on other equipment, or imported, left out: each series is its
    /// own line.
    public let otherEquipmentSets: Int
  }

  /// A session that was looked at as a baseline and not used.
  public struct PassedOver: Hashable, Sendable, Identifiable {
    public enum Reason: Hashable, Sendable {
      /// Its value is lower than the baseline's, so it is not the highest.
      case belowBaseline
      /// Reps at the top weight are only compared at the same top weight, and this one differs.
      case differentTopLoad
    }

    public let id: Int
    public let date: Date
    public let value: Double
    public let reason: Reason
  }

  /// Sessions passed over as a group, and their working sets.
  public struct Tally: Hashable, Sendable {
    public let sessions: Int
    public let sets: Int
    static let none = Tally(sessions: 0, sets: 0)
  }

  public let basis: Basis
  public let metric: TrendMetric
  /// The movement's name where the surface does not already say it (the scorecard), else `nil`.
  public let exerciseName: String?
  /// The machine, as the chart's legend names it, where the surface knows it.
  public let seriesLabel: String?
  /// A fraction, so 0.06 means +6%. The figure on screen.
  public let fraction: Double
  /// How far to trust it. `nil` for a measured metric.
  public let certainty: Certainty?
  public let loadAssumption: String?
  public let current: Side
  public let baseline: Side
  /// Other sessions in the band that were not the baseline, newest first. Six-week only.
  public let passedOver: [PassedOver]
  /// Sessions outside the comparison band. Six-week only.
  public let outsideBand: Tally
  /// Sessions in which no set had a value on the metric: every set above the estimable rep limit.
  /// Six-week only.
  public let withoutFigure: Tally
  /// Earlier sessions older than the one compared. Last-time only.
  public let olderThanBaseline: Tally

  /// The latest, or this workout's, value on the metric.
  public var currentValue: Double? {
    ProgressTrendAnalyzer.value(of: metric, in: current.figures)
  }

  /// The baseline's value on the metric.
  public var baselineValue: Double? {
    ProgressTrendAnalyzer.value(of: metric, in: baseline.figures)
  }

  // MARK: - Derivation

  /// The working behind a Progress row's six-week change, or `nil` when the row has none to explain.
  ///
  /// - Parameters:
  ///   - samples: The movement's working sets across series, as the board reads them. The row's own
  ///     series is picked out by `key`; the rest are the sets on other equipment.
  ///   - warmups: The movement's warm-ups, which the board never sees. Listed as left out.
  ///   - label: A series' name, as the board names it.
  public static func sixWeek(
    key: ProgressionKey,
    samples: [ProgressionSample],
    warmups: [ProgressionSample] = [],
    estimatesOneRepMax: Bool,
    assumesAddedLoad: Bool = false,
    label: (ProgressionKey) -> String
  ) -> ChangeWorking? {
    let own = samples.filter { key.contains($0) }
    let sessions = ProgressTrendAnalyzer.sessions(from: own)
    guard
      let comparison = ProgressTrendAnalyzer.comparison(
        sessions: sessions, estimatesOneRepMax: estimatesOneRepMax,
        assumesAddedLoad: assumesAddedLoad),
      let base = comparison.base, let change = comparison.change
    else { return nil }

    func side(_ point: ProgressTrendAnalyzer.ComparisonPoint) -> Side {
      let ordered = own.enumerated()
        .filter { $0.element.sessionID == point.sessionID }
        .sorted { ($0.element.completedAt, $0.offset) < ($1.element.completedAt, $1.offset) }
        .map { PriorSetRecord(weightKg: $0.element.weightKg, reps: $0.element.reps, completedAt: $0.element.completedAt) }
      return Side(
        date: point.date, sets: ordered,
        warmupSets: warmups.filter { $0.sessionID == point.sessionID }.count,
        otherEquipmentSets: samples.filter { $0.sessionID == point.sessionID && !key.contains($0) }.count)
    }

    let usedIDs: Set<SessionID> = [comparison.latest.sessionID, base.sessionID]
    let candidateIDs = Set(comparison.candidates.map(\.sessionID))
    let passed = comparison.inBand
      .filter { !usedIDs.contains($0.sessionID) }
      .sorted { $0.date > $1.date }
      .enumerated()
      .map { index, point in
        PassedOver(
          id: index, date: point.date, value: point.value,
          reason: candidateIDs.contains(point.sessionID) ? .belowBaseline : .differentTopLoad)
      }
    let inBandIDs = Set(comparison.inBand.map(\.sessionID))
    let valuedIDs = Set(comparison.points.map(\.sessionID))
    func tally(_ matching: (ProgressTrendAnalyzer.Session) -> Bool) -> Tally {
      let picked = sessions.filter(matching)
      return Tally(sessions: picked.count, sets: picked.reduce(0) { $0 + $1.samples.count })
    }

    return ChangeWorking(
      basis: .sixWeek, metric: comparison.metric, exerciseName: nil, seriesLabel: label(key),
      fraction: change, certainty: comparison.certainty,
      loadAssumption: assumesAddedLoad ? ExerciseModality.unknownLoadAssumption : nil,
      current: side(comparison.latest), baseline: side(base), passedOver: passed,
      outsideBand: tally {
        valuedIDs.contains($0.id) && !inBandIDs.contains($0.id) && $0.id != comparison.latest.sessionID
      },
      withoutFigure: tally { !valuedIDs.contains($0.id) },
      olderThanBaseline: .none)
  }

  /// The working behind a finished workout's biggest gain, or `nil` for a gain built without the
  /// sets it came from, which has nothing to open.
  public static func lastTime(gain: WorkoutScorecard.Gain) -> ChangeWorking? {
    guard let input = gain.basis, !input.currentSets.isEmpty, !input.previousSets.isEmpty else { return nil }
    let current = Side(
      date: input.currentSets.map(\.completedAt).min() ?? .distantPast, sets: input.currentSets,
      warmupSets: input.leftOut.currentWarmups, otherEquipmentSets: input.leftOut.currentOtherEquipment)
    let baseline = Side(
      date: input.previousSets.map(\.completedAt).min() ?? .distantPast, sets: input.previousSets,
      warmupSets: input.leftOut.previousWarmups, otherEquipmentSets: input.leftOut.previousOtherEquipment)
    guard
      let now = ProgressTrendAnalyzer.value(of: gain.metric, in: current.figures),
      let then = ProgressTrendAnalyzer.value(of: gain.metric, in: baseline.figures), then > 0
    else { return nil }
    return ChangeWorking(
      basis: .lastTime, metric: gain.metric, exerciseName: gain.exerciseName, seriesLabel: nil,
      fraction: now / then - 1, certainty: gain.certainty, loadAssumption: gain.loadAssumption,
      current: current, baseline: baseline, passedOver: [], outsideBand: .none, withoutFigure: .none,
      olderThanBaseline: Tally(sessions: input.leftOut.olderSessions, sets: input.leftOut.olderSets))
  }

  // MARK: - Words

  /// The rule, stated from the constants the arithmetic uses.
  static func rule(basis: Basis, metric: TrendMetric, loadAssumption: String?, format: WorkedFromFormat)
    -> String
  {
    let against =
      basis == .sixWeek
      ? "the baseline's. The baseline is the session with the highest figure among those "
        + "\(ProgressCopy.comparisonBandText) before the latest session, so a movement with no "
        + "session in that band has no change"
      : "last time's. Last time is the most recent earlier session that trained the same movement "
        + "on the same machine. The scorecard shows the largest gain among the movements that "
        + "improved on it"
    let subject = basis == .sixWeek ? "the latest session's" : "this workout's"
    let change = "The change is \(subject) figure divided by \(against), minus one. "
    switch metric {
    case .estimatedMax:
      let divisor = Int(StrengthMath.epleyRepsDivisor)
      let limit = StrengthMath.maximumEstimableReps
      return change
        + "A session's figure is the highest estimate among its sets, each converted with the Epley "
        + "formula: weight × (1 + reps ÷ \(divisor)). One rep at a load is its own one-rep max, so a "
        + "single is taken as measured. Sets above \(limit) reps are not estimated. "
        + "A change carries the weaker confidence of its two estimates. "
        + EstimateWorking.confidenceLadder()
    case .heaviestLoad:
      return change + "A session's figure is the heaviest load it logged. These are loads you entered, so nothing is estimated."
    case .addedLoad:
      return change
        + "A session's figure is the heaviest load it logged, read as added load. "
        + (loadAssumption.map { $0 + " " } ?? "")
        + "Nothing is estimated, and the change is rated Low confidence."
    case .repsAtTopLoad:
      return change
        + "A session's figure is the most reps it logged at its heaviest weight, and sessions are only "
        + "compared at the same top weight. These are reps you entered, so nothing is estimated."
        + (loadAssumption.map { " " + $0 + " The change is rated Low confidence." } ?? "")
    }
  }

  private func valueText(_ value: Double, format: WorkedFromFormat, spoken: Bool = false) -> String {
    switch metric {
    case .estimatedMax: spoken ? format.estimateSpoken(value) : format.estimate(value)
    case .heaviestLoad, .addedLoad: spoken ? format.loadSpoken(value) : format.load(value)
    case .repsAtTopLoad: "\(Int(value)) \(Int(value) == 1 ? "rep" : "reps")"
    }
  }

  private static func sets(_ count: Int) -> String { count == 1 ? "1 set" : "\(count) sets" }
  private static func sessions(_ count: Int) -> String { count == 1 ? "1 session" : "\(count) sessions" }

  private enum Standing {
    case figure
    case counted
    case excluded(EstimateWorking.Exclusion)
  }

  private struct Row {
    let set: PriorSetRecord
    let estimate: Claim<Double>?
    let standing: Standing
  }

  /// Each set on a side, with whether it decided the side's value. Decided by the same functions the
  /// value is: the best-supported estimate for an estimated max, the heaviest load, and the most reps
  /// at the top weight.
  private func rows(of side: Side) -> [Row] {
    switch metric {
    case .estimatedMax:
      let claims = side.sets.map { StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }
      let winner = ProgressTrendAnalyzer.bestEstimateClaim(in: side.figures)
      return zip(side.sets, claims).map { set, claim in
        guard let value = claim.value else {
          return Row(
            set: set, estimate: nil,
            standing: .excluded(
              set.reps > StrengthMath.maximumEstimableReps
                ? .aboveRepLimit(reps: set.reps) : .implausibleLoad))
        }
        let decides = value == winner?.value && claim.certainty == winner?.certainty
        return Row(set: set, estimate: claim, standing: decides ? .figure : .counted)
      }
    case .heaviestLoad, .addedLoad:
      let top = side.sets.map(\.weightKg).max()
      return side.sets.map { Row(set: $0, estimate: nil, standing: $0.weightKg == top ? .figure : .counted) }
    case .repsAtTopLoad:
      let top = side.sets.map(\.weightKg).max() ?? 0
      let best = ProgressTrendAnalyzer.value(of: .repsAtTopLoad, in: side.figures)
      return side.sets.map { set in
        let atTop = abs(set.weightKg - top) < PersonalRecordDetector.loadMatchingTolerance
        return Row(
          set: set, estimate: nil,
          standing: atTop && Double(set.reps) == best ? .figure : .counted)
      }
    }
  }

  /// What the account says, built from this derivation and nothing else.
  public func account(format: WorkedFromFormat) -> WorkedFromAccount {
    let roles =
      basis == .sixWeek ? (current: "Latest session", baseline: "Baseline") : (current: "This workout", baseline: "Last time")
    let metricName = ProgressCopy.metricName(metric)
    let rounded = (fraction * 100).rounded()
    let figure = rounded == 0 ? "Unchanged" : ProgressCopy.signedPercent(fraction)
    let confidence = certainty.map(ScorecardCopy.confidenceWords) ?? "Measured, not estimated"
    let span = "\(format.day(baseline.date)) to \(format.day(current.date))"
    let caption = [confidence, exerciseName, seriesLabel, span].compactMap { $0 }.joined(separator: " · ")
    let title = "\(metricName) " + (basis == .sixWeek ? "over six weeks" : "since last time")

    func isExcluded(_ row: Row) -> Bool {
      if case .excluded = row.standing { true } else { false }
    }
    func isFigure(_ row: Row) -> Bool {
      if case .figure = row.standing { true } else { false }
    }
    let currentRows = rows(of: current)
    let baselineRows = rows(of: baseline)
    let currentFigureCount = currentRows.filter(isFigure).count
    let baselineFigureCount = baselineRows.filter(isFigure).count

    func lines(_ rows: [Row], role: String, prefix: String, figureCount: Int) -> [WorkedFromAccount.Line] {
      rows.enumerated().map { index, row in
        let headline = format.set(weightKg: row.set.weightKg, reps: row.set.reps)
        let date = format.day(row.set.completedAt)
        let context = [role, date, seriesLabel].compactMap { $0 }.joined(separator: " · ")
        let setSpoken = format.setSpoken(weightKg: row.set.weightKg, reps: row.set.reps)
        let standing: WorkedFromAccount.Standing
        let detail: String
        let spokenDetail: String
        switch row.standing {
        case .excluded(let reason):
          standing = .excluded
          detail = EstimateWorking.words(for: reason, format: format)
          spokenDetail = detail
        case .figure, .counted:
          let decides = isFigure(row)
          standing = decides ? .produced : .counted
          let verdict =
            decides
            ? (figureCount > 1 ? "This set ties for the figure." : "This set is the figure.")
            : "Below the figure."
          switch metric {
          case .estimatedMax:
            let estimate = row.estimate?.value.map { format.estimate($0) } ?? ""
            let estimateSpoken = row.estimate?.value.map { format.estimateSpoken($0) } ?? ""
            if row.set.reps == 1 {
              detail = "A single is taken as measured: \(estimate). \(verdict)"
              spokenDetail = "A single is taken as measured, \(estimateSpoken). \(verdict)"
            } else {
              let load = LoadText.entered(row.set.weightKg, in: format.unit, locale: format.locale)
              let divisor = Int(StrengthMath.epleyRepsDivisor)
              detail = "\(load) × (1 + \(row.set.reps) ÷ \(divisor)) → \(estimate). \(verdict)"
              spokenDetail =
                "\(load) times one plus \(row.set.reps) over \(divisor) comes to \(estimateSpoken). \(verdict)"
            }
          case .heaviestLoad, .addedLoad:
            detail = decides ? "The heaviest load of the session. \(verdict)" : "Lighter than the heaviest load. \(verdict)"
            spokenDetail = detail
          case .repsAtTopLoad:
            detail = decides ? "The most reps at the session's heaviest weight. \(verdict)" : "Not the most reps at the session's heaviest weight. \(verdict)"
            spokenDetail = detail
          }
        }
        return WorkedFromAccount.Line(
          id: "\(prefix)-\(index)", standing: standing, headline: headline, context: context,
          detail: detail, spoken: "\(setSpoken), \(role), \(date). \(spokenDetail)")
      }
    }

    let currentValueText = currentValue.map { valueText($0, format: format) } ?? "none"
    let baselineValueText = baselineValue.map { valueText($0, format: format) } ?? "none"
    var sections: [WorkedFromAccount.Section] = [
      WorkedFromAccount.Section(
        id: "current", heading: "\(roles.current) · \(format.day(current.date))",
        note: "Its figure is \(currentValueText).",
        lines: lines(
          currentRows.filter { !isExcluded($0) }, role: roles.current, prefix: "current",
          figureCount: currentFigureCount)),
      WorkedFromAccount.Section(
        id: "baseline", heading: "\(roles.baseline) · \(format.day(baseline.date))",
        note: (basis == .sixWeek
          ? "The highest figure among the sessions \(ProgressCopy.comparisonBandText) before the latest. "
          : "The most recent earlier session on this machine. ")
          + "Its figure is \(baselineValueText).",
        lines: lines(
          baselineRows.filter { !isExcluded($0) }, role: roles.baseline, prefix: "baseline",
          figureCount: baselineFigureCount)),
    ]

    if !passedOver.isEmpty {
      sections.append(
        WorkedFromAccount.Section(
          id: "passed", heading: "Other sessions in the band",
          note: "Looked at as a baseline and passed over: the baseline is the highest figure.",
          lines: passedOver.map { other in
            let day = format.day(other.date)
            let value = valueText(other.value, format: format)
            let reason: String
            switch other.reason {
            case .belowBaseline: reason = "Below the baseline, so it was not used."
            case .differentTopLoad: reason = "Reps are only compared at the same top weight, and this session's differs."
            }
            return WorkedFromAccount.Line(
              id: "passed-\(other.id)", standing: .counted, headline: day, context: nil,
              detail: "\(metricName) \(value). \(reason)",
              spoken: "\(day), \(valueText(other.value, format: format, spoken: true)). \(reason)")
          }))
    }

    var left: [WorkedFromAccount.Line] = []
    func leftLine(_ id: String, headline: String, context: String?, detail: String) {
      left.append(
        WorkedFromAccount.Line(
          id: id, standing: .excluded, headline: headline, context: context, detail: detail,
          spoken: [headline, context, detail].compactMap { $0 }.joined(separator: ". ")))
    }
    // A set that could not be estimated is left out, in the words every account uses for it, and
    // listed with the others rather than among the sets that counted.
    left += lines(
      currentRows.filter(isExcluded), role: roles.current, prefix: "current-left", figureCount: 0)
    left += lines(
      baselineRows.filter(isExcluded), role: roles.baseline, prefix: "baseline-left", figureCount: 0)
    for (role, side, id) in [(roles.current, current, "current"), (roles.baseline, baseline, "baseline")] {
      let context = "\(role) · \(format.day(side.date))"
      if side.warmupSets > 0 {
        leftLine(
          "\(id)-warmups", headline: side.warmupSets == 1 ? "1 warm-up set" : "\(side.warmupSets) warm-up sets",
          context: context, detail: "Left out: warm-ups are real work and are not the prescription, so they never count.")
      }
      if side.otherEquipmentSets > 0 {
        leftLine(
          "\(id)-elsewhere", headline: "\(Self.sets(side.otherEquipmentSets)) on other equipment",
          context: context,
          detail: "Left out: each machine has its own line, and imported history has its own, so they are never mixed into this one.")
      }
    }
    if outsideBand.sessions > 0 {
      leftLine(
        "outside-band", headline: "\(Self.sessions(outsideBand.sessions)) outside the band",
        context: Self.sets(outsideBand.sets),
        detail: "Left out: a baseline is read from the sessions \(ProgressCopy.comparisonBandText) before the latest, and these sit outside that band.")
    }
    if withoutFigure.sessions > 0 {
      leftLine(
        "without-figure", headline: "\(Self.sessions(withoutFigure.sessions)) with no estimate",
        context: Self.sets(withoutFigure.sets),
        detail: "Left out: every set in it is above \(StrengthMath.maximumEstimableReps) reps, where no one-rep max is estimated.")
    }
    if olderThanBaseline.sessions > 0 {
      leftLine(
        "older", headline: "\(Self.sessions(olderThanBaseline.sessions)) before last time",
        context: Self.sets(olderThanBaseline.sets),
        detail: "Left out: only the most recent earlier session on this machine is compared.")
    }
    sections.append(
      WorkedFromAccount.Section(
        id: "left", heading: "Left out",
        note: left.isEmpty
          ? "Nothing was left out. Warm-ups, other machines and imported history are never mixed into a comparison."
          : "Warm-ups, other machines and imported history are never mixed into a comparison.",
        lines: left))

    let excludedRows = (currentRows + baselineRows).filter(isExcluded).count
    let countedSets = currentRows.count + baselineRows.count - excludedRows
    let leftOutSets =
      excludedRows + current.warmupSets + current.otherEquipmentSets + baseline.warmupSets
      + baseline.otherEquipmentSets + outsideBand.sets + withoutFigure.sets + olderThanBaseline.sets
    let spoken =
      "\(title), \(figure), \(caption). "
      + "\(roles.current) \(format.day(current.date)): \(currentValue.map { valueText($0, format: format, spoken: true) } ?? "none"). "
      + "\(roles.baseline) \(format.day(baseline.date)): \(baselineValue.map { valueText($0, format: format, spoken: true) } ?? "none"). "
      + "\(Self.sets(countedSets)) counted, \(Self.sets(leftOutSets)) left out."

    return WorkedFromAccount(
      title: title, figure: figure, figureCaption: caption,
      ruleHeading: metric == .estimatedMax ? "Formula" : "Rule",
      rule: Self.rule(basis: basis, metric: metric, loadAssumption: loadAssumption, format: format),
      sections: sections, spoken: spoken)
  }
}

extension ChangeWorking.Side {
  /// The side's sets as the two figures every metric reads.
  fileprivate var figures: [ProgressTrendAnalyzer.SetFigures] {
    sets.map { (weightKg: $0.weightKg, reps: $0.reps) }
  }
}
