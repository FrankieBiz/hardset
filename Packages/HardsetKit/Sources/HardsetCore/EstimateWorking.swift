import Foundation

extension ProgressionKey {
  /// Whether `sample` belongs to this key's series. The exercise is not on a sample, so it is the
  /// caller's to match; machine and imported status are what separate one series from another.
  func contains(_ sample: ProgressionSample) -> Bool {
    machineID == sample.machineID && isImported == sample.isImported
  }
}

/// Which sets produced one session's estimated one-rep max on one machine, by what arithmetic, and
/// what was left out.
///
/// This is the working behind a point on the estimate chart and the latest figure in its legend.
/// It does not re-implement the estimate: every set is run through `StrengthMath.estimatedOneRepMax`,
/// the session's figure is picked by `StrengthMath.bestSupportedEstimate`, and `ProgressionAnalyzer`
/// builds its points through the same two steps (`claims(for:estimatesOneRepMax:)` and
/// `best(of:)`), so the figure here and the point on the chart are one calculation.
public struct EstimateWorking: Hashable, Sendable {
  /// Why a set did not feed the figure.
  public enum Exclusion: Hashable, Sendable {
    /// A warm-up. Never an estimate, however heavy.
    case warmup
    /// More reps than `StrengthMath.maximumEstimableReps`, where no one-rep max is estimated.
    case aboveRepLimit(reps: Int)
    /// A load of zero or below, or above `StrengthMath.implausibleWeightKg`.
    case implausibleLoad
    /// The movement logs a load that is not the load moved, so nothing is estimated from it.
    case movementNotEstimated(assumesAddedLoad: Bool)
    /// A set from the same session on other equipment, or imported. Each machine is its own line, and
    /// imported history is a line of its own that is never joined to a machine's.
    case otherSeries(label: String, isImported: Bool)
  }

  public enum Standing: Hashable, Sendable {
    /// Its estimate is the figure: the highest, and on a tie the better supported.
    case figure
    /// Estimated and compared, and below the figure.
    case counted
    case excluded(Exclusion)
  }

  public struct Entry: Hashable, Sendable, Identifiable {
    public let id: Int
    public let weightKg: Double
    public let reps: Int
    public let completedAt: Date
    /// The series the set belongs to, as the chart's legend names it.
    public let seriesLabel: String
    /// This set's own estimate, when it has one.
    public let estimateKg: Double?
    /// True when the set is a single, which is taken as measured and not estimated.
    public let isMeasuredSingle: Bool
    public let standing: Standing
  }

  public let key: ProgressionKey
  public let sessionID: SessionID
  /// The session's date: when its first set was completed.
  public let date: Date
  public let seriesLabel: String
  /// The session's estimated one-rep max, or `nil` when none of its sets could be estimated.
  public let figureKg: Double?
  /// The figure's own certainty, from the claim it came from. `.unevaluated` with no figure.
  public let certainty: Certainty
  /// In the order the sets were performed, with the sets left out among them.
  public let entries: [Entry]
  /// Sets in other sessions on other equipment or in imported history, never mixed into this line.
  public let setsOnOtherSeries: Int

  /// How many sets share the figure exactly.
  public var figureSetCount: Int { entries.filter { $0.standing == .figure }.count }

  // MARK: - The calculation, shared with the chart

