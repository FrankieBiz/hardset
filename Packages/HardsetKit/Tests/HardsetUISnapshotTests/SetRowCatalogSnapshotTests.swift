#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the set row catalogue so the log control, value fields and rows can be reviewed from
  /// images alone. Each section is captured on its own in a window as tall as that section, and,
  /// like the other catalogue suites, it asserts nothing about pixels.
  @MainActor
  @Suite("Set row catalogue renders for review", .serialized)
  struct SetRowCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size. A starting guess: raise any
    /// height whose PNG is cropped at the bottom edge.
    private static func height(_ section: SetRowCatalogView.Section) -> CGFloat {
      switch section {
      case .logControl: 780
      case .fields: 760
      case .rows: 1800
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in SetRowCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-setrow-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          SetRowCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          SetRowCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          SetRowCatalogView(section: section)
        }
      }
    }

    /// The rows stacked at an accessibility size, where the log control says "Log set" or "Logged".
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-setrow-rows-dark-ax3",
        size: CGSize(width: Self.width, height: 5200),
        typeSize: .accessibility3
      ) {
        SetRowCatalogView(section: .rows)
      }
    }
  }
#endif
