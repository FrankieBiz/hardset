import Foundation
import Testing

@testable import HardsetCore

@Suite("The muscle vocabulary is permanent, so it is pinned")
struct MuscleVocabularyTests {
  /// The load-bearing test in this file. Every raw value here reaches a CloudKit-synced column;
  /// a rename after shipping orphans every peer record still carrying the old spelling, visible
  /// only as volume that quietly stopped counting. This test is what makes that a deliberate act
  /// rather than a refactor.
  @Test("Every raw value is pinned and none has changed")
  func rawValuesArePinned() {
    let expected: Set<String> = [
      "chest",
      "frontDelts", "sideDelts", "rearDelts", "rotatorCuff",
      "lats", "upperBack", "traps", "lowerBack",
      "biceps", "triceps", "forearms",
      "abs", "obliques", "neck",
      "quadriceps", "hamstrings", "glutes", "adductors", "hipAbductors",
      "gastrocnemius", "soleus",
    ]
    #expect(Set(Muscle.allCases.map(\.rawValue)) == expected)
    #expect(Muscle.allCases.count == 22)
    // The shipped set and the enum cannot drift apart.
    #expect(shippedMuscleKeys == expected)
  }

  /// Adding a token is permitted and cheap; this only asks that it be noticed.
  @Test("Adding a token requires updating the pinned set deliberately")
  func shippedSetCoversEveryCase() {
    for muscle in Muscle.allCases {
      #expect(shippedMuscleKeys.contains(muscle.rawValue), "\(muscle.rawValue) is not pinned")
    }
  }

  /// The sentinel is already live via the column DEFAULT, so a collision would be a real token
  /// that silently means "not attributed".
  @Test("No muscle raw value collides with the reserved sentinel")
  func noSentinelCollision() {
    #expect(!Muscle.allCases.map(\.rawValue).contains(MuscleKey.notAttributedRawValue))
  }

  @Test("Raw values are lowerCamelCase ASCII letters only")
  func rawValueShape() {
    for muscle in Muscle.allCases {
      let raw = muscle.rawValue
      let allLetters = raw.allSatisfy(\.isLetter)
      #expect(allLetters, "\(raw) contains a non-letter")
      #expect(raw.first?.isLowercase == true, "\(raw) does not start lowercase")
      #expect(raw == raw.trimmingCharacters(in: .whitespaces))
    }
  }

  @Test("Every token states the tissue it owns")
  func tissueDefinitionsExist() {
    for muscle in Muscle.allCases {
      #expect(!muscle.tissueDefinition.isEmpty, "\(muscle.rawValue) has no tissue definition")
    }
  }

  /// The boundary two authors would otherwise split two ways.
  @Test("The traps / upper back boundary is stated, and the lower trapezius is in upperBack")
  func trapsBoundaryIsExplicit() {
    #expect(Muscle.traps.tissueDefinition.contains("Upper trapezius ONLY"))
    #expect(Muscle.traps.tissueDefinition.contains("ELEVATION"))
    #expect(Muscle.upperBack.tissueDefinition.contains("LOWER trapezius"))
    #expect(Muscle.upperBack.tissueDefinition.contains("RETRACTION"))
  }

  @Test("Grip is excluded from forearms in the definition itself")
  func gripIsExcluded() {
    #expect(Muscle.forearms.tissueDefinition.contains("Grip is NEVER credited here"))
  }
}

@Suite("The rollup is one canonical edge")
struct MuscleGroupTests {
  /// Two definitions of the hierarchy that can disagree is the bug; this asserts they cannot.
  @Test("Muscle.group and MuscleGroup.members agree in both directions")
  func hierarchyAgrees() {
    for muscle in Muscle.allCases {
      #expect(
        muscle.group.members.contains(muscle),
        "\(muscle.rawValue) claims \(muscle.group.rawValue) but is not a member"
      )
    }
    for group in MuscleGroup.allCases {
      for member in group.members {
        #expect(member.group == group, "\(member.rawValue) is in \(group.rawValue) twice over")
      }
    }
  }

  @Test("Every muscle is in exactly one group, and every group is non-empty")
  func partitionIsExact() {
    let all = MuscleGroup.allCases.flatMap(\.members)
    #expect(all.count == Muscle.allCases.count)
    #expect(Set(all).count == Muscle.allCases.count)
    for group in MuscleGroup.allCases {
      #expect(!group.members.isEmpty, "\(group.rawValue) is empty")
    }
  }

  /// `Muscle` and `MuscleGroup` genuinely collide on these two raw values, so any export must
  /// namespace or a reader cannot tell a muscle from a group.
  @Test("The known raw-value collisions are namespaced on export")
  func collisionsAreNamespaced() {
    let muscleRaws = Set(Muscle.allCases.map(\.rawValue))
    let colliding = MuscleGroup.allCases.filter { muscleRaws.contains($0.rawValue) }
    // Three, not two. The spec said glutes and neck; `chest` is also both a muscle and a group,
    // which is precisely why an export must namespace rather than rely on a remembered list.
    #expect(Set(colliding.map(\.rawValue)) == ["chest", "glutes", "neck"])
    #expect(MuscleGroup.chest.exportKey != Muscle.chest.displayNameKey)
    #expect(MuscleGroup.glutes.exportKey == "group.glutes")
    #expect(Muscle.glutes.displayNameKey == "muscle.glutes")
    #expect(MuscleGroup.glutes.exportKey != Muscle.glutes.displayNameKey)
  }
}

