import Foundation

/// Which sets produced the weekly working-set count the Volume screen leads with, and what was left
/// out.
///
/// That count is the screen's monument, 88 pt, because it is a count of what the lifter logged and
/// not an estimate. A large number the lifter cannot inspect is exactly what the product refuses, so
/// it opens the same "Worked from" sheet as every figure that can say how it was made.
///
/// It takes the inputs `VolumeAnalyzer.report` takes and asks the same question of every set through
/// `VolumeAnalyzer.credit(for:attribution:)`: a warm-up is left out, and every other set is a working
/// set, whether or not its movement has muscles recorded. So `total` is `report.hardSets`, by the
/// same classification and not by a second one, and a test holds the two equal.
public struct WorkingSetCountWorking: Hashable, Sendable {
  /// A movement whose sets were counted.
  public struct Movement: Hashable, Sendable, Identifiable {
    public let exerciseID: ExerciseID
    public let name: String
    public let workingSets: Int
    /// Created by a workout import. Its sets count like any other.
    public let isImported: Bool
    /// False when the movement has no muscles recorded, so its sets are working sets that credit no
    /// muscle. They are in the count and the account says they are.
    public let hasMuscles: Bool

    public var id: ExerciseID { exerciseID }
  }

  /// The count on screen: working sets in the window.
  public let total: Int
  /// The movements the count came from, the most sets first.
  public let movements: [Movement]
  /// Warm-up sets in the window, left out of the count.
  public let warmupSets: Int

  /// Working sets on movements with no muscles recorded: counted here, credited to no muscle.
  public var unattributedSets: Int { movements.filter { !$0.hasMuscles }.reduce(0) { $0 + $1.workingSets } }

  // MARK: - Derivation

  /// - Parameters:
  ///   - sets: The window's sets, warm-ups included, as `VolumeAnalyzer.report` is given them.
  ///   - imported: The movements a workout import created; only the lines say which they are.
  ///   - name: A movement's name, for the lines.
  public static func derive(
    sets: [CountableSet],
    attribution: AttributionIndex,
    imported: Set<ExerciseID> = [],
    name: (ExerciseID) -> String
  ) -> WorkingSetCountWorking {
    var counts: [ExerciseID: (sets: Int, hasMuscles: Bool)] = [:]
    var warmups = 0
    var total = 0
    for set in sets {
      switch VolumeAnalyzer.credit(for: set, attribution: attribution) {
      case .warmup:
        warmups += 1
      case .unattributed:
        total += 1
        counts[set.exerciseID, default: (0, false)].sets += 1
      case .attributed:
        total += 1
        counts[set.exerciseID, default: (0, true)].sets += 1
      }
    }
    let movements = counts
      .map { id, tally in
        Movement(
          exerciseID: id, name: name(id), workingSets: tally.sets, isImported: imported.contains(id),
          hasMuscles: tally.hasMuscles)
      }
      .sorted {
        if $0.workingSets != $1.workingSets { return $0.workingSets > $1.workingSets }
        if $0.name != $1.name { return $0.name < $1.name }
        return $0.exerciseID.rawValue.uuidString < $1.exerciseID.rawValue.uuidString
      }
    return WorkingSetCountWorking(total: total, movements: movements, warmupSets: warmups)
  }

  // MARK: - Words

  static func rule() -> String {
    "A working set is a set you logged that is not marked as a warm-up. Every working set counts "
      + "once, whichever movement it was on and whether or not the movement has muscles recorded. "
      + "This is a count of what you logged, so it carries no confidence rating and no target."
  }

  private static func sets(_ count: Int) -> String { count == 1 ? "1 set" : "\(count) sets" }

  /// What the account says, built from this derivation and nothing else.
  ///
  /// - Parameter windowLabel: The window the count covers, in words: "Last 7 days, 14 Nov to now".
  public func account(windowLabel: String, format: WorkedFromFormat) -> WorkedFromAccount {
    let count = format.sets(Double(total))
    let noun = total == 1 ? "working set" : "working sets"

    let counted = movements.map { movement in
      let context =
        ([Self.sets(movement.workingSets)]
        + (movement.hasMuscles ? [] : ["no muscles recorded"])
        + (movement.isImported ? ["imported movement"] : [])).joined(separator: " · ")
      return WorkedFromAccount.Line(
        id: "counted-\(movement.exerciseID)", standing: .counted, headline: movement.name,
        context: context,
        detail: "\(Self.sets(movement.workingSets)) counted"
          + (movement.hasMuscles
            ? "."
            : ", and credited to no muscle until the movement has a body part. Set it in Library, on the Train tab."),
        spoken: "\(movement.name), \(Self.sets(movement.workingSets))"
          + (movement.hasMuscles ? "" : ", no muscles recorded")
          + (movement.isImported ? ", imported movement" : "") + ".")
    }

    var left: [WorkedFromAccount.Line] = []
    if warmupSets > 0 {
      let warmupText = warmupSets == 1 ? "1 warm-up set" : "\(warmupSets) warm-up sets"
      left.append(
        WorkedFromAccount.Line(
          id: "warmups", standing: .excluded, headline: warmupText, context: nil,
          detail: "Left out: warm-ups are real work and are not the prescription, so they never count.",
          spoken: "\(warmupText). Left out: warm-ups never count."))
    }

    let sections = [
      WorkedFromAccount.Section(
        id: "counted", heading: "Where the count comes from",
        note: movements.isEmpty
          ? "No working set was logged in this window."
          : "The sets below add up to \(count).",
        lines: counted),
      WorkedFromAccount.Section(
        id: "left", heading: "Left out",
        note: left.isEmpty ? "Nothing in this window was left out." : "Warm-ups never count.",
        lines: left),
    ]

    let from = movements.isEmpty
      ? "No set was logged."
      : "Counted from \(movements.map { "\($0.name) \($0.workingSets)" }.joined(separator: ", "))."
    let leftSentence = warmupSets == 0
      ? "Nothing was left out."
      : "Left out: \(warmupSets == 1 ? "1 warm-up set" : "\(warmupSets) warm-up sets")."

    return WorkedFromAccount(
      title: "Working sets", figure: "\(count) \(noun)",
      figureCaption: "\(windowLabel) · counted from sets you logged, not estimated",
      ruleHeading: "How sets are counted", rule: Self.rule(), sections: sections,
      spoken: "\(count) \(noun), \(windowLabel), counted from sets you logged, not estimated. "
        + "\(from) \(leftSentence)")
  }
}
