import Foundation

/// Which sets produced one muscle's weekly count, what each was credited and why, and what was left
/// out.
///
/// The working behind a figure on the Volume rows and the deep muscle map. It takes the same inputs
/// `VolumeAnalyzer.report` takes, a window's sets and the attribution of their movements, and asks
/// the same question of every set through `VolumeAnalyzer.credit(for:attribution:)`, so the total
/// here is the count on screen and a set cannot be counted one way in the report and another way in
/// its explanation.
///
/// Sets are grouped by movement because that is how credit is given: every set of a movement credits
/// a muscle the same amount, by the role the movement has for it.
public struct MuscleCountWorking: Hashable, Sendable {
  /// A movement whose sets were counted, or whose sets were involved and counted for nothing.
  public struct Movement: Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String
    /// The movement's role for this muscle: direct 1.0, indirect 0.5, stabilizing 0.
    public let role: MuscleRole
    /// What one set of the movement credits this muscle.
    public let creditPerSet: Double
    public let setCount: Int
    /// What all of its sets credited together.
    public let credit: Double

    public var id: ExerciseID { exerciseID }
  }

  /// A movement with no muscles recorded: its sets are working sets and credit no muscle.
  public struct Unattributed: Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String
    public let setCount: Int

    public var id: ExerciseID { exerciseID }
  }

  public let muscle: Muscle
  /// The muscle's fractional sets: the figure on the row, summed in the order the sets were done.
  public let total: Double
  /// Movements that credited the muscle, the biggest credit first.
  public let credited: [Movement]
  /// Movements that involve the muscle only to stabilise it. Their sets credit it nothing.
  public let stabilizing: [Movement]
  /// Every movement in the window with no muscles recorded. Any of them may have trained this
  /// muscle, which is why the count is a floor while any exist.
  public let unattributed: [Unattributed]
  /// Warm-ups in the window. They count toward no muscle.
  public let warmupSets: Int
  /// Working sets on movements recorded as training other muscles and not this one.
  public let unrelatedSets: Int
  /// Working sets in the window, as the report counts them.
  public let hardSets: Int

  /// True when a set could not be attributed, so the count is at least what is shown.
  public var isLowerBound: Bool { !unattributed.isEmpty }

  /// Where this count sits on the published research: the engine's own answer for the same count.
  public var certainty: Certainty {
    VolumeAnalyzer.doseResponse(fractionalSets: total, for: muscle).certainty
  }

  // MARK: - Derivation

  /// - Parameters:
  ///   - sets: The window's sets, warm-ups included, as `VolumeAnalyzer.report` is given them.
  ///   - name: A movement's name, for the lines.
  public static func derive(
    muscle: Muscle,
    sets: [CountableSet],
    attribution: AttributionIndex,
    name: (ExerciseID) -> String
  ) -> MuscleCountWorking {
    struct Tally {
      var role: MuscleRole
      var creditPerSet: Double
      var setCount = 0
      var credit = 0.0
    }
    let key = MuscleKey(muscle)
    var total = 0.0
    var hardSets = 0
    var warmups = 0
    var unrelated = 0
    var credited: [ExerciseID: Tally] = [:]
    var stabilizing: [ExerciseID: Tally] = [:]
    var unattributed: [ExerciseID: Int] = [:]

    for set in sets {
      switch VolumeAnalyzer.credit(for: set, attribution: attribution) {
      case .warmup:
        warmups += 1
      case .unattributed:
        hardSets += 1
        unattributed[set.exerciseID, default: 0] += 1
      case .attributed(let contributions):
        hardSets += 1
        let mine = contributions.filter { $0.key == key }
        guard let strongest = mine.max(by: { $0.setWeight < $1.setWeight }) else {
          unrelated += 1
          continue
        }
        // The report adds each contribution's weight; so does this.
        let credit = mine.reduce(0) { $0 + $1.setWeight }
        total += credit
        var tally = (credit > 0 ? credited : stabilizing)[set.exerciseID]
          ?? Tally(role: strongest.role, creditPerSet: credit)
        tally.setCount += 1
        tally.credit += credit
        if credit > 0 {
          credited[set.exerciseID] = tally
        } else {
          stabilizing[set.exerciseID] = tally
        }
      }
    }

    func movements(_ tallies: [ExerciseID: Tally]) -> [Movement] {
      tallies
        .map { id, tally in
          Movement(
            exerciseID: id, name: name(id), role: tally.role, creditPerSet: tally.creditPerSet,
            setCount: tally.setCount, credit: tally.credit)
        }
        .sorted {
          if $0.credit != $1.credit { return $0.credit > $1.credit }
          if $0.setCount != $1.setCount { return $0.setCount > $1.setCount }
          if $0.name != $1.name { return $0.name < $1.name }
          return $0.exerciseID.rawValue.uuidString < $1.exerciseID.rawValue.uuidString
        }
    }

    return MuscleCountWorking(
      muscle: muscle, total: total, credited: movements(credited),
      stabilizing: movements(stabilizing),
      unattributed: unattributed
        .map { Unattributed(exerciseID: $0.key, name: name($0.key), setCount: $0.value) }
        .sorted {
          if $0.setCount != $1.setCount { return $0.setCount > $1.setCount }
          if $0.name != $1.name { return $0.name < $1.name }
          return $0.exerciseID.rawValue.uuidString < $1.exerciseID.rawValue.uuidString
        },
      warmupSets: warmups, unrelatedSets: unrelated, hardSets: hardSets)
  }

  // MARK: - Words

  /// The counting rule, stated from the weights the arithmetic uses.
  static func rule(format: WorkedFromFormat) -> String {
    let direct = format.credit(SetCounting.weight(.direct))
    let indirect = format.credit(SetCounting.weight(.indirect))
    let stabilizer = format.sets(SetCounting.weight(.stabilizer))
    return "A completed working set credits \(direct) set to each muscle the movement trains directly, "
      + "\(indirect) to each it trains indirectly, and \(stabilizer) to each it only stabilises. "
      + "Warm-ups never count. A count is a number of fractional sets, not a rating, and there is "
      + "no target for it to meet. " + VolumeAnalyzer.certaintyMeaning
  }

  static func roleWord(_ role: MuscleRole) -> String {
    switch role {
    case .direct: "direct"
    case .indirect: "indirect"
    case .stabilizer: "stabilizing"
    }
  }

  private static func sets(_ count: Int) -> String { count == 1 ? "1 set" : "\(count) sets" }

  /// What the account says, built from this derivation and nothing else.
  ///
  /// - Parameters:
  ///   - muscleName: The muscle as the lifter reads it, so Core carries no display copy.
  ///   - windowLabel: The window the count covers, in words: "Last 7 days, 14 Nov to now".
  public func account(
    muscleName: String, windowLabel: String, format: WorkedFromFormat
  ) -> WorkedFromAccount {
    let lowered = muscleName.lowercased()
    let confidence = ScorecardCopy.confidenceWords(certainty)
    let floor = isLowerBound ? "≥ " : ""

    let creditedLines = credited.map { movement in
      let each = format.credit(movement.creditPerSet)
      return WorkedFromAccount.Line(
        id: "credited-\(movement.exerciseID)", standing: .counted, headline: movement.name,
        context: "\(Self.sets(movement.setCount)) · \(Self.roleWord(movement.role))",
        detail: "\(Self.sets(movement.setCount)) at \(each) each: \(format.sets(movement.credit)) "
          + "\(movement.credit == 1 ? "set" : "sets") credited to \(lowered).",
        spoken: "\(movement.name), \(Self.sets(movement.setCount)), \(Self.roleWord(movement.role)), "
          + "\(each) each, \(format.sets(movement.credit)) \(movement.credit == 1 ? "set" : "sets") "
          + "credited to \(lowered).")
    }

    var leftLines: [WorkedFromAccount.Line] = []
    for movement in stabilizing {
      leftLines.append(
        WorkedFromAccount.Line(
          id: "stabilizing-\(movement.exerciseID)", standing: .excluded, headline: movement.name,
          context: "\(Self.sets(movement.setCount)) · \(Self.roleWord(movement.role))",
          detail: "Left out: this movement only stabilises \(lowered), which credits \(format.sets(0)), "
            + "so these sets add nothing to it.",
          spoken: "\(movement.name), \(Self.sets(movement.setCount)), stabilizing. Left out: it only "
            + "stabilises \(lowered), which credits nothing."))
    }
    for movement in unattributed {
      leftLines.append(
        WorkedFromAccount.Line(
          id: "unattributed-\(movement.exerciseID)", standing: .excluded, headline: movement.name,
          context: "\(Self.sets(movement.setCount)) · no muscles recorded",
          detail: "Left out: no muscles are recorded for this movement, so its sets credit no muscle. "
            + "It may have trained \(lowered), so the count is at least what is shown.",
          spoken: "\(movement.name), \(Self.sets(movement.setCount)), no muscles recorded. Left out: "
            + "its sets credit no muscle, and it may have trained \(lowered), so the count is at "
            + "least what is shown."))
    }
    let warmupText = warmupSets == 1 ? "1 warm-up set" : "\(warmupSets) warm-up sets"
    if warmupSets > 0 {
      leftLines.append(
        WorkedFromAccount.Line(
          id: "warmups", standing: .excluded, headline: warmupText, context: nil,
          detail: "Left out: warm-ups count toward no muscle.",
          spoken: "\(warmupText). Left out: warm-ups count toward no muscle."))
    }
    if unrelatedSets > 0 {
      leftLines.append(
        WorkedFromAccount.Line(
          id: "unrelated", standing: .excluded,
          headline: "\(Self.sets(unrelatedSets)) on other movements",
          context: nil,
          detail: "Left out: these movements are recorded as training other muscles, not \(lowered), so they are not listed one by one.",
          spoken: "\(Self.sets(unrelatedSets)) on movements recorded as training other muscles, not "
            + "\(lowered). Left out, and not listed one by one."))
    }

    var sections: [WorkedFromAccount.Section] = []
    sections.append(
      WorkedFromAccount.Section(
        id: "credited", heading: "Where the count comes from",
        note: credited.isEmpty
          ? "No set in this window credited \(lowered)."
          : "The credits below add up to \(format.sets(total)).",
        lines: creditedLines))
    sections.append(
      WorkedFromAccount.Section(
        id: "left", heading: "Left out",
        note: leftLines.isEmpty
          ? "Nothing in this window was left out."
          : "Warm-ups never count, and a movement counts only toward the muscles it is recorded as training.",
        lines: leftLines))

    let creditedSentence: String
    if credited.isEmpty {
      creditedSentence = "No set credited \(lowered)."
    } else {
      let parts = credited.map { "\($0.name) \(format.sets($0.credit))" }
      creditedSentence = "Credited by \(parts.joined(separator: ", "))."
    }
    var leftParts: [String] = []
    if warmupSets > 0 { leftParts.append(warmupText) }
    let stabilizingCount = stabilizing.reduce(0) { $0 + $1.setCount }
    if stabilizingCount > 0 { leftParts.append("\(Self.sets(stabilizingCount)) that only stabilise") }
    let unattributedCount = unattributed.reduce(0) { $0 + $1.setCount }
    if unattributedCount > 0 {
      leftParts.append("\(Self.sets(unattributedCount)) on movements with no muscles recorded")
    }
    if unrelatedSets > 0 { leftParts.append("\(Self.sets(unrelatedSets)) on other muscles' movements") }
    let leftSentence = leftParts.isEmpty ? "Nothing was left out." : "Left out: \(leftParts.joined(separator: ", "))."
    let spoken =
      "\(muscleName), \(isLowerBound ? "at least " : "")\(format.sets(total)) fractional sets, "
      + "\(windowLabel), \(confidence). \(creditedSentence) \(leftSentence)"

    return WorkedFromAccount(
      title: "\(muscleName), fractional sets", figure: "\(floor)\(format.sets(total)) sets",
      figureCaption: "\(windowLabel) · \(confidence)", ruleHeading: "How sets are counted",
      rule: Self.rule(format: format), sections: sections, spoken: spoken)
  }
}
