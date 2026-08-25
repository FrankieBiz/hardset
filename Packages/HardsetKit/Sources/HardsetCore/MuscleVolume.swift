import Foundation

/// One completed set, reduced to what volume counting needs.
///
/// Deliberately not `LoggedSet`: the analyser must not be able to see a load, a rep count or a
/// date, because none of those belong in a set count and a type that cannot see them cannot
/// accidentally use them.
public struct CountableSet: Hashable, Sendable {
  public let exerciseID: ExerciseID
  public let kind: SetKind

  public var isWarmup: Bool { kind == .warmup }

  public init(exerciseID: ExerciseID, kind: SetKind) {
    self.exerciseID = exerciseID
    self.kind = kind
  }

  public init(exerciseID: ExerciseID, isWarmup: Bool) {
    self.init(exerciseID: exerciseID, kind: isWarmup ? .warmup : .working)
  }
}

/// Exercise attribution, looked up once.
///
/// Returns `nil` — not an empty array — for an exercise nobody has attributed. Those are different
/// facts: "this movement trains nothing" versus "we do not know what this movement trains", and
/// collapsing them is how a volume report starts quietly under-counting.
public struct AttributionIndex: Sendable {
  private let byExercise: [ExerciseID: [MuscleContribution]]

  public init(_ byExercise: [ExerciseID: [MuscleContribution]]) {
    self.byExercise = byExercise
  }

  public init(entries: [CatalogEntry]) {
    var map: [ExerciseID: [MuscleContribution]] = [:]
    for entry in entries where !entry.isUnattributed {
      map[entry.id] = entry.contributions
    }
    self.byExercise = map
  }

  public func contributions(for exerciseID: ExerciseID) -> [MuscleContribution]? {
    byExercise[exerciseID]
  }

  public var count: Int { byExercise.count }
}

/// Weekly fractional set volume, per muscle, with its own coverage attached.
///
/// The coverage field is the point. The ancestor app's scorers returned a neutral 70 when they
/// recognised nothing, so three unknown lifts composed into a confident "78/100 — Dialed in".
/// Here, sets whose exercise has no attribution are counted separately and make every per-muscle
/// figure an explicit lower bound. A number and the reason to distrust it travel together.
public struct MuscleVolumeReport: Hashable, Sendable {
  /// Fractional sets per muscle: 1.0 per direct set, 0.5 per indirect, 0 per stabilising.
  /// Muscles with no credit are absent rather than present-at-zero — those are different facts.
  public let fractionalSets: [MuscleKey: Double]
  /// Completed working sets counted. Warm-ups are excluded and never appear here.
  public let hardSets: Int
  /// Working sets whose exercise had no attribution. These contribute to `hardSets` and to
  /// nothing else.
  public let unattributedHardSets: Int
  /// Sets that credited any muscle in a group, counted ONCE each.
  ///
  /// Deliberately not a sum of the group's members. Summing fractional sets across a group
  /// double-counts every compound movement — a bench press would add to chest, front delts and
  /// triceps and then be counted three times in "upper body". This is a count of sets, and it is
  /// the only group-level number the app may show.
  public let setsTouchingGroup: [MuscleGroup: Int]

  /// Share of counted sets that could be attributed. 1.0 when everything was known.
  public var coverage: Double {
    guard hardSets > 0 else { return 1 }
    return Double(hardSets - unattributedHardSets) / Double(hardSets)
  }

  /// True when at least one set could not be attributed, so every per-muscle figure is a floor
  /// rather than a total. The UI must render "≥ 8 sets", not "8 sets".
  public var isLowerBound: Bool { unattributedHardSets > 0 }

  /// Fractional sets for one muscle. Absent means zero credited — which is a real answer, and the
  /// one a coverage gap is made of.
  public func sets(for muscle: Muscle) -> Double {
    fractionalSets[MuscleKey(muscle)] ?? 0
  }

  /// Muscles credited nothing at all. The coverage gap, and the most useful thing in the report.
  ///
  /// Excludes the tokens with no direct movement in the catalogue yet — reporting "you have no
  /// neck work" when the app ships no neck exercise is blaming the user for a content gap.
  ///
  /// **"Credited nothing" is not the same claim as "not trained."** When `isLowerBound` is true some
  /// sets could not be attributed, so a muscle in this list may well have been trained by one of
  /// them. Any caller presenting this as a gap must say so — and in the degenerate case where
  /// nothing at all was attributed, this returns every muscle, which read as "you trained nothing"
  /// when the truth was "the app could not tell what you trained".
  public func untrainedMuscles(excluding excluded: Set<Muscle>) -> [Muscle] {
    Muscle.allCases.filter { !excluded.contains($0) && sets(for: $0) == 0 }
  }

  public init(
    fractionalSets: [MuscleKey: Double],
    hardSets: Int,
    unattributedHardSets: Int,
    setsTouchingGroup: [MuscleGroup: Int]
  ) {
    self.fractionalSets = fractionalSets
    self.hardSets = hardSets
    self.unattributedHardSets = unattributedHardSets
    self.setsTouchingGroup = setsTouchingGroup
  }
}

