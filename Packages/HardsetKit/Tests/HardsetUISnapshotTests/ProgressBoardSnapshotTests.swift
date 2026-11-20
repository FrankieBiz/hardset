#if canImport(UIKit)
  import Foundation
  import GRDB
  import HardsetStore
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

    @Test func matchedImportedHistory() async throws {
      let database = try DatabaseQueue()
      try HardsetMigrations.migrator().migrate(database)
      let movement = try CatalogSeeder(database: database).createCustomExercise(named: "Chest Press")
      let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n"
        + "2026-09-20 10:00:00,Push,1h,Chest Press,1,40,8\n"
        + "2026-11-01 10:00:00,Push,1h,chest press,1,45,8\n"
      let preview = try WorkoutCSVImport.preview(csv, strongUnit: .kilograms)
      _ = try await DataTransferStore(database: database).importWorkouts(preview)
      let board = try await ProgressBoardStore(database: database).loadBoard()
      let history = try await ProgressionStore(database: database).loadHistory(for: movement.id)
      for light in [false, true] {
        let style: UIUserInterfaceStyle = light ? .light : .dark
        let suffix = light ? "light" : "dark"
        try await Snapshot.capture("kit-progressboard-imported-" + suffix, size: Self.tall, style: style) {
          Self.screen(board)
        }
        try await Snapshot.capture("kit-progresschart-imported-" + suffix, size: Self.tall, style: style) {
          NavigationStack {
            ScrollView {
              ProgressionChartView(series: history.series.map {
                .init(label: history.label(for: $0.key), points: $0.points,
                  recordSessionIDs: history.recordSessionIDs[$0.key] ?? [],
                  bestAtWeight: history.bestAtWeight[$0.key] ?? [])
              }, unit: .kilograms, onExplain: {})
              .padding(Tokens.Spacing.loose)
            }
            .background(Tokens.Color.canvas)
            .hardsetNavigationTitle("Chest Press")
          }
          .tint(Tokens.Color.plateBlue)
        }
      }
      try await Snapshot.capture("kit-progresschart-imported-ax3", size: CGSize(width: 402, height: 3000),
        typeSize: .accessibility3) {
        NavigationStack {
          ScrollView {
            ProgressionChartView(series: history.series.map {
              .init(label: history.label(for: $0.key), points: $0.points,
                recordSessionIDs: history.recordSessionIDs[$0.key] ?? [],
                bestAtWeight: history.bestAtWeight[$0.key] ?? [])
            }, unit: .kilograms, onExplain: {})
            .padding(Tokens.Spacing.loose)
          }
          .background(Tokens.Color.canvas)
          .hardsetNavigationTitle("Chest Press")
        }
        .tint(Tokens.Color.plateBlue)
      }
    }

    @Test func changeWithWeakerPriorEstimate() async throws {
      let key = ProgressionKey(exerciseID: ExerciseID(), machineID: MachineID())
      let samples = [
        ProgressionSample(sessionID: SessionID(), machineID: key.machineID, weightKg: 40, reps: 12,
          completedAt: Self.day.addingTimeInterval(-42 * 86_400)),
        ProgressionSample(sessionID: SessionID(), machineID: key.machineID, weightKg: 60, reps: 5,
          completedAt: Self.day),
      ]
      let trend = try #require(ProgressTrendAnalyzer.trend(key: key, samples: samples,
        incrementKg: 2.5, estimatesOneRepMax: true))
      let board = ProgressBoard.make([.init(row: .init(trend: trend, exerciseName: "Chest press",
        machineName: "Hammer Strength"), bodyPart: .chest)])
      try await Snapshot.capture("kit-progressboard-weaker-certainty-dark", size: Self.tall) { Self.screen(board) }
      try await Snapshot.capture("kit-progressboard-weaker-certainty-light", size: Self.tall, style: .light) { Self.screen(board) }
      try await Snapshot.capture("kit-progressboard-weaker-certainty-ax3", size: CGSize(width: 402, height: 2400),
        typeSize: .accessibility3) { Self.screen(board) }
    }

    @Test func mixedMetricsNeverShareARanking() async throws {
      let rows = [
        Self.row("Chest press", machine: "Hammer Strength", metric: .estimatedMax, change: 0.08, certainty: .high),
        Self.row("High-rep squat", machine: nil, metric: .heaviestLoad, change: 0.9),
        Self.row("Pull-up", machine: nil, metric: .repsAtTopLoad, change: 0.99),
      ]
      let board = ProgressBoard.make(rows.map { .init(row: $0, bodyPart: .chest) })
      try await Snapshot.capture("kit-progressboard-mixed-metrics-dark", size: Self.tall) { Self.screen(board) }
      try await Snapshot.capture("kit-progressboard-mixed-metrics-light", size: Self.tall, style: .light) { Self.screen(board) }
      try await Snapshot.capture("kit-progressboard-mixed-metrics-ax3", size: CGSize(width: 402, height: 3000),
        typeSize: .accessibility3) { Self.screen(board) }
    }

    @Test func machineMovementWithoutMachineIdentity() async throws {
      let database = try DatabaseQueue()
      try HardsetMigrations.migrator().migrate(database)
      let catalog = CatalogSeeder(database: database)
      try catalog.seed(now: Self.day)
      let lift = try #require(try catalog.selectableExercises().first { $0.modality == .machine })
      let logger = LoggerStore(database: database)
      let session = try logger.startSession(at: Self.day)
      try logger.logSet(sessionID: session, exerciseID: lift.id,
        draft: .init(weightKg: 40, reps: 8), at: Self.day)
      try logger.finishSession(session, at: Self.day.addingTimeInterval(3600))
      let board = try await ProgressBoardStore(database: database).loadBoard()
      let history = try await ProgressionStore(database: database).loadHistory(for: lift.id)
      try await Snapshot.capture("kit-progressboard-no-machine-dark", size: Self.phone) { Self.screen(board) }
      try await Snapshot.capture("kit-progressboard-no-machine-light", size: Self.phone, style: .light) { Self.screen(board) }
      try await Snapshot.capture("kit-progressboard-no-machine-ax3", size: CGSize(width: 402, height: 2400),
        typeSize: .accessibility3) { Self.screen(board) }
      for accessible in [false, true] {
        let suffix = accessible ? "ax3" : "dark"
        try await Snapshot.capture("kit-progresschart-no-machine-" + suffix,
          size: CGSize(width: 402, height: accessible ? 2400 : 1400),
          typeSize: accessible ? .accessibility3 : .large) {
          NavigationStack {
            ScrollView {
              ProgressionChartView(series: history.series.map {
                .init(label: history.label(for: $0.key), points: $0.points)
              }, unit: .kilograms, onExplain: {})
              .padding(Tokens.Spacing.loose)
            }
            .background(Tokens.Color.canvas)
            .hardsetNavigationTitle(lift.name)
          }
          .tint(Tokens.Color.plateBlue)
        }
      }
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
