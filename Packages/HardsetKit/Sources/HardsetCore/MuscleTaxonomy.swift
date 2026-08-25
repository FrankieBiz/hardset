import Foundation

// MARK: - The vocabulary

/// The permanent muscle vocabulary. 22 tokens.
///
/// Every raw value here reaches a CloudKit-synchronised TEXT column. **Adding a case later is
/// permitted and cheap. Renaming or removing one is permanently impossible** from the first build
/// that reaches a second device: SQLiteData forbids renaming columns forever and CloudKit's
/// production schema is additive-only, so a re-spelling becomes a data migration across every
/// user's device rather than a schema edit. That asymmetry is the single most important fact about
/// this file and the one a future contributor is least likely to infer from the code.
///
/// A token is admissible on exactly one of two grounds, and each entry below records which:
///
/// - **Ground A — dissociation.** A common exercise gives one sibling essentially nothing while
///   giving the other a lot, shown by a *hypertrophy outcome measurement* — not by activation.
///   Only `gastrocnemius`/`soleus` and `hipAbductors` qualify.
/// - **Ground B — disjoint loaded joint action.** Two tokens are loaded by joint actions in
///   different planes, such that resisting one applies essentially no resistance to the other.
///   This is an argument from the direction of the resistance, **not** from a trial. It is honest
///   as a *coverage* question ("does this program contain work resisting this action?") and is
///   never a dose-response claim. Ground B attributions may never carry `.high` certainty.
///
/// Deliberately NOT `Codable`. That is defence in depth only — `MuscleKey` is the type that
/// actually closes the throwing-decode path.
///
/// Declaration order is display order.
public enum Muscle: String, CaseIterable, Sendable, Hashable {
  case chest
  case frontDelts, sideDelts, rearDelts, rotatorCuff
  case lats, upperBack, traps, lowerBack
  case biceps, triceps, forearms
  case abs, obliques
  case neck
  case quadriceps, hamstrings, glutes, adductors, hipAbductors, gastrocnemius, soleus

  /// String Catalog key, resolved by the UI layer. Never a title-cased fallback from the raw
  /// value: a generated display name looks authored and is not.
  public var displayNameKey: String { "muscle.\(rawValue)" }

  /// The tissue this slot owns, written down so two authors cannot split the same tissue two
  /// different ways. Total switch, no `default` — an unstated boundary is where authoring drift
  /// starts, and the `traps`/`upperBack` line below is the one most likely to be got wrong.
  public var tissueDefinition: String {
    switch self {
    case .chest:
      "Pectoralis major, all regions. Humeral horizontal ADDUCTION and shoulder FLEXION."
    case .frontDelts: "Anterior deltoid. Shoulder FLEXION."
    case .sideDelts: "Lateral deltoid. Shoulder ABDUCTION in the frontal plane."
    case .rearDelts: "Posterior deltoid. Humeral horizontal ABDUCTION and EXTENSION."
    case .rotatorCuff:
      "Supraspinatus, infraspinatus, subscapularis, teres minor as one unit. Humeral "
        + "EXTERNAL and INTERNAL ROTATION. One token, not four: cuff hypertrophy evidence in "
        + "healthy people is a BFR case series and a preliminary isokinetic study."
    case .lats: "Latissimus dorsi. Humeral shoulder EXTENSION and ADDUCTION."
    case .upperBack:
      "Rhomboids, MIDDLE and LOWER trapezius, teres major. The tissue producing scapular "
        + "RETRACTION and DEPRESSION. Note: the lower trapezius lives here, not in `traps`. "
        + "That is counterintuitive from the name and is exactly where two authors diverge."
    case .traps: "Upper trapezius ONLY. The tissue producing scapular ELEVATION."
    case .lowerBack: "Lumbar and thoracic erector spinae. Spinal EXTENSION."
    case .biceps:
      "Biceps brachii and brachialis. Elbow FLEXION. Head and brachialis splits rejected: "
        + "no dissociating hypertrophy trial."
    case .triceps:
      "Triceps brachii, all three heads. Elbow EXTENSION. The long-head split is rejected — "
        + "overhead training grew the long head more, but neutral still grew it substantially, "
        + "which is a magnitude difference, not a dissociation."
    case .forearms:
      "Wrist and finger flexors and extensors. Wrist FLEXION/EXTENSION and radioulnar "
        + "ROTATION. Grip is NEVER credited here — a held bar is a stabiliser, not a trained "
        + "muscle. See MuscleRole.stabilizer."
    case .abs: "Rectus abdominis. Trunk FLEXION."
    case .obliques: "External and internal obliques. Trunk ROTATION and LATERAL FLEXION."
    case .neck:
      "Cervical flexors and extensors. Neck FLEXION and EXTENSION. Exists so neck work is not "
        + "mis-filed onto `traps`, which is where both predecessor apps put it."
    case .quadriceps:
      "The whole quadriceps femoris, all four heads. Knee EXTENSION. Rectus femoris is NOT "
        + "split out: the trials offered as support were an underpowered null and a magnitude "
        + "difference, not a dissociation."
    case .hamstrings:
      "Biceps femoris, semitendinosus, semimembranosus. Knee FLEXION and hip EXTENSION. Head "
        + "split rejected: magnitude differences only."
    case .glutes: "Gluteus maximus. Hip EXTENSION."
    case .adductors:
      "Adductor group including adductor magnus. Hip ADDUCTION and, in flexed positions, hip "
        + "EXTENSION."
    case .hipAbductors:
      "Gluteus medius and minimus as ONE unit — the granularity the only trial measuring them "
        + "used. Splitting them would claim resolution the measurement did not have. Hip "
        + "ABDUCTION."
    case .gastrocnemius: "Both gastrocnemius heads. Plantarflexion with the knee EXTENDED."
    case .soleus: "Soleus. Plantarflexion at any knee angle."
    }
  }

