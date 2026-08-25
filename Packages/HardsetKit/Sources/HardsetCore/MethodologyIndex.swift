import Foundation

/// Every derived number in the app, and where it comes from — as data rather than as a screen.
///
/// # Why this is in Core and not in the view
///
/// It started as a `static let` on `MethodologyIndexScreen`, whose doc comment claimed
/// "`MethodologyIndexTests` fails if the count drifts, so adding one is a deliberate act rather
/// than an omission." **That test did not exist**, and could not: the screen lives in
/// `HardsetFeature`, and there is no `HardsetFeatureTests` target. The enforcement was a comment.
///
/// The set of numbers the app derives is Core knowledge — the same knowledge the `EvidenceSource`
/// values themselves are. So it lives here, where `MethodologyIndexTests` can sweep
/// `Sources/HardsetCore` for `EvidenceSource` declarations and fail when one is missing from this
/// list. The screen renders it and knows nothing.
///
/// App Review guideline 1.4.1 asks for the methodology behind a number presented as a measurement.
/// The app answers that *in situ* — each screen showing a derived figure carries its own sheet,
/// generated from the same source the code computes with. This exists because in-situ disclosure has
/// one gap: a reviewer, or a lifter deciding whether to trust any of it, cannot see the whole set
/// without finding every screen that hides one.
public enum MethodologyIndex {
  public struct Section: Hashable, Sendable, Identifiable {
    public let title: String
    public let sources: [EvidenceSource]

    public var id: String { title }

    public init(title: String, sources: [EvidenceSource]) {
      self.title = title
      self.sources = sources
    }
  }

  /// Grouped the way a reader looks for them, not the way the modules are arranged.
  ///
  /// **Adding an `EvidenceSource` anywhere in `HardsetCore` and not adding it here fails
  /// `MethodologyIndexTests`.** That is the point: an undisclosed derived number is exactly what
  /// guideline 1.4.1 is about, and a list maintained by memory is not a list.
  public static let sections: [Section] = [
    Section(title: "Sets and muscles", sources: [SetCounting.source]),
    Section(
      title: "Strength",
      sources: [StrengthMath.measuredSource, StrengthMath.epleySource, ProgressionAnalyzer.source]
    ),
    Section(
      title: "Volume over a week",
      sources: [VolumeAnalyzer.doseResponseSource, VolumeAnalyzer.targetSource]
    ),
    Section(
      title: "Plans and bodyweight",
      sources: [SplitPlanAssessment.source, BodyweightTrend.source]
    ),
  ]

  /// Every source the index lists, flattened. What the test compares against the source tree.
  public static var allSources: [EvidenceSource] { sections.flatMap(\.sources) }

  /// The lead-in shown above the list.
  public static let preamble = """
    Every number Hardset shows you is either something you logged, or something worked out from \
    what you logged. This is the second kind, in full. Where the evidence does not reach, the app \
    says so instead of showing a number.
    """
}
