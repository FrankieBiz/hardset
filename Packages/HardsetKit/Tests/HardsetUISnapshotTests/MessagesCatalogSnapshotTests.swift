#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the messages catalogue so the ledger, banners, loading line and empty states can be
  /// reviewed from images. Each section is captured on its own, in a window as tall as that
  /// section. Like the screen suite it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it
  /// asserts nothing about pixels.
  @MainActor
  @Suite("Messages catalogue renders for review", .serialized)
  struct MessagesCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: MessagesCatalogView.Section) -> CGFloat {
      switch section {
      case .ledger: 900
      case .banners: 1_500
      case .loading: 420
      case .empty: 1_500
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in MessagesCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-messages-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          MessagesCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          MessagesCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          MessagesCatalogView(section: section)
        }
      }
    }

    /// The ledger stacked one figure per line, and the banners with their text at an accessibility
    /// size, where nothing may truncate.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-messages-ledger-dark-ax3",
        size: CGSize(width: Self.width, height: 3_000),
        typeSize: .accessibility3
      ) {
        MessagesCatalogView(section: .ledger)
      }
      try await Snapshot.capture(
        "kit-messages-banners-dark-ax3",
        size: CGSize(width: Self.width, height: 4_200),
        typeSize: .accessibility3
      ) {
        MessagesCatalogView(section: .banners)
      }
    }
  }
#endif
