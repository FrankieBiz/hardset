import HardsetCore
import HardsetStore
import HardsetUI
import SQLiteData
import SwiftUI

/// Everything the app needs, constructed once.
///
/// Assembled here rather than in the app target because the app target cannot be compiled from a
/// sandboxed command line, so anything that lives there is unverifiable. This builds and previews
/// on the host.
@MainActor
public struct HardsetEnvironment {
  public let logger: LoggerStore
  public let catalog: CatalogSeeder
  public let volume: VolumeStore
  public let history: HistoryStore
  public let progression: ProgressionStore
  public let health: DeviceHealthStore
  public let receipts: ReceiptStore
  public let transfer: DataTransferStore
  public let gyms: GymStore
  /// Whether this launch replicates to iCloud. Shown in Settings, so a local-only build says
  /// plainly where the lifter's workouts live instead of leaving them to assume a backup.
  public let sync: SyncStatus?

  /// - Parameter sync: `nil` in previews and tests, where no launch decided it; Settings then
  ///   omits the section rather than claiming either state.
  public init(database: any DatabaseWriter, sync: SyncStatus? = nil) {
    self.sync = sync
    self.logger = LoggerStore(database: database)
    self.catalog = CatalogSeeder(database: database)
    self.volume = VolumeStore(database: database)
    self.history = HistoryStore(database: database)
    self.progression = ProgressionStore(database: database)
    self.gyms = GymStore(database: database)
    self.health = DeviceHealthStore(database: database)
    self.receipts = ReceiptStore(database: database)
    self.transfer = DataTransferStore(database: database)
  }
}

/// The app's three tabs, plus the workout-in-progress bar.
///
/// A live session is deliberately NOT a full-screen modal. It lives in the tab bar's bottom
/// accessory, so a lifter mid-workout can still open their history or check the week's volume
/// without abandoning the session — which is what a modal would force. That slot is what
/// `tabViewBottomAccessory` exists for, and the tab bar minimises on scroll so the set grid keeps
/// the screen. Tapping the accessory returns to the workout, as a now-playing bar returns to what
/// is playing; on the Train tab it is hidden, because the session screen already shows the same
/// sets and rest.
@MainActor
public struct HardsetRootView: View {
  @State private var model: WorkoutRootModel
  /// Held here rather than left to the tab view, so the workout accessory can bring the lifter
  /// back to Train from whichever tab they are reading.
  @State private var selectedTab: RootTab = .train
  @State private var startFailed = false
  @State private var isChoosingGym = false
  @State private var isAddingGym = false
  @State private var isShowingSettings = false
  /// The newest finished workout, for the start screen. `nil` when there is none, and then the
  /// start screen shows nothing in its place rather than a placeholder that implies a history.
  @State private var lastWorkoutSnapshot = SnapshotLoader<[SessionSummary]>()
  /// The day the start screen's header names. Read when the view is made and again whenever the
  /// app returns to the foreground on a later day; read only while drawing, the header went on
  /// naming yesterday for a lifter who left the app open overnight.
  @State private var today = Date.now
  /// The gym picked on the start screen that no workout has recorded yet, as an ID, `noGymPick`
  /// for "Not recorded", or empty when there is none.
  ///
  /// Scene state rather than a stored preference: iOS restores it after ending the app in the
  /// background between choosing and starting, a force-quit discards it, and it is cleared once a
  /// workout starts and its session records the gym. From then on the learned last-used gym is
  /// the default again, so there is still no setting to go stale.
  @SceneStorage("hardset.pendingGymPick") private var pendingGymPick = ""
  /// Inferred from the device's locale on first launch rather than asked, and stored the moment the
  /// user disagrees. Kilograms remain the canonical storage unit either way — this only decides
  /// what is displayed and what typed numbers are read as.
  @AppStorage("hardset.useImperial") private var useImperial =
    Locale.current.measurementSystem == .us
  /// Why the last gym write failed, in the user's words. A `try?` here hid a real failure behind a
  /// button that appeared to do nothing, which is precisely what this app is not allowed to do.
  @State private var gymError: String?
  /// Why the gym just named could not be saved. Shown inside the name sheet, which stays up so the
  /// typed name is still there for the retry; the picker's banner would be hidden behind it.
  @State private var addGymError: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  private let environment: HardsetEnvironment
  /// Overrides the stored preference. Exists for previews and tests; the app passes `nil` so the
  /// user's own choice wins.
  private let unitOverride: WeightUnit?
  private let hooks: RestTimerHooks

