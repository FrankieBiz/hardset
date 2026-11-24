import Foundation

// MARK: - Inputs

/// One movement's working sets across the whole of the lifter's history.
///
/// The two counts are deliberately separate (D31). `setCount` is every working set and is what the
/// lifetime total is made from; `pastSetCount` is the part dated at or before the moment the sheet
/// was opened, which is the only part that can be placed in time. A set dated in the future is in
/// the total and in neither `lastAt` nor `firstAt`, so it can never become "last trained".
public struct MuscleHistoryCount: Hashable, Sendable {
  public let exerciseID: ExerciseID
  /// Every working set of the movement, including any dated after the moment the sheet opened.
  public let setCount: Int
  /// The working sets dated at or before that moment.
  public let pastSetCount: Int
  /// The latest working set at or before that moment. Nil when every set is dated in the future.
  public let lastAt: Date?
  /// The earliest working set at or before that moment. Nil when every set is dated in the future.
  public let firstAt: Date?

  /// Working sets dated after the moment the sheet opened.
  public var futureSetCount: Int { max(setCount - pastSetCount, 0) }

  public init(
    exerciseID: ExerciseID, setCount: Int, pastSetCount: Int? = nil,
    lastAt: Date? = nil, firstAt: Date? = nil
  ) {
    self.exerciseID = exerciseID
    self.setCount = setCount
    self.pastSetCount = pastSetCount ?? setCount
    self.lastAt = lastAt
    self.firstAt = firstAt
  }
}

/// One seven-day window of muscle history, with the sets it was counted from.
///
/// The sets travel with the report so a figure on the sheet can open the working it was made from
/// without a second read, and so the account cannot describe a different window.
public struct MuscleHistoryWeek: Hashable, Sendable {
  /// Inclusive local midnight that opens the window.
  public let start: Date
  /// Exclusive: the next window's start, or the moment the sheet opened for the current window.
  public let end: Date
  /// An instant on the last day counted, for labelling.
  public let lastDay: Date
  public let report: MuscleVolumeReport
  public let sets: [CountableSet]

  public init(
    start: Date, end: Date, lastDay: Date, report: MuscleVolumeReport, sets: [CountableSet]
  ) {
    self.start = start
    self.end = end
    self.lastDay = lastDay
    self.report = report
    self.sets = sets
  }
}

/// The span a group of windows covers, for the sentence that names it by dates.
public struct MuscleHistorySpan: Hashable, Sendable {
  public let start: Date
  /// Exclusive: the next span's start, or the moment the sheet opened for the current span.
  public let end: Date
  /// An instant on the last day counted, for labelling.
  public let lastDay: Date

  public init(start: Date, end: Date, lastDay: Date) {
    self.start = start
    self.end = end
    self.lastDay = lastDay
  }
}

/// The muscle a working set most recently credited, and the movement that set it.
public struct MuscleLastTrained: Hashable, Sendable {
  public let date: Date
  public let exerciseID: ExerciseID
  public let movementName: String

  public init(date: Date, exerciseID: ExerciseID, movementName: String) {
    self.date = date
    self.exerciseID = exerciseID
    self.movementName = movementName
  }
}

// MARK: - The history

/// What the muscle history sheet shows, derived from one read of the lifter's sets.
///
/// Five things, and no seven-day figure: the four-week total, the four weeks before it, the lifetime
/// total, the twelve-week shape and the last time each muscle was credited. A lifetime total is a
/// sum of fractional credits under the app's counting convention, so it is derived and never drawn
/// as a monument (D21).
public struct MuscleHistory: Sendable {
  /// Windows `weeksBack` 0 to 3, merged.
  public let current: MuscleVolumeReport
  /// Windows `weeksBack` 4 to 7, merged.
  public let previous: MuscleVolumeReport
  /// Every working set in history, credited through the movement's current attribution.
  public let lifetime: MuscleVolumeReport
  /// Oldest first, at most twelve, and never a week entirely before the first logged working set.
  public let weeks: [MuscleHistoryWeek]
  /// The latest working set that credited each muscle, at or before the moment the sheet opened.
  public let lastTrained: [MuscleKey: MuscleLastTrained]
  /// The first working set at or before that moment; nil when no set is dated in the past.
  public let firstSetAt: Date?
  /// Working sets dated after that moment (D31): in `lifetime`, in no window and in no date.
  public let futureDatedSets: Int
  /// The last four weeks, for the label above the current figure.
  public let currentSpan: MuscleHistorySpan
  /// The four weeks before those, for the label above the earlier figure.
  public let previousSpan: MuscleHistorySpan
  /// Whether any set in history belongs to a movement a workout import created.
  public let includesImportedHistory: Bool
  /// The per-movement counts the lifetime total was made from, kept so its working can be derived
  /// on demand without a second read.
  public let counts: [MuscleHistoryCount]

