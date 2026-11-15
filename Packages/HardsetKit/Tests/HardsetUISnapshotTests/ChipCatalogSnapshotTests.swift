#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the chip, tag and segment catalogue so those controls can be reviewed from images.
  ///
  /// Each section is captured on its own, in a window as tall as that section, in dark, light and
  /// Increase Contrast, plus an accessibility text size for every section, because chips, tags and
  /// segments all reflow there. Like the token suite it is inert unless `HARDSET_SNAPSHOT_DIR` is
  /// set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Chip catalogue renders for review", .serialized)
  struct ChipCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: ChipCatalogView.Section) -> CGFloat {
      switch section {
      case .chips: 360
      case .tags: 260
      case .segments: 420
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in ChipCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-chips-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) { ChipCatalogView(section: section) }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          ChipCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          ChipCatalogView(section: section)
        }
      }
    }

    /// Chips and tags as a rail and a wrapping label, and segments as wrapped labels.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-chips-chips-dark-ax3", size: CGSize(width: Self.width, height: 700),
        typeSize: .accessibility3
      ) { ChipCatalogView(section: .chips) }
      try await Snapshot.capture(
        "kit-chips-tags-dark-ax3", size: CGSize(width: Self.width, height: 900),
        typeSize: .accessibility3
      ) { ChipCatalogView(section: .tags) }
      try await Snapshot.capture(
        "kit-chips-segments-dark-ax3", size: CGSize(width: Self.width, height: 1800),
        typeSize: .accessibility3
      ) { ChipCatalogView(section: .segments) }
    }
  }
#endif