@Suite("A muscle key cannot split one muscle into two buckets")
struct MuscleKeyTests {
  /// The reason `MuscleKey` is a struct and not an enum: an enum case could construct a second
  /// distinct Hashable value with an identical storedValue, splitting one muscle's volume in two
  /// while the grand total still reconciled.
  @Test("One token produces exactly one key")
  func oneTokenOneKey() {
    #expect(MuscleKey(.chest) == MuscleKey(stored: "chest"))
    #expect(MuscleKey(.chest).hashValue == MuscleKey(stored: "chest").hashValue)
    var counts: [MuscleKey: Int] = [:]
    counts[MuscleKey(.chest), default: 0] += 1
    counts[MuscleKey(stored: "chest"), default: 0] += 1
    #expect(counts.count == 1)
  }

  /// Non-normalising is deliberate: a round trip must not rewrite a peer's bytes.
  @Test("Storage is byte-preserved, never normalised")
  func bytesArePreserved() {
    for raw in [" chest", "Chest", "chest ", "CHEST", "che st"] {
      #expect(MuscleKey(stored: raw).storedValue == raw)
      // And none of those is silently accepted as the real thing.
      #expect(!MuscleKey(stored: raw).isAttributed, "\(raw) was accepted as attributed")
    }
  }

  @Test("An unknown token is not attributed, belongs to no group, and is distinguished from the sentinel")
  func unknownTokenBehaviour() {
    let future = MuscleKey(stored: "serratusAnterior")
    #expect(!future.isAttributed)
    #expect(future.muscle == nil)
    #expect(future.group == nil)
    #expect(!future.isReservedSentinel)
    #expect(future.displayNameKey == "muscle.notRecognised")

    let sentinel = MuscleKey(stored: MuscleKey.notAttributedRawValue)
    #expect(sentinel.isReservedSentinel)
    #expect(!sentinel.isAttributed)
    #expect(sentinel.group == nil)
    // Two different facts, two different strings.
    #expect(sentinel.displayNameKey == "muscle.notAttributed")
    #expect(sentinel.displayNameKey != future.displayNameKey)
  }

  @Test("A known token resolves to its display key and group")
  func knownTokenBehaviour() {
    let key = MuscleKey(.gastrocnemius)
    #expect(key.isAttributed)
    #expect(key.muscle == .gastrocnemius)
    #expect(key.group == .legs)
    #expect(key.displayNameKey == "muscle.gastrocnemius")
  }
}

@Suite("Fractional counting is a stated convention, not an inherited finding")
struct SetCountingTests {
  @Test("The weights are 1.0, 0.5 and 0")
  func weights() {
    #expect(SetCounting.weight(.direct) == 1.0)
    #expect(SetCounting.weight(.indirect) == 0.5)
    #expect(SetCounting.weight(.stabilizer) == 0.0)
  }

  /// Bracing and grip must contribute nothing. This is the seed's original defect, now
  /// unrepresentable: a stabiliser weighs zero.
  @Test("A stabiliser credits nothing")
  func stabiliserCreditsNothing() {
    let bracing = MuscleContribution(
      .abs, role: .stabilizer, certainty: .moderate, source: .anatomy
    )
    #expect(bracing.setWeight == 0)
  }

  /// Guideline 1.4.1 asks for methodology behind an accuracy claim. If this text stops saying the
  /// 0.5 is an assumption, the disclosure has started overclaiming.
  @Test("The disclosure states that the 0.5 weight is an assumption Hardset adopts")
  func disclosureIsHonest() {
    let methodology = SetCounting.source.methodology
    #expect(methodology.contains("fixed the 0.5 weight in advance"))
    #expect(methodology.contains("assumption"))
    #expect(methodology.contains("Hardset adopts it as a stated convention"))
    #expect(methodology.contains("Hardset's own convention"))
    #expect(SetCounting.source.citation?.contains("10.1007/s40279-025-02344-w") == true)
  }

