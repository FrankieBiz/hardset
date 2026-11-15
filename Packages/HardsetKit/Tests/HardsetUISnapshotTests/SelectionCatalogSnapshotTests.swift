#if canImport(UIKit)
  import Foundation
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the selection catalogue (rows, the search field, the indicator and card states) so
  /// the entry and selection kit can be reviewed from images. Like the other catalogue suites it is
  /// inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Selection catalogue renders for review", .serialized)
  struct SelectionCatalogSnapshotTests {
    private static let width: CGFloat = 402

    /// The window height each section needs at the standard text size, so nothing is cropped.
    private static func height(_ section: SelectionCatalogView.Section) -> CGFloat {
      switch section {
      case .rows: 840
      case .field: 360
      case .indicators: 620
      }
    }

    @Test func sectionsInEveryAppearance() async throws {
      for section in SelectionCatalogView.Section.allCases {
        let size = CGSize(width: Self.width, height: Self.height(section))
        let name = "kit-selection-\(section.rawValue)"
        try await Snapshot.capture("\(name)-dark", size: size) {
          SelectionCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-light", size: size, style: .light) {
          SelectionCatalogView(section: section)
        }
        try await Snapshot.capture("\(name)-dark-contrast", size: size, contrast: .high) {
          SelectionCatalogView(section: section)
        }
      }
    }

    /// The two sections whose layout changes at accessibility sizes: the badge moves under the
    /// title, and the field and its clear button grow.
    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-selection-rows-dark-ax3",
        size: CGSize(width: Self.width, height: 3200),
        typeSize: .accessibility3
      ) {
        SelectionCatalogView(section: .rows)
      }
      try await Snapshot.capture(
        "kit-selection-field-dark-ax3",
        size: CGSize(width: Self.width, height: 900),
        typeSize: .accessibility3
      ) {
        SelectionCatalogView(section: .field)
      }
    }
  }
#endif
