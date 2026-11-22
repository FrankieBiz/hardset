import Foundation

/// Which set set a record, what it beat, by how much, and the rule that called it a record.
///
/// The working behind a record star on the chart and a record on the receipt. It does not decide
/// anything: the chart's findings are `ProgressTrendAnalyzer.recordFindings`, the replay the stars
/// themselves come from, and the receipt's are the `PersonalRecord`s the detector already attached
/// to each line. The margin a record needed is `PersonalRecordDetector.requiredMarginKg`, the very
/// function the detector applied, so what the lifter is told it needed is what was required.
public struct RecordWorking: Hashable, Sendable {
  /// One record: the set that set it and what it was measured against.
  public struct Entry: Hashable, Sendable, Identifiable {
    public let id: String
    /// What the detector found: the kind, the set's figures and the previous best it beat.
    public let record: PersonalRecord
    /// When the set was done, where the history knows it.
    public let setDate: Date?
    /// The earlier set the record beat, where the history names exactly one.
    public let beaten: PriorSetRecord?
    /// The equipment's own load step as the detector was given it. `nil` means it was not known and
    /// the detector assumed one 5 lb plate, as `PersonalRecordDetector.defaultIncrementKg` says.
    public let incrementKg: Double?
  }

  /// The records of one session on one machine, or of one set on a receipt.
  public struct Group: Hashable, Sendable, Identifiable {
    public let id: String
    public let date: Date?
    /// The machine as the chart's legend names it, or the receipt's equipment words.
    public let equipmentLabel: String
    /// A receipt's movement and set, which name the group where the date does not.
    public let setTitle: String?
    /// What the records were compared with, in words.
    public let scope: String
    public let entries: [Entry]
  }

  /// Newest first on a chart; in the order performed on a receipt.
  public let groups: [Group]

  public var entryCount: Int { groups.reduce(0) { $0 + $1.entries.count } }

  // MARK: - Derivation