/// Counts fractional sets. Takes sets and attribution, and nothing else.
///
/// The function is structurally unable to see a target or a band, so no threshold can leak from
/// warnings into the arithmetic. That separation is the bug the ancestor documented in its own
/// source: deriving an "optional muscle" flag from `mev == 0` made every per-session band look
/// optional and silently emptied session volume scoring.
public enum VolumeAnalyzer {
  public static func report(
    sets: [CountableSet],
    attribution: AttributionIndex
  ) -> MuscleVolumeReport {
    var fractional: [MuscleKey: Double] = [:]
    var touching: [MuscleGroup: Set<Int>] = [:]
    var hardSets = 0
    var unattributed = 0

    for (index, set) in sets.enumerated() {
      // Warm-ups are real work and are not the prescription. They count nowhere here.
      //
      // Nor do drops, and for a different reason: a drop is counted as part of the set it
      // continues rather than as another set. See `SetCounting.dropSetConvention` — it is an
      // adopted convention, not a finding, and the app says so where App Review reads it.
      guard set.kind.countsAsWorkingSet else { continue }
      hardSets += 1

      guard let contributions = attribution.contributions(for: set.exerciseID) else {
        unattributed += 1
        continue
      }

      for contribution in contributions {
        let weight = contribution.setWeight
        guard weight > 0 else { continue }
        fractional[contribution.key, default: 0] += weight
        // Counted once per set per group, however many of the group's muscles it credits.
        if let group = contribution.key.group {
          touching[group, default: []].insert(index)
        }
      }
    }

    return MuscleVolumeReport(
      fractionalSets: fractional,
      hardSets: hardSets,
      unattributedHardSets: unattributed,
      setsTouchingGroup: touching.mapValues(\.count)
    )
  }
}

/// Where a weekly fractional count sits on the published dose-response, when it may sit anywhere
/// at all.
public struct DoseResponsePosition: Hashable, Sendable {
  public let fractionalSets: Double
  /// The paper's own caution boundary. Above it the credible intervals widen enough that the
  /// best-fit model is compatible with a plateau or an inverted-U, so no per-set return may be
  /// asserted.
  public let isBeyondStudiedRange: Bool

  public init(fractionalSets: Double, isBeyondStudiedRange: Bool) {
    self.fractionalSets = fractionalSets
    self.isBeyondStudiedRange = isBeyondStudiedRange
  }
}

extension VolumeAnalyzer {
  /// Roughly where the studies stop. Hardset's cut point, not the paper's: it reports that "few
  /// studies have explored ~25+ fractional weekly sets" without naming a threshold.
  public static let studiedRangeCeiling: Double = 25

  public static let doseResponseSource = EvidenceSource(
    id: "hardset-dose-response-v1",
    title: "Volume dose-response",
    methodology: """
      Weekly fractional sets per muscle are placed against the dose-response relationship fitted \
      across 67 training studies. The best-fit form showed diminishing returns rather than an \
      inverted-U, but the credible intervals widen with volume and few studies examined more than \
      about 25 fractional weekly sets, so above that the app reports the count and declines to \
      say what an additional set buys.
      """,
    citation: """
      Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. Sports Med 2025. \
      DOI 10.1007/s40279-025-02344-w, PMID 41343037.
      """,
    validRange: """
      Applies only to the eight sites measured in that corpus. For every other muscle this is \
      unevaluated, not approximate. The ~25-set ceiling is Hardset's chosen cut point, not a \
      figure the paper states.
      """
  )

  /// A muscle's position on the dose-response curve, or the honest absence of one.
  ///
  /// `.unevaluated` for every `counted` muscle — that is most of the vocabulary — because the
  /// relationship was never fitted for them and an approximation would be indistinguishable from
  /// a measurement.
  public static func doseResponse(
    fractionalSets: Double,
    for muscle: Muscle
  ) -> Claim<DoseResponsePosition> {
    guard muscle.tier == .modelled else {
      return .unevaluated(source: doseResponseSource)
    }
    let beyond = fractionalSets > studiedRangeCeiling
    return Claim(
      DoseResponsePosition(fractionalSets: fractionalSets, isBeyondStudiedRange: beyond),
      // `SetCounting.certaintyCeiling` states this rule, and stating it twice is how the two
      // copies drift. Identical by construction for a modelled muscle, which is the only kind
      // that reaches this line -- the guard above returned for the rest.
      certainty: SetCounting.certaintyCeiling(for: muscle, fractionalSets: fractionalSets),
      source: doseResponseSource
    )
  }

  /// Whether a weekly set TARGET exists for a muscle.
  ///
  /// v1 returns `.unevaluated` for every muscle, and that is the finding rather than a placeholder.
  /// No per-muscle weekly set target is published for any muscle: the corpus gives a dose-response
  /// relationship for eight sites, not targets; the ancestor app's bands were practitioner numbers
  /// carrying no citation; and the ~4-fractional-set figure often quoted as a minimum is the volume
  /// at which modelled gain first exceeds the smallest detectable effect size, which is a
  /// detectability artefact and not a biological floor.
  ///
  /// It exists as a function so that any future warning code can only iterate evaluated targets,
  /// which makes "warn without a target" unrepresentable rather than merely discouraged.
  public static func weeklyTarget(for muscle: Muscle) -> Claim<ClosedRange<Double>> {
    .unevaluated(source: targetSource)
  }

  public static let targetSource = EvidenceSource(
    id: "hardset-weekly-target-v1",
    title: "Weekly set target",
    methodology: """
      Hardset does not publish a weekly set target for any muscle, because no such target is \
      established. What the literature supports is a dose-response relationship for eight \
      measured sites and a general finding that higher volumes tended to produce more growth. \
      The app therefore shows what you did and where it is empty, and does not tell you what \
      number you should have hit.
      """,
    citation: "Pelland JC et al. Sports Med 2025. DOI 10.1007/s40279-025-02344-w.",
    validRange: "No muscle has an evaluated target in this version."
  )
}
