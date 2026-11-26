#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders "What Hardset won't say" as the root view, one capture per appearance, so the sheet can
  /// be reviewed from images.
  ///
  /// The sheet is a whole screen rather than a catalogue section. All four rows fit at the default
  /// content size, and the accessibility capture is tall enough for the same four with their source
  /// limits wrapped. Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set,
  /// and it asserts nothing about pixels.
  @MainActor
  @Suite("Refusals sheet renders for review", .serialized)
  struct RefusalsSheetSnapshotTests {
    /// Four rows of prose, their source titles and their stated limits.
    private static let fourRows = CGSize(width: 402, height: 1600)
    /// The same four at Accessibility 3, where every sentence wraps several times.
    private static let accessibility = CGSize(width: 402, height: 3600)

    /// The sheet as a real presentation shows it: `hardsetSheet()` tints the presented content
    /// plate blue, so the toolbar's Done is drawn in plate blue here too.
    private static func sheet() -> some View {
      RefusalsSheet()
        .tint(Tokens.Color.plateBlue)
    }

    @Test func darkAndLight() async throws {
      try await Snapshot.capture("kit-refusals-dark", size: Self.fourRows) {
        Self.sheet()
      }
      try await Snapshot.capture("kit-refusals-light", size: Self.fourRows, style: .light) {
        Self.sheet()
      }
    }

    @Test func accessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-refusals-accessibility", size: Self.accessibility, typeSize: .accessibility3
      ) {
        Self.sheet()
      }
    }
  }
#endif
