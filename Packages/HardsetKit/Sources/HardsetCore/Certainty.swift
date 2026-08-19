import Foundation

/// How much the app actually knows about a number it is about to show.
///
/// `unevaluated` is the load-bearing case. The reference app's scorers fell back to a
/// neutral 70 when they did not recognise an exercise, so three unknown lifts composed
/// into a confident "78/100 -- Dialed in". A fallback that looks like a measurement is
/// worse than no measurement, so this type makes "I don't know" representable and
/// `Claim` makes it unforgeable.
public enum Certainty: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
  /// No basis to produce a value. Render the absence, never a number.
  case unevaluated
  /// Directionally useful, wide error bars. Hedge in the UI.
  case low
  /// Supported by evidence that does not cleanly cover this case.
  case moderate
  /// Directly supported, within the range the underlying method was validated on.
  case high

  private var rank: Int {
    switch self {
    case .unevaluated: 0
    case .low: 1
    case .moderate: 2
    case .high: 3
    }
  }

  public static func < (lhs: Certainty, rhs: Certainty) -> Bool { lhs.rank < rhs.rank }

  /// Certainty never improves by combining inputs. A composite is only as good as its
  /// weakest component, and any `unevaluated` input makes the whole thing unevaluated.
  public static func combine(_ values: some Sequence<Certainty>) -> Certainty {
    values.min() ?? .unevaluated
  }
}

/// Where a number came from, in enough detail to satisfy App Review guideline 1.4.1.
///
/// The disclosure the reviewer reads is generated from these records, so it cannot
/// drift from what the code actually does.
public struct EvidenceSource: Hashable, Sendable, Codable, Identifiable {
  public let id: String
  /// Short human label, e.g. "Epley 1-rep-max estimate".
  public let title: String
  /// Plain-language methodology. This is the text guideline 1.4.1 asks for.
  public let methodology: String
  /// Literature citation, when one exists.
  public let citation: String?
  /// The bounds the method was validated within, stated plainly.
  public let validRange: String?

  public init(
    id: String, title: String, methodology: String,
    citation: String? = nil, validRange: String? = nil
  ) {
    self.id = id
    self.title = title
    self.methodology = methodology
    self.citation = citation
    self.validRange = validRange
  }
}

/// An input the app guessed rather than knew, paired with the affordance to correct it.
///
/// Every volume band moved by an inferred experience level must surface one of these,
/// which is why `label` and `correctionPrompt` are non-optional.
public struct Assumption: Hashable, Sendable, Codable, Identifiable {
  public let id: String
  /// Chip text, e.g. "assumes intermediate".
  public let label: String
  /// What tapping the chip offers, e.g. "Set your training experience".
  public let correctionPrompt: String

  public init(id: String, label: String, correctionPrompt: String) {
    self.id = id
    self.label = label
    self.correctionPrompt = correctionPrompt
  }
}

/// A value the app is willing to show, carrying its own certainty and provenance.
///
/// The type enforces the honesty rule structurally: `value` is non-nil if and only if
/// `certainty != .unevaluated`. There is no way to construct a confident-looking number
/// with no basis, and no neutral default to fall back to.
public struct Claim<Value: Sendable & Hashable>: Sendable, Hashable {
  public let value: Value?
  public let certainty: Certainty
  public let source: EvidenceSource
  public let assumptions: [Assumption]

  /// A value the app can stand behind.
  /// - Precondition: `certainty` must not be `.unevaluated`; use `unevaluated(source:)`.
  public init(
    _ value: Value,
    certainty: Certainty,
    source: EvidenceSource,
    assumptions: [Assumption] = []
  ) {
    precondition(
      certainty != .unevaluated,
      "A Claim carrying a value cannot be .unevaluated -- use Claim.unevaluated(source:)."
    )
    self.value = value
    self.certainty = certainty
    self.source = source
    self.assumptions = assumptions
  }

  private init(source: EvidenceSource, assumptions: [Assumption]) {
    self.value = nil
    self.certainty = .unevaluated
    self.source = source
    self.assumptions = assumptions
  }

  /// The honest empty result. Callers must render this as an absence.
  public static func unevaluated(
    source: EvidenceSource,
    assumptions: [Assumption] = []
  ) -> Claim {
    Claim(source: source, assumptions: assumptions)
  }

  public var isEvaluated: Bool { value != nil }

  /// Transform the value while preserving certainty and provenance untouched.
  public func map<T: Sendable & Hashable>(_ transform: (Value) -> T) -> Claim<T> {
    guard let value else {
      return .unevaluated(source: source, assumptions: assumptions)
    }
    return Claim<T>(
      transform(value), certainty: certainty, source: source, assumptions: assumptions
    )
  }
}
