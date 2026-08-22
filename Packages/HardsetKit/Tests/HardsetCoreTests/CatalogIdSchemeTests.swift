import CryptoKit
import Foundation
import Testing

@testable import HardsetCore

/// `CatalogExercise.id` is a permanent primary key that every logged set references, and it is a
/// UUID **version 5** -- a hash of the slug, not a random value. That is deliberate: two devices
/// seeding the catalogue must write identical rows rather than duplicating each other, and
/// SQLiteData forbids a UNIQUE constraint on anything but the primary key of a synchronized table,
/// so there is no database-level backstop.
///
/// The scheme was not written down anywhere. All 50 original ids are valid v5 UUIDs, so one clearly
/// existed, but 684 combinations of namespace and name template failed to reproduce them -- it was
/// lost. Two authors adding the same movement would therefore have minted different ids, producing
/// two permanent rows for one exercise on an additive-only schema.
///
/// So the scheme is recorded now, in `Tools/catalog_id.py` and here, and enforced. The original
/// entries are grandfathered because their ids cannot change; everything added from now on must
/// derive.
@Suite("Catalogue ids follow one recorded scheme")
struct CatalogIdSchemeTests {
  /// `uuid5(NAMESPACE_DNS, "catalog.hardset.app")`. Recorded as a literal so the derivation cannot
  /// drift with a library change.
  static let namespace = UUID(uuidString: "0DD2C109-7335-5EB0-ABA6-8F1EE6E4F48A")!

  /// Authored before the scheme was recorded. Permanent: changing one orphans every set that
  /// references it. This list must never gain an entry -- see `exemptListIsExact`.
  static let grandfathered: Set<String> = [
    "back-extension",
    "barbell-back-squat",
    "barbell-bench-press",
    "barbell-curl",
    "barbell-front-squat",
    "barbell-row",
    "bulgarian-split-squat",
    "cable-crunch",
    "cable-fly",
    "cable-lateral-raise",
    "cable-triceps-pushdown",
    "chest-press-machine",
    "chest-supported-row",
    "chin-up",
    "close-grip-bench-press",
    "conventional-deadlift",
    "dip",
    "dumbbell-bench-press",
    "dumbbell-curl",
    "face-pull",
    "hack-squat",
    "hammer-curl",
    "hanging-leg-raise",
    "hip-thrust",
    "incline-barbell-bench-press",
    "incline-dumbbell-curl",
    "incline-dumbbell-press",
    "lat-pulldown",
    "lateral-raise",
    "leg-extension",
    "leg-press",
    "lying-leg-curl",
    "overhead-cable-extension",
    "overhead-press",
    "pec-deck",
    "preacher-curl",
    "pull-up",
    "reverse-pec-deck",
    "reverse-wrist-curl",
    "romanian-deadlift",
    "seated-cable-row",
    "seated-calf-raise",
    "seated-dumbbell-press",
    "seated-leg-curl",
    "shrug",
    "single-arm-dumbbell-row",
    "skull-crusher",
    "standing-calf-raise",
    "straight-arm-pulldown",
    "wrist-curl",
  ]

  /// RFC 4122 version 5: SHA-1 over the namespace bytes followed by the name, with the version and
  /// variant nibbles overwritten.
  private func derivedID(slug: String) -> UUID {
    var input = [UInt8]()
    withUnsafeBytes(of: Self.namespace.uuid) { input.append(contentsOf: $0) }
    input.append(contentsOf: Array(slug.utf8))

    var digest = Array(Insecure.SHA1.hash(data: Data(input)))
    digest[6] = (digest[6] & 0x0F) | 0x50
    digest[8] = (digest[8] & 0x3F) | 0x80

    let b = digest
    return UUID(
      uuid: (
        b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
        b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
      )
    )
  }

  @Test("The recorded namespace is itself the documented derivation")
  func namespaceIsWhatWeSayItIs() {
    // uuid5(NAMESPACE_DNS, "catalog.hardset.app"), computed here rather than trusted.
    let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
    var input = [UInt8]()
    withUnsafeBytes(of: dns.uuid) { input.append(contentsOf: $0) }
    input.append(contentsOf: Array("catalog.hardset.app".utf8))
    var digest = Array(Insecure.SHA1.hash(data: Data(input)))
    digest[6] = (digest[6] & 0x0F) | 0x50
    digest[8] = (digest[8] & 0x3F) | 0x80
    let b = digest
    let computed = UUID(
      uuid: (
        b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
        b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
      )
    )
    #expect(computed == Self.namespace)
  }

  @Test("Every entry added since the scheme was recorded derives its id from its slug")
  func newEntriesConform() {
    for entry in ExerciseCatalog.v1 where !Self.grandfathered.contains(entry.slug) {
      let expected = derivedID(slug: entry.slug).uuidString.lowercased()
      #expect(
        entry.id == expected,
        """
        \(entry.slug) has id \(entry.id) but the recorded scheme gives \(expected).
        Get the id from: python3 Tools/catalog_id.py \(entry.slug)
        """
      )
    }
  }

  @Test("The grandfathered list is exactly the set of non-conforming entries, and cannot grow")
  func exemptListIsExact() {
    let nonConforming = Set(
      ExerciseCatalog.v1
        .filter { $0.id != derivedID(slug: $0.slug).uuidString.lowercased() }
        .map(\.slug)
    )
    // If this fails with extra slugs on the left, someone hand-minted an id instead of deriving
    // one. If it fails with extra on the right, someone changed a permanent key.
    let unexpected = nonConforming.subtracting(Self.grandfathered).sorted()
    let resolved = Self.grandfathered.subtracting(nonConforming).sorted()
    #expect(
      nonConforming == Self.grandfathered,
      """
      hand-minted ids that should have been derived: \(unexpected)
      grandfathered slugs whose id changed: \(resolved)
      """
    )
  }

  @Test("A slug is a stable key, so the derivation is exact rather than normalised")
  func derivationIsCaseAndPunctuationExact() {
    #expect(derivedID(slug: "hip-abduction-machine") != derivedID(slug: "hip_abduction_machine"))
    #expect(derivedID(slug: "hip-abduction-machine") != derivedID(slug: "Hip-Abduction-Machine"))
    // And it agrees with the Python tool, which is what an author actually runs.
    #expect(
      derivedID(slug: "hip-abduction-machine").uuidString.lowercased()
        == "bbfdb297-a7b9-540c-a745-68e77c79a7ee"
    )
  }
}
