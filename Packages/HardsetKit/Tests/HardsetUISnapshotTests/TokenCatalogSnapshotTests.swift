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
  /// Increase Contrast, an accessibility text size and Reduce Motion. Like the screen suite it is
  /// inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @Suite("Token catalogue renders for review", .serialized)
  struct TokenCatalogSnapshotTests {
    @Test func catalogue() async throws {
      let tall = CGSize(width: 402, height: 2400)
      try await Snapshot.capture("tokens-dark", size: tall) { TokenCatalogView() }
      try await Snapshot.capture("tokens-light", size: tall, style: .light) { TokenCatalogView() }
      try await Snapshot.capture("tokens-dark-contrast", size: tall, contrast: .high) { TokenCatalogView() }
      try await Snapshot.capture("tokens-dark-ax3", size: CGSize(width: 402, height: 3600), typeSize: .accessibility3) {
        TokenCatalogView()
      }
      try await Snapshot.capture("tokens-dark-reduced-motion", size: tall) {
        TokenCatalogView().environment(\.accessibilityReduceMotion, true)
      }
    }
  }
#endif
