import Foundation

extension RecordWorking {
  /// The working behind the record notice the live session draws for the set just logged.
  ///
  /// The notice states what the records beat, and for an estimated max a figure that is itself an
  /// estimate, so it cannot be taken on trust either. This explains exactly the records on screen: one
  /// line for each, built from the same `PersonalRecord` the notice draws and the margin the detector
  /// applied. The set each beat is named from the replay the chart's stars come from, which finds the
  /// same record on the saved history, and where it cannot name exactly one set the line is written
  /// without it, as a receipt's is.
  ///
  /// When one of the records is an estimated max the account also carries the estimate's own working,
  /// from `EstimateWorking`: the formula, which of this session's sets fed the figure and which were
  /// left out. Under "Left out of the comparison" it counts what the record was never measured
  /// against: warm-ups, sets on other equipment and imported history.
  ///
  /// - Parameters:
  ///   - records: The records the notice shows, in the order it shows them.
  ///   - samples: The movement's working sets across series, as `ProgressionHistory` reads them,
  ///     including the set just logged.
  ///   - warmups: The movement's warm-ups, which no analysis reads.
  ///   - incrementKg: The machine's load step the detector was given, or `nil` when it has none.
  /// - Returns: `nil` when there are no records to explain.
  public static func liveAccount(
    records: [PersonalRecord],
    exerciseName: String,
    sessionID: SessionID,
    key: ProgressionKey,
    samples: [ProgressionSample],
    warmups: [ProgressionSample],
    estimatesOneRepMax: Bool,
    assumesAddedLoad: Bool = false,
    incrementKg: Double?,
    label: (ProgressionKey) -> String,
    format: WorkedFromFormat
  ) -> WorkedFromAccount? {
    guard !records.isEmpty else { return nil }
    let findings = ProgressTrendAnalyzer.recordFindings(
      samples: samples.filter { key.contains($0) }, incrementKg: incrementKg,
      estimatesOneRepMax: estimatesOneRepMax
    ).filter { $0.sessionID == sessionID }

    let seriesLabel = label(key)
    let entries = records.enumerated().map { index, record -> Entry in
      let finding = findings.first { $0.record == record }
      return Entry(
        id: "live-\(index)", record: record, setDate: finding?.sample.completedAt,
        beaten: finding?.beaten, incrementKg: incrementKg)
    }
    let setDate = entries.compactMap(\.setDate).min()
    let working = RecordWorking(
      groups: [
        Group(
          id: "live", date: setDate, equipmentLabel: seriesLabel, setTitle: exerciseName,
          scope: scope(of: key), entries: entries)
      ])

    let estimatedRecord = records.first { $0.kind == .estimatedOneRepMax }
    let title = records.count == 1 ? "New record" : "New records"
    var caption = [exerciseName, seriesLabel].joined(separator: " · ")
    if let estimatedRecord {
      // An estimate never stands without how far to trust it, from the estimator itself.
      let certainty = StrengthMath.estimatedOneRepMax(
        weightKg: estimatedRecord.weightKg, reps: estimatedRecord.reps
      ).certainty
      caption = ScorecardCopy.confidenceWords(certainty) + " · " + caption
    }
    if let setDate { caption += " · " + format.day(setDate) }
    let base = working.account(title: title, caption: caption, format: format)

    var sections = base.sections
    var rule = base.rule
    var spoken = base.spoken

    if estimatedRecord != nil,
      let estimate = EstimateWorking.derive(
        key: key, sessionID: sessionID, samples: samples, warmups: warmups,
        estimatesOneRepMax: estimatesOneRepMax, assumesAddedLoad: assumesAddedLoad, label: label)
    {
      let account = estimate.account(format: format)
      rule += "\n\n" + EstimateWorking.rule(format: format)
      spoken += " " + account.spoken
      sections += account.sections.map { section in
        WorkedFromAccount.Section(
          id: "estimate-\(section.id)",
          heading: section.id == "left" ? "Left out of this estimate" : "This session's estimate · " + section.heading,
          note: section.note, lines: section.lines)
      }
    }

    // What the record was never measured against, counted: it is how "every earlier working set on
    // this machine" is true without a list of hundreds of sets.
    let otherEquipment = samples.filter { !key.contains($0) && !$0.isImported }.count
    let imported = samples.filter { !key.contains($0) && $0.isImported }.count
    var left: [WorkedFromAccount.Line] = []
    func leftLine(_ id: String, count: Int, noun: String, context: String, detail: String) {
      guard count > 0 else { return }
      let headline = "\(count) \(noun)"
      left.append(
        WorkedFromAccount.Line(
          id: id, standing: .excluded, headline: headline, context: context, detail: detail,
          spoken: "\(headline), \(context). \(detail)"))
    }
    leftLine(
      "comparison-warmups", count: warmups.count, noun: warmups.count == 1 ? "warm-up set" : "warm-up sets",
      context: "Every session",
      detail: "Left out: warm-ups are never compared with, so a record cannot have beaten one.")
    leftLine(
      "comparison-elsewhere", count: otherEquipment, noun: otherEquipment == 1 ? "set on other equipment" : "sets on other equipment",
      context: "Every session",
      detail: "Left out: each machine has its own history, so a record on \(seriesLabel) is never measured against another machine.")
    leftLine(
      "comparison-imported", count: imported, noun: imported == 1 ? "imported set" : "imported sets",
      context: "Every session",
      detail: "Left out: imported history is a line of its own and is never compared with sets you logged.")
    sections.append(
      WorkedFromAccount.Section(
        id: "comparison-left", heading: "Left out of the comparison",
        note: left.isEmpty
          ? "Nothing was left out. Warm-ups, other machines and imported history are never compared with."
          : "Warm-ups, other machines and imported history are never compared with.",
        lines: left))
    spoken += left.isEmpty
      ? " Nothing was left out of the comparison."
      : " Left out of the comparison: " + left.map(\.headline).joined(separator: ", ") + "."

    return WorkedFromAccount(
      title: title, figure: base.figure, figureCaption: caption, ruleHeading: base.ruleHeading,
      rule: rule, sections: sections, spoken: spoken)
  }
}