  public init(
    environment: HardsetEnvironment,
    unit: WeightUnit? = nil,
    hooks: RestTimerHooks = .inert,
    restAfterSet: Duration? = nil
  ) {
    self.environment = environment
    self.unitOverride = unit
    self.hooks = hooks
    _model = State(initialValue: WorkoutRootModel(
      logger: environment.logger, catalog: environment.catalog, gyms: environment.gyms,
      restAfterSet: restAfterSet, onStartRest: { duration, metadata in hooks.start(duration, metadata) }
    ))
  }

  /// What every screen displays in. One derivation, so no screen can disagree with another.
  private var unit: WeightUnit {
    unitOverride ?? (useImperial ? .pounds : .kilograms)
  }

  private var coordinator: SessionCoordinator? { model.coordinator }

  public var body: some View {
    rootContent
      // One banner per kind of rest-timer problem, each with the action that can actually fix it:
      // Open Settings when alarms are denied, Retry when scheduling failed, Reset when the saved
      // rest could not be read. A single generic "Retry" could never fix a denied permission.
      .safeAreaInset(edge: .top) {
        if let issue = hooks.issue() {
          RestTimerIssueBanner(issue: issue, retry: hooks.retry, reset: hooks.resetRestTimer)
        }
      }
  }

  /// The tabs are drawn whatever the root's readiness. Only Train waits for the catalogue, recovery
  /// and gyms, because only Train offers a new workout; History, Volume, and Settings with its
  /// export read their own data and stay reachable when preparing a workout fails.
  private var rootContent: some View {
    tabs
      .tint(Tokens.Color.accent)
      // Above every tab, so Settings opens from each tab's header alike, and outside anything
      // that changes when a workout starts or finishes, so finishing while it is open cannot pull
      // its anchor out from under it.
      .sheet(isPresented: $isShowingSettings) {
        SettingsSheet(
          useImperial: $useImperial, transfer: environment.transfer,
          health: environment.health, sync: environment.sync, gyms: environment.gyms,
          // An import adds finished workouts, so the start screen's last workout may have
          // changed underneath the sheet, which does not make the start screen appear again.
          // A gym renamed or archived in Settings changes the names the start screen and the gym
          // picker show; an archived pick falls back to the learned default in the model.
          onDataChanged: {
            Task { await refreshLastWorkout() }
            do {
              try model.refreshGyms()
            } catch {
              gymError = "Your gyms could not be re-read. Close and reopen the list to try again."
            }
          }
        ) { isShowingSettings = false }
          .hardsetSheet()
      }
      .task { await prepare() }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active, !Calendar.current.isDate(today, inSameDayAs: .now) else { return }
        today = .now
      }
  }

  private var tabs: some View {
    TabView(selection: $selectedTab) {
      Tab("Train", systemImage: "figure.strengthtraining.traditional", value: RootTab.train) {
        NavigationStack {
          trainTab
        }
      }
      Tab("Volume", systemImage: "chart.bar.xaxis", value: RootTab.volume) {
        NavigationStack {
          // The screen draws its own header; the title stays as the screen's accessible name.
          WeeklyVolumeScreen(
            store: environment.volume, onShowSettings: { isShowingSettings = true }
          )
          // Matches the screen's own header: the window is the last 7 days and can step back.
          .navigationTitle("Volume")
          .hardsetTabRoot()
        }
      }
      Tab("History", systemImage: "clock.arrow.circlepath", value: RootTab.history) {
        NavigationStack {
          HistoryScreen(
            store: environment.history, unit: unit, receipts: environment.receipts,
            progression: environment.progression,
            // Deleting a workout or a set there can change which workout is the latest.
            onHistoryChanged: { Task { await refreshLastWorkout() } },
            onShowSettings: { isShowingSettings = true }
          )
          .navigationTitle("History")
          .hardsetTabRoot()
        }
      }
    }
    #if os(iOS)
      // Always attached and switched with `isEnabled`. The slot is reserved by the modifier, not
      // by its content, so an empty accessory still drew a pill above the tab bar; and adding or
      // removing the modifier itself gave the tab view a new identity, rebuilding every tab's
      // state each time a workout started or finished.
      .tabViewBottomAccessory(isEnabled: isAccessoryShown) { liveSessionAccessory }
      .tabBarMinimizeBehavior(coordinator != nil ? .onScrollDown : .automatic)
    #endif
  }

  /// A workout is open and the lifter is on another tab. On Train the session screen itself shows
  /// the sets and the rest bar, and the accessory would only repeat them above the tab bar.
  private var isAccessoryShown: Bool {
    coordinator != nil && selectedTab != .train
  }

  /// Loads the root, then what the start screen shows from it. Shared by the first appearance and
  /// "Try again", so a load that succeeds only on retry fills in everything a first load does.
  private func prepare() async {
    await model.load()
    guard model.isReady else { return }
    restorePendingGymPick()
    await refreshLastWorkout()
  }

  // MARK: - Train

  @ViewBuilder private var trainTab: some View {
    if let coordinator {
      LiveSessionScreen(
        coordinator: coordinator,
        unit: unit,
        hooks: hooks,
        catalog: environment.catalog,
        gyms: environment.gyms,
        progression: environment.progression,
        // A session can belong to a gym archived since it began. It still has machines, so the
        // header says a gym is recorded rather than claiming there is none.
        gymName: gymName(for: coordinator.gymID) ?? (coordinator.gymID == nil ? nil : "Saved gym"),
        onShowSettings: { isShowingSettings = true },
        onFinished: {
          model.clearFinishedWorkout()
          // The workout just finished is now the last one, so the start screen says so.
          Task { await refreshLastWorkout() }
        }
      )
      // The live session draws its own header, with the gym and the settings action. The title
      // stays as the screen's accessible name; the stock bar is hidden.
      .navigationTitle("Workout")
      .hardsetTabRoot()
    } else if model.isReady {
      startView
        .navigationTitle("Train")
        .hardsetTabRoot()
    } else if let error = model.lastError {
      preparationFailure(error)
        .navigationTitle("Train")
        .hardsetTabRoot()
    } else {
      VStack(alignment: .leading, spacing: 0) {
        trainHeader
        HardsetLoadingState("Preparing your workout…")
      }
      .background(Tokens.Color.background)
      .navigationTitle("Train")
      .hardsetTabRoot()
    }
  }

  /// The Train header, with the settings action, shared by the start screen and the states before
  /// it so Settings is reachable while a workout is still being prepared.
  private var trainHeader: some View {
    ScreenHeader("Train", subtitle: Self.dayLabel(today)) {
      HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
        isShowingSettings = true
      }
    }
  }

  /// The catalogue, the open workout or the gyms could not be read, so no new workout is offered.
  ///
  /// Said about the workout only, because that is all that is held back: the other tabs and
  /// Settings keep working. The error itself follows, small and selectable as on the startup
  /// screen, because on a phone with no debugger attached this is the only place to read it.
  private func preparationFailure(_ error: any Error) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
        trainHeader
        VStack(spacing: Tokens.Spacing.regular) {
          HardsetEmptyState(
            title: "Could not prepare a workout",
            detail: "Your history and exports are still available.",
            systemImage: "exclamationmark.triangle",
            actionTitle: "Try again",
            actionSystemImage: "arrow.clockwise",
            action: { Task { await prepare() } }
          )
          Text(verbatim: String(describing: error))
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(6)
            .textSelection(.enabled)
            .padding(.horizontal, Tokens.Spacing.section)
            .accessibilityLabel("Error details: \(String(describing: error))")
        }
      }
      .padding(.bottom, Tokens.Spacing.block)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Tokens.Color.background)
  }

  /// The start screen: where the lifter is, the one action, and what they did last time.
  ///
  /// Deliberately calm. There is no streak to keep and no prompt to train more, and nothing is
  /// filled in that the lifter has not recorded — with no history, the last-workout card is absent
  /// rather than a placeholder implying one.
  private var startView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.block) {
        trainHeader

        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
          gymCard

          VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
            Button(action: startEmptyWorkout) {
              Label("Start workout", systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(HardsetButtonStyle(.primary, size: .logger))

            if startFailed {
              HardsetBanner(
                .error,
                message: "Could not start a workout. Nothing has been lost — try again."
              )
              .transition(.opacity)
            }

            // Said where the button is, because it is the first thing a lifter used to a
            // programme app would expect: the workout is theirs to build, not one handed to them.
            Text(
              "The workout starts empty and you add movements as you go. Hardset does not "
                + "invent a program."
            )
            .font(Tokens.Text.provenance)
            .foregroundStyle(Tokens.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .animation(
          Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion),
          value: startFailed
        )

        if let lastWorkout {
          lastWorkoutCard(lastWorkout)
            .padding(.horizontal, Tokens.Spacing.loose)
        }
      }
      .padding(.bottom, Tokens.Spacing.block)
    }
    .scrollBounceBehavior(.basedOnSize)
    .background(Tokens.Color.background)
    // A failure belongs to the visit it happened in; reopening the picker starts clean.
    .sheet(isPresented: $isChoosingGym, onDismiss: { gymError = nil }) { gymSheet.hardsetSheet() }
  }

  /// A day, as the start screen's context line: "Saturday 7 November", in the device's format.
  private static func dayLabel(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.wide).day().month(.wide))
  }

  /// Sets where this workout is, which is what makes per-machine tracking reachable at all: a
  /// machine belongs to a gym, so a session with no gym can only ever log `machineID == nil`.
  ///
  /// Stated as one card rather than a required step. It is preselected from the last gym used, so
  /// the common case — training at the same place — costs nothing. With no gym it is an
  /// invitation in neutral colours, not a warning: training without one is a valid choice.
  private var gymCard: some View {
    Button {
      isChoosingGym = true
    } label: {
      HStack(spacing: Tokens.Spacing.regular) {
        Image(systemName: "mappin.and.ellipse")
          .font(Tokens.Text.headline)
          .foregroundStyle(Tokens.Color.accent)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
          if let selectedGymName {
            Text("Training at")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
            Text(selectedGymName)
              .font(Tokens.Text.title)
              .foregroundStyle(Tokens.Color.textPrimary)
          } else {
            Text(gymInvitation)
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.textPrimary)
            Text("Optional. Loads are recorded per machine, and machines belong to a gym.")
              .font(Tokens.Text.caption)
              .foregroundStyle(Tokens.Color.textSecondary)
          }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

        if selectedGymName != nil {
          Text("Change")
            .font(Tokens.Text.labelEmphasis)
            .foregroundStyle(Tokens.Color.accent)
        }
        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption.weight(.semibold))
          .foregroundStyle(Tokens.Color.textSecondary)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(OutlinedCardButtonStyle())
    .accessibilityLabel(gymCardAccessibilityLabel)
    .accessibilityHint("Opens the list of gyms")
  }

  private var selectedGymName: String? {
    gymName(for: model.selectedGym)
  }

  /// "Add" when there is nothing to choose from yet, "Choose" when there is. Asking someone to
  /// add a gym they already have would send them to the wrong button.
  private var gymInvitation: String {
    model.gymOptions.isEmpty ? "Add a gym to track machines" : "Choose a gym to track machines"
  }

  private var gymCardAccessibilityLabel: String {
    if let selectedGymName {
      return "Training at \(selectedGymName)"
    }
    return gymInvitation
  }

  /// A gym's name from the list already loaded for the picker. `nil` for no gym, and for one that
  /// has since been archived, so a header never names a place the app cannot show.
  private func gymName(for id: GymID?) -> String? {
    guard let id else { return nil }
    return model.gymOptions.first { $0.id == id }?.name
  }

  // MARK: - Last workout

  private var lastWorkout: SessionSummary? { lastWorkoutSnapshot.value?.first }

  /// The newest finished workout, as it was recorded.
  ///
  /// Read-only on purpose: it states what happened and leads nowhere, so it cannot be mistaken for
  /// a plan to repeat. Duration appears only when the timeline is plausible — a forgotten session
  /// is not presented as a six-hour effort here any more than it is in history.
  private func lastWorkoutCard(_ summary: SessionSummary) -> some View {
    let title = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let date = Self.sessionDate(summary.timeline.startedAt)
    let duration = summary.hasImplausibleDuration ? nil : summary.timeline.duration

    return VStack(alignment: .leading, spacing: Tokens.Spacing.snug) {
      SectionLabel("Last workout")

      VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.regular) {
          VStack(alignment: .leading, spacing: Tokens.Spacing.hairline) {
            Text(title.isEmpty ? date : title)
              .font(Tokens.Text.headline)
              .foregroundStyle(Tokens.Color.textPrimary)
            if !title.isEmpty {
              Text(date)
                .font(Tokens.Text.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          if let duration {
            // The same clock format the history list uses, so the two never disagree.
            Label(duration.clockString, systemImage: "clock")
              .labelStyle(.titleAndIcon)
              .font(Tokens.Text.figure)
              .foregroundStyle(Tokens.Color.textSecondary)
              .accessibilityLabel("Duration \(duration.clockString)")
          }
        }

        if summary.volume.isEmpty {
          Text("Finished with no sets logged.")
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
        } else {
          StatLedger(ledgerItems(summary.volume))
        }

        if !summary.exerciseNames.isEmpty {
          Text(summary.exerciseNames.joined(separator: ", "))
            .font(Tokens.Text.label)
            .foregroundStyle(Tokens.Color.textSecondary)
            .lineLimit(2)
        }
      }
      .padding(Tokens.Spacing.loose)
      .frame(maxWidth: .infinity, alignment: .leading)
      .hardsetCard()
      .accessibilityElement(children: .combine)
    }
  }

  /// Working sets, reps, and volume in the unit the lifter reads, rounded to whole units.
  ///
  /// Volume is left out when it rounds to zero rather than shown as "0 kg": bodyweight work has
  /// real sets and reps and no added load, and a zero there reads as a session that did nothing.
  private func ledgerItems(_ volume: SessionVolume) -> [StatLedger.Item] {
    var items: [StatLedger.Item] = [
      StatLedger.Item(label: "Working sets", value: volume.workingSets.formatted()),
      StatLedger.Item(label: "Reps", value: volume.reps.formatted()),
    ]
    let displayed = unit.fromKilograms(volume.volumeKg).rounded()
    if displayed > 0 {
      items.append(
        StatLedger.Item(
          label: "Volume",
          value: displayed.formatted(.number.precision(.fractionLength(0))),
          unit: unit.abbreviation
        )
      )
    }
    return items
  }

  /// "Thursday 5 November", with the year added only when it is not this year, so an old session
  /// is never read as a recent one.
  private static func sessionDate(_ date: Date) -> String {
    let style: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.wide)
    if Calendar.current.isDate(date, equalTo: Date.now, toGranularity: .year) {
      return date.formatted(style)
    }
    return date.formatted(style.year())
  }

  // MARK: - Gyms

  private var gymSheet: some View {
    NavigationStack {
      GymPickerView(
        gyms: model.gymOptions.map { GymOption(id: $0.id, name: $0.name) },
        selected: model.selectedGym,
        errorMessage: gymError,
        onSelect: { id in
          chooseGym(id)
          isChoosingGym = false
        },
        onAddGym: { isAddingGym = true }
      )
      .hardsetNavigationTitle("Choose a gym")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { isChoosingGym = false }
        }
      }
      // Attached INSIDE the gym sheet on purpose. Two `.sheet` modifiers on the same anchor means
      // the second one silently never presents: "Add a gym" was a button that did nothing.
      .sheet(isPresented: $isAddingGym, onDismiss: { addGymError = nil }) {
        NameEntrySheet(
          title: "Add a gym",
          prompt: "Name",
          footnote: "Machines are recorded per gym, so this is what groups them.",
          errorMessage: addGymError,
          onConfirm: { name in addGym(named: name) },
          onCancel: { isAddingGym = false }
        )
        .hardsetSheet()
      }
    }
  }

  /// `try?` deliberately, unlike the gym write below: this reads something optional to show, and a
  /// failure leaves the card absent rather than wrong. The history tab, which depends entirely on
  /// the same read, states its failure in full.
  private func refreshLastWorkout() async {
    let store = environment.history
    await lastWorkoutSnapshot.load { try await store.loadRecentSessions(limit: 1) }
  }

  /// Takes the name as an argument rather than reading it back out of state. The version that
  /// read `@State` written by a `TextField` inside an `.alert` received an empty string every
  /// time, so no gym was ever created even though the field visibly held text.
  ///
  /// The name sheet closes only once the gym exists. When the write fails it stays up with the
  /// reason inside it, so the name the lifter typed is still there to try again.
  private func addGym(named name: String) {
    guard !name.isEmpty else { return }
    let id: GymID
    do {
      id = try environment.gyms.createGym(name: name)
    } catch {
      // In the lifter's words. The error's own description is the database's, statement and all.
      addGymError = "“\(name)” could not be saved. Try again."
      return
    }
    isAddingGym = false
    chooseGym(id)
    do {
      try model.refreshGyms()
      gymError = nil
      isChoosingGym = false
    } catch {
      // The write succeeded; a failed follow-up read must not claim it did not.
      gymError = "The gym was saved, but its list could not be read."
    }
  }

  /// Selects where the next workout is, and keeps the pick for this scene until a workout records
  /// it, so iOS ending the app in the background between choosing and starting does not lose it.
  private func chooseGym(_ id: GymID?) {
    model.selectedGym = id
    pendingGymPick = id?.rawValue.uuidString ?? Self.noGymPick
  }

  /// Puts back a pick kept by `chooseGym` once the saved gyms are known. One that can no longer be
  /// applied, such as a gym archived since, is dropped and the learned default stands.
  private func restorePendingGymPick() {
    guard !pendingGymPick.isEmpty else { return }
    let restored: Bool
    if pendingGymPick == Self.noGymPick {
      restored = model.restoreGymPick(nil)
    } else if let raw = UUID(uuidString: pendingGymPick) {
      restored = model.restoreGymPick(GymID(rawValue: raw))
    } else {
      restored = false
    }
    if !restored { pendingGymPick = "" }
  }

  /// `pendingGymPick`'s value for "Not recorded", which is a real choice and not the absence of one.
  private static let noGymPick = "none"

  private func startEmptyWorkout() {
    do {
      try model.startWorkout()
      startFailed = false
      // The pick is spent: the session recorded it, and the learned default takes over again.
      pendingGymPick = ""
    } catch {
      startFailed = true
    }
  }

  // MARK: - Accessory

  /// The open workout, from another tab: its sets and the rest, and one tap back to it.
  ///
  /// A button, as a now-playing bar is: it looked like one and did nothing, so a lifter checking
  /// History between sets had to find the Train tab, which may be minimised, to get back.
  @ViewBuilder private var liveSessionAccessory: some View {
    if let coordinator {
      Button {
        selectedTab = .train
      } label: {
        HStack(spacing: Tokens.Spacing.snug) {
          // A steady mark, not a pulse: the workout is open, and nothing about that changes from
          // second to second, so nothing here moves.
          Circle()
            .fill(Tokens.Color.accent)
            .frame(width: Tokens.Spacing.snug, height: Tokens.Spacing.snug)
            .accessibilityHidden(true)
          loggedSetsLine(coordinator.loggedSetCount)
          Spacer(minLength: 0)
          accessoryRest
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The whole pill answers a tap, not only its text.
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        Text("Workout in progress, ^[\(coordinator.loggedSetCount) set](inflect: true) logged")
      )
      // The label replaces the button's content, so the rest is restated here or it would never
      // be spoken.
      .accessibilityValue(restAccessibilityValue)
      .accessibilityHint("Returns to the workout")
    }
  }

  /// The rest as the accessory shows it: counting down, or frozen while paused. The rest controls
  /// themselves are one tap away on the workout.
  @ViewBuilder private var accessoryRest: some View {
    let state = hooks.state()
    if case .running(let endsAt) = state {
      Image(systemName: "timer")
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(Tokens.Color.accent)
        .accessibilityHidden(true)
      // System-rendered from the deadline, so the accessory costs no updates.
      Text(timerInterval: Date()...max(endsAt, Date()), countsDown: true)
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.accent)
    } else if case .paused(let remaining) = state {
      // Static, like the rest bar's paused figure: nothing is counting, so nothing ticks.
      Image(systemName: "pause.fill")
        .font(Tokens.Text.caption.weight(.semibold))
        .foregroundStyle(Tokens.Color.textSecondary)
        .accessibilityHidden(true)
      Text(remaining.clockString)
        .font(Tokens.Text.figure)
        .foregroundStyle(Tokens.Color.textSecondary)
    }
  }

  /// The rest for VoiceOver, rendered by the system from the deadline like the visible countdown.
  /// Empty when no rest is running or paused.
  private var restAccessibilityValue: Text {
    let state = hooks.state()
    if case .running(let endsAt) = state {
      return Text("Resting, ")
        + Text(timerInterval: Date()...max(endsAt, Date()), countsDown: true)
        + Text(" left")
    }
    if case .paused(let remaining) = state {
      return Text("Rest paused, \(remaining.clockString) left")
    }
    return Text(verbatim: "")
  }

  /// "3 sets logged", with the count alone set as a figure.
  ///
  /// Two texts rather than one inflected string, so the count can take the figure face without
  /// reaching into an attributed string's runs. The noun agrees with the count, so one set does not
  /// read "1 sets"; the accessory's spoken label keeps the system's inflection for VoiceOver.
  private func loggedSetsLine(_ count: Int) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.tight) {
      Text(count, format: .number)
        .font(Tokens.Text.figure)
      Text(count == 1 ? "set logged" : "sets logged")
        .font(Tokens.Text.label)
    }
    .foregroundStyle(Tokens.Color.textPrimary)
    .lineLimit(1)
  }
}

