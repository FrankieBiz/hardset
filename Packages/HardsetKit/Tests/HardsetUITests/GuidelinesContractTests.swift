import Foundation
import Testing

@testable import HardsetUI

/// The design contract, actually enforced.
///
/// `docs/UI-GUIDELINES.md` states that every value in `Tokens` is "verified against this document by
/// script". No such script existed. The document is the design contract for the whole app, and a
/// contract that claims to be checked and is not is worse than one that admits it is prose -- this
/// codebase has already shipped two guidelines claims that were false about the code.
///
/// Both sides are read as text rather than by evaluating a `Color`. Extracting a hex back out of a
/// resolved `SwiftUI.Color` means going through a colour space and a trait collection, which is
/// exactly where a comparison stops being a comparison of the authored values.
@Suite("Every colour in the guidelines matches the token that implements it")
struct GuidelinesContractTests {
  /// The document, found relative to this file rather than through a bundle.
  ///
  /// The package deliberately ships no resources, and the document lives outside the package
  /// anyway. `#filePath` is the only handle on the repository root that survives being run from a
  /// different working directory.
  static let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // HardsetUITests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // HardsetKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repository root

  private func read(_ relative: String) throws -> String {
    let url = Self.repositoryRoot.appending(path: relative)
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// Doc name to token name. Spelled out rather than derived, because the correspondence is itself
  /// the thing worth stating: the document talks about certainty levels, the code about `statusHigh`.
  private static let tokenNames: [String: String] = [
    "ground": "ground",
    "surface": "surface",
    "raised": "raised",
    "overlay": "overlay",
    "hairline": "hairline",
    "textPrimary": "textPrimary",
    "textSecondary": "textSecondary",
    "textTertiary": "textTertiary",
    "high": "statusHigh",
    "moderate": "statusModerate",
    "low": "statusLow",
  ]

  /// `| `ground` | `#080A0E` | ...` — the elevation, ink and status tables.
  private func documentedColours(_ doc: String) -> [(name: String, hex: String)] {
    let pattern = try! NSRegularExpression(
      pattern: #"^\|\s*`(\w+)`\s*\|\s*`#([0-9A-Fa-f]{6})`"#, options: [.anchorsMatchLines]
    )
    return pattern.matches(in: doc, range: NSRange(doc.startIndex..., in: doc)).compactMap { match in
      guard let name = Range(match.range(at: 1), in: doc),
        let hex = Range(match.range(at: 2), in: doc)
      else { return nil }
      return (String(doc[name]), String(doc[hex]).uppercased())
    }
  }

  /// `public static let ground = dynamic(light: srgb(0x08_0A_0E), ...` — first hex per token.
  private func implementedColours(_ source: String) -> [String: String] {
    let pattern = try! NSRegularExpression(
      pattern: #"static let (\w+)\s*=\s*(?:dynamic\()?\s*(?:light:\s*)?srgb\(0x([0-9A-Fa-f_]+)\)"#,
      options: [.anchorsMatchLines]
    )
    var found: [String: String] = [:]
    for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
      guard let name = Range(match.range(at: 1), in: source),
        let hex = Range(match.range(at: 2), in: source)
      else { continue }
      found[String(source[name])] =
        String(source[hex]).replacingOccurrences(of: "_", with: "").uppercased()
    }
    return found
  }

  @Test("The document and the tokens agree on every named colour")
  func namedColoursAgree() throws {
    let doc = try read("docs/UI-GUIDELINES.md")
    let source = try read("Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift")
    let implemented = implementedColours(source)

    var checked = 0
    for (documentedName, hex) in documentedColours(doc) {
      // `unevaluated` reuses `textTertiary` and has no token of its own, which the document says.
      guard let tokenName = Self.tokenNames[documentedName] else { continue }
      let actual = try #require(
        implemented[tokenName], "no token named \(tokenName) in DesignTokens.swift"
      )
      #expect(
        actual == hex,
        "\(documentedName): the guidelines say #\(hex), \(tokenName) is #\(actual)"
      )
      checked += 1
    }

    // The mapping itself has to stay honest: if a row is renamed in the document and the map is not
    // updated, the loop above silently checks fewer things.
    #expect(
      checked == Self.tokenNames.count,
      "checked \(checked) of \(Self.tokenNames.count) mapped tokens -- a documented row was renamed"
    )
  }

  /// Spent hue is the most easily broken part of the contract: three series colours, in fixed order,
  /// with a neutral for the overflow. Swapping two of them is invisible on a chart with one line.
  @Test("The series palette matches the document, in order")
  func seriesPaletteAgrees() throws {
    let doc = try read("docs/UI-GUIDELINES.md")
    let source = try read("Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift")

    let pattern = try NSRegularExpression(
      pattern: #"^\|\s*(\d+|overflow)\s*\|\s*`#([0-9A-Fa-f]{6})`"#, options: [.anchorsMatchLines]
    )
    let documented = pattern.matches(in: doc, range: NSRange(doc.startIndex..., in: doc))
      .compactMap { match -> String? in
        guard let hex = Range(match.range(at: 2), in: doc) else { return nil }
        return String(doc[hex]).uppercased()
      }
    #expect(documented.count == 4, "expected three series hues and an overflow in the document")

    // Every hex the source mentions, in source order, is enough to assert containment and order.
    let sourceHexes = implementedSourceOrder(source)
    for hex in documented {
      #expect(sourceHexes.contains(hex), "series colour #\(hex) is documented but not implemented")
    }
    // The three hues appear in the same relative order as the document lists them.
    let indices = documented.prefix(3).compactMap { sourceHexes.firstIndex(of: $0) }
    #expect(indices.count == 3)
    #expect(indices == indices.sorted(), "the series hues are implemented in a different order")
  }

  private func implementedSourceOrder(_ source: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: #"srgb\(0x([0-9A-Fa-f_]+)\)"#)
    return pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
      .compactMap { match in
        guard let hex = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[hex]).replacingOccurrences(of: "_", with: "").uppercased()
      }
  }

  /// The accent is the app's identity and the document is emphatic that it is white, the same value
  /// as `textPrimary`. A hue creeping in here is the single most visible way to break the design.
  @Test("The accent is still the ink colour, not a hue")
  func accentIsInk() throws {
    let source = try read("Packages/HardsetKit/Sources/HardsetUI/DesignTokens.swift")
    #expect(
      source.contains("public static let accent = textPrimary"),
      "the accent is no longer defined as textPrimary"
    )
  }
}
