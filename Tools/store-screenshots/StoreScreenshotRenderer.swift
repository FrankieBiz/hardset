// App Store gallery renderer.
//
// This file is NOT part of the package. `Tools/render_store_screenshots.sh` copies it into
// Packages/HardsetKit/Tests/HardsetUISnapshotTests for the duration of one run, builds that test
// target for the iOS Simulator, renders the four gallery screens at the two required App Store
// pixel sizes, and removes it again. Keeping it here means the kit adds no test target, no test
// assertion and no CI step to the shipping project.
//
// What it does reuse is the existing render path: the real `SessionView`, `VolumeReportView` and
// `ProgressBoardView`, the real `Tokens` type, and the same `UIHostingController` + `UIWindow`
// capture technique as `ScreenSnapshotTests.Snapshot`. Nothing is drawn by hand.
#if canImport(UIKit)
  import Foundation
  import HardsetCore
  import HardsetStore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  @MainActor
  @Suite("App Store gallery renders", .serialized)
  struct StoreScreenshotTests {
    /// 6.9-inch (iPhone 16/17 Pro Max class): 440 x 956 pt at 3x = 1320 x 2868 px.
    /// 6.5-inch (iPhone 11 Pro Max class): 414 x 896 pt at 3x = 1242 x 2688 px.
    private static let sizes: [(label: String, size: CGSize, pixels: String)] = [
      ("6.9", CGSize(width: 440, height: 956), "1320x2868"),
      ("6.5", CGSize(width: 414, height: 896), "1242x2688"),
    ]

    @Test func renderGallery() async throws {
      guard let directory = ProcessInfo.processInfo.environment["HARDSET_STORE_SHOT_DIR"]
        .flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) })
      else { return }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      for spec in Self.sizes {
        try await Self.capture(
          "01-train-\(spec.label)", size: spec.size, directory: directory
        ) {
          Self.Shot(caption: "It tells you when it's estimating.") { Self.session() }
        }
        try await Self.capture(
          "02-volume-\(spec.label)", size: spec.size, directory: directory
        ) {
          Self.Shot(caption: "Shows its math. Refuses to invent targets.") { Self.volume() }
        }
        try await Self.capture(
          "03-progress-\(spec.label)", size: spec.size, directory: directory
        ) {
          Self.Shot(caption: "Different machines. Never merged.") { Self.progress() }
        }
        try await Self.capture(
          "04-muscle-history-\(spec.label)", size: spec.size, directory: directory
        ) {
          Self.Shot(caption: "Muscle history. One purchase, no subscription.") {
            Self.muscleHistory()
          }
        }
      }
    }

    // MARK: - The gallery card

    /// One App Store image: the plan's caption in the app's own `display` type, then the real
    /// screen at the remaining height. The caption is part of the store image, not of the app.
    private struct Shot<Content: View>: View {
      let caption: String
      @ViewBuilder let content: Content

      var body: some View {
        VStack(alignment: .leading, spacing: 0) {
          Text(caption)
            .font(Tokens.Text.display)
            .foregroundStyle(Tokens.Color.chalk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
          content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Tokens.Color.canvas)
        .environment(\.colorScheme, .dark)
      }
    }

    // MARK: - The four screens

    /// Points of the live session hosted above the card's top edge, so its rows clear the pinned stack.
    /// 240 pt at the 6.5-inch card and 197 at the 6.9, measured once the list has settled (the
    /// capture waits three seconds, because the session scrolls itself to the next set to log).
    /// Each lands the card's top edge on a clean boundary: the 6.5 starts at the first set row and
    /// the 6.9 at the column header, and both end with the third row whole above the notice, so no
    /// line of text is cut through its glyphs. A change here needs a look at both renders.
    private static func sessionCrop(for cardHeight: CGFloat) -> CGFloat {
      cardHeight > 820 ? 197 : 240
    }

    private static func session() -> some View {
      // Same-machine history, so every mark on this screen is one the app can produce: last time
      // was 215 lb x 8 on this machine, today's two logged sets are 225 lb x 8 (a real +10 lb
      // beat, exactly one 10 lb step), and the third row is the next set to log. No `priorNote`:
      // a note about another machine would contradict the same-machine history.
      let exerciseID = ExerciseID()
      let machineID = MachineID()
      let key = ProgressionKey(exerciseID: exerciseID, machineID: machineID)
      let lastTimeKg = WeightUnit.pounds.toKilograms(215)
      let todayKg = WeightUnit.pounds.toKilograms(225)
      let stepKg = WeightUnit.pounds.toKilograms(10)
      let lastTime = PriorSetRecord(weightKg: lastTimeKg, reps: 8, completedAt: .distantPast)
      let history = PriorPerformance(
        key: key,
        lastSets: [lastTime, lastTime, lastTime],
        heaviestSet: lastTime
      )
      var state = ExerciseLogState(
        exerciseID: exerciseID,
        machineID: machineID,
        exerciseName: "Incline Chest Press",
        machineName: "Plate-Loaded Incline",
        machineIncrementKg: stepKg,
        prior: history,
        weightUnit: .pounds,
        slots: [
          SetSlot(draft: SetEntryDraft(weightKg: todayKg, reps: 8)),
          SetSlot(draft: SetEntryDraft(weightKg: todayKg, reps: 8)),
          SetSlot(draft: SetEntryDraft(weightKg: todayKg, reps: 8)),
        ]
      )
      // What the logger computes for a set logged today: the comparison excludes the current
      // session, so it is the same-machine history above, and not the first logged set.
      let records = PersonalRecordDetector.records(
        for: PersonalRecordDetector.Candidate(weightKg: todayKg, reps: 8),
        history: history.lastSets,
        increment: stepKg)
      state.markLogged(slotID: state.slots[0].id, setID: SetID())
      state.markLogged(slotID: state.slots[1].id, setID: SetID())
      let meter = RestMetadata(
        exerciseName: "Incline Chest Press", setOrdinal: 2, plannedSets: 3,
        machineName: "Plate-Loaded Incline", totalRest: .seconds(102))

      let screen = SessionView(
        exercises: .constant([state]),
        unit: .pounds,
        title: "Workout",
        gymName: "Metroflex Gym",
        startedAt: Date().addingTimeInterval(-1_800),
        lastLoggedAt: Date(),
        restState: .running(endsAt: Date().addingTimeInterval(102)),
        restMetadata: meter,
        records: records,
        recordsExerciseName: "Incline Chest Press",
        onLogSet: { _, _ in },
        onAddExercise: {},
        onSelectMachine: { _ in },
        onShowHistory: { _ in },
        onShowSettings: {},
        onFinish: {}
      )
      // Two records stack a tall notice on the rest bar, and together they cover the rows. The
      // real screen is hosted taller than the card and anchored at the bottom, so the card shows
      // its lower part: the logged rows, the next-up row, the notice and the rest bar. Nothing is
      // drawn or moved; the part cropped away is the title, the gym line and the machine line.
      return GeometryReader { proxy in
        screen
          .frame(width: proxy.size.width, height: proxy.size.height + Self.sessionCrop(for: proxy.size.height))
          .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
          .clipped()
      }
    }

    private static func volume() -> some View {
      VolumeReportView(
        report: MuscleVolumeReport(
          fractionalSets: [
            MuscleKey(.chest): 10,
            MuscleKey(.frontDelts): 7.5,
            MuscleKey(.triceps): 6,
            MuscleKey(.lats): 5,
            MuscleKey(.biceps): 3,
          ],
          hardSets: 14,
          unattributedHardSets: 0,
          setsTouchingGroup: [.chest: 8, .shoulders: 7, .arms: 9, .back: 5]
        ),
        excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
        title: "Volume",
        subtitle: "Last 7 days",
        onExplainCounting: {},
        onShowSettings: {},
        onShowWorking: { _ in },
        onShowTotalWorking: {}
      )
    }

    private static func progress() -> some View {
      let day = Date(timeIntervalSince1970: 1_793_000_000)
      func row(
        _ name: String, machine: String?, metric: TrendMetric, change: Double?,
        stalled: Int? = nil, certainty: Certainty? = nil,
        sparkline: [Double] = [50, 52, 51, 55, 57, 60]
      ) -> ProgressBoard.Row {
        ProgressBoard.Row(
          trend: MovementTrend(
            key: ProgressionKey(
              exerciseID: ExerciseID(), machineID: machine == nil ? nil : MachineID()),
            metric: metric, sparkline: sparkline, sixWeekChange: change, sessionCount: 6,
            stalledSessions: stalled, latestDate: day, certainty: certainty),
          exerciseName: name, machineName: machine)
      }

      let chest = row(
        "Chest Press", machine: "Hammer Strength", metric: .estimatedMax, change: 0.08,
        certainty: .moderate)
      let incline = row(
        "Leg Press", machine: "45° Incline Sled", metric: .estimatedMax, change: 0.12,
        certainty: .moderate)
      let cable = row(
        "Leg Press", machine: "Horizontal Cable Sled", metric: .estimatedMax, change: nil,
        certainty: nil, sparkline: [82, 84, 83])
      let press = row(
        "Overhead Press", machine: "Barbell", metric: .heaviestLoad, change: nil,
        stalled: 3, certainty: nil)
      let board = ProgressBoard(
        sections: [
          ProgressBoard.Section(category: .quads, rows: [incline, cable, press])
        ],
        mostImproved: [incline, cable, chest])

      return NavigationStack {
        ProgressBoardView(
          board: board, title: "Progress", subtitle: "4 movements",
          onShowSettings: {}, onSelect: { _ in }
        )
        .hardsetTabRoot()
      }
      .tint(Tokens.Color.plateBlue)
      .background(Tokens.Color.canvas.ignoresSafeArea())
    }

    /// Muscle history, the paid screen, built by `MuscleHistoryAnalyzer.history` from counts and
    /// weekly reports that are themselves derived from one attribution, so no figure is typed.
    /// Incline Chest Press credits Chest directly and Front delts indirectly; every other muscle,
    /// Side delts included, reads "No credited sets". Twelve weeks, one of them zero, the last four
    /// above the four before, and no imported history.
    private static func muscleHistory() -> some View {
      let now = Date(timeIntervalSince1970: 1_793_527_200)
      let day = 86_400.0
      let incline = ExerciseID()
      let contributions = [
        MuscleContribution(.chest, role: .direct, certainty: .moderate, source: .anatomy),
        MuscleContribution(.frontDelts, role: .indirect, certainty: .moderate, source: .anatomy),
      ]
      // Working sets of the movement per week, newest first. The zero is week ten.
      let setsPerWeek = [6, 5, 5, 4, 3, 4, 3, 3, 4, 0, 3, 2]
      let weeks = setsPerWeek.enumerated().map { item -> MuscleHistoryWeek in
        let range = VolumeWindowRange(endingAt: now, weeksBack: item.offset)
        var fractional: [MuscleKey: Double] = [:]
        for contribution in contributions where item.element > 0 {
          fractional[contribution.key, default: 0] += Double(item.element) * contribution.setWeight
        }
        return MuscleHistoryWeek(
          start: range.start, end: range.end, lastDay: range.lastDay,
          report: MuscleVolumeReport(
            fractionalSets: fractional, hardSets: item.element, unattributedHardSets: 0,
            setsTouchingGroup: [:]),
          sets: [])
      }
      let history = MuscleHistoryAnalyzer.history(
        counts: [
          MuscleHistoryCount(
            exerciseID: incline, setCount: setsPerWeek.reduce(0, +),
            lastAt: now - 1 * day, firstAt: now - 80 * day)
        ],
        weeks: weeks,
        attribution: AttributionIndex([incline: contributions]),
        imported: [],
        names: [incline: "Incline Chest Press"])

      let sheet = ScrollView {
        MuscleHistoryView(history: history, onShowWorking: { _, _ in })
      }
      .background(Tokens.Color.canvas)

      // The sheet is hosted taller than the card and anchored at the bottom, so the card shows
      // its lower part: the rows for Chest, Front delts and Side delts rather than the
      // sheet's title and explanatory text above them. The sheet's navigation title is cropped
      // away with them; nothing is drawn or moved by hand.
      return GeometryReader { proxy in
        sheet
          .frame(width: proxy.size.width, height: proxy.size.height + Self.sheetCrop)
          .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
          .clipped()
      }
    }

    /// Points of the muscle history sheet hosted above the card's top edge.
    private static let sheetCrop: CGFloat = 270

    // MARK: - Rendering

    private enum RenderError: Error { case noImage }

    /// Hosts the card in a window of `size`, lets the first layout and the views' own tasks
    /// settle, and writes the frame at 3x: the native pixel density of both target devices.
    private static func capture<Content: View>(
      _ name: String, size: CGSize, directory: URL,
      @ViewBuilder _ content: () -> Content
    ) async throws {
      let host = UIHostingController(rootView: content())
      host.overrideUserInterfaceStyle = .dark
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.overrideUserInterfaceStyle = .dark
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.layoutIfNeeded()
      try await Task.sleep(for: .milliseconds(3_000))
      host.view.layoutIfNeeded()

      let format = UIGraphicsImageRendererFormat()
      format.scale = 3
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
          window.layer.render(in: context.cgContext)
        }
      }
      guard let data = image.pngData() else { throw RenderError.noImage }
      try data.write(to: directory.appendingPathComponent("\(name).png"))
      window.isHidden = true
      window.rootViewController = nil
    }
  }
#endif