  public init(
    current: MuscleVolumeReport, previous: MuscleVolumeReport, lifetime: MuscleVolumeReport,
    weeks: [MuscleHistoryWeek], lastTrained: [MuscleKey: MuscleLastTrained],
    firstSetAt: Date?, futureDatedSets: Int, currentSpan: MuscleHistorySpan,
    previousSpan: MuscleHistorySpan, includesImportedHistory: Bool,
    counts: [MuscleHistoryCount]
  ) {
    self.current = current
    self.previous = previous
    self.lifetime = lifetime
    self.weeks = weeks
    self.lastTrained = lastTrained
    self.firstSetAt = firstSetAt
    self.futureDatedSets = futureDatedSets
    self.currentSpan = currentSpan
    self.previousSpan = previousSpan
    self.includesImportedHistory = includesImportedHistory
    self.counts = counts
  }

  /// True when nothing at all has been logged, so the sheet says what it will show rather than
  /// drawing twenty-two empty rows.
  public var isEmpty: Bool { lifetime.hardSets == 0 }

  /// True when a working set could not be attributed, so every per-muscle lifetime figure is a
  /// floor rather than a total.
  public var isLowerBound: Bool { lifetime.isLowerBound }

  public func lifetimeSets(for muscle: Muscle) -> Double { lifetime.sets(for: muscle) }
  public func currentSets(for muscle: Muscle) -> Double { current.sets(for: muscle) }
  public func previousSets(for muscle: Muscle) -> Double { previous.sets(for: muscle) }

  /// Current four weeks minus the four before. Positive is more credited sets.
  public func difference(for muscle: Muscle) -> Double {
    currentSets(for: muscle) - previousSets(for: muscle)
  }

  /// The twelve-week shape, oldest first, with an untrained week at zero rather than absent: a
  /// missing point would interpolate across the gap, and the shape must dip.
  public func shape(for muscle: Muscle) -> [Double] {
    weeks.map { $0.report.sets(for: muscle) }
  }

  /// A muscle with any credited set at all, now or at any point in history.
  public func isTrained(_ muscle: Muscle) -> Bool {
    lifetimeSets(for: muscle) > 0
  }

  /// The state of a muscle with no credited set: content debt, a floor, or a plain absence.
  public func emptyState(for muscle: Muscle) -> MuscleHistoryEmptyState {
    if ExerciseCatalog.unauthoredDirectTokens.contains(muscle) { return .contentDebt }
    return lifetime.isLowerBound ? .floor(unattributed: lifetime.unattributedHardSets) : .noneCredited
  }

  /// The sets behind the last four weeks: the four newest points of the shape.
  public var currentSets: [CountableSet] { weeks.suffix(4).flatMap(\.sets) }

  /// The sets behind the four weeks before.
  public var previousSets: [CountableSet] { weeks.dropLast(4).suffix(4).flatMap(\.sets) }

  /// Every working set in history, materialised from the grouped counts on demand (D24 §3.6).
  public var lifetimeSets: [CountableSet] {
    counts.flatMap { count in
      repeatElement(CountableSet(exerciseID: count.exerciseID, isWarmup: false), count: count.setCount)
    }
  }
}

/// Why a muscle with no credited set has none.
public enum MuscleHistoryEmptyState: Hashable, Sendable {
  /// No catalogue movement credits it directly yet: the app's gap, not the lifter's.
  case contentDebt
  /// No credited set, and history holds working sets whose movement has no body part recorded, so
  /// the figure is a floor rather than a fact.
  case floor(unattributed: Int)
  /// No credited set and no unattributed set: a plain absence.
  case noneCredited
}

// MARK: - The analyzer

