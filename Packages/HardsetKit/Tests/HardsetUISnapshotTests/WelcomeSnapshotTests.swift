#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the Welcome bar and the plate tray so the first screen's centrepiece can be reviewed
  /// from images: the empty bar, one plate a side, a full stack that bends it, and the tray at an
  /// accessibility size. The auto-demo is off in every capture, because a capture must not wait four
  /// seconds and load a plate on its own. Like the other render suites it is inert unless
  /// `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels.
  @MainActor
  @Suite("Welcome bar renders for review", .serialized)
  struct WelcomeSnapshotTests {
    private static let size = CGSize(width: 402, height: 440)

    private static func bar(_ plates: [Plate], unit: WeightUnit = .kilograms) -> some View {
      WelcomeBarView(unit: unit, initialPlates: plates, isAutoDemoEnabled: false)
        .padding(.horizontal, Tokens.Spacing.loose)
        .frame(maxHeight: .infinity)
        .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    @Test func barStates() async throws {
      try await Snapshot.capture("welcome-bar-empty-dark", size: Self.size) { Self.bar([]) }
      try await Snapshot.capture("welcome-bar-loaded-dark", size: Self.size) {
        Self.bar([.twenty])
      }
      try await Snapshot.capture("welcome-bar-stacked-dark", size: Self.size) {
        Self.bar([.twentyFive, .twenty, .fifteen, .ten, .five])
      }
      try await Snapshot.capture("welcome-bar-loaded-light", size: Self.size, style: .light) {
        Self.bar([.twenty])
      }
      try await Snapshot.capture(
        "welcome-bar-stacked-dark-contrast", size: Self.size, contrast: .high
      ) { Self.bar([.twentyFive, .twenty, .fifteen, .ten, .five]) }
    }

    /// Pounds, where the total reads one decimal place: 60 kg is 132.3 lb.
    @Test func pounds() async throws {
      try await Snapshot.capture("welcome-bar-loaded-pounds-dark", size: Self.size) {
        Self.bar([.twenty], unit: .pounds)
      }
    }

    @Test func accessibilitySize() async throws {
      try await Snapshot.capture(
        "welcome-bar-loaded-dark-ax3", size: CGSize(width: 402, height: 760),
        typeSize: .accessibility3
      ) { Self.bar([.twenty]) }
    }
  }
#endif
