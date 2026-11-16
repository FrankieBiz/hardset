#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the honesty catalogue so the certainty badge, its open detail, the assumption chip and
  /// the unevaluated readout can be reviewed from images. Each section is captured on its own, in a
  /// window as tall as that section. Like the screen suite it is inert unless
  /// `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Honesty catalogue renders for review", .serialized)
  struct HonestyCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: HonestyCatalogView.Section) -> CGFloat {
      switch section {
      case .badges: 760
      case .detail: 1850
      case .chips: 540
      case .readouts: 560
      }
    }

    /// The window height each section needs at accessibility3, where every line wraps further.
    private static func heightAX3(_ section: HonestyCatalogView.Section) -> CGFloat {
      switch section {
      case .badges: 1500
      case .detail: 6000
      case .chips: 1800
      case .readouts: 1900
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in HonestyCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-honesty-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          HonestyCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          HonestyCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          HonestyCatalogView(section: section)
        }
      }
    }

    /// Increase Contrast in the light appearance, where the unevaluated capsule is carried only by
    /// its outline.
    @Test func badgesInLightContrast() async throws {
      try await Snapshot.capture(
        "kit-honesty-badges-light-contrast",
        size: CGSize(width: Self.width, height: Self.height(.badges)),
        style: .light,
        contrast: .high
      ) {
        HonestyCatalogView(section: .badges)
      }
    }

    /// Every section at an accessibility text size: "Moderate confidence" wraps while "High
    /// confidence" stays on one line, the detail switches to its sheet layout, the chip label wraps
    /// inside its hit region, and the readout wraps.
    @Test func accessibilitySizes() async throws {
      for section in HonestyCatalogView.Section.allCases {
        try await Snapshot.capture(
          "kit-honesty-\(section.rawValue)-dark-ax3",
          size: CGSize(width: Self.width, height: Self.heightAX3(section)),
          typeSize: .accessibility3
        ) {
          HonestyCatalogView(section: section)
        }
      }
    }
  }
#endif