/// Builds the history from one read: per-movement counts, twelve window reports, and attribution.
///
/// It does no database work. The lifetime total is `Σ_movements count × weight`, which is exactly
/// what materialising every set and crediting it one at a time produces, because the weight is a
/// property of the movement's role and not of the set. That equality is what keeps the lifetime
/// figure and the twelve-week shape reconcilable even though SQL computes one and the window reader
/// the other.
public enum MuscleHistoryAnalyzer {
  /// - Parameters:
  ///   - counts: One entry per movement, over the whole history, already separated into sets dated
  ///     at or before the moment the sheet opened and sets dated after it (D31).
  ///   - weeks: The twelve windows, newest first: index 0 is `weeksBack: 0`.
  ///   - imported: Movements a workout import created, so the sheet can say imports are counted.
  ///   - names: Movement names, for the last-trained line.
  public static func history(
    counts: [MuscleHistoryCount],
    weeks: [MuscleHistoryWeek],
    attribution: AttributionIndex,
    imported: Set<ExerciseID> = [],
    names: [ExerciseID: String] = [:]
  ) -> MuscleHistory {
    let newestFirst = Array(weeks.prefix(12))
    let current = MuscleVolumeReport.merge(Array(newestFirst.prefix(4).map(\.report)))
    let previous = MuscleVolumeReport.merge(Array(newestFirst.dropFirst(4).prefix(4).map(\.report)))

    var fractional: [MuscleKey: Double] = [:]
    var groups: [MuscleGroup: Int] = [:]
    var hardSets = 0
    var unattributed = 0
    var last: [MuscleKey: MuscleLastTrained] = [:]
    var firstSetAt: Date?
    var future = 0

    for count in counts {
      future += count.futureSetCount
      if let first = count.firstAt {
        firstSetAt = firstSetAt.map { min($0, first) } ?? first
      }
      guard count.setCount > 0 else { continue }
      hardSets += count.setCount
      guard let contributions = attribution.contributions(for: count.exerciseID) else {
        // No attribution is not "trains nothing": these sets credit no muscle and make every
        // figure a floor.
        unattributed += count.setCount
        continue
      }
      for contribution in contributions where contribution.setWeight > 0 {
        fractional[contribution.key, default: 0] += Double(count.setCount) * contribution.setWeight
      }
      for group in Set(contributions.filter { $0.setWeight > 0 }.compactMap(\.key.group)) {
        groups[group, default: 0] += count.setCount
      }
      guard let date = count.lastAt else { continue }
      for contribution in contributions where contribution.setWeight > 0 {
        let existing = last[contribution.key]
        let isNewer =
          existing == nil || date > existing!.date
          || (date == existing!.date
            && count.exerciseID.rawValue.uuidString < existing!.exerciseID.rawValue.uuidString)
        guard isNewer else { continue }
        last[contribution.key] = MuscleLastTrained(
          date: date, exerciseID: count.exerciseID,
          movementName: names[count.exerciseID] ?? "Unknown movement")
      }
    }

    let lifetime = MuscleVolumeReport(
      fractionalSets: fractional, hardSets: hardSets, unattributedHardSets: unattributed,
      setsTouchingGroup: groups)

    // Short history is not drawn as empty pre-history: a week entirely before the first logged
    // working set is dropped, so nine empty points cannot read as nine untrained weeks.
    let kept: [MuscleHistoryWeek]
    if let firstSetAt {
      kept = newestFirst.filter { $0.end > firstSetAt }
    } else {
      kept = []
    }

    let currentSpan = span(of: Array(newestFirst.prefix(4)), fallback: newestFirst.first)
    let previousSpan = span(
      of: Array(newestFirst.dropFirst(4).prefix(4)), fallback: newestFirst.dropFirst(4).first)
    let includesImports =
      imported.isEmpty
      ? false
      : counts.contains { imported.contains($0.exerciseID) && $0.setCount > 0 }

    return MuscleHistory(
      current: current, previous: previous, lifetime: lifetime,
      weeks: kept.reversed(), lastTrained: last, firstSetAt: firstSetAt,
      futureDatedSets: future, currentSpan: currentSpan, previousSpan: previousSpan,
      includesImportedHistory: includesImports, counts: counts)
  }

  /// The span a run of windows covers. A run that the read did not return falls back to the
  /// neighbouring window so the label always names days that were counted.
  private static func span(
    of windows: [MuscleHistoryWeek], fallback: MuscleHistoryWeek?
  ) -> MuscleHistorySpan {
    let first = windows.first ?? fallback
    let last = windows.last ?? fallback
    guard let first, let last else {
      let distant = Date.distantPast
      return MuscleHistorySpan(start: distant, end: distant, lastDay: distant)
    }
    return MuscleHistorySpan(start: first.start, end: last.end, lastDay: last.lastDay)
  }
}

// MARK: - Copy

/// The words the muscle history sheet uses, generated beside the rule that decides each state.
///
/// Core carries no display copy for a muscle's name, but these sentences are the sheet's own and are
/// tested here so the words cannot drift from the arithmetic they describe.
public enum MuscleHistoryCopy {
  /// The surface's name (D30). The sheet title, the entry row and the store copy all use it.
  public static let title = "Muscle history"

  /// What a fractional set is, said once above the rows.
  public static let counting =
    "A completed working set credits 1.0 set to each muscle the movement trains directly, 0.5 to "
    + "each it trains indirectly, and 0 to each it only stabilises. Warm-ups never count. Every "
    + "number here is a number of fractional sets, not a rating."