  /// Each set's estimate, in the order of `samples`, with `nil` where the movement is not estimated
  /// at all. The one place a session's sets are turned into claims.
  static func claims(
    for samples: [ProgressionSample], estimatesOneRepMax: Bool
  ) -> [Claim<Double>?] {
    samples.map {
      estimatesOneRepMax
        ? StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) : nil
    }
  }

  /// The claim that is the session's figure, or `nil` when no set could be estimated.
  static func best(of claims: [Claim<Double>?]) -> Claim<Double>? {
    StrengthMath.bestSupportedEstimate(claims.compactMap { $0 })
  }

  // MARK: - Derivation

  /// The working behind `sessionID`'s estimate on `key`'s series.
  ///
  /// - Parameters:
  ///   - samples: Every working set of the exercise, across machines, as the history reads them.
  ///   - warmups: The exercise's warm-up sets, which the history leaves out of `samples`. They are
  ///     listed as left out rather than missing; empty when the caller has none to show.
  ///   - label: The name a series goes by in the chart's legend.
  /// - Returns: `nil` when the session has no set on this series.
  public static func derive(
    key: ProgressionKey,
    sessionID: SessionID,
    samples: [ProgressionSample],
    warmups: [ProgressionSample] = [],
    estimatesOneRepMax: Bool,
    assumesAddedLoad: Bool = false,
    label: (ProgressionKey) -> String
  ) -> EstimateWorking? {
    func series(of sample: ProgressionSample) -> ProgressionKey {
      ProgressionKey(
        exerciseID: key.exerciseID, machineID: sample.machineID, isImported: sample.isImported)
    }

    let own = samples.enumerated()
      .filter { $0.element.sessionID == sessionID && key.contains($0.element) }
      .sorted { ($0.element.completedAt, $0.offset) < ($1.element.completedAt, $1.offset) }
      .map(\.element)
    guard !own.isEmpty else { return nil }

    let estimates = Self.claims(for: own, estimatesOneRepMax: estimatesOneRepMax)
    let winner = Self.best(of: estimates)
    let seriesLabel = label(key)

    var rows: [(sample: ProgressionSample, estimate: Claim<Double>?, standing: Standing, order: Int)] = []
    var order = 0

    for (sample, claim) in zip(own, estimates) {
      let standing: Standing
      if !estimatesOneRepMax {
        standing = .excluded(.movementNotEstimated(assumesAddedLoad: assumesAddedLoad))
      } else if let claim, let value = claim.value {
        let isFigure = value == winner?.value && claim.certainty == winner?.certainty
        standing = isFigure ? .figure : .counted
      } else if sample.reps > StrengthMath.maximumEstimableReps {
        standing = .excluded(.aboveRepLimit(reps: sample.reps))
      } else {
        // `estimatedOneRepMax` refuses only an implausible load or too many reps.
        standing = .excluded(.implausibleLoad)
      }
      rows.append((sample, claim, standing, order))
      order += 1
    }

    for sample in samples where sample.sessionID == sessionID && !key.contains(sample) {
      let other = series(of: sample)
      rows.append((sample, nil, .excluded(.otherSeries(label: label(other), isImported: other.isImported)), order))
      order += 1
    }
    for sample in warmups where sample.sessionID == sessionID {
      rows.append((sample, nil, .excluded(.warmup), order))
      order += 1
    }

    let entries = rows
      .sorted { ($0.sample.completedAt, $0.order) < ($1.sample.completedAt, $1.order) }
      .enumerated()
      .map { index, row in
        Entry(
          id: index, weightKg: row.sample.weightKg, reps: row.sample.reps,
          completedAt: row.sample.completedAt,
          seriesLabel: key.contains(row.sample) ? seriesLabel : label(series(of: row.sample)),
          estimateKg: row.estimate?.value,
          isMeasuredSingle: row.estimate?.source.id == StrengthMath.measuredSource.id,
          standing: row.standing)
      }

    return EstimateWorking(
      key: key, sessionID: sessionID, date: own.map(\.completedAt).min() ?? .distantPast,
      seriesLabel: seriesLabel, figureKg: winner?.value, certainty: winner?.certainty ?? .unevaluated,
      entries: entries,
      setsOnOtherSeries: samples.filter { $0.sessionID != sessionID && !key.contains($0) }.count)
  }

  /// The working behind a series' latest session that has an estimate: the one its legend row shows.
  public static func deriveLatest(
    key: ProgressionKey,
    samples: [ProgressionSample],
    warmups: [ProgressionSample] = [],
    estimatesOneRepMax: Bool,
    assumesAddedLoad: Bool = false,
    label: (ProgressionKey) -> String
  ) -> EstimateWorking? {
    let own = samples.filter { key.contains($0) }
    let estimates = Self.claims(for: own, estimatesOneRepMax: estimatesOneRepMax)
    // The chart draws a point per session that has an estimate and its legend reads the latest of
    // them, by date and then by session id: the order `ProgressionAnalyzer` sorts its points in.
    var estimable = Set<SessionID>()
    for (sample, claim) in zip(own, estimates) where claim?.value != nil {
      estimable.insert(sample.sessionID)
    }
    let latest = Dictionary(grouping: own.filter { estimable.contains($0.sessionID) }, by: \.sessionID)
      .map { id, sets in (date: sets.map(\.completedAt).min() ?? .distantPast, id: id) }
      .max {
        if $0.date != $1.date { return $0.date < $1.date }
        return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
      }
    guard let latest else { return nil }
    return derive(
      key: key, sessionID: latest.id, samples: samples, warmups: warmups,
      estimatesOneRepMax: estimatesOneRepMax, assumesAddedLoad: assumesAddedLoad, label: label)
  }

  // MARK: - Words

  /// The formula, stated from the constants the arithmetic uses.
  static func rule(format: WorkedFromFormat) -> String {
    let divisor = Int(StrengthMath.epleyRepsDivisor)
    let limit = StrengthMath.maximumEstimableReps
    let step = format.unit == .kilograms ? "0.5 kg" : "1 lb"
    return "Each set is converted with the Epley formula: weight × (1 + reps ÷ \(divisor)). "
      + "One rep at a load is its own one-rep max, so a single is taken as measured. "
      + "Sets above \(limit) reps are not estimated. "
      + "The session's figure is the highest estimate among its sets, shown to the nearest \(step). "
      + confidenceLadder()
  }

  /// How confidence follows the set, read from the estimator itself, one run of rep counts per level,
  /// so the words cannot say a level the estimator does not give: "1 rep is high, 2 to 10 reps is
  /// moderate, 11 to 12 reps is low."
  static func confidenceLadder() -> String {
    var runs: [(certainty: Certainty, reps: ClosedRange<Int>)] = []
    for reps in 1...StrengthMath.maximumEstimableReps {
      // Any plausible load: the level depends on the reps, never on the weight.
      let certainty = StrengthMath.estimatedOneRepMax(weightKg: 100, reps: reps).certainty
      if let last = runs.last, last.certainty == certainty {
        runs[runs.count - 1].reps = last.reps.lowerBound...reps
      } else {
        runs.append((certainty, reps...reps))
      }
    }
    let phrases = runs.map { run -> String in
      let span = run.reps.count == 1
        ? "\(run.reps.lowerBound) \(run.reps.lowerBound == 1 ? "rep" : "reps")"
        : "\(run.reps.lowerBound) to \(run.reps.upperBound) reps"
      return "\(span) is \(run.certainty.rawValue)"
    }
    return "Confidence follows the set: \(phrases.joined(separator: ", "))."
  }

  /// What the account says, built from this derivation and nothing else.
  public func account(format: WorkedFromFormat) -> WorkedFromAccount {
    let day = format.day(date)
    let confidence = ScorecardCopy.confidenceWords(certainty)
    let figure = figureKg.map { format.estimate($0) } ?? "No estimate"

    let fed = entries.filter { $0.standing == .figure || $0.standing == .counted }
    let left = entries.filter {
      if case .excluded = $0.standing { return true }
      return false
    }

    var sections: [WorkedFromAccount.Section] = []
    if !fed.isEmpty {
      sections.append(
        WorkedFromAccount.Section(
          id: "fed", heading: "Sets that fed this figure",
          note: figureSetCount > 1
            ? "\(figureSetCount) sets share the highest estimate."
            : "The set with the highest estimate is the figure.",
          lines: fed.map { line(for: $0, format: format) }))
    }

    var leftLines = left.map { line(for: $0, format: format) }
    if setsOnOtherSeries > 0 {
      let count = setsOnOtherSeries
      leftLines.append(
        WorkedFromAccount.Line(
          id: "other-series", standing: .excluded,
          headline: count == 1 ? "1 set on other equipment" : "\(count) sets on other equipment",
          context: "Other sessions",
          detail: "Each machine has its own line, and imported history has its own, so they are never mixed into this one.",
          spoken: "\(count) \(count == 1 ? "set" : "sets") from other sessions on other equipment or in imported history. "
            + "Each has its own line and is never mixed into this one."))
    }
    sections.append(
      WorkedFromAccount.Section(
        id: "left", heading: "Left out",
        note: leftLines.isEmpty
          ? "Nothing in this session was left out. Warm-ups, other machines and imported history are never mixed into this line."
          : "Warm-ups, other machines and imported history are never mixed into this line.",
        lines: leftLines))

    let figureSet = entries.first { $0.standing == .figure }
    let origin: String
    if figureKg == nil {
      origin = "No set in this session could be estimated."
    } else if figureSetCount > 1 {
      origin = "It comes from \(figureSetCount) sets that estimate the same."
    } else if let figureSet {
      origin = "It comes from \(format.setSpoken(weightKg: figureSet.weightKg, reps: figureSet.reps))."
    } else {
      origin = ""
    }
    let leftCount = left.count + (setsOnOtherSeries > 0 ? 1 : 0)
    let counted = "\(fed.count) \(fed.count == 1 ? "set" : "sets") counted"
    let spoken =
      "Estimated one-rep max, \(figureKg.map { format.estimateSpoken($0) } ?? "no estimate"), "
      + "\(confidence), \(seriesLabel), \(day). \(origin) \(counted), \(leftCount) left out."

    return WorkedFromAccount(
      title: "Estimated one-rep max", figure: figure,
      figureCaption: "\(confidence) · \(seriesLabel) · \(day)",
      ruleHeading: "Formula", rule: Self.rule(format: format),
      sections: sections, spoken: spoken)
  }

  private func line(for entry: Entry, format: WorkedFromFormat) -> WorkedFromAccount.Line {
    let headline = format.set(weightKg: entry.weightKg, reps: entry.reps)
    let date = format.day(entry.completedAt)
    let context = "\(date) · \(entry.seriesLabel)"
    let divisor = Int(StrengthMath.epleyRepsDivisor)
    let setSpoken = format.setSpoken(weightKg: entry.weightKg, reps: entry.reps)
    let when = "on \(date), \(entry.seriesLabel)"

    let detail: String
    let spokenDetail: String
    let standing: WorkedFromAccount.Standing
    switch entry.standing {
    case .figure, .counted:
      let isFigure = entry.standing == .figure
      standing = isFigure ? .produced : .counted
      let estimate = entry.estimateKg.map { format.estimate($0) } ?? ""
      let estimateSpoken = entry.estimateKg.map { format.estimateSpoken($0) } ?? ""
      let verdict = isFigure
        ? (figureSetCount > 1 ? "This set ties for the figure." : "This set is the figure.")
        : "Below the figure."
      if entry.isMeasuredSingle {
        detail = "A single is taken as measured: \(estimate). \(verdict)"
        spokenDetail = "A single is taken as measured, \(estimateSpoken). \(verdict)"
      } else {
        let load = LoadText.entered(entry.weightKg, in: format.unit, locale: format.locale)
        detail = "\(load) × (1 + \(entry.reps) ÷ \(divisor)) → \(estimate). \(verdict)"
        spokenDetail =
          "\(LoadText.entered(entry.weightKg, in: format.unit, locale: format.locale)) times one plus "
          + "\(entry.reps) over \(divisor) comes to \(estimateSpoken). \(verdict)"
      }
    case .excluded(let reason):
      standing = .excluded
      let words = Self.words(for: reason, format: format)
      detail = words
      spokenDetail = words
    }
    return WorkedFromAccount.Line(
      id: "entry-\(entry.id)", standing: standing, headline: headline, context: context,
      detail: detail, spoken: "\(setSpoken) \(when). \(spokenDetail)")
  }

  static func words(for reason: Exclusion, format: WorkedFromFormat) -> String {
    switch reason {
    case .warmup:
      return "Left out: a warm-up. Warm-ups are never counted."
    case .aboveRepLimit(let reps):
      return "Left out: \(reps) reps is above \(StrengthMath.maximumEstimableReps), where no one-rep max is estimated."
    case .implausibleLoad:
      let ceiling = format.load(StrengthMath.implausibleWeightKg)
      return "Left out: a load of zero, or above \(ceiling), is not estimated."
    case .movementNotEstimated(let assumesAddedLoad):
      // An unknown movement is one whose equipment is not set, and Progress says so in these words,
      // from one place, with the one place the lifter can end it.
      let notSet = ProgressCopy.equipmentNotSet
      return assumesAddedLoad
        ? "Left out: " + notSet.prefix(1).lowercased() + notSet.dropFirst()
        : "Left out: body mass is not recorded with each set, so a one-rep max is not estimated for bodyweight movements."
    case .otherSeries(let label, let isImported):
      return isImported
        ? "Left out: imported history. It is a line of its own and is never joined to a machine's, so this set does not feed this one."
        : "Left out: logged on \(label). Each machine has its own line, so this set does not feed this one."
    }
  }
}
