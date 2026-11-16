#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the methodology sheet as the root view, one capture per state, so the disclosure can
  /// be reviewed from images.
  ///
  /// The sheet is a whole screen, so it is not a catalogue section. The default state, high
  /// certainty with every part of the source present, is also captured in light and with
  /// Increase Contrast. Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is
  /// set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Methodology sheet renders for review", .serialized)
  struct MethodologySheetSnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    private static let tall = CGSize(width: 402, height: 1300)
    private static let accessibility = CGSize(width: 402, height: 2600)

    private static let shortMethodology =
      "A completed working set credits one set to each muscle labelled direct on the movement "
      + "and half a set to each labelled indirect. The counts are stated conventions, and the "
      + "sheet shows exactly the values the arithmetic uses."

    /// A source with a citation but no stated validity range.
    private static let withoutRange = EvidenceSource(
      id: "snapshot-no-range",
      title: "Citation only",
      methodology: shortMethodology,
      citation: "Example A, Example B. Journal 2025. DOI 10.0000/example.",
      validRange: nil
    )

    /// A source with only its method, so neither the limits section nor the citation card shows.
    private static let bare = EvidenceSource(
      id: "snapshot-bare",
      title: "Method only",
      methodology: shortMethodology
    )

    /// The fractional counting source with its methodology repeated until the sheet scrolls.
    private static let long = EvidenceSource(
      id: "snapshot-long",
      title: "Long methodology",
      methodology: Array(repeating: shortMethodology, count: 8).joined(separator: "\n\n"),
      citation: SetCounting.source.citation,
      validRange: SetCounting.source.validRange
    )

    /// The default state in every appearance: high certainty, valid range and citation present.
    @Test func defaultStateInEveryAppearance() async throws {
      try await Snapshot.capture("kit-methodology-high-dark", size: Self.phone) {
        MethodologySheet(source: SetCounting.source, certainty: .high)
      }
      try await Snapshot.capture("kit-methodology-high-light", size: Self.phone, style: .light) {
        MethodologySheet(source: SetCounting.source, certainty: .high)
      }
      try await Snapshot.capture(
        "kit-methodology-high-dark-contrast", size: Self.phone, contrast: .high
      ) {
        MethodologySheet(source: SetCounting.source, certainty: .high)
      }
    }

    /// The other certainty levels, and no certainty at all.
    @Test func certaintyLevels() async throws {
      try await Snapshot.capture("kit-methodology-moderate-dark", size: Self.phone) {
        MethodologySheet(source: SetCounting.source, certainty: .moderate)
      }
      try await Snapshot.capture("kit-methodology-low-dark", size: Self.phone) {
        MethodologySheet(source: SetCounting.source, certainty: .low)
      }
      try await Snapshot.capture("kit-methodology-unevaluated-dark", size: Self.phone) {
        MethodologySheet(source: VolumeAnalyzer.targetSource, certainty: .unevaluated)
      }
      try await Snapshot.capture("kit-methodology-no-certainty-dark", size: Self.phone) {
        MethodologySheet(source: ProgressionAnalyzer.source)
      }
    }

    /// Which parts of the source are present: the limits section and the citation card.
    @Test func sourceParts() async throws {
      try await Snapshot.capture("kit-methodology-no-range-dark", size: Self.phone) {
        MethodologySheet(source: Self.withoutRange, certainty: .moderate)
      }
      try await Snapshot.capture("kit-methodology-no-citation-dark", size: Self.phone) {
        MethodologySheet(source: ProgressionAnalyzer.source, certainty: .moderate)
      }
      try await Snapshot.capture("kit-methodology-method-only-dark", size: Self.phone) {
        MethodologySheet(source: Self.bare, certainty: .high)
      }
    }

    @Test func longMethodology() async throws {
      try await Snapshot.capture("kit-methodology-long-dark", size: Self.tall) {
        MethodologySheet(source: Self.long, certainty: .moderate)
      }
    }

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-methodology-high-dark-ax3", size: Self.accessibility, typeSize: .accessibility3
      ) {
        MethodologySheet(source: SetCounting.source, certainty: .high)
      }
    }
  }
#endif
