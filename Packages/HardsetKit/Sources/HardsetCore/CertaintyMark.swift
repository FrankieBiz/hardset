import Foundation

/// How a certainty looks and reads: a glyph and a word, never colour alone.
///
/// Certainty is a visual system (spec §3, item 2). The words and glyphs used to live in
/// `HardsetUI` as `CertaintyLevel`, a mirror of `Certainty` that no test could reach. They are
/// decided here instead, so the claim "each level has its own shape and its own word" is checked on
/// every run, and the UI only draws what this says.
public struct CertaintyMark: Hashable, Sendable {
  public let certainty: Certainty
  /// An SF Symbol. Each level has its own shape, so the level reads with colour turned off.
  public let symbolName: String
  /// The badge text: "Moderate confidence".
  public let word: String
  /// For dense rows, where the full word would repeat down a list: "Moderate".
  public let shortWord: String
  /// The colour role. A second carrier of the level, never the only one.
  public let role: Palette.Role

  public static func of(_ certainty: Certainty) -> CertaintyMark {
    switch certainty {
    case .high:
      CertaintyMark(
        certainty: .high, symbolName: "checkmark.seal", word: "High confidence",
        shortWord: "High", role: .certaintyHigh)
    case .moderate:
      CertaintyMark(
        certainty: .moderate, symbolName: "circle.lefthalf.filled", word: "Moderate confidence",
        shortWord: "Moderate", role: .certaintyModerate)
    case .low:
      // A dashed circle, not a warning triangle: a low-confidence figure is a caveat about a
      // number, and a warning glyph made it read as an error (spec §3, item 2).
      CertaintyMark(
        certainty: .low, symbolName: "circle.dashed", word: "Low confidence",
        shortWord: "Low", role: .certaintyLow)
    case .unevaluated:
      // Stated plainly rather than hidden: the app's claim is that it says when it does not know.
      CertaintyMark(
        certainty: .unevaluated, symbolName: "questionmark.circle", word: "Not evaluated",
        shortWord: "Not evaluated", role: .certaintyUnevaluated)
    }
  }
}

extension Certainty {
  /// The glyph and word for this level.
  public var mark: CertaintyMark { .of(self) }
}

/// A caveat on a number: true, worth saying, and not an error.
///
/// Each one is grey text with a calm glyph. The lower bound used to be orange with an exclamation
/// mark, which made "at least this much" read as a failure (spec §3, item 2).
public struct CaveatMark: Hashable, Sendable {
  public let symbolName: String
  /// Shown beside the glyph.
  public let word: String
  /// The colour role. The palette's tested neutral, never a warning colour.
  public let role: Palette.Role

  /// "≥ 8 sets": some sets could not be attributed, so the figure is a floor.
  public static let lowerBound = CaveatMark(
    symbolName: "greaterthan.circle", word: "At least", role: .certaintyUnevaluated)
  /// The suggested loads came from another machine's history.
  public static let otherMachine = CaveatMark(
    symbolName: "arrow.triangle.branch", word: "From another machine", role: .certaintyUnevaluated)
  /// A session left open longer than any real workout (`DECISIONS.md` §21).
  public static let lengthUnknown = CaveatMark(
    symbolName: "clock.badge.questionmark", word: "Length unknown", role: .certaintyUnevaluated)

  public static let all: [CaveatMark] = [.lowerBound, .otherMachine, .lengthUnknown]
}

extension Assumption {
  /// The suggested loads were borrowed from the same movement on a different machine, because
  /// this machine has no history. The correction is choosing the machine the lifter is on.
  public static let borrowedFromOtherMachine = Assumption(
    id: "prefill.otherMachine",
    label: "From another machine",
    correctionPrompt: "Choose the machine you're on"
  )

  /// The unit was guessed from the device's region, not chosen (spec 3.5).
  public static func unitFromRegion(_ unit: WeightUnit) -> Assumption {
    let name =
      switch unit {
      case .kilograms: "kilograms"
      case .pounds: "pounds"
      }
    return Assumption(
      id: "unit.fromRegion",
      label: "Weights in \(name), from your region",
      correctionPrompt: "Change the unit"
    )
  }
}
