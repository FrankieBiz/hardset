#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the token catalogue so the design system can be reviewed from images alone.
  ///
  /// The development machine cannot compile SwiftUI, so the catalogue is how the palette, type,
  /// machined surfaces and controls are seen in every appearance the app supports: dark, light,
  /// Increase Contrast and an accessibility text size. Each section is captured on
  /// its own, in a window as tall as that section, because one tall image of the whole page would
  /// crop its lower sections. Like the screen suite it is inert unless `HARDSET_SNAPSHOT_DIR` is
  /// set, and it asserts nothing about pixels.
  @Suite("Token catalogue renders for review", .serialized)
  struct TokenCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: TokenCatalogView.Section) -> CGFloat {
      switch section {
      case .palette: 1700
      case .machined: 600
      case .type: 1100
      case .buttons: 1200
      case .certainty: 500
      case .motion: 700
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in TokenCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "tokens-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          TokenCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          TokenCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          TokenCatalogView(section: section)
        }
      }
    }

    /// The two sections whose layout changes at accessibility sizes.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "tokens-type-dark-ax3",
        size: CGSize(width: Self.width, height: 2200),
        typeSize: .accessibility3
      ) {
        TokenCatalogView(section: .type)
      }
      try await Snapshot.capture(
        "tokens-buttons-dark-ax3",
        size: CGSize(width: Self.width, height: 2000),
        typeSize: .accessibility3
      ) {
        TokenCatalogView(section: .buttons)
      }
    }
  }
#endif
