#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the shared surfaces catalogue so the press faces, cards and the weighted type overload
  /// can be reviewed from images. Each section is captured on its own, in a window as tall as that
  /// section. Like the screen suite it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it
  /// asserts nothing about pixels.
  @MainActor
  @Suite("Surfaces catalogue renders for review", .serialized)
  struct SurfacesCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: SurfacesCatalogView.Section) -> CGFloat {
      switch section {
      case .press: 760
      case .cards: 520
      case .typeWeight: 260
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in SurfacesCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-surfaces-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          SurfacesCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          SurfacesCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          SurfacesCatalogView(section: section)
        }
      }
    }

    /// The weighted overload at an accessibility size, where the tracking must stay proportional.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-surfaces-typeWeight-dark-ax3",
        size: CGSize(width: Self.width, height: 900),
        typeSize: .accessibility3
      ) {
        SurfacesCatalogView(section: .typeWeight)
      }
    }
  }
#endif
