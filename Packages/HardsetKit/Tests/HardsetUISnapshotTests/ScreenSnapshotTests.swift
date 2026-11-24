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
    @Test func workoutReceipt() async throws {
      let receipt = WorkoutReceipt(id: SessionID(), title: "Push", startedAt: Date(timeIntervalSince1970: 1793527200),
        finishedAt: Date(timeIntervalSince1970: 1793530800), lines: [
          .init(id: SetID(), exerciseName: "Incline Press", machineName: "Cybex · Station 2", weightKg: 80, reps: 8,
            isWarmup: false, records: [.init(kind: .heaviestLoad, weightKg: 80, reps: 8, previousWeightKg: 75)]),
          .init(id: SetID(), exerciseName: "Press (Imported • Strong)", machineName: nil, weightKg: 60, reps: 10,
            isWarmup: false, isImported: true),
        ])
      try await Snapshot.capture("receipt-dark-375", size: Snapshot.narrow) {
        ScrollView { WorkoutReceiptView(receipt: receipt, unit: .kilograms) }
          .background(Tokens.Color.canvas)
      }
      try await Snapshot.capture("receipt-light-ax3", style: .light, typeSize: .accessibility3) {
        ScrollView { WorkoutReceiptView(receipt: receipt, unit: .pounds) }
          .background(Tokens.Color.canvas)
      }
    }

    /// The scorecard at the top of a finished workout's receipt: a record on the yellow surface, the
    /// biggest gain, a win, a record with no beaten pair, a match and a first time, in both
    /// appearances, at the narrowest width and at an accessibility size.
    @Test func workoutReceiptScorecard() async throws {
      func key() -> ProgressionKey { ProgressionKey(exerciseID: ExerciseID()) }
      func entry(
        _ name: String, _ outcome: WorkoutScorecard.Outcome,
        equipment: WorkoutReceipt.Equipment? = nil
      ) -> WorkoutScorecard.Entry {
        WorkoutScorecard.Entry(
          key: key(), exerciseName: name, outcome: outcome, equipment: equipment)
      }
      let scorecard = WorkoutScorecard(
        entries: [
          entry("Incline Press", .beat(.beat(addedKg: 0, addedReps: 1)),
            equipment: .machine("Cybex · Station 2")),
          entry("Cable Row", .beat(.beat(addedKg: 2.5, addedReps: 1))),
          entry("Pec Deck", .beat(nil)),
          entry("Lateral Raise", .matched),
          // A machine first time says so; a barbell one has no machine to name.
          entry("Hack Squat", .firstTime, equipment: .machine("Hack Squat Sled")),
          entry("Barbell Row", .firstTime, equipment: .freeWeight),
          entry("Curl", .notBeaten),
        ],
        beatenCount: 3, comparedCount: 5, recordMovementCount: 2,
        biggestGain: .init(
          key: key(), exerciseName: "Incline Press", fraction: 0.0625, metric: .estimatedMax,
          certainty: .moderate,
          basis: ScorecardInput(
            key: key(), exerciseName: "Incline Press",
            currentSets: [PriorSetRecord(weightKg: 80, reps: 9, completedAt: .distantPast)],
            previousSets: [PriorSetRecord(weightKg: 80, reps: 8, completedAt: .distantPast)])))
      let receipt = WorkoutReceipt(
        id: SessionID(), title: "Push", startedAt: Date(timeIntervalSince1970: 1793527200),
        finishedAt: Date(timeIntervalSince1970: 1793530800),
        lines: [
          .init(id: SetID(), exerciseName: "Incline Press", machineName: "Cybex · Station 2",
            weightKg: 80, reps: 9, isWarmup: false)
        ],
        scorecard: scorecard)
      try await Snapshot.capture("receipt-scorecard-dark-375", size: Snapshot.narrow) {
        ScrollView { WorkoutReceiptView(receipt: receipt, unit: .kilograms) }
          .background(Tokens.Color.canvas)
      }
      try await Snapshot.capture("receipt-scorecard-light-375", size: Snapshot.narrow, style: .light) {
        ScrollView { WorkoutReceiptView(receipt: receipt, unit: .pounds) }
          .background(Tokens.Color.canvas)
      }
      try await Snapshot.capture("receipt-scorecard-dark-ax3", typeSize: .accessibility3) {
        ScrollView { WorkoutReceiptView(receipt: receipt, unit: .kilograms) }
          .background(Tokens.Color.canvas)
      }
      // On the screen, where the gain opens the sets it was worked from. The renders above are what
      // the shared image holds, which never has the control.
      try await Snapshot.capture("receipt-scorecard-working-dark-375", size: Snapshot.narrow) {
        ScrollView { WorkoutReceiptView(receipt: receipt, unit: .kilograms, onExplainGain: {}) }
          .background(Tokens.Color.canvas)
      }
    }

    @Test func machineLoadStep() async throws {
      try await Snapshot.capture("machine-step-pounds-375", size: Snapshot.narrow) {
        LoadStepSheet(machineName: "Cybex Leg Press", incrementKg: 2.5, unit: .pounds, onSave: { _ in true }, onCancel: {})
      }
    }

    @Test func deepMuscleMap() async throws {
      let report = MuscleVolumeReport(fractionalSets: [MuscleKey(.chest): 8, MuscleKey(.triceps): 4],
        hardSets: 10, unattributedHardSets: 2, setsTouchingGroup: [:])
      try await Snapshot.capture("muscle-map-dark-375", size: Snapshot.narrow) {
        ScrollView { MuscleHeatmapView(report: report) }.background(Tokens.Color.canvas)
      }
      try await Snapshot.capture("muscle-map-light-ax3", style: .light, typeSize: .accessibility3) {
        ScrollView { MuscleHeatmapView(report: report) }.background(Tokens.Color.canvas)
      }
    }

    // MARK: - Logger

    @Test func liveSession() async throws {
      try await Snapshot.capture("session-dark") { Fixtures.session() }
      try await Snapshot.capture("session-light", style: .light) { Fixtures.session() }
      try await Snapshot.capture("session-dark-375", size: Snapshot.narrow) { Fixtures.session() }
      try await Snapshot.capture("session-dark-ax3", typeSize: .accessibility3) {
        Fixtures.session()
      }
      // Increase Contrast brings back the outlines that the monochrome session draws without: the
      // editable figures, the inline controls and the panels.
      try await Snapshot.capture("session-dark-contrast", contrast: .high) { Fixtures.session() }
      try await Snapshot.capture("session-light-ax3", style: .light, typeSize: .accessibility3) {
        Fixtures.session()
      }
    }

    /// The list with nothing pinned over it, so every row can be seen. The first row not yet written
    /// is a blank warm-up, which cannot be logged, so the one blue control is the working set behind
    /// it: the primary action owns the accent wherever its row sits.
    @Test func liveSessionPrimaryAction() async throws {
      let tall = CGSize(width: Snapshot.phone.width, height: 1200)
      try await Snapshot.capture("session-dark-primary", size: tall) { Fixtures.session(pinned: false) }
      try await Snapshot.capture("session-light-primary", size: tall, style: .light) {
        Fixtures.session(pinned: false)
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
        .background(Tokens.Color.canvas)
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
        .background(Tokens.Color.canvas)
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
        .background(Tokens.Color.canvas)
      }
      // The 64 pt countdown grows to its accessibility1 cap and the words drop under it.
      try await Snapshot.capture(
        "restbar-dark-ax3", size: CGSize(width: 402, height: 520), typeSize: .accessibility3
      ) {
        VStack {
          Spacer()
          Fixtures.restBar()
        }
        .background(Tokens.Color.canvas)
      }
      // Paused shows static text, so this isolates the one-line layout from the live timer.
      try await Snapshot.capture("restbar-paused-440", size: CGSize(width: 440, height: 200)) {
        VStack {
          Spacer()
          Fixtures.restBar(paused: true)
        }
        .background(Tokens.Color.canvas)
      }
    }

    // MARK: - Analysis

    @Test func weeklyVolume() async throws {
      try await Snapshot.capture("volume-dark") { Fixtures.volume() }
      try await Snapshot.capture("volume-light", style: .light) { Fixtures.volume() }
      // The monument is the one figure whose width is set by Dynamic Type, capped at accessibility1,
      // so this is the capture that shows it stacked over its sentence at the largest setting.
      try await Snapshot.capture(
        "volume-dark-ax3", size: CGSize(width: 402, height: 2800), typeSize: .accessibility3
      ) { Fixtures.volume() }
    }

    /// Volume as the tab draws it, with every control on and the whole list in view: the header's
    /// settings glyph, the window controls with "Later" dimmed on the newest window, the figures
    /// that open their working, the lower-bound note and the gap lists. In both appearances and at
    /// an accessibility size, where the figure drops under the name.
    @Test func weeklyVolumeInFull() async throws {
      let tall = CGSize(width: Snapshot.phone.width, height: 2000)
      try await Snapshot.capture("volume-full-dark", size: tall) { Fixtures.volumeFull() }
      try await Snapshot.capture("volume-full-light", size: tall, style: .light) {
        Fixtures.volumeFull()
      }
      try await Snapshot.capture(
        "volume-full-dark-ax3", size: CGSize(width: Snapshot.phone.width, height: 4800),
        typeSize: .accessibility3
      ) { Fixtures.volumeFull() }
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
          .hardsetNavigationTitle("Choose a gym")
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
      // The local-only state a build without iCloud opens in, which every personal-team device
      // build is. Rendered tall so the section, below the fold on a phone, is in frame.
      try await Snapshot.capture(
        "settings-local-only-dark", size: CGSize(width: Snapshot.phone.width, height: 1600)
      ) {
        SettingsSheet(useImperial: .constant(false), sync: .localOnly) {}
      }
    }

    /// The app target's startup states, rebuilt from the same components: it cannot be rendered
    /// from this package directly.
    @Test func startupStates() async throws {
      try await Snapshot.capture("startup-failed-dark") {
        VStack(spacing: Tokens.Spacing.regular) {
          HardsetEmptyState(
            title: "Could not open Hardset",
            detail: "Your workouts are still saved on this phone, and nothing has been erased. "
              + "Do not delete the app: deleting it is what deletes them. Try again; if it keeps "
              + "happening, share the error below so it can be looked at.",
            systemImage: "exclamationmark.triangle",
            actionTitle: "Try again",
            actionSystemImage: "arrow.clockwise",
            action: {}
          )
          Button(action: {}) {
            Label("Share error details", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(HardsetButtonStyle(.secondary))
          Text(verbatim: "SQLite error 11: database disk image is malformed")
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.chalkDim)
            .multilineTextAlignment(.center)
            .lineLimit(6)
            .padding(.horizontal, Tokens.Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.canvas)
      }
      try await Snapshot.capture("startup-opening-light", style: .light) {
        HardsetLoadingState("Opening your workouts…")
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
      // The last-workout section leads with its volume at 72 pt; at accessibility3 the unit and the
      // ledger stack, and the screen scrolls, so the window is tall enough to hold all of it.
      try await Snapshot.capture(
        "root-start-dark-ax3", size: CGSize(width: 402, height: 2600), typeSize: .accessibility3
      ) {
        HardsetRootView(environment: environment, unit: .kilograms)
      }
    }

    /// The start screen with the most on it: a gym, two saved workouts (one up next), the controls
    /// that follow the empty start, and the last workout. Tall, so the whole column is in view, in
    /// both appearances and at an accessibility size, where the rows of saved workouts stack.
    @Test func startScreenWithSavedWorkouts() async throws {
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

      let pressEntries = try environment.catalog.search("Press")
      let press = try #require(pressEntries.first)
      let day = Date(timeIntervalSinceNow: -4 * 86_400)
      try await environment.templates.save(
        WorkoutTemplate(
          name: "Upper A", position: 0,
          exercises: [TemplateExercise(exerciseID: press.id, exerciseName: press.name, plannedSets: 3)],
          lastDoneAt: day),
        now: day)
      try await environment.templates.save(
        WorkoutTemplate(
          name: "Upper B", position: 1,
          exercises: [TemplateExercise(exerciseID: press.id, exerciseName: press.name, plannedSets: 3)]),
        now: day)

      let tall = CGSize(width: Snapshot.phone.width, height: 1500)
      let settle: Duration = .seconds(4)
      try await Snapshot.capture("train-saved-dark", size: tall, settle: settle) {
        HardsetRootView(environment: environment, unit: .kilograms)
      }
      try await Snapshot.capture("train-saved-light", size: tall, style: .light, settle: settle) {
        HardsetRootView(environment: environment, unit: .kilograms)
      }
      try await Snapshot.capture(
        "train-saved-dark-ax3", size: CGSize(width: Snapshot.phone.width, height: 3200),
        typeSize: .accessibility3, settle: settle
      ) {
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
      .background(Tokens.Color.canvas)
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
        .background(Tokens.Color.canvas)
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
    /// result at 2x to `<name>.png`. `contrast` overrides Increase Contrast, so the high-contrast
    /// palette can be rendered without changing the Simulator's settings. `settle` is how long the
    /// window runs before the frame is taken: the default covers a view's own tasks, and a screen
    /// that reads a database through the real stores needs longer.
    static func capture<Content: View>(
      _ name: String,
      size: CGSize = Snapshot.phone,
      style: UIUserInterfaceStyle = .dark,
      typeSize: DynamicTypeSize = .large,
      contrast: UIAccessibilityContrast = .normal,
      settle: Duration = .milliseconds(800),
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
      host.traitOverrides.accessibilityContrast = contrast
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.overrideUserInterfaceStyle = style
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.layoutIfNeeded()
      // `.task` modifiers, database reads and the first full layout land on later run-loop turns.
      try await Task.sleep(for: settle)
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

    /// - Parameter pinned: Draws the rest bar and a record notice over the list, as the live screen
    ///   does just after a set; `false` leaves the list clear, so every row can be looked at.
    static func session(pinned: Bool = true) -> some View {
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
        restState: pinned ? .running(endsAt: Date().addingTimeInterval(96)) : .idle,
        restMetadata: RestMetadata(
          exerciseName: "Leg Press", setOrdinal: 1, plannedSets: 3, machineName: "Hammer Strength"
        ),
        records: pinned
          ? [
            PersonalRecord(kind: .heaviestLoad, weightKg: 105, reps: 8, previousWeightKg: 100),
            PersonalRecord(
              kind: .estimatedOneRepMax, weightKg: 128, reps: 8, previousWeightKg: 122),
          ] : [],
        onLogSet: { _, _ in },
        onAddExercise: {},
        onSelectMachine: { _ in },
        onShowHistory: { _ in },
        onShowSettings: {},
        // As in the app, where a record notice can open the working behind its records. It is also
        // what lets the notice collapse to one line at accessibility sizes.
        onExplainRecords: pinned ? {} : nil
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
        onExplainCounting: {},
        onShowLibrary: {},
        onShowTotalWorking: {}
      )
    }

    static func volumeFull() -> some View {
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
        title: "Volume",
        subtitle: "Last 7 days, 16 Nov to now",
        onExplainCounting: {},
        onShowSettings: {},
        onEarlier: {},
        onShowWorking: { _ in },
        onShowTotalWorking: {}
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
            hasImplausibleDuration: false,
            // C10 residual: a workout brought in from another app says so on its row.
            isImported: true
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
      .background(Tokens.Color.canvas)
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
      .background(Tokens.Color.canvas)
    }
  }
#endif
