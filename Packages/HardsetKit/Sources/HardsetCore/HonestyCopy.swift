import Foundation

/// One claim the app refuses to make, and the rule that stops it.
///
/// The row is built from the engine rather than written in the view: the id and the source title
/// come from the `EvidenceSource` the rule lives in, and where no source exists the id is the rule's
/// own anchor and the limit is the sentence the screen already shows. A sheet of promises that names
/// its own rules by hand is a second copy of the engine, and the first edit to a limit leaves it
/// lying. Everything here is read, so the sheet can only say what the code does.
public struct Refusal: Hashable, Sendable, Identifiable {
  /// The code reference: the id of the engine `EvidenceSource` the rule lives in, or the
  /// rule's own anchor where no source exists. Unique across the four rows.
  public let id: String
  /// The claim the app does not make, one sentence, number from the constant.
  public let headline: String
  /// What it does instead, one sentence, no number to hit.
  public let body: String
  /// The source's own title, from the engine, so the row cannot name it differently.
  public let sourceTitle: String
  /// The source's own stated limit, from the engine; the row shows it under the body.
  public let sourceLimit: String

  public init(
    id: String, headline: String, body: String, sourceTitle: String, sourceLimit: String
  ) {
    self.id = id
    self.headline = headline
    self.body = body
    self.sourceTitle = sourceTitle
    self.sourceLimit = sourceLimit
  }
}

/// The words behind "What Hardset won't say": the four refusals, each named by the rule that makes
/// it.
///
/// Kept in Core beside the arithmetic, not in the sheet, for the same reason every other disclosure
/// is generated: a claim about what the app will not do is only worth reading if the code enforcing
/// it is the thing that wrote the sentence. The headline that names a number takes that number as a
/// parameter, so a test can prove it is read from the constant rather than typed; the live row calls
/// it with the default.
public enum HonestyCopy {
  public static let title = "What Hardset won't say"

  public static let introduction =
    "These are the claims this app does not make, and the rule that stops each one."

  public static var refusals: [Refusal] { [repsCeiling, weeklyTarget, machineChange, futureDated] }

  /// A one-rep-max estimate's rep ceiling, in the words a lifter reads.
  ///
  /// - Parameter limit: The highest rep count still eligible for an estimate. Parameterised so a
  ///   test can pass a different number and prove the string follows it.
  public static func repsCeilingLine(limit: Int = StrengthMath.maximumEstimableReps) -> String {
    "No one-rep-max estimate above \(limit) reps."
  }

  /// What happens to a set past the ceiling. The number is the same constant the engine checks.
  public static func repsCeilingBody(limit: Int = StrengthMath.maximumEstimableReps) -> String {
    "A set longer than \(limit) reps does not predict a single. The set is still logged and still "
      + "counts as work."
  }

  /// A weekly set target's scope, said in the tense the engine is in.
  ///
  /// No muscle has an evaluated target today, so the row says so. It is written as a function over
  /// the count the engine actually evaluates, so the day a target is published the sentence changes
  /// with it instead of continuing to claim an absence that no longer holds.
  ///
  /// - Parameters:
  ///   - evaluatedTargets: How many muscles `VolumeAnalyzer.weeklyTarget(for:)` answers today.
  ///   - total: The size of the muscle vocabulary; read from `Muscle.allCases`, never typed.
  public static func weeklyTargetLine(
    evaluatedTargets: Int, of total: Int = Muscle.allCases.count
  ) -> String {
    guard evaluatedTargets > 0 else {
      return "No weekly set target for any muscle."
    }
    return "A weekly set target is shown for \(evaluatedTargets) of \(total) muscles."
  }

  // MARK: - Rows

  private static var repsCeiling: Refusal {
    Refusal(
      id: StrengthMath.epleySource.id,
      headline: repsCeilingLine(),
      body: repsCeilingBody(),
      sourceTitle: StrengthMath.epleySource.title,
      sourceLimit: limit(of: StrengthMath.epleySource)
    )
  }

  private static var weeklyTarget: Refusal {
    Refusal(
      id: VolumeAnalyzer.targetSource.id,
      headline: weeklyTargetLine(evaluatedTargets: evaluatedTargetCount),
      body: weeklyTargetBody,
      sourceTitle: VolumeAnalyzer.targetSource.title,
      sourceLimit: limit(of: VolumeAnalyzer.targetSource)
    )
  }

  private static var machineChange: Refusal {
    Refusal(
      id: ProgressionAnalyzer.source.id,
      headline: "No progress measured across a machine change.",
      body: machineChangeBody,
      sourceTitle: ProgressionAnalyzer.source.title,
      sourceLimit: limit(of: ProgressionAnalyzer.source)
    )
  }

  /// D31 is enforced inside `MuscleHistory`, which publishes no `EvidenceSource` for it. The id is
  /// the rule's own anchor, the title is the surface's name, and the limit is the exact sentence
  /// that surface shows, so the sheet cannot state the rule differently from the screen.
  private static var futureDated: Refusal {
    Refusal(
      id: "muscle-history.future-dated",
      headline: "No timing verdict for a session dated in the future.",
      body: futureDatedBody,
      sourceTitle: MuscleHistoryCopy.title,
      sourceLimit: MuscleHistoryCopy.futureDated(1)
    )
  }

  // MARK: - Working

  /// The muscles whose weekly target the engine can state today. Read through the public answer,
  /// never assumed, so the row describes the version it is running in.
  private static var evaluatedTargetCount: Int {
    Muscle.allCases.filter { VolumeAnalyzer.weeklyTarget(for: $0).value != nil }.count
  }

  /// An `EvidenceSource`'s stated limit, or the empty string when it declares none. Every row this
  /// sheet draws cites a source that states one; the copy test holds that true rather than letting
  /// a caption go silently blank.
  private static func limit(of source: EvidenceSource) -> String {
    source.validRange ?? ""
  }

  private static let weeklyTargetBody =
    "It shows what you did and where it is empty, and names no number to hit."

  private static let machineChangeBody =
    "Sessions on different machines are drawn as separate lines. A difference after a switch is a "
    + "difference between the machines, not a change in strength."

  private static let futureDatedBody =
    "It counts in lifetime totals, never in last trained or the weekly figures."
}