  /// Where this token's number may be interpreted, and where it may only be counted.
  public var tier: MuscleEvidenceTier {
    switch self {
    case .chest, .frontDelts, .biceps, .triceps, .quadriceps, .hamstrings: .modelled
    default: .counted
    }
  }

  /// Which admission ground justifies the token existing at all. Surfaced to the user, because a
  /// Ground B split is a reasonable thing to disagree with and hiding that is the dishonest move.
  public var admissionGround: MuscleAdmissionGround {
    switch self {
    case .gastrocnemius, .soleus, .hipAbductors: .dissociation
    default: .disjointJointAction
    }
  }

  /// Rendering detail only, NOT a taxonomy gate. wger ships highlight art for serratus anterior
  /// and brachialis, so "has a distinct silhouette region" was never a real requirement and must
  /// not be cited as a reason for the vocabulary's resolution.
  public var isDrawable: Bool {
    switch self {
    case .rotatorCuff: false
    default: true
    }
  }

  /// Written out rather than searched, so the compiler checks exhaustiveness.
  public var group: MuscleGroup {
    switch self {
    case .chest: .chest
    case .frontDelts, .sideDelts, .rearDelts, .rotatorCuff: .shoulders
    case .lats, .upperBack, .traps, .lowerBack: .back
    case .biceps, .triceps, .forearms: .arms
    case .abs, .obliques: .core
    case .neck: .neck
    case .quadriceps, .hamstrings, .adductors, .hipAbductors, .gastrocnemius, .soleus: .legs
    case .glutes: .glutes
    }
  }
}

/// Where a token's number may be interpreted.
public enum MuscleEvidenceTier: String, Sendable, Hashable, CaseIterable {
  /// The token's meaning matches, one-to-one, a site measured as a hypertrophy outcome in the
  /// 67-study corpus behind the fractional-counting scheme. A weekly fractional count may be
  /// placed on that published dose-response relationship — at `.moderate` and never higher.
  case modelled
  /// A real token with real attribution, credited at full fractional weight and shown as a number
  /// and as present/absent. Never placed on a dose-response curve and never compared to a target.
  case counted
}

/// Why a token is allowed to exist.
public enum MuscleAdmissionGround: String, Sendable, Hashable, CaseIterable {
  /// A hypertrophy outcome measurement shows one sibling gets essentially nothing.
  case dissociation
  /// The loaded joint actions are in different planes. An argument from resistance direction, not
  /// from a trial. Honest as coverage, never as dose.
  case disjointJointAction

  /// The sentence the UI must show when asked why this split exists. The Ground B wording is
  /// deliberately unflattering to itself.
  public var userFacingBasis: String {
    switch self {
    case .dissociation:
      "A training study measured one of these muscles growing while the other barely changed."
    case .disjointJointAction:
      "Justified by the direction of the resistance, not by a study measuring these muscles "
        + "separately."
    }
  }
}

