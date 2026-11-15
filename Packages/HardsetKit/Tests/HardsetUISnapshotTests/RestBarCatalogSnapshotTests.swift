#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the rest bar over its knurled countdown so the backing, the two layouts and the
  /// accessibility size can be reviewed from images. The bar is the root view of each capture, one
  /// capture per state. Like the screen suite it is inert unless `HARDSET_SNAPSHOT_DIR` is set,
  /// and it asserts nothing about pixels.
  @MainActor
  @Suite("Rest bar renders for review", .serialized)
  struct RestBarCatalogSnapshotTests {
    private static let metadata = RestMetadata(
      exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4, machineName: "Hammer Strength"
    )

    /// A fixed instant, so the running capture does not depend on the clock the run starts at.
    private static let referenceDate = Date(timeIntervalSince1970: 1_793_000_000)

    private static func bar(
      width: CGFloat, withMetadata: Bool = true, state: RestTimerState? = nil
    ) -> some View {
      VStack {
        Spacer()
        RestBarView(
          state: state ?? .paused(remaining: .seconds(96)),
          metadata: withMetadata ? metadata : nil,
          referenceDate: referenceDate,
          onAdjust: { _ in },
          onPauseResume: {},
          onSkip: {}
        )
      }
      .frame(width: width)
      .background(Tokens.Color.canvas)
    }

    @Test func pausedAtPhoneWidth() async throws {
      let size = CGSize(width: 402, height: 200)
      try await Snapshot.capture("kit-restbar-paused-402-metadata-dark", size: size) {
        Self.bar(width: 402)
      }
      try await Snapshot.capture("kit-restbar-paused-402-metadata-light", size: size, style: .light) {
        Self.bar(width: 402)
      }
      try await Snapshot.capture(
        "kit-restbar-paused-402-metadata-dark-contrast", size: size, contrast: .high
      ) {
        Self.bar(width: 402)
      }
      try await Snapshot.capture("kit-restbar-paused-402-plain-dark", size: size) {
        Self.bar(width: 402, withMetadata: false)
      }
    }

    @Test func pausedAtProMaxWidth() async throws {
      let size = CGSize(width: 440, height: 200)
      try await Snapshot.capture("kit-restbar-paused-440-metadata-dark", size: size) {
        Self.bar(width: 440)
      }
      try await Snapshot.capture("kit-restbar-paused-440-plain-dark", size: size) {
        Self.bar(width: 440, withMetadata: false)
      }
    }

    @Test func accessibilitySizes() async throws {
      try await Snapshot.capture(
        "kit-restbar-paused-402-metadata-dark-ax3",
        size: CGSize(width: 402, height: 520),
        typeSize: .accessibility3
      ) {
        Self.bar(width: 402)
      }
    }

    /// Last on purpose: a live timer once stalled a render at the one width where the bar takes
    /// its one-line layout. The reference date is fixed, so the countdown reads the same each run.
    @Test func runningAtProMaxWidth() async throws {
      try await Snapshot.capture(
        "kit-restbar-running-440-metadata-dark", size: CGSize(width: 440, height: 200)
      ) {
        Self.bar(
          width: 440,
          state: .running(endsAt: Self.referenceDate.addingTimeInterval(96))
        )
      }
    }
  }
#endif