  /// The eight measured sites bound where the scheme was tested. Applying it elsewhere is an
  /// extrapolation and the validRange has to say so.
  @Test("The valid range names the extrapolation and the ~25-set boundary")
  func validRangeIsStated() {
    let range = SetCounting.source.validRange ?? ""
    #expect(range.contains("extrapolation"))
    #expect(range.contains("25 fractional weekly sets"))
    #expect(range.contains("No isometric or stabilising contribution"))
  }

  /// A weekly total can never be .high: that needs a trial measuring this muscle's growth from
  /// these movements, and an aggregate over many movements cannot qualify.
  @Test("A weekly total is never high certainty")
  func neverHigh() {
    for muscle in Muscle.allCases {
      for sets in [0.0, 4.0, 10.0, 25.0, 40.0] {
        #expect(SetCounting.certaintyCeiling(for: muscle, fractionalSets: sets) != .high)
      }
    }
  }

  @Test("Modelled muscles cap at moderate, counted muscles at low")
  func tierCeilings() {
    #expect(SetCounting.certaintyCeiling(for: .quadriceps, fractionalSets: 10) == .moderate)
    #expect(SetCounting.certaintyCeiling(for: .glutes, fractionalSets: 10) == .low)
    // Above ~25 fractional sets even a modelled muscle drops: few studies explored that range.
    #expect(SetCounting.certaintyCeiling(for: .quadriceps, fractionalSets: 26) == .low)
  }

  @Test("Exactly six tokens are modelled, and they are the measured sites")
  func modelledTier() {
    let modelled = Muscle.allCases.filter { $0.tier == .modelled }
    #expect(Set(modelled) == [.chest, .frontDelts, .biceps, .triceps, .quadriceps, .hamstrings])
  }

  /// An attribution justifiable only by surface EMG must be impossible to express, not merely
  /// discouraged.
  @Test("There is no EMG source id")
  func noEMGSource() {
    let mentionsEMG = AttributionSourceID.allCases
      .map(\.rawValue)
      .contains { $0.lowercased().contains("emg") }
    #expect(!mentionsEMG)
  }

  /// Only the two Ground A splits may claim a trial dissociated them.
  @Test("Only the dissociation-grounded tokens claim outcome evidence")
  func admissionGrounds() {
    let dissociation = Muscle.allCases.filter { $0.admissionGround == .dissociation }
    #expect(Set(dissociation) == [.gastrocnemius, .soleus, .hipAbductors])
    // And Ground B says out loud that it is not a trial.
    #expect(
      MuscleAdmissionGround.disjointJointAction.userFacingBasis
        .contains("not by a study measuring these muscles separately")
    )
  }
}

@Suite("The attribution column decodes tolerantly and admits what it could not read")
struct MuscleColumnTests {
  private func contribution(
    _ muscle: Muscle, _ role: MuscleRole, _ certainty: Certainty = .moderate
  ) -> MuscleContribution {
    MuscleContribution(muscle, role: role, certainty: certainty, source: .anatomy)
  }

  @Test("A round trip preserves everything")
  func roundTrip() {
    let original = [
      contribution(.quadriceps, .direct),
      contribution(.glutes, .direct),
      contribution(.adductors, .indirect),
      contribution(.abs, .stabilizer),
    ]
    let decoded = MuscleColumn.decodeContributions(MuscleColumn.encode(original))
    #expect(decoded.isClean)
    #expect(decoded.contributions.count == 4)
    // Order is declaration order, NOT insertion order — `abs` precedes `quadriceps` in the enum.
    // Comparing to the input order would be asserting the wrong contract.
    #expect(decoded.contributions.compactMap(\.key.muscle) == [.abs, .quadriceps, .glutes, .adductors])
    #expect(Set(decoded.contributions.map(\.key)) == Set(original.map(\.key)))
    let byKey = Dictionary(uniqueKeysWithValues: decoded.contributions.map { ($0.key, $0.role) })
    for contribution in original {
      #expect(byKey[contribution.key] == contribution.role)
    }
  }

  @Test("Encoding orders by declaration order, not insertion order")
  func encodingIsOrdered() {
    let scrambled = [
      contribution(.soleus, .direct),
      contribution(.chest, .direct),
      contribution(.biceps, .indirect),
    ]
    let decoded = MuscleColumn.decodeContributions(MuscleColumn.encode(scrambled))
    #expect(decoded.contributions.compactMap(\.key.muscle) == [.chest, .biceps, .soleus])
  }

  /// A malformed column must never look like "no secondaries" — that is indistinguishable from a
  /// correctly-empty row and hides the failure.
  @Test("Unparseable JSON is reported, never silently empty")
  func malformedIsReported() {
    for bad in ["", "not json", "{\"muscle\":\"chest\"}", "null", "17"] {
      let decoded = MuscleColumn.decodeContributions(bad)
      #expect(decoded.contributions.isEmpty)
      #expect(decoded.unreadableEntryCount == 1, "\(bad) was silently swallowed")
      #expect(!decoded.isClean)
    }
  }