/// Derived in code and NEVER stored in any column.
///
/// Storing a group would create a second source of truth that can disagree with the first, and
/// would freeze the group set forever. The moment any code path persists a group key — a CSV
/// header, a widget configuration, a notification payload — that freedom is silently gone.
/// Exports must namespace, because `Muscle` and `MuscleGroup` collide on `glutes` and `neck`.
public enum MuscleGroup: String, CaseIterable, Sendable, Hashable {
  case chest, shoulders, back, arms, core, neck, legs, glutes

  /// The one canonical edge of the hierarchy.
  public var members: [Muscle] {
    switch self {
    case .chest: [.chest]
    case .shoulders: [.frontDelts, .sideDelts, .rearDelts, .rotatorCuff]
    case .back: [.lats, .upperBack, .traps, .lowerBack]
    case .arms: [.biceps, .triceps, .forearms]
    case .core: [.abs, .obliques]
    case .neck: [.neck]
    case .legs: [.quadriceps, .hamstrings, .adductors, .hipAbductors, .gastrocnemius, .soleus]
    case .glutes: [.glutes]
    }
  }

  public var displayNameKey: String { "muscleGroup.\(rawValue)" }

  /// Namespaced key for export, so a reader can never confuse `muscle.glutes` with
  /// `group.glutes`.
  public var exportKey: String { "group.\(rawValue)" }
}

// MARK: - The storage boundary

/// The ONLY type that crosses the storage boundary.
///
/// A struct, not an enum. Swift has no per-case access control, so an enum with
/// `case known(Muscle) / case unrecognised(String)` could not prevent `.unrecognised("chest")`
/// being constructed as a SECOND bucket for a known muscle: a distinct `Hashable` value returning
/// an identical `storedValue`, so a `[MuscleKey: Double]` map would split one muscle's volume in
/// two while the grand total still reconciled. With a private stored `String` and a single public
/// initialiser, one token can only ever produce one key.
public struct MuscleKey: Hashable, Sendable {
  /// Reserved permanently. Already the column DEFAULT and the Swift property default, so it is a
  /// live value whether or not anyone decides it is: any insert omitting the column — including a
  /// peer record arriving without the field — produces it. No `Muscle` case may ever take it.
  public static let notAttributedRawValue = "unknown"

  private let raw: String

  /// Total, non-failable, non-throwing, and **non-normalising**. Non-normalising is the point:
  /// `storedValue` must be byte-identical to what came out of the column. No trimming, no case
  /// folding, no Unicode normalisation — otherwise a round trip rewrites a peer's data.
  public init(stored raw: String) { self.raw = raw }

  public init(_ muscle: Muscle) { self.raw = muscle.rawValue }

  public var storedValue: String { raw }
  public var muscle: Muscle? { Muscle(rawValue: raw) }
  public var isAttributed: Bool { muscle != nil }
  public var isReservedSentinel: Bool { raw == Self.notAttributedRawValue }

  /// Never the raw string. "Not attributed" and "Not recognised" are different facts about the
  /// same row — "nobody has attributed this yet" versus "a newer version of the app knows
  /// something this one does not" — and deserve different copy, with identical non-counting and
  /// non-grouping treatment.
  public var displayNameKey: String {
    if let muscle { return muscle.displayNameKey }
    return isReservedSentinel ? "muscle.notAttributed" : "muscle.notRecognised"
  }

  /// Unknown tokens belong to no group. They are never folded into a bucket that would make them
  /// look counted.
  public var group: MuscleGroup? { muscle?.group }
}

/// How a muscle participates in a movement.
///
/// Deliberately NOT `Codable`: decoded via `MuscleRole(rawValue:) ?? .indirect` inside the
/// tolerant decoder, which records the fallback rather than hiding it.
public enum MuscleRole: String, Sendable, Hashable, CaseIterable {
  /// A prime mover. Credited a full set.
  case direct
  /// A synergist working through a meaningful range. Credited half a set.
  case indirect
  /// Involved, but not trained through a range — isometric bracing, a held grip, a fixed torso.
  /// Credited nothing. Recorded rather than dropped so authors have somewhere to put involvement
  /// that is real but is not growth stimulus.
  case stabilizer

  /// Ordering used to resolve a muscle appearing twice in one entry: keep the highest weight.
  var precedence: Int {
    switch self {
    case .direct: 2
    case .indirect: 1
    case .stabilizer: 0
    }
  }
}