/// The root's tabs, as the tab view's selection.
private nonisolated enum RootTab: Hashable, Sendable {
  case train, volume, history
}

/// The start screen's gym card: a full-width card that is also one button.
///
/// Outlined with the measured control border rather than a card's decorative hairline, because
/// the boundary is what tells the lifter it can be tapped. Pressed, it sinks to the pressed fill;
/// with Reduce Motion on, the scale is dropped and only the fill changes.
private struct OutlinedCardButtonStyle: ButtonStyle {
  // Spelled out rather than `Configuration`: this file imports SQLiteData, whose GRDB
  // `Configuration` shadows the style's associated type and breaks the conformance.
  func makeBody(configuration: ButtonStyleConfiguration) -> some View {
    OutlinedCardButtonBody(configuration: configuration)
  }
}

private struct OutlinedCardButtonBody: View {
  let configuration: ButtonStyleConfiguration

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card)
    configuration.label
      .padding(.horizontal, Tokens.Spacing.loose)
      .padding(.vertical, Tokens.Spacing.regular)
      .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget, alignment: .leading)
      .background(
        configuration.isPressed ? Tokens.Color.surfacePressed : Tokens.Color.surface,
        in: shape
      )
      .overlay {
        shape.strokeBorder(Tokens.Color.controlBorder, lineWidth: Tokens.Stroke.hairline)
      }
      .contentShape(shape)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.4)
      .animation(Tokens.Motion.press, value: configuration.isPressed)
  }
}
