#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the three pitch pages the way the first-launch pager shows them: a headline, a line
  /// of copy and one live element, each on the app canvas at phone size. The still frames cover the
  /// states a lifter reaches by touching: the set row before and after its tap, every segment of
  /// the estimate (so the four certainty levels can be read from images), and the rest bar. The
  /// rest capture uses a paused timer so the countdown text is the same on every run. Like the
  /// other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing
  /// about pixels.
  @MainActor
  @Suite("Pitch pages render for review", .serialized)
  struct PitchSnapshotTests {
    private static let size = CGSize(width: 402, height: 640)

    private static func page<Page: View>(_ page: Page) -> some View {
      page
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    @Test func setRowPage() async throws {
      try await Snapshot.capture("pitch-1-ready-dark", size: Self.size) {
        Self.page(PitchSetRowPage(unit: .kilograms))
      }
      try await Snapshot.capture("pitch-1-logged-dark", size: Self.size) {
        Self.page(PitchSetRowPage(unit: .kilograms, isFirstLogged: true))
      }
      try await Snapshot.capture("pitch-1-ready-light", size: Self.size, style: .light) {
        Self.page(PitchSetRowPage(unit: .kilograms))
      }
      try await Snapshot.capture("pitch-1-ready-pounds-dark", size: Self.size) {
        Self.page(PitchSetRowPage(unit: .pounds))
      }
    }

    /// One capture per segment, so the four certainty levels (and the not-evaluated state that
    /// refuses to show a number) can each be read from an image.
    @Test func estimatePage() async throws {
      for reps in PitchEstimateDemo.repOptions {
        try await Snapshot.capture("pitch-2-\(reps)-reps-dark", size: Self.size) {
          Self.page(PitchEstimatePage(unit: .kilograms, initialReps: reps))
        }
      }
      try await Snapshot.capture("pitch-2-3-reps-light", size: Self.size, style: .light) {
        Self.page(PitchEstimatePage(unit: .kilograms, initialReps: 3))
      }
      try await Snapshot.capture(
        "pitch-2-15-reps-dark-contrast", size: Self.size, contrast: .high
      ) { Self.page(PitchEstimatePage(unit: .kilograms, initialReps: 15)) }
    }

    @Test func restPage() async throws {
      try await Snapshot.capture("pitch-3-paused-dark", size: Self.size) {
        Self.page(
          PitchRestPage(
            timer: DemoRestTimer(initialState: .paused(remaining: .seconds(90)))))
      }
      try await Snapshot.capture("pitch-3-paused-light", size: Self.size, style: .light) {
        Self.page(
          PitchRestPage(
            timer: DemoRestTimer(initialState: .paused(remaining: .seconds(90)))))
      }
    }

    /// At an accessibility size the page scrolls: the capture is tall enough to show all of it.
    @Test func accessibilitySize() async throws {
      try await Snapshot.capture(
        "pitch-2-3-reps-dark-ax3", size: CGSize(width: 402, height: 1400),
        typeSize: .accessibility3
      ) { Self.page(PitchEstimatePage(unit: .kilograms, initialReps: 3)) }
      try await Snapshot.capture(
        "pitch-1-ready-dark-ax3", size: CGSize(width: 402, height: 1400),
        typeSize: .accessibility3
      ) { Self.page(PitchSetRowPage(unit: .kilograms)) }
    }
  }
#endif