  /// That credit uses the attribution the movements have now.
  public static let currentAttribution =
    "Muscles are credited by the body parts your movements have now, so editing a movement's body "
    + "part changes these figures."

  /// Why no certainty badge sits on a four-week or lifetime figure (D24 §3.2).
  public static let weeklyBadgeStaysOnVolume =
    "The confidence badge on Volume is about weekly sets. These totals cover four weeks or a "
    + "lifetime, so this sheet does not rate them."

  /// That the lifetime total is history, not time since install.
  public static let importedHistory =
    "Lifetime sets include workouts you imported, so that total is your history, not time since "
    + "you installed Hardset."

  /// D31's one sentence. Nothing is clamped, dropped, or shown as a negative interval.
  public static func futureDated(_ sets: Int) -> String {
    if sets == 1 {
      return "1 working set is dated in the future. It counts in lifetime totals, not in last "
        + "trained or the weekly figures."
    }
    return "\(sets) working sets are dated in the future. They count in lifetime totals, not in "
      + "last trained or the weekly figures."
  }

  /// A muscle with no credited set.
  public static let noCreditedSets = "No credited sets"

  /// A muscle with no credited set in a history that holds unattributed sets.
  public static func noCreditedSetsFloor(_ sets: Int) -> String {
    let count = sets == 1 ? "1 working set has" : "\(sets) working sets have"
    return "No credited sets · \(count) no body part recorded."
  }

  /// Where a movement with no body part gets one. The sentence is the free screen's way out, said
  /// as a control because the sheet can open the Library.
  public static let floorWayOut = "Set a body part in Library"

  /// What the sheet says before anything has been logged.
  public static let nothingLoggedTitle = "No history yet"
  public static let nothingLoggedDetail =
    "Log a set and muscle history starts here: last trained, the last four weeks against the four "
    + "before, lifetime totals and the twelve-week shape."

  /// "Last trained", "Last 4 weeks", "The 4 weeks before", "Lifetime".
  public static let lastTrained = "Last trained"
  public static let lastFourWeeks = "Last 4 weeks"
  public static let fourWeeksBefore = "The 4 weeks before"
  public static let lifetime = "Lifetime"
  public static let sinceFirstSet = "All logged history"

  /// The signed difference, in words and sets, never a percentage. A zero previous window has
  /// nothing to divide by, so it says so rather than inventing one.
  public static func comparison(
    current: Double, previous: Double, format: WorkedFromFormat
  ) -> String {
    if current > 0, previous > 0 {
      let difference = current - previous
      if abs(difference) < 0.05 { return "The same as the 4 weeks before." }
      if difference > 0 {
        return "Up \(format.sets(difference)) sets on the 4 weeks before."
      }
      return "Down \(format.sets(-difference)) sets on the 4 weeks before."
    }
    if current > 0 {
      return "None in the 4 weeks before."
    }
    if previous > 0 {
      return "None in the last 4 weeks, down from \(format.sets(previous)) in the 4 before."
    }
    return "No credited sets in either four-week stretch."
  }

  /// "12 weeks, Sep 2, 2026 to Nov 23, 2026", or "1 week" when only the current window holds
  /// history. The count is the points drawn, so the label names exactly the span the shape covers.
  public static func shapeSpan(
    weeks: Int, first: Date, last: Date, format: WorkedFromFormat
  ) -> String {
    let span = weeks == 1 ? "1 week" : "\(weeks) weeks"
    guard weeks > 1 else { return span }
    return "\(span), \(format.day(first)) to \(format.day(last))"
  }
}

// MARK: - Inspection

/// Which derived figure on the sheet a lifter opened the working for.
public enum MuscleHistoryFigure: String, Hashable, Sendable, CaseIterable {
  /// The current four weeks against the four weeks before.
  case fourWeeks
  /// Every working set in history.
  case lifetime
}

extension MuscleHistory {
  /// The working behind one of a muscle's derived figures, built from the same inputs through the
  /// same `MuscleCountWorking` derivation the figure came from.
  ///
  /// - Parameters:
  ///   - attribution: The attribution the figures were counted with, read in the same snapshot.
  ///   - imported: Movements a workout import created, so their lines say so.
  ///   - name: A movement's name, for the lines.
  public func account(
    muscle: Muscle,
    figure: MuscleHistoryFigure,
    muscleName: String,
    attribution: AttributionIndex,
    imported: Set<ExerciseID> = [],
    name: (ExerciseID) -> String,
    format: WorkedFromFormat
  ) -> WorkedFromAccount {
    switch figure {
    case .fourWeeks:
      return fourWeekAccount(
        muscle: muscle, muscleName: muscleName, attribution: attribution, imported: imported,
        name: name, format: format)
    case .lifetime:
      return lifetimeAccount(
        muscle: muscle, muscleName: muscleName, attribution: attribution, imported: imported,
        name: name, format: format)
    }
  }

