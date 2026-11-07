#if canImport(UIKit)
  import Foundation
  import GRDB
  import HardsetCore
  import HardsetFeature
  import HardsetStore
  import HardsetUI
  import SwiftUI
  import Testing
  import UIKit

  /// Renders the app's screens to PNG files so the interface can be looked at.
  ///
  /// The development machine is Linux and cannot compile SwiftUI, so this suite is how the
  /// interface gets seen at all: CI runs it on the iOS Simulator with `HARDSET_SNAPSHOT_DIR` set
  /// and uploads the images. Without that variable every test returns at once, so an ordinary
  /// `xcodebuild test` or `swift test` is unaffected. It asserts nothing about pixels; it exists to
  /// be looked at, in both appearances, at the narrowest supported width, and at a large
  /// accessibility text size.
  @Suite("Screens render for review", .serialized)
  @MainActor
  struct ScreenSnapshotTests {
    // MARK: - Logger

    @Test func liveSession() async throws {
      try await Snapshot.capture("session-dark") { Fixtures.session() }
      try await Snapshot.capture("session-light", style: .light) { Fixtures.session() }
      try await Snapshot.capture("session-dark-375", size: Snapshot.narrow) { Fixtures.session() }
      try await Snapshot.capture("session-dark-ax3", typeSize: .accessibility3) {
        Fixtures.session()
      }
    }

    @Test func setRowsAndCard() async throws {
      try await Snapshot.capture("exercise-card-dark", size: Snapshot.short) {
        ScrollView {
          ExerciseSectionView(
            state: .constant(Fixtures.legPress()),
            unit: .kilograms,
            onLogSet: { _ in },
            onSelectMachine: {},
            onShowHistory: {}
          )
          .padding(Tokens.Spacing.regular)
        }
        .background(Tokens.Color.background)
      }
      try await Snapshot.capture("exercise-card-pounds-375", size: Snapshot.narrowShort) {
        ScrollView {
          ExerciseSectionView(
            state: .constant(Fixtures.legPress()),
            unit: .pounds,
            onLogSet: { _ in },
            onSelectMachine: {},
            onShowHistory: {}
          )
          .padding(Tokens.Spacing.regular)
        }
        .background(Tokens.Color.background)
      }
    }

    @Test func keypadAndRest() async throws {
      try await Snapshot.capture("keypad-dark", size: CGSize(width: 402, height: 520)) {
        NumericPad(
          buffer: .constant(
            NumericEntryBuffer(value: 102.5, maximumIntegerDigits: 4, maximumFractionDigits: 2)
          ),
          title: "Weight",
          unit: "kg",
          onDone: {},
          onNext: {}
        )
      }
      try await Snapshot.capture("restbar-dark-402", size: CGSize(width: 402, height: 200)) {
        VStack {
          Spacer()
          Fixtures.restBar()
        }
        .background(Tokens.Color.background)
      }
      // Paused shows static text, so this isolates the one-line layout from the live timer.
      try await Snapshot.capture("restbar-paused-440", size: CGSize(width: 440, height: 200)) {
        VStack {
          Spacer()
          Fixtures.restBar(paused: true)
        }
        .background(Tokens.Color.background)
      }
    }

    // MARK: - Analysis

    @Test func weeklyVolume() async throws {
      try await Snapshot.capture("volume-dark") { Fixtures.volume() }
      try await Snapshot.capture("volume-light", style: .light) { Fixtures.volume() }
    }

    @Test func history() async throws {
      try await Snapshot.capture("history-dark") { Fixtures.history() }
      try await Snapshot.capture("history-light", style: .light) { Fixtures.history() }
    }

    @Test func progression() async throws {
      try await Snapshot.capture("chart-dark") { Fixtures.chart() }
      try await Snapshot.capture("chart-light", style: .light) { Fixtures.chart() }
    }

    @Test func methodology() async throws {
      try await Snapshot.capture("methodology-dark") {
        MethodologySheet(source: SetCounting.source, certainty: .moderate)
      }
    }

    // MARK: - Pickers, entry, settings

    @Test func pickers() async throws {
      try await Snapshot.capture("exercise-picker-dark") {
        NavigationStack {
          ExercisePickerView(
            query: .constant(""),
            entries: ExerciseCatalog.v1.compactMap(\.catalogEntry)
          ) { _ in }
          .hardsetNavigationTitle("Add movement")
        }
      }
      try await Snapshot.capture("machine-picker-dark") {
        NavigationStack {
          MachinePickerView(
            recent: [
              MachineOption(
                id: MachineID(), displayName: "Hammer Strength Leg Press", stackIncrementKg: 10),
              MachineOption(id: MachineID(), displayName: "Cybex Leg Press", stackIncrementKg: 4.5),
            ],
            others: [MachineOption(id: MachineID(), displayName: "Panatta Leg Press")],
            selected: nil,
            unit: .kilograms,
            onSelect: { _ in },
            onAddMachine: {}
          )
          .hardsetNavigationTitle("Machine")
        }
      }
      try await Snapshot.capture("gym-picker-light", style: .light) {
        NavigationStack {
          GymPickerView(
            gyms: [
              GymOption(id: GymID(), name: "Metroflex Gym"),
              GymOption(id: GymID(), name: "Equinox Hudson Yards"),
            ],
            selected: nil,
            onSelect: { _ in },
            onAddGym: {}
          )
          .hardsetNavigationTitle("Where are you training?")
        }
      }
      try await Snapshot.capture("name-entry-dark", size: Snapshot.short) {
        NameEntrySheet(
          title: "Add a machine",
          prompt: "Name or brand",
          footnote: "Whatever you'd recognise it by.",
          onConfirm: { _ in },
          onCancel: {}
        )
      }
      try await Snapshot.capture("settings-dark") {
        SettingsSheet(useImperial: .constant(false)) {}
      }
    }

    @Test func components() async throws {
      try await Snapshot.capture("components-dark") { Fixtures.gallery() }
      try await Snapshot.capture("components-light", style: .light) { Fixtures.gallery() }
    }

    // MARK: - The real root view, on a real database

    /// The start screen as a lifter sees it after one finished workout: header, gym card, the
    /// start action and the last-workout card, with the tab bar beneath.
    @Test func startScreen() async throws {
      guard Snapshot.directory != nil else { return }
      let database = try Fixtures.database()
      let environment = HardsetEnvironment(database: database)
      try environment.catalog.seed()
      let gym = try environment.gyms.createGym(name: "Metroflex Gym")
      let coordinator = try SessionCoordinator.start(
        store: environment.logger, gymID: gym, plan: [], restAfterSet: nil
      )
      try Fixtures.logTwoSets(in: coordinator, catalog: environment.catalog)
      try coordinator.finish()

      try await Snapshot.capture("root-start-dark") {
        HardsetRootView(environment: environment, unit: .kilograms)
      }
      try await Snapshot.capture("root-start-light", style: .light) {
        HardsetRootView(environment: environment, unit: .kilograms)
      }
    }

    /// The live session wired to a real coordinator and database, as the Train tab shows it.
    /// Rendered outside the tab view: this renderer cannot draw the tab bar's glass accessory,
    /// which veiled the whole screen when it was included.
    @Test func liveSessionOnRealData() async throws {
      guard Snapshot.directory != nil else { return }
      let database = try Fixtures.database()
      let environment = HardsetEnvironment(database: database)
      try environment.catalog.seed()
      let gym = try environment.gyms.createGym(name: "Metroflex Gym")
      let coordinator = try SessionCoordinator.start(
        store: environment.logger, gymID: gym, plan: [], restAfterSet: nil
      )
      try Fixtures.logTwoSets(in: coordinator, catalog: environment.catalog)

      try await Snapshot.capture("live-session-real-dark") {
        NavigationStack {
          LiveSessionScreen(
            coordinator: coordinator,
            unit: .kilograms,
            catalog: environment.catalog,
            gyms: environment.gyms,
            progression: environment.progression,
            gymName: "Metroflex Gym",
            onShowSettings: {}
          )
          .hardsetTabRoot()
        }
      }
    }

    /// Outlined capsules drawn by SwiftUI's own renderer rather than through Core Animation, to
    /// tell a real drawing defect from an artefact of the layer renderer used everywhere else.
    @Test func capsulesThroughImageRenderer() async throws {
      guard let directory = Snapshot.directory else { return }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let strip = VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
        HStack {
          HardsetChip("All", isSelected: true) {}
          HardsetChip("Back", isSelected: false) {}
          HardsetChip("Shoulders", isSelected: false) {}
        }
        CertaintyBadge(level: .moderate, methodology: "Method.")
        CertaintyBadge(level: .high, methodology: "Method.")
      }
      .padding(Tokens.Spacing.loose)
      .frame(width: 402, alignment: .leading)
      .background(Tokens.Color.background)
      .environment(\.colorScheme, .dark)

      let renderer = ImageRenderer(content: strip)
      renderer.scale = 2
      let data = try #require(renderer.uiImage?.pngData())
      try data.write(to: directory.appendingPathComponent("capsules-imagerenderer-dark.png"))
    }

    /// Last on purpose: the first run stalled here, at the one width where the bar takes its
    /// one-line layout beside a live countdown. Kept separate so a stall cannot hide the rest.
    @Test func restBarRunningAtProMaxWidth() async throws {
      try await Snapshot.capture("restbar-running-440", size: CGSize(width: 440, height: 200)) {
        VStack {
          Spacer()
          Fixtures.restBar()
        }
        .background(Tokens.Color.background)
      }
    }
  }

  // MARK: - Rendering

  @MainActor
  enum Snapshot {
    static let phone = CGSize(width: 402, height: 874)
    static let narrow = CGSize(width: 375, height: 667)
    static let short = CGSize(width: 402, height: 560)
    static let narrowShort = CGSize(width: 375, height: 560)

    static let directory: URL? = ProcessInfo.processInfo.environment["HARDSET_SNAPSHOT_DIR"]
      .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    /// Hosts `content` in a window of `size`, lets its tasks and first layout run, and writes the
    /// result at 2x to `<name>.png`.
    static func capture<Content: View>(
      _ name: String,
      size: CGSize = Snapshot.phone,
      style: UIUserInterfaceStyle = .dark,
      typeSize: DynamicTypeSize = .large,
      @ViewBuilder _ content: () -> Content
    ) async throws {
      guard let directory else { return }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let host = UIHostingController(
        rootView: content()
          .environment(\.dynamicTypeSize, typeSize)
          .environment(\.colorScheme, style == .dark ? .dark : .light)
      )
      host.overrideUserInterfaceStyle = style
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.overrideUserInterfaceStyle = style
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.layoutIfNeeded()
      // `.task` modifiers, database reads and the first full layout land on later run-loop turns.
      try await Task.sleep(for: .milliseconds(800))
      host.view.layoutIfNeeded()

      let format = UIGraphicsImageRendererFormat()
      format.scale = 2
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
          window.layer.render(in: context.cgContext)
        }
      }
      let data = try #require(image.pngData())
      try data.write(to: directory.appendingPathComponent("\(name).png"))
      window.isHidden = true
      window.rootViewController = nil
    }
  }

  // MARK: - Fixtures

  @MainActor
  enum Fixtures {
    static let day = Date(timeIntervalSince1970: 1_793_000_000)

    /// An in-memory database migrated exactly as the app's is, as the Store suites build theirs.
    static func database() throws -> DatabaseQueue {
      var configuration = Configuration()
      configuration.foreignKeysEnabled = true
      let queue = try DatabaseQueue(configuration: configuration)
      try HardsetMigrations.migrator().migrate(queue)
      return queue
    }

    /// Adds the first two catalogue movements and logs a set on each, through the coordinator's
    /// real write path.
    static func logTwoSets(in coordinator: SessionCoordinator, catalog: CatalogSeeder) throws {
      let entries = try catalog.search("Press")
      for (offset, entry) in entries.prefix(2).enumerated() {
        _ = coordinator.addExercise(entry, plannedSets: 3)
        guard let state = coordinator.exercises.last, let slot = state.slots.first else { continue }
        let index = coordinator.exercises.count - 1
        coordinator.exercises[index].slots[0].draft = SetEntryDraft(
          weightKg: offset == 0 ? 100 : 60, reps: 8
        )
        _ = coordinator.logSet(slotID: slot.id, inExercise: state.id)
      }
    }

    static func legPress() -> ExerciseLogState {
      let exercise = ExerciseID()
      let machine = MachineID()
      let key = ProgressionKey(exerciseID: exercise, machineID: machine)
      let records = [
        PriorSetRecord(weightKg: 100, reps: 10, completedAt: .distantPast),
        PriorSetRecord(weightKg: 105, reps: 8, completedAt: .distantPast),
        PriorSetRecord(weightKg: 60, reps: 12, completedAt: .distantPast),
      ]
      let snapshot = PriorPerformanceSnapshot(
        entries: [key: PriorPerformance(key: key, lastSets: records, heaviestSet: records[1])],
        capturedAt: .distantPast
      )
      var state = ExerciseLogState.build(
        exerciseID: exercise,
        machineID: machine,
        exerciseName: "Leg Press",
        machineName: "Hammer Strength",
        machineIncrementKg: 10,
        snapshot: snapshot
      )
      state.markLogged(slotID: state.slots[0].id, setID: SetID())
      state.appendSlot(isWarmup: true)
      return state
    }

    static func session() -> some View {
      SessionView(
        exercises: .constant([
          legPress(),
          .build(
            exerciseID: ExerciseID(),
            exerciseName: "Standing Calf Raise",
            snapshot: .empty(capturedAt: .distantPast)
          ),
        ]),
        unit: .kilograms,
        title: "Workout",
        gymName: "Metroflex Gym",
        restState: .running(endsAt: Date().addingTimeInterval(96)),
        restMetadata: RestMetadata(
          exerciseName: "Leg Press", setOrdinal: 1, plannedSets: 3, machineName: "Hammer Strength"
        ),
        records: [
          PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 8, previousWeightKg: 100),
          PersonalRecord(kind: .estimatedOneRepMax, weightKg: 128, reps: 8, previousWeightKg: 122),
        ],
        onLogSet: { _, _ in },
        onAddExercise: {},
        onSelectMachine: { _ in },
        onShowHistory: { _ in },
        onShowSettings: {}
      )
    }

    static func restBar(paused: Bool = false) -> some View {
      RestBarView(
        state: paused ? .paused(remaining: .seconds(96)) : .running(endsAt: Date().addingTimeInterval(96)),
        metadata: RestMetadata(
          exerciseName: "Leg Press", setOrdinal: 2, plannedSets: 4, machineName: "Hammer Strength"
        ),
        onAdjust: { _ in },
        onPauseResume: {},
        onSkip: {}
      )
    }

    static func volume() -> some View {
      VolumeReportView(
        report: MuscleVolumeReport(
          fractionalSets: [
            MuscleKey(.chest): 12, MuscleKey(.lats): 9, MuscleKey(.quadriceps): 8,
            MuscleKey(.triceps): 6.5, MuscleKey(.biceps): 6, MuscleKey(.upperBack): 5,
            MuscleKey(.frontDelts): 4, MuscleKey(.hamstrings): 3, MuscleKey(.glutes): 3,
            MuscleKey(.sideDelts): 2, MuscleKey(.neck): 1,
          ],
          hardSets: 34,
          unattributedHardSets: 3,
          setsTouchingGroup: [.chest: 12, .back: 14, .legs: 11, .arms: 12, .shoulders: 6]
        ),
        excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
        title: "This week",
        subtitle: "Last 7 days",
        onExplainCounting: {}
      )
    }

    static func history() -> some View {
      HistoryView(
        rows: [
          HistoryRow(
            id: SessionID(), title: "Push", date: day,
            duration: .seconds(4_320),
            exerciseNames: ["Bench Press", "Overhead Press", "Cable Triceps Pushdown"],
            volume: SessionVolume(workingSets: 12, warmupSets: 2, volumeKg: 9_400, reps: 96),
            hasImplausibleDuration: false
          ),
          HistoryRow(
            id: SessionID(), title: "Legs", date: day.addingTimeInterval(-172_800),
            duration: .seconds(72_000),
            exerciseNames: ["Barbell Back Squat", "Romanian Deadlift"],
            volume: SessionVolume(workingSets: 8, warmupSets: 3, volumeKg: 11_200, reps: 64),
            hasImplausibleDuration: true
          ),
          HistoryRow(
            id: SessionID(), title: "", date: day.addingTimeInterval(-2_678_400),
            duration: .seconds(2_700),
            exerciseNames: ["Lat Pulldown"],
            volume: SessionVolume(workingSets: 4, warmupSets: 0, volumeKg: 2_100, reps: 40),
            hasImplausibleDuration: false
          ),
        ],
        unit: .kilograms,
        title: "History"
      )
    }

    static func chart() -> some View {
      func point(_ n: Int, _ load: Double, _ estimate: Double?) -> ProgressionPoint {
        ProgressionPoint(
          sessionID: SessionID(), machineID: nil,
          date: day.addingTimeInterval(Double(n) * 604_800),
          heaviestLoadKg: load, bestEstimatedOneRepMaxKg: estimate, workingSets: 3
        )
      }
      return ScrollView {
        ProgressionChartView(
          series: [
            .init(
              label: "Hammer Strength",
              points: [point(0, 100, 116), point(1, 105, 122), point(2, 110, 128)]
            ),
            .init(label: "Cybex", points: [point(3, 85, 99), point(4, 90, 105)]),
          ],
          machineChanges: [
            MachineChange(
              date: day.addingTimeInterval(3 * 604_800),
              fromMachineID: MachineID(), toMachineID: MachineID(),
              heaviestLoadDeltaKg: -25
            )
          ],
          unit: .kilograms,
          onExplain: {}
        )
        .padding(Tokens.Spacing.loose)
      }
      .background(Tokens.Color.background)
    }

    static func gallery() -> some View {
      ScrollView {
        VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
          ScreenHeader("Train", subtitle: "Saturday 7 November") {
            HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {}
          }
          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            SectionLabel("Chest", count: 6)
            HardsetSegmentedControl(
              selection: .constant(false),
              segments: [HardsetSegment("kg", value: false), HardsetSegment("lb", value: true)]
            )
            HStack {
              HardsetChip("All", isSelected: true) {}
              HardsetChip("Back", isSelected: false) {}
              HardsetChip("Legs", isSelected: false) {}
            }
            StatLedger([
              .init(label: "Working sets", value: "12"),
              .init(label: "Reps", value: "96"),
              .init(label: "Volume", value: "9,400", unit: "kg"),
            ])
            HardsetBanner(.record, title: "Heaviest weight", message: "105 kg, up from 100 kg")
            HardsetBanner(.caveat, message: "Counts below are lower bounds.")
            HardsetBanner(.error, message: "That set could not be saved. It has not been logged.")
            ForEach(CertaintyLevel.allCases, id: \.self) { level in
              CertaintyBadge(level: level, methodology: "Method.", citation: nil)
            }
            Button("Start workout") {}
              .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
            Button("Finish workout") {}
              .buttonStyle(HardsetButtonStyle(.secondary))
            Button("How sets are counted") {}
              .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
            HardsetEmptyState(
              title: "Nothing added yet",
              detail: "Add a movement to start logging sets.",
              systemImage: "dumbbell",
              actionTitle: "Add movement",
              action: {}
            )
          }
          .padding(.horizontal, Tokens.Spacing.loose)
        }
      }
      .background(Tokens.Color.background)
    }
  }
#endif
