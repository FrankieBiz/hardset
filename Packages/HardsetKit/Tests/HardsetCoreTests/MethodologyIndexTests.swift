import Foundation
import Testing

@testable import HardsetCore

/// The test `MethodologyIndexScreen` claimed existed, and did not.
///
/// Its doc comment read "`MethodologyIndexTests` fails if the count drifts, so adding one is a
/// deliberate act rather than an omission." Nothing enforced it. An `EvidenceSource` added anywhere
/// and left out of the index is a number the app derives and does not disclose in one place, which
/// is precisely what App Review guideline 1.4.1 is about — and a list maintained by memory is not
/// a list.
///
/// Swept from the source tree rather than pinned to a count, so it fails on the *cause* (a new
/// source) rather than on a number someone can update without looking.
@Suite("Every derived number is disclosed in the index")
struct MethodologyIndexTests {
  static let coreSources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // HardsetCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // HardsetKit
    .appending(path: "Sources/HardsetCore")

  /// `static let name = EvidenceSource(` declarations, as `Type.name`.
  ///
  /// Read from disk for the same reason `GuidelinesContractTests` reads the view modules: Swift has
  /// no reflection over statics, so the only way a sweep cannot miss a newly added one is to read
  /// the files.
  static func declaredSources() throws -> [String] {
    let names = try FileManager.default.contentsOfDirectory(atPath: coreSources.path)
    var found: [String] = []
    for name in names where name.hasSuffix(".swift") {
      let text = try String(contentsOf: coreSources.appending(path: name), encoding: .utf8)
      // The owning type is the last `public enum`/`struct` declared above the property, which is
      // how every source in this module is written: a `static let` inside the type that computes
      // with it.
      var owner = ""
      for line in text.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Only TOP-LEVEL declarations own a source, matched on the raw line at column zero
        // rather than on the trimmed one. Three separate false readings came from getting this
        // wrong, and each is worth naming because the next person will hit one:
        //
        //   * `BodyweightTrend.Direction` is a NESTED `public enum`, so matching the trimmed line
        //     attributed the file's source to the nested type.
        //   * The sources in MuscleVolume.swift live in an `extension VolumeAnalyzer`, which a
        //     struct/enum-only match walks past — crediting whichever type was declared above.
        //   * `public nonisolated enum BodyweightTrend` carries a modifier, so matching the literal
        //     prefix "public enum " missed it entirely and the sweep silently found one fewer.
        //
        // Hence: require column zero, then take the token after whichever declaration keyword
        // appears, so any modifier between `public` and the keyword is tolerated.
        if line.hasPrefix("public ") || line.hasPrefix("extension ") {
          for keyword in ["enum ", "struct ", "extension "] {
            guard let range = line.range(of: keyword) else { continue }
            owner =
              line[range.upperBound...]
              .components(separatedBy: CharacterSet(charactersIn: " :{<"))
              .first ?? ""
            break
          }
        }
        guard trimmed.contains("EvidenceSource("), trimmed.contains("static let") else { continue }
        // `public static let epleySource = EvidenceSource(`
        guard let afterLet = trimmed.components(separatedBy: "static let ").last,
          let property = afterLet.components(separatedBy: CharacterSet(charactersIn: " :=")).first,
          !property.isEmpty, !owner.isEmpty
        else { continue }
        found.append("\(owner).\(property)")
      }
    }
    return found.sorted()
  }

  @Test("Every EvidenceSource declared in HardsetCore appears in the index")
  func indexIsExhaustive() throws {
    let declared = try Self.declaredSources()
    // Guard the sweep against being trivially true: this module genuinely declares several.
    #expect(declared.count >= 8, "sweep found \(declared.count) sources, which looks broken")

    let indexed = Set(MethodologyIndex.allSources.map(\.id))

    // Matched on the source's own `id`, not on the property name, because that is what the
    // disclosure is keyed to and what a reviewer would see.
    var missing: [String] = []
    for symbol in declared {
      let ids = try Self.idsFor(symbol)
      let covered = ids.contains { indexed.contains($0) }
      if !covered { missing.append(symbol) }
    }
    #expect(
      missing.isEmpty,
      """
      These EvidenceSource values are declared in HardsetCore but are not in \
      MethodologyIndex.sections, so the app derives a number it does not disclose in one place: \
      \(missing.joined(separator: ", ")). Add them to MethodologyIndex.
      """
    )
  }

  /// The `id` each declared source actually carries, resolved by name.
  ///
  /// Spelled out rather than reflected, and that is the intended cost: a new source has to be added
  /// here as well as to the index, which is one more place a reviewer's eye passes over.
  static func idsFor(_ symbol: String) throws -> [String] {
    switch symbol {
    case "SetCounting.source": [SetCounting.source.id]
    case "StrengthMath.measuredSource": [StrengthMath.measuredSource.id]
    case "StrengthMath.epleySource": [StrengthMath.epleySource.id]
    case "ProgressionAnalyzer.source": [ProgressionAnalyzer.source.id]
    case "VolumeAnalyzer.doseResponseSource": [VolumeAnalyzer.doseResponseSource.id]
    case "VolumeAnalyzer.targetSource": [VolumeAnalyzer.targetSource.id]
    case "SplitPlanAssessment.source": [SplitPlanAssessment.source.id]
    case "BodyweightTrend.source": [BodyweightTrend.source.id]
    default:
      // An unrecognised declaration is a failure, not a pass. A new source that nobody taught this
      // switch about must not slip through as "covered".
      []
    }
  }

  @Test("The index carries no duplicates and every entry has a real methodology")
  func indexIsWellFormed() throws {
    let all = MethodologyIndex.allSources
    #expect(Set(all.map(\.id)).count == all.count, "the index lists the same source twice")

    let allDescribed = all.allSatisfy { !$0.methodology.isEmpty && !$0.title.isEmpty }
    #expect(allDescribed)

    let sectionsNamed = MethodologyIndex.sections.allSatisfy { !$0.title.isEmpty }
    #expect(sectionsNamed)
    let sectionsPopulated = MethodologyIndex.sections.allSatisfy { !$0.sources.isEmpty }
    #expect(sectionsPopulated)
  }
}