  private func fourWeekAccount(
    muscle: Muscle, muscleName: String, attribution: AttributionIndex,
    imported: Set<ExerciseID>, name: (ExerciseID) -> String, format: WorkedFromFormat
  ) -> WorkedFromAccount {
    let currentWorking = MuscleCountWorking.derive(
      muscle: muscle, sets: currentSets, attribution: attribution, imported: imported, name: name)
    let previousWorking = MuscleCountWorking.derive(
      muscle: muscle, sets: previousSets, attribution: attribution, imported: imported, name: name)
    let currentLabel = "\(MuscleHistoryCopy.lastFourWeeks), "
      + "\(format.day(currentSpan.start)) to now"
    let previousLabel = "\(MuscleHistoryCopy.fourWeeksBefore), "
      + "\(format.day(previousSpan.start)) to \(format.day(previousSpan.lastDay))"
    let currentAccount = currentWorking.account(
      muscleName: muscleName, windowLabel: currentLabel, format: format, statesCertainty: false)
    let previousAccount = previousWorking.account(
      muscleName: muscleName, windowLabel: previousLabel, format: format, statesCertainty: false)
    let comparison = MuscleHistoryCopy.comparison(
      current: currentWorking.total, previous: previousWorking.total, format: format)
    let floor = currentWorking.isLowerBound ? "≥ " : ""
    let sections =
      prefixed(currentAccount.sections, prefix: "current", label: MuscleHistoryCopy.lastFourWeeks)
      + prefixed(
        previousAccount.sections, prefix: "previous", label: MuscleHistoryCopy.fourWeeksBefore)
    return WorkedFromAccount(
      title: "\(muscleName), the last 4 weeks",
      figure: "\(floor)\(format.sets(currentWorking.total)) sets",
      figureCaption: "\(currentLabel) · \(comparison)",
      ruleHeading: "How sets are counted",
      rule: MuscleCountWorking.rule(format: format, statesCertainty: false),
      sections: sections,
      spoken: "\(currentAccount.spoken) \(comparison) \(previousAccount.spoken)")
  }

  private func lifetimeAccount(
    muscle: Muscle, muscleName: String, attribution: AttributionIndex,
    imported: Set<ExerciseID>, name: (ExerciseID) -> String, format: WorkedFromFormat
  ) -> WorkedFromAccount {
    let working = MuscleCountWorking.derive(
      muscle: muscle, sets: lifetimeSets, attribution: attribution, imported: imported, name: name)
    let account = working.account(
      muscleName: muscleName, windowLabel: MuscleHistoryCopy.sinceFirstSet, format: format,
      statesCertainty: false)
    // The aggregate excluded warm-ups in SQL, so this account cannot list them one by one or count
    // them. It says they were excluded, without a number, rather than leaving their absence silent.
    let sections = account.sections.map { section in
      guard section.id == "left" else { return section }
      let line = WorkedFromAccount.Line(
        id: "warmups-aggregate", standing: .excluded, headline: "Warm-up sets", context: nil,
        detail: "Left out: warm-ups count toward no muscle. They were excluded from this total and "
          + "are not counted here one by one.",
        spoken: "Warm-up sets. Left out: warm-ups count toward no muscle.")
      return WorkedFromAccount.Section(
        id: section.id, heading: section.heading, note: section.note,
        lines: section.lines + [line])
    }
    let floor = working.isLowerBound ? "≥ " : ""
    return WorkedFromAccount(
      title: "\(muscleName), lifetime fractional sets",
      figure: "\(floor)\(format.sets(working.total)) sets",
      figureCaption: MuscleHistoryCopy.sinceFirstSet,
      ruleHeading: "How sets are counted",
      rule: account.rule,
      sections: sections,
      spoken: account.spoken)
  }

  /// The window accounts' sections under the window they belong to, so the two derivations cannot
  /// be read as one.
  private func prefixed(
    _ sections: [WorkedFromAccount.Section], prefix: String, label: String
  ) -> [WorkedFromAccount.Section] {
    sections.map { section in
      WorkedFromAccount.Section(
        id: "\(prefix)-\(section.id)",
        heading: section.id == "credited" ? "\(label) · where the count comes from"
          : "\(label) · left out",
        note: section.note, lines: section.lines)
    }
  }
}
