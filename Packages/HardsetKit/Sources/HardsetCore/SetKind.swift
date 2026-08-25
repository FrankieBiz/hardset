import Foundation

/// What kind of set a row is.
///
/// Three cases, and deliberately only three. The research corpus proposed modelling
/// `{working, warmup, amrap, drop, backoff}` up front so a later release would be "a UI change
/// rather than a migration" — that reasoning does not apply here. SQLiteData's rule is that a
/// column may be *added* at any time and never removed or renamed, so an unused case costs
/// nothing to defer and a speculative one costs a permanent commitment to a vocabulary nobody
/// has designed a screen for yet. Myo-reps and cluster sets are refused for a different reason:
/// they need genuine sub-set structure with intra-set rests, which means a second concurrent
/// alarm and a nested model.
///
/// # Storage
///
/// This is the write-side source of truth. Storage keeps two flags — `loggedSets.isWarmup`, which
/// has existed since the first migration and is filtered on in SQL in half a dozen places, and
/// `loggedSets.isDropSet`, added alongside it. Modelling the pair as an enum here is what keeps
/// "a warm-up that is also a drop set" out of everything the app writes, since nothing but
/// `storage` produces the pair. `STRICT` tables forbid `CHECK`, so the constraint cannot live in
/// SQL and has to live in a type.
public enum SetKind: String, Codable, Sendable, Hashable, CaseIterable {
  /// A working set. The only kind that counts toward volume.
  case warmup
  case working
  /// A continuation of the working set above it, at reduced load, taken with no rest in between.
  ///
  /// A drop is part of the set it continues rather than a set of its own — see
  /// `SetCounting.dropSetConvention` for why that is the counting convention and what it is
  /// grounded in, which is not a finding.
  case drop

  /// Whether a set of this kind counts as one working set.
  ///
  /// False for warm-ups, which were never counted, and false for drops, which are counted as part
  /// of their parent set rather than as extra sets.
  public var countsAsWorkingSet: Bool { self == .working }
}

// MARK: - Storage projection

extension SetKind {
  /// Flat, two-column form for persistence.
  ///
  /// The fourth combination — both flags set — is not produced by anything, because this is the
  /// only thing that produces the pair.
  public var storage: (isWarmup: Bool, isDropSet: Bool) {
    switch self {
    case .warmup: (true, false)
    case .working: (false, false)
    case .drop: (false, true)
    }
  }

  /// Rebuild from persisted columns.
  ///
  /// Unlike `RestTimerState`, the impossible combination is resolved rather than thrown. The
  /// difference is what the caller could do about it: a corrupt rest timer is one device's
  /// transient state and discarding it costs nothing, while this decode sits on the crash-recovery
  /// path, where throwing would take a whole workout's written sets down with one bad row. A row
  /// flagged both ways reads as a warm-up, which is the reading that cannot inflate anything —
  /// both kinds are excluded from working-set counts, and treating it as a warm-up additionally
  /// keeps it out of the load history that seeds suggestions.
  public init(isWarmup: Bool, isDropSet: Bool) {
    switch (isWarmup, isDropSet) {
    case (true, _): self = .warmup
    case (false, true): self = .drop
    case (false, false): self = .working
    }
  }
}