/// The closed set of things that may justify an attribution in CURATED content.
///
/// There is deliberately **no `emg` case**. An attribution justifiable only by a surface-EMG
/// amplitude study is structurally impossible to express here, not merely against policy.
public enum AttributionSourceID: String, Sendable, Hashable, CaseIterable {
  /// A controlled trial measuring that muscle's growth from that movement.
  case trial
  /// Membership of the direct/indirect classification in the fractional-counting corpus.
  case pellandTable1 = "pelland-table-1"
  /// Textbook anatomy — the joint action the load resists. Caps at `.moderate`.
  case anatomy
  /// A stated Hardset convention with no trial behind it. Caps at `.moderate`.
  case convention
  /// Authored by the user on their own exercise.
  case user
}

/// One muscle's participation in one movement.
public struct MuscleContribution: Hashable, Sendable {
  public let key: MuscleKey
  public let role: MuscleRole
  public let certainty: Certainty
  /// A `String`, not `AttributionSourceID`: a v2 source id must survive a v1 read unchanged. The
  /// allowlist is enforced against curated content by a test, not at decode time.
  public let sourceID: String
  public let citation: String?

  public init(
    key: MuscleKey,
    role: MuscleRole,
    certainty: Certainty,
    sourceID: String,
    citation: String? = nil
  ) {
    self.key = key
    self.role = role
    self.certainty = certainty
    self.sourceID = sourceID
    self.citation = citation
  }

  public init(
    _ muscle: Muscle,
    role: MuscleRole,
    certainty: Certainty,
    source: AttributionSourceID,
    citation: String? = nil
  ) {
    self.init(
      key: MuscleKey(muscle), role: role, certainty: certainty,
      sourceID: source.rawValue, citation: citation
    )
  }

  /// Sets credited to this muscle per completed working set.
  public var setWeight: Double { SetCounting.weight(role) }

  /// The stored `sourceID` for anything the lifter asserted about their own movement.
  ///
  /// Deliberately **not** `AttributionSourceID.user.rawValue`. That enum is the closed allowlist of
  /// what may justify an attribution in *curated* content, enforced by a test over the catalogue;
  /// this is a value written into user rows, and the two have been spelled differently since the
  /// first user row was written. Unifying them would mean rewriting stored JSON in rows already on
  /// devices, which buys nothing. This constant exists so there is one definition rather than one
  /// per writer.
  public static let userSourceID = "user-declared"
}

// MARK: - Counting

/// Fractional set counting.
///
/// Stores the ROLE and derives the fraction. A number baked into 240 authored rows becomes a stale
/// copy of a counting convention the moment the convention is revisited, with no way to tell an
/// intentional per-exercise weight from a stale default.
public enum SetCounting {
  public static func weight(_ role: MuscleRole) -> Double {
    switch role {
    case .direct: 1.0
    case .indirect: 0.5
    case .stabilizer: 0.0
    }
  }

  /// Why a drop set adds no sets to the count.
  ///
  /// Stated as plainly as the 0.5 weight is, and for the same reason: it is **an adopted
  /// convention, not an inherited finding**, and nothing in the app may claim otherwise.
  ///
  /// There is no established convention for mapping a drop onto a set count. The dose-response
  /// work the counting scheme comes from fitted studies of conventionally performed sets, and the
  /// drop-set literature describes the technique as one set carried past failure at reducing
  /// loads rather than as several sets. Counting each drop as another set would silently inflate
  /// a week — three sets dropped twice would report nine — so Hardset counts the chain once, as
  /// the set it continues. That is the reading that cannot manufacture volume, which is the only
  /// ground being claimed for it.
  ///
  /// It is a counting choice and not a claim about training: nothing here says a drop is worth
  /// less than a set, only that the app will not report it as one. Tonnage is unaffected, because
  /// tonnage is arithmetic over what was lifted rather than a convention — every drop's load and
  /// reps count in full.
  public static let dropSetConvention = """
    A drop set is counted as part of the set it continues, not as an extra set. No convention for \
    counting drops is established, and the fractional scheme below was fitted to studies of \
    conventionally performed sets; counting each drop separately would report three sets dropped \
    twice as nine. Hardset counts the chain once. This is a counting choice and not a judgement \
    about the technique. Every drop's load and reps still count in full toward tonnage.
    """