  /// The records on a chart's lines, from the replay the stars come from.
  ///
  /// - Parameters:
  ///   - keys: The series on the chart.
  ///   - samples: The exercise's working sets, as the history reads them.
  ///   - incrementKg: A series' machine's load step, as the replay was given it.
  ///   - label: A series' name in the chart's legend.
  public static func derive(
    keys: [ProgressionKey],
    samples: [ProgressionSample],
    estimatesOneRepMax: Bool,
    incrementKg: (ProgressionKey) -> Double?,
    label: (ProgressionKey) -> String
  ) -> RecordWorking {
    var groups: [Group] = []
    for key in keys {
      let step = incrementKg(key)
      let findings = ProgressTrendAnalyzer.recordFindings(
        samples: samples.filter { key.contains($0) }, incrementKg: step,
        estimatesOneRepMax: estimatesOneRepMax)
      let bySession = Dictionary(grouping: findings, by: \.sessionID)
      for (session, found) in bySession {
        let entries = found.enumerated().map { index, finding in
          Entry(
            id: "\(session)-\(index)", record: finding.record, setDate: finding.sample.completedAt,
            beaten: finding.beaten, incrementKg: step)
        }
        groups.append(
          Group(
            id: "\(label(key))-\(session)", date: found.map(\.sample.completedAt).min(),
            equipmentLabel: label(key), setTitle: nil, scope: scope(of: key), entries: entries))
      }
    }
    groups.sort {
      if $0.date != $1.date { return ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
      return $0.id < $1.id
    }
    return RecordWorking(groups: groups)
  }

  /// What a series' records were compared with. Each series is its own history: a machine's, the
  /// movement's with no machine recorded, or imported history, which records no machine and is kept
  /// apart from logged sets, so no record on one is measured against the other.
  static func scope(of key: ProgressionKey) -> String {
    if key.isImported {
      return "every earlier imported set of this movement. Imported history is never compared with sets you logged"
    }
    return key.machineID == nil
      ? "every earlier working set of this movement with no machine recorded"
      : "every earlier working set on this machine"
  }

  /// The records a receipt already carries, one group per set that earned any.
  ///
  /// - Parameter line: Limits the working to one set; `nil` covers the whole workout.
  public static func derive(receipt: WorkoutReceipt, line only: WorkoutReceipt.Line? = nil)
    -> RecordWorking
  {
    let groups = receipt.lines
      .filter { !$0.records.isEmpty && (only == nil || $0.id == only?.id) }
      .map { line in
        Group(
          id: "\(line.id)", date: nil, equipmentLabel: line.equipmentLabel,
          setTitle: line.exerciseName,
          scope: "every earlier working set on the \(line.equipment.recordScope)",
          entries: line.records.map {
            Entry(
              id: "\(line.id)-\($0.kind.rawValue)", record: $0, setDate: nil, beaten: nil,
              incrementKg: line.incrementKg)
          })
      }
    return RecordWorking(groups: groups)
  }

  // MARK: - Words

  /// What a record is, stated from the constants the detector uses.
  static func rule(format: WorkedFromFormat) -> String {
    let relative = format.sets(PersonalRecordDetector.relativeThreshold * 100) + "%"
    let plate = "\(format.sets(WeightUnit.pounds.plateIncrement)) lb"
    return "A record is a working set that beats everything logged before it on the same equipment by a real margin. "
      + "Heaviest weight, and most weight for at least that many reps, each need at least the greater of "
      + "\(relative) and one plate step more than the old best. The step is the machine's own, or one "
      + "\(plate) plate when none is saved. "
      + "Most reps at an exact weight needs one more rep than you have ever logged there. "
      + "Best estimated one-rep max needs \(relative) more, and an estimate on both sides. "
      + "Matching a past set is not a record, a warm-up never is, and a movement's first session only builds history."
  }

  /// A piece of a sentence, so one template renders both as written and as read aloud.
  private enum Piece {
    case words(String)
    case set(Double, Int)
    case load(Double)
    case estimate(Double)
  }

  private static func render(_ pieces: [Piece], format: WorkedFromFormat, spoken: Bool) -> String {
    pieces.map { piece in
      switch piece {
      case .words(let text): text
      case .set(let kg, let reps): spoken ? format.setSpoken(weightKg: kg, reps: reps) : format.set(weightKg: kg, reps: reps)
      case .load(let kg): spoken ? format.loadSpoken(kg) : format.load(kg)
      case .estimate(let kg): spoken ? format.estimateSpoken(kg) : format.estimate(kg)
      }
    }.joined()
  }

  /// "+5%", "+5.3%": a gain as a signed percent to one decimal at most.
  private static func percent(_ fraction: Double, format: WorkedFromFormat) -> String {
    "+\(format.sets(fraction * 100))%"
  }

  /// What the record beat, what it beat it by and what the rule needed, as pieces of one sentence.
  private static func pieces(for entry: Entry, format: WorkedFromFormat) -> [Piece] {
    let record = entry.record
    let relative = format.sets(PersonalRecordDetector.relativeThreshold * 100) + "%"
    var pieces: [Piece] = []

    /// How the old best is named: the set with its day where the history knows it, otherwise by its figures.
    func previous(fallback: [Piece]) -> [Piece] {
      guard let beaten = entry.beaten else { return fallback }
      return [.set(beaten.weightKg, beaten.reps), .words(" on \(format.day(beaten.completedAt))")]
    }

    switch record.kind {
    case .heaviestLoad:
      let old = record.previousWeightKg ?? 0
      let gain = record.weightKg - old
      let required = PersonalRecordDetector.requiredMarginKg(over: old, increment: entry.incrementKg)
      let share = percent(old > 0 ? gain / old : 0, format: format)
      pieces.append(.words("Beat your previous heaviest weight, "))
      pieces.append(contentsOf: previous(fallback: [.load(old)]))
      pieces.append(.words(", by "))
      pieces.append(.load(gain))
      pieces.append(.words(" (\(share)). A new heaviest weight needs at least "))
      pieces.append(.load(required))
      pieces.append(.words(" more: the greater of \(relative) of "))
      pieces.append(.load(old))
      pieces.append(.words(" and one plate step."))
    case .repsAtLoad:
      let oldReps = record.previousReps ?? 0
      let gain = record.reps - oldReps
      pieces.append(.words("Beat "))
      pieces.append(
        contentsOf: previous(fallback: [
          .words("\(oldReps) \(oldReps == 1 ? "rep" : "reps") at "), .load(record.weightKg),
        ]))
      pieces.append(
        .words(
          " by \(gain) \(gain == 1 ? "rep" : "reps"). "
            + "A reps record needs more reps than you have ever logged at exactly this weight."))
    case .loadAtReps:
      let old = record.previousWeightKg ?? 0
      let oldReps = record.previousReps ?? 0
      let gain = record.weightKg - old
      let required = PersonalRecordDetector.requiredMarginKg(over: old, increment: entry.incrementKg)
      let share = percent(old > 0 ? gain / old : 0, format: format)
      pieces.append(.words("Beat "))
      pieces.append(contentsOf: previous(fallback: [.set(old, oldReps)]))
      pieces.append(.words(" by "))
      pieces.append(.load(gain))
      pieces.append(.words(" (\(share)). It needs at least "))
      pieces.append(.load(required))
      pieces.append(
        .words(" more than the best earlier set of \(record.reps) reps or more: the greater of \(relative) of "))
      pieces.append(.load(old))
      pieces.append(.words(" and one plate step."))
    case .estimatedOneRepMax:
      let old = record.previousWeightKg ?? 0
      let estimate = StrengthMath.estimatedOneRepMax(weightKg: record.weightKg, reps: record.reps).value ?? 0
      let share = percent(old > 0 ? estimate / old - 1 : 0, format: format)
      pieces.append(.words("This set's estimated one-rep max, "))
      pieces.append(.estimate(estimate))
      pieces.append(.words(", beat your previous best estimate, "))
      pieces.append(.estimate(old))
      if let beaten = entry.beaten {
        pieces.append(.words(", from "))
        pieces.append(.set(beaten.weightKg, beaten.reps))
        pieces.append(.words(" on \(format.day(beaten.completedAt))"))
      }
      pieces.append(
        .words(", by \(share). It needs at least \(relative) more, with an estimate on both sides."))
    }
    return pieces
  }

  /// What the account says, built from this derivation and nothing else.
  ///
  /// - Parameters:
  ///   - title: What is being explained: "Records", "Records on this set".
  ///   - caption: What qualifies it, in `provenance`: where and when.
  public func account(title: String, caption: String, format: WorkedFromFormat) -> WorkedFromAccount {
    let sections = groups.map { group -> WorkedFromAccount.Section in
      let heading: String
      if let setTitle = group.setTitle, let first = group.entries.first {
        heading = "\(setTitle), \(format.set(weightKg: first.record.weightKg, reps: first.record.reps))"
      } else if let date = group.date {
        heading = "\(format.day(date)) · \(group.equipmentLabel)"
      } else {
        heading = group.equipmentLabel
      }
      let lines = group.entries.map { entry -> WorkedFromAccount.Line in
        let record = entry.record
        let detail = Self.render(Self.pieces(for: entry, format: format), format: format, spoken: false)
        let spokenDetail = Self.render(Self.pieces(for: entry, format: format), format: format, spoken: true)
        let setText = format.set(weightKg: record.weightKg, reps: record.reps)
        let context = [setText, group.equipmentLabel].joined(separator: " · ")
        return WorkedFromAccount.Line(
          id: "record-\(entry.id)", standing: .produced, headline: record.qualifiedLabel,
          context: context, detail: detail,
          spoken: "\(record.qualifiedLabel). \(format.setSpoken(weightKg: record.weightKg, reps: record.reps)), "
            + "\(group.equipmentLabel). \(spokenDetail)",
          standingWord: "Set the record")
      }
      return WorkedFromAccount.Section(
        id: "group-\(group.id)", heading: heading,
        note: "Compared with \(group.scope).", lines: lines)
    }

    let count = entryCount
    let figure = "\(count) \(count == 1 ? "record" : "records")"
    let spoken = "\(title), \(figure), \(caption). "
      + groups.map { group in
        let kinds = group.entries.map { $0.record.kind.label }.joined(separator: ", ")
        let when = group.date.map { format.day($0) } ?? group.setTitle ?? group.equipmentLabel
        return "\(when): \(kinds)."
      }.joined(separator: " ")
    return WorkedFromAccount(
      title: title, figure: figure, figureCaption: caption, ruleHeading: "What counts as a record",
      rule: Self.rule(format: format), sections: sections, spoken: spoken)
  }

  // MARK: - Accounts

  /// The account behind a chart's record stars, for every line that has one. `nil` when no line set
  /// a record, so nothing is offered that would explain an absence.
  public static func chartAccount(
    keys: [ProgressionKey], samples: [ProgressionSample], estimatesOneRepMax: Bool,
    incrementKg: (ProgressionKey) -> Double?, label: (ProgressionKey) -> String,
    format: WorkedFromFormat
  ) -> WorkedFromAccount? {
    let working = derive(
      keys: keys, samples: samples, estimatesOneRepMax: estimatesOneRepMax,
      incrementKg: incrementKg, label: label)
    guard !working.groups.isEmpty else { return nil }
    let sessions = working.groups.count
    let labels = Array(Set(working.groups.map(\.equipmentLabel))).sorted()
    return working.account(
      title: "Records", caption: "\(sessions) \(sessions == 1 ? "session" : "sessions") with a star · \(labels.joined(separator: ", "))",
      format: format)
  }

  /// The account behind the records on a receipt, or on one of its sets. `nil` when there are none.
  public static func receiptAccount(
    receipt: WorkoutReceipt, line: WorkoutReceipt.Line? = nil, format: WorkedFromFormat
  ) -> WorkedFromAccount? {
    let working = derive(receipt: receipt, line: line)
    guard !working.groups.isEmpty else { return nil }
    let name = receipt.title.isEmpty ? "Workout" : receipt.title
    return working.account(
      title: line == nil ? "Records in this workout" : "Records on this set",
      caption: "\(name) · \(format.day(receipt.startedAt))", format: format)
  }
}
