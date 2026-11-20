#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the Progress tab's board and the movement chart's new marks for review from images.
  /// Like the other render suites it is inert unless `HARDSET_SNAPSHOT_DIR` is set, and it asserts
  /// nothing about pixels: what it protects is that every state draws at all, for a person to read.
  @MainActor
  @Suite("Progress board renders for review", .serialized)
  struct ProgressBoardSnapshotTests {
    private static let phone = CGSize(width: 402, height: 874)
    private static let tall = CGSize(width: 402, height: 1400)
    private static let day = Date(timeIntervalSince1970: 1_793_000_000)

    private static func row(
      _ name: String, machine: String?, metric: TrendMetric, change: Double?, stalled: Int? = nil,
      certainty: Certainty? = nil, sparkline: [Double] = [50, 52, 51, 55, 57, 60]
    ) -> ProgressBoard.Row {
      ProgressBoard.Row(
        trend: MovementTrend(
          key: ProgressionKey(exerciseID: ExerciseID(), machineID: machine == nil ? nil : MachineID()),
          metric: metric, sparkline: sparkline, sixWeekChange: change, sessionCount: 6,
          stalledSessions: stalled, latestDate: day, certainty: certainty),
        exerciseName: name, machineName: machine)
    }

    /// Three body parts and one movement with none, an estimate with its badge, a heaviest-load row,
    /// a stalled row, a row with no six-week window and a bodyweight row measured in reps.
    private static var board: ProgressBoard {
      let press = row("Chest press", machine: "Hammer Strength Chest Press", metric: .estimatedMax,
        change: 0.08, certainty: .moderate)
      let fly = row("Cable fly", machine: nil, metric: .estimatedMax, change: 0.05, certainty: .high)
      let row2 = row("Lever row", machine: "Nautilus Lever Row", metric: .estimatedMax,
        change: 0.12, stalled: 3, certainty: .low)
      let squat = row("Back squat", machine: nil, metric: .heaviestLoad, change: nil)
      let pullup = row("Pull-up", machine: nil, metric: .repsAtTopLoad, change: 0.2,
        sparkline: [6, 7, 8, 8, 9, 10])
      let mystery = row("Pendulum squat", machine: nil, metric: .heaviestLoad, change: -0.03)
      return ProgressBoard(
        sections: [
          ProgressBoard.Section(category: .chest, rows: [press, fly]),
          ProgressBoard.Section(category: .back, rows: [row2, pullup]),
          ProgressBoard.Section(category: .quads, rows: [squat]),
          ProgressBoard.Section(category: nil, rows: [mystery]),
        ],
        mostImproved: [row2, press, pullup])
    }

    private static func screen(_ board: ProgressBoard) -> some View {
      NavigationStack {
        ProgressBoardView(
          board: board, title: "Progress", subtitle: "6 movements", onShowSettings: {},
          onSelect: { _ in }
        )
        .hardsetTabRoot()
      }
      .tint(Tokens.Color.plateBlue)
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    @Test func boardInEveryAppearance() async throws {
      try await Snapshot.capture("kit-progressboard-dark", size: Self.tall) { Self.screen(Self.board) }
      try await Snapshot.capture("kit-progressboard-light", size: Self.tall, style: .light) {
        Self.screen(Self.board)
      }
      try await Snapshot.capture("kit-progressboard-dark-contrast", size: Self.tall, contrast: .high) {
        Self.screen(Self.board)
      }
    }

    @Test func emptyBoard() async throws {
      try await Snapshot.capture("kit-progressboard-empty-dark", size: Self.phone) {
        Self.screen(ProgressBoard.empty)
      }
    }

    @Test func boardAtAccessibilitySize() async throws {
      try await Snapshot.capture(
        "kit-progressboard-dark-ax3", size: CGSize(width: 402, height: 4000),
        typeSize: .accessibility3
      ) { Self.screen(Self.board) }
    }

    // MARK: - Chart marks

    private static func point(
      _ session: SessionID, _ week: Int, _ load: Double, _ estimate: Double
    ) -> ProgressionPoint {
      ProgressionPoint(
        sessionID: session, machineID: nil, date: day.addingTimeInterval(Double(week) * 604_800),
        heaviestLoadKg: load, bestEstimatedOneRepMaxKg: estimate, workingSets: 3,
        bestEstimateCertainty: .moderate)
    }

    /// One machine over five weeks: the second and fourth sessions set records and wear a star, and
    /// the table beneath lists the best reps at each weight used.
    private static func chart() -> some View {
      let sessions = (0..<5).map { _ in SessionID() }
      let points = [
        point(sessions[0], 0, 40, 53.3), point(sessions[1], 1, 40, 56), point(sessions[2], 2, 40, 56),
        point(sessions[3], 3, 42.5, 59.5), point(sessions[4], 4, 42.5, 59.5),
      ]
      let ledger = [
        BestAtWeight(weightKg: 42.5, reps: 10, achievedAt: day.addingTimeInterval(3 * 604_800)),
        BestAtWeight(weightKg: 40, reps: 12, achievedAt: day.addingTimeInterval(604_800)),
      ]
      return NavigationStack {
        ScrollView {
          ProgressionChartView(
            series: [
              .init(
                label: "Hammer Strength", points: points,
                recordSessionIDs: [sessions[1], sessions[3]], bestAtWeight: ledger)
            ],
            unit: .kilograms, onExplain: {}
          )
          .padding(Tokens.Spacing.loose)
        }
        .background(Tokens.Color.canvas)
        .hardsetNavigationTitle("Chest press")
      }
      .tint(Tokens.Color.plateBlue)
    }

    @Test func chartWithRecordMarksAndBestAtEachWeight() async throws {
      try await Snapshot.capture("kit-progresschart-records-dark", size: Self.tall) { Self.chart() }
      try await Snapshot.capture("kit-progresschart-records-light", size: Self.tall, style: .light) {
        Self.chart()
      }
      try await Snapshot.capture(
        "kit-progresschart-records-dark-ax3", size: CGSize(width: 402, height: 3200),
        typeSize: .accessibility3
      ) { Self.chart() }
    }
  }
#endif