  /// One `EvidenceSource`, so the App Review 1.4.1 disclosure is generated by the same code that
  /// does the counting and cannot drift from it.
  ///
  /// Read the methodology text carefully before changing it. The 0.5 weight is an **adopted
  /// convention, not an inherited finding**: Pelland et al. fixed it a priori and compared three
  /// fixed schemes rather than estimating a weight from data, and their own discussion calls it
  /// "an assumption" and "a heuristic". Claiming entitlement to the number because it was "fitted
  /// under that labelling" is false and must not appear anywhere.
  public static let source = EvidenceSource(
    id: "hardset-fractional-credit-v1",
    title: "Fractional set counting",
    methodology: """
      A completed working set credits 1.0 set to each muscle labelled direct on the movement, \
      0.5 to each labelled indirect, and 0 to each labelled stabilising. The 1.0/0.5 split \
      follows the fractional scheme that best fitted 67 training studies in Pelland et al. \
      (2025). Those authors fixed the 0.5 weight in advance rather than estimating it from the \
      data, and describe it as an assumption and a heuristic; Hardset adopts it as a stated \
      convention. The 0 weight for stabilising and gripping muscles is Hardset's own convention \
      and is not part of the scheme that was tested. \

      \(SetCounting.dropSetConvention)
      """,
    citation: """
      Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. Sports Med 2025. \
      DOI 10.1007/s40279-025-02344-w, PMID 41343037.
      """,
    validRange: """
      The scheme was compared against studies measuring eight sites: quadriceps and knee \
      extensors, rectus femoris, hamstrings and posterior thigh, pectoralis major, anterior \
      deltoid, trapezius, triceps brachii and elbow extensors, biceps brachii and elbow flexors. \
      Applying it to any other muscle is an extrapolation. Few studies examined more than about \
      25 fractional weekly sets, so counts above that fall outside the fitted range. No isometric \
      or stabilising contribution appears anywhere in the classification.
      """
  )

  /// Ceiling on the certainty of any weekly per-muscle total.
  ///
  /// Never `.high`: that would require a trial measuring this muscle's growth from these
  /// movements, and an aggregate over many movements cannot qualify. `.moderate` at best for a
  /// `modelled` muscle, `.low` for a `counted` one, and `.low` above roughly 25 fractional sets
  /// because few studies explored that range. The ~25 cut point is Hardset's convention.
  ///
  /// This was dead for its whole life — declared `public`, called only by its own tests — while
  /// `VolumeAnalyzer.doseResponse` computed the identical rule inline. Two copies of one
  /// convention is how the cut point ends up meaning 25 in one place and something else in the
  /// other, so `doseResponse` now calls this and the threshold is read from the single constant
  /// that documents it rather than retyped as a literal.
  public static func certaintyCeiling(for muscle: Muscle, fractionalSets: Double) -> Certainty {
    if fractionalSets > VolumeAnalyzer.studiedRangeCeiling { return .low }
    return muscle.tier == .modelled ? .moderate : .low
  }
}

// MARK: - Decoding

/// The result of reading an attribution column, including what could not be read.
///
/// The tolerant decoder is only safe **because** it reports its failures. A caller that discards
/// `unreadableEntryCount` makes it strictly worse than the strict decoder it replaced, because it
/// hides failures instead of throwing them.
public struct DecodedAttribution: Hashable, Sendable {
  public let contributions: [MuscleContribution]
  /// Elements that could not be read at all.
  public let unreadableEntryCount: Int
  /// Fields that were present but unparseable and fell back to a default.
  public let degradedFieldCount: Int

  public init(
    contributions: [MuscleContribution],
    unreadableEntryCount: Int = 0,
    degradedFieldCount: Int = 0
  ) {
    self.contributions = contributions
    self.unreadableEntryCount = unreadableEntryCount
    self.degradedFieldCount = degradedFieldCount
  }

  public var isClean: Bool { unreadableEntryCount == 0 && degradedFieldCount == 0 }
}

/// The one conversion between the frozen TEXT columns and the vocabulary.
///
/// The column is named `secondaryMusclesJSON`, but it holds the **complete** contribution list,
/// including the display primary at `role: "direct"`. The name is frozen; the grammar inside it is
/// not. This is what makes a two-prime-mover movement (a deadlift is hamstrings *and* glutes)
/// expressible without ever adding a column.
public enum MuscleColumn {
  public static func decodePrimary(_ stored: String) -> MuscleKey { MuscleKey(stored: stored) }