  @Test("An empty array is clean and empty, which is different from malformed")
  func emptyIsClean() {
    let decoded = MuscleColumn.decodeContributions("[]")
    #expect(decoded.contributions.isEmpty)
    #expect(decoded.isClean)
  }

  /// The bare-array form the current reader writes, and what user CSV imports produce.
  @Test("A legacy bare array of strings is salvaged, not rejected")
  func legacyBareArray() {
    let decoded = MuscleColumn.decodeContributions("[\"biceps\",\"forearms\"]")
    #expect(decoded.contributions.count == 2)
    let allIndirect = decoded.contributions.allSatisfy { $0.role == .indirect }
    let allLegacy = decoded.contributions.allSatisfy { $0.sourceID == "legacy-bare-array" }
    let allLow = decoded.contributions.allSatisfy { $0.certainty == .low }
    #expect(allIndirect)
    #expect(allLegacy)
    #expect(allLow)
  }

  /// A newer app version's token must survive a round trip through an older build unchanged.
  @Test("An unknown muscle token survives a read")
  func unknownTokenSurvives() {
    let json = "[{\"muscle\":\"serratusAnterior\",\"role\":\"direct\",\"certainty\":\"low\",\"source\":\"trial\"}]"
    let decoded = MuscleColumn.decodeContributions(json)
    #expect(decoded.contributions.count == 1)
    let only = decoded.contributions[0]
    #expect(only.key.storedValue == "serratusAnterior")
    #expect(!only.key.isAttributed)
    #expect(only.role == .direct)
    // Re-encoding does not destroy it.
    #expect(MuscleColumn.encode(decoded.contributions).contains("serratusAnterior"))
  }

  /// Likewise a source id this build has never heard of.
  @Test("An unknown source id is kept, not rejected")
  func unknownSourceKept() {
    let json = "[{\"muscle\":\"chest\",\"role\":\"direct\",\"certainty\":\"high\",\"source\":\"future-meta-analysis\"}]"
    let decoded = MuscleColumn.decodeContributions(json)
    #expect(decoded.contributions[0].sourceID == "future-meta-analysis")
  }

  @Test("An unknown role or certainty degrades to a safe default and is counted as degraded")
  func unknownFieldsDegrade() {
    let json = "[{\"muscle\":\"chest\",\"role\":\"prime\",\"certainty\":\"total\",\"source\":\"anatomy\"}]"
    let decoded = MuscleColumn.decodeContributions(json)
    #expect(decoded.contributions[0].role == .indirect)
    #expect(decoded.contributions[0].certainty == .low)
    #expect(decoded.degradedFieldCount == 2)
    #expect(!decoded.isClean)
  }

  @Test("A missing certainty degrades rather than being assumed")
  func missingCertaintyDegrades() {
    let json = "[{\"muscle\":\"chest\",\"role\":\"direct\",\"source\":\"anatomy\"}]"
    let decoded = MuscleColumn.decodeContributions(json)
    #expect(decoded.contributions[0].certainty == .low)
    #expect(decoded.degradedFieldCount == 1)
  }

  @Test("A junk element is counted unreadable while its siblings survive")
  func partialSalvage() {
    let json = "[{\"muscle\":\"chest\",\"role\":\"direct\",\"certainty\":\"moderate\",\"source\":\"anatomy\"},42,{\"role\":\"direct\"}]"
    let decoded = MuscleColumn.decodeContributions(json)
    #expect(decoded.contributions.count == 1)
    #expect(decoded.contributions[0].key.muscle == .chest)
    #expect(decoded.unreadableEntryCount == 2)
  }

  /// The second guard against one muscle occupying two buckets: highest weight wins.
  @Test("A duplicated muscle collapses to its highest-weight role")
  func duplicatesCollapse() {
    let json = """
      [{"muscle":"glutes","role":"stabilizer","certainty":"low","source":"anatomy"},\
      {"muscle":"glutes","role":"direct","certainty":"moderate","source":"convention"}]
      """
    let decoded = MuscleColumn.decodeContributions(json)
    #expect(decoded.contributions.count == 1)
    #expect(decoded.contributions[0].role == .direct)
    #expect(decoded.degradedFieldCount == 1)
  }

  @Test("The primary column is decoded without normalising")
  func primaryDecoding() {
    #expect(MuscleColumn.decodePrimary("quadriceps").muscle == .quadriceps)
    #expect(MuscleColumn.decodePrimary("unknown").isReservedSentinel)
    #expect(MuscleColumn.decodePrimary(" chest").storedValue == " chest")
  }
}
