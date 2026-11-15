#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the screen-chrome catalogue so the headers, the header icon buttons and the section
  /// labels can be reviewed from images. Each section is captured on its own, in a window as tall
  /// as that section. Like the screen suite it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and
  /// it asserts nothing about pixels.
  @MainActor
  @Suite("Screen chrome catalogue renders for review", .serialized)
  struct ScreenChromeCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: ScreenChromeCatalogView.Section) -> CGFloat {
      switch section {
      case .headers: 900
      case .icons: 360
      case .labels: 360
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in ScreenChromeCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-chrome-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          ScreenChromeCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          ScreenChromeCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          ScreenChromeCatalogView(section: section)
        }
      }
    }

    /// The headers at an accessibility size, where the trailing controls sit above the title.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-chrome-headers-dark-ax3",
        size: CGSize(width: Self.width, height: 2400),
        typeSize: .accessibility3
      ) {
        ScreenChromeCatalogView(section: .headers)
      }
    }
  }
#endif