  /// Parsed with `JSONSerialization`, not `JSONDecoder`, because element-wise salvage requires it:
  /// a `[String]` decode throws on the whole array for one non-string element.
  public static func decodeContributions(_ storedJSON: String) -> DecodedAttribution {
    guard
      let data = storedJSON.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data)
    else {
      // Never a silent `?? []`.
      return DecodedAttribution(contributions: [], unreadableEntryCount: 1)
    }
    guard let elements = root as? [Any] else {
      return DecodedAttribution(contributions: [], unreadableEntryCount: 1)
    }

    var contributions: [MuscleContribution] = []
    var unreadable = 0
    var degraded = 0

    for element in elements {
      if let legacy = element as? String {
        // The bare-array form user-created rows and CSV imports produce. Accepted on read,
        // never written.
        contributions.append(
          MuscleContribution(
            key: MuscleKey(stored: legacy), role: .indirect, certainty: .low,
            sourceID: "legacy-bare-array", citation: nil
          )
        )
        continue
      }
      guard let object = element as? [String: Any],
        let muscleValue = object["muscle"] as? String
      else {
        unreadable += 1
        continue
      }

      let role: MuscleRole
      if let rawRole = object["role"] as? String {
        if let parsed = MuscleRole(rawValue: rawRole) {
          role = parsed
        } else {
          role = .indirect
          degraded += 1
        }
      } else {
        role = .indirect
      }

      let certainty: Certainty
      if let rawCertainty = object["certainty"] as? String {
        if let parsed = Certainty(rawValue: rawCertainty) {
          certainty = parsed
        } else {
          certainty = .low
          degraded += 1
        }
      } else {
        certainty = .low
        degraded += 1
      }

      // An unknown source id is KEPT, not rejected: a v2 source must survive a v1 read.
      let sourceID = (object["source"] as? String) ?? "unspecified"

      contributions.append(
        MuscleContribution(
          key: MuscleKey(stored: muscleValue), role: role, certainty: certainty,
          sourceID: sourceID, citation: object["citation"] as? String
        )
      )
    }

    // One muscle may not occupy two buckets. Keep the highest-weight role.
    var deduped: [String: MuscleContribution] = [:]
    for contribution in contributions {
      let key = contribution.key.storedValue
      if let existing = deduped[key] {
        degraded += 1
        if contribution.role.precedence > existing.role.precedence { deduped[key] = contribution }
      } else {
        deduped[key] = contribution
      }
    }

    return DecodedAttribution(
      contributions: ordered(Array(deduped.values)),
      unreadableEntryCount: unreadable,
      degradedFieldCount: degraded
    )
  }

  /// Always emits the object grammar, ordered by `Muscle.allCases`. Never the bare-array form.
  public static func encode(_ contributions: [MuscleContribution]) -> String {
    let objects: [[String: String]] = ordered(contributions).map { contribution in
      var object = [
        "muscle": contribution.key.storedValue,
        "role": contribution.role.rawValue,
        "certainty": contribution.certainty.rawValue,
        "source": contribution.sourceID,
      ]
      if let citation = contribution.citation { object["citation"] = citation }
      return object
    }
    guard
      let data = try? JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys]),
      let json = String(data: data, encoding: .utf8)
    else { return "[]" }
    return json
  }

  /// Declaration order for known muscles; unknown tokens last, stably by stored value.
  static func ordered(_ contributions: [MuscleContribution]) -> [MuscleContribution] {
    let index = Dictionary(
      uniqueKeysWithValues: Muscle.allCases.enumerated().map { ($1, $0) }
    )
    return contributions.sorted { lhs, rhs in
      let l = lhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
      let r = rhs.key.muscle.map { index[$0] ?? Int.max } ?? Int.max
      if l != r { return l < r }
      return lhs.key.storedValue < rhs.key.storedValue
    }
  }
}

// MARK: - The shipped set

/// Append-only. Every entry is permanent.
///
/// Renaming or removing one silently orphans every peer record and user-created row still
/// carrying the old spelling — visible only as volume that quietly stopped counting. Nothing in
/// CloudKit or SQLiteData detects this.
public let shippedMuscleKeys: Set<String> = [
  "chest",
  "frontDelts", "sideDelts", "rearDelts", "rotatorCuff",
  "lats", "upperBack", "traps", "lowerBack",
  "biceps", "triceps", "forearms",
  "abs", "obliques", "neck",
  "quadriceps", "hamstrings", "glutes", "adductors", "hipAbductors",
  "gastrocnemius", "soleus",
]
