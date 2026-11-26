#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders one saved workout's history for review from images. Like the other render suites it
  /// is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts nothing about pixels: what it
  /// protects is that both states draw at all, in both appearances and at a large text size.
  @MainActor
  @Suite("Saved workout history renders for review", .serialized)
  struct TemplateHistorySnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    private static let tall = CGSize(width: 402, height: 1_500)
    private static let accessibility = CGSize(width: 402, height: 3_200)

    /// Fixed dates and loads, so the image shows the same session twice.
    private static let start = Date(timeIntervalSince1970: 1_793_000_000)

    private static func movement(
      _ name: String, machine: String? = nil, sets: Int, volumeKg: Double
    ) -> TemplateHistory.Movement {
      TemplateHistory.Movement(
        id: "\(name)|\(machine ?? "")", exerciseName: name, machineName: machine,
        workingSetCount: sets, volumeKg: volumeKg)
    }

    private static var twoSessions: TemplateHistory {
      let newer = TemplateHistory.Session(
        id: SessionID(),
        finishedAt: start.addingTimeInterval(4 * 86_400),
        movements: [
          movement("Barbell bench press", sets: 4, volumeKg: 3_520),
          movement("Cable row", sets: 3, volumeKg: 2_160),
          movement("Pull-up", sets: 3, volumeKg: 0),
        ])
      let older = TemplateHistory.Session(
        id: SessionID(),
        finishedAt: start.addingTimeInterval(86_400),
        movements: [
          movement("Barbell bench press", sets: 3, volumeKg: 2_400),
          movement("Incline press", machine: "Hammer Strength", sets: 3, volumeKg: 1_800),
        ])
      return TemplateHistory(
        sessions: [newer, older], totalSessionCount: 37, limit: 12)
    }

    private static func history(_ history: TemplateHistory, unit: WeightUnit = .kilograms)
      -> some View
    {
      ScrollView {
        TemplateHistoryView(history: history, unit: unit)
      }
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// The sheet's empty branch: the same words and quiet empty state, without a session block.
    private static var empty: some View {
      ScrollView {
        HardsetEmptyState(
          title: TemplateHistoryCopy.empty,
          detail: "Finish this workout with a working set and it will appear here.",
          systemImage: "clock.arrow.circlepath",
          style: .quiet)
      }
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    @Test func twoSessionsInBothAppearances() async throws {
      try await Snapshot.capture("workout-history-two-sessions-dark", size: Self.tall) {
        Self.history(Self.twoSessions)
      }
      try await Snapshot.capture(
        "workout-history-two-sessions-light", size: Self.tall, style: .light
      ) {
        Self.history(Self.twoSessions)
      }
    }

    @Test func twoSessionsAtAccessibilitySize() async throws {
      try await Snapshot.capture(
        "workout-history-two-sessions-accessibility3", size: Self.accessibility,
        typeSize: .accessibility3
      ) {
        Self.history(Self.twoSessions)
      }
    }

    @Test func emptyHistory() async throws {
      try await Snapshot.capture("workout-history-empty-dark", size: Self.phone) {
        Self.empty
      }
    }
  }
#endif
