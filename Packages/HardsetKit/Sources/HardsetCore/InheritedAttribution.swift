import Foundation

/// Deriving a movement's attribution from a curated one it resembles.
///
/// # The problem this solves
///
/// A movement the lifter creates by hand credits exactly one muscle, `direct`, `low` certainty. So
/// `Nautilus High Lever Row`, typed in at the rack, credits lats and nothing else — while the
/// curated `Chest Supported Row` it is plainly a variant of credits rear delts, upper back and
/// biceps too. Every weekly figure that movement touches is then quietly short. For a lifter whose
/// gym is mostly brand-specific machines, that is most of their training.
///
/// # Why the provenance does not come with it
///
/// The muscles carry over and the **citation does not**. The literature cited for a chest-supported
/// row is evidence about *that* movement; a lifter asserting their lever row is like it is one
/// person's judgement about one machine. Copying the citation across would launder a trial into a
/// claim it never made — the single most dishonest thing this feature could do — so every inherited
/// contribution is rewritten to the user source with no citation, and its certainty is capped.
///
/// Capped by `min`, not assigned: a template contribution that was already `.unevaluated` stays
/// `.unevaluated` rather than being promoted to `.low` on its way through.
///
/// # Why stabilisers are dropped
///
/// A stabiliser credits nothing, so dropping one changes no arithmetic. What it avoids is a claim
/// the lifter never endorsed: the sheet shows the muscles being inherited so they can be removed,
/// and it shows credited muscles only — grip and bracing are deliberately not presented as trained
/// work anywhere in this app. Inheriting a row that is invisible in the sheet would be exactly the
/// silent claim this type exists to prevent.
///
/// # Why copying, not referencing
///
/// A later catalogue correction does not propagate. That is the right default: it is the lifter's
/// movement now, and a curated edit silently rewriting what their own movement trains is worse than
/// it going slightly stale.
public enum InheritedAttribution {
  /// The most an inherited attribution may claim. One person's judgement about one machine.
  public static let ceiling: Certainty = .low

  /// The template's muscles and roles, rewritten as the lifter's own assertion.
  ///
  /// - Parameters:
  ///   - template: the curated movement's contributions, as stored.
  ///   - primary: the muscle the lifter chose. Always present in the result at `.direct`, even when
  ///     the template does not credit it, because it is the one attribution they actually made.
  /// - Returns: contributions in template order with the chosen primary first, deduplicated by
  ///   muscle keeping the strongest role.
  public static func inherited(
    from template: [MuscleContribution],
    primary: Muscle
  ) -> [MuscleContribution] {
    var byKey: [MuscleKey: MuscleContribution] = [:]
    var order: [MuscleKey] = []

    func consider(_ contribution: MuscleContribution) {
      guard let existing = byKey[contribution.key] else {
        byKey[contribution.key] = contribution
        order.append(contribution.key)
        return
      }
      // A muscle named twice in one entry keeps the strongest role, which is the same rule the
      // curated decoder applies. Nothing here may quietly downgrade a direct credit to indirect.
      if contribution.role.precedence > existing.role.precedence {
        byKey[contribution.key] = contribution
      }
    }

    // First, so the lifter's own choice leads the list and can never be overridden by the
    // template's reading of the same muscle.
    consider(
      MuscleContribution(
        key: MuscleKey(primary),
        role: .direct,
        certainty: ceiling,
        sourceID: MuscleContribution.userSourceID,
        citation: nil
      )
    )

    for contribution in template where contribution.setWeight > 0 {
      consider(
        MuscleContribution(
          key: contribution.key,
          role: contribution.role,
          certainty: min(contribution.certainty, ceiling),
          sourceID: MuscleContribution.userSourceID,
          citation: nil
        )
      )
    }

    return order.compactMap { byKey[$0] }
  }
}
