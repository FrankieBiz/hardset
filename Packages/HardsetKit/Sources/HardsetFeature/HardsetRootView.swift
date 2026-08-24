import HardsetCore
import HardsetStore
import HardsetUI
import SQLiteData
import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

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
  /// Creating and retiring the lifter's own movements.
  public let exercises: ExerciseStore
  /// Plans: arrangements of movements the lifter already trains. Never prescriptions.
  public let splits: SplitStore
  public let gyms: GymStore
  /// Device-local, and never registered with the sync engine. See `BodyweightStore`.
  public let bodyweight: BodyweightStore

  public init(database: any DatabaseWriter) {
    self.logger = LoggerStore(database: database)
    self.catalog = CatalogSeeder(database: database)
    self.volume = VolumeStore(database: database)
    self.history = HistoryStore(database: database)
    self.progression = ProgressionStore(database: database)
    self.exercises = ExerciseStore(database: database)
    self.splits = SplitStore(database: database)
    self.gyms = GymStore(database: database)
    self.bodyweight = BodyweightStore(database: database)
  }
}

/// The app's three tabs, plus the workout-in-progress bar.
///
/// A live session is deliberately NOT a full-screen modal. It lives in the tab bar's bottom
/// accessory, so a lifter mid-workout can still open their history or check the week's volume
/// without abandoning the session — which is what a modal would force. That slot is what
/// `tabViewBottomAccessory` exists for, and the tab bar minimises on scroll so the set grid keeps
/// the screen.
@MainActor
public struct HardsetRootView: View {
  @State private var coordinator: SessionCoordinator?
  /// The finished workout, held until the lifter dismisses its summary.
  ///
  /// Kept separately from `coordinator`, which is cleared the moment the session closes so the
  /// live-session accessory disappears with it. A workout that is over should not still show a
  /// pill saying it is in progress.
  @State private var finished: FinishedSession?
  @State private var startFailed = false
  /// A workout is open in the database but could not be reopened. Stated, because the alternative is
  /// the lifter training a second time into a day whose sets they cannot see.
  @State private var recoveryFailed = false
  /// Where the next workout will be. Preselected from the last one, changeable in one tap, and
  /// allowed to stay nil — training somewhere new must not require setup first.
  @State private var selectedGym: GymID?
  @State private var gymOptions: [GymRecord] = []
  @State private var isChoosingGym = false
  @State private var isAddingGym = false
  @State private var isShowingSettings = false
  /// Inferred from the device's locale on first launch rather than asked, and stored the moment the
  /// user disagrees. Kilograms remain the canonical storage unit either way — this only decides
  /// what is displayed and what typed numbers are read as.
  @AppStorage("hardset.useImperial") private var useImperial =
    Locale.current.measurementSystem == .us
  /// Rest after a working set, in seconds. **Zero means off, and that is the default**: the app has
  /// no basis for prescribing a rest length, so it waits to be told one. Stored in seconds rather
  /// than as a `Duration` because `@AppStorage` cannot hold one.
  @AppStorage("hardset.restSeconds") private var restSeconds = 0
  /// Whether the set row offers an effort field. Off by default: an unused column in the logger is
  /// clutter in the one place the app cannot afford it.
  @AppStorage("hardset.tracksRPE") private var tracksRPE = false
  /// Why the last gym write failed, in the user's words. A `try?` here hid a real failure behind a
  /// button that appeared to do nothing, which is precisely what this app is not allowed to do.
  @State private var gymError: String?
  /// The gym whose name is being repaired.
  @State private var renamingGym: RenameTarget?
  /// Which tab is showing. Bound so repeating a workout from History can move the lifter to the
  /// logger, which is where the workout it just started actually is.
  @State private var selectedTab: RootTab = .train
  private let environment: HardsetEnvironment
  /// Overrides the stored preference. Exists for previews and tests; the app passes `nil` so the
  /// user's own choice wins.
  private let unitOverride: WeightUnit?
  private let hooks: RestTimerHooks
  private let restAfterSet: Duration?

  public init(
    environment: HardsetEnvironment,
    unit: WeightUnit? = nil,
    hooks: RestTimerHooks = .inert,
    restAfterSet: Duration? = nil
  ) {
    self.environment = environment
    self.unitOverride = unit
    self.hooks = hooks
    self.restAfterSet = restAfterSet
  }

  /// What every screen displays in. One derivation, so no screen can disagree with another.
  private var unit: WeightUnit {
    unitOverride ?? (useImperial ? .pounds : .kilograms)
  }

  /// What a logged working set should request. One derivation, so the live session and a resumed
  /// session cannot disagree about whether rest is on.
  private var resolvedRest: Duration? {
    if let restAfterSet { return restAfterSet }
    return restSeconds > 0 ? .seconds(restSeconds) : nil
  }

  public var body: some View {
    tabs
      // Dark-only in v1, and forced rather than following the system. One palette tuned precisely
      // beats two tuned adequately, and this app is read at arm's length in a badly lit gym.
      //
      // Our own tokens are appearance-independent already -- they resolve to the same values in
      // either scheme -- so this exists for the chrome we do not draw: list backgrounds, the tab
      // bar, navigation bars, `ContentUnavailableView`. Light mode stays a later decision, which
      // is cheap because `Tokens.Color.dynamic` already has a slot waiting for it.
      // Keeps a live session in step with the setting. Without this, turning the rest timer on
      // mid-workout silently does nothing until the next session.
      .onChange(of: resolvedRest) { _, updated in
        coordinator?.restAfterSet = updated
        // Asked for the first time the lifter actually chooses a rest length. Nothing in the app
        // ever requested AlarmKit permission, so every schedule on a fresh install was refused and
        // the timer counted down in silence.
        if updated != nil { Task { await hooks.requestAuthorization() } }
      }
      // The screen stays awake while a workout is open, and only while one is open.
      //
      // A lifter sets the phone down between sets and picks it up ninety seconds later. Without
      // this they unlock it, find their place, and tap the row -- for every set of every workout.
      // Scoped to an open session rather than the whole app, because keeping the display awake on
      // the history tab would be draining the battery for nothing.
      #if os(iOS)
        .onChange(of: coordinator == nil) { _, noSession in
          UIApplication.shared.isIdleTimerDisabled = !noSession
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = coordinator != nil }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
      #endif
      .preferredColorScheme(.dark)
      // Pinning `Tokens.Color.accent` only fixed the colours *we* draw. System-drawn chrome --
      // the tab bar's selected item, toggles, the navigation back button -- reads its tint from
      // the environment, which was still the stock blue. Chrome is greyscale in this app, so the
      // one hue the design exists to remove was left sitting in the tab bar until this line.
      .tint(Tokens.Color.accent)
      .task {
        // Seeding is idempotent and non-destructive, so running it every launch is the intended
        // usage rather than something to guard with a flag that can drift from reality.
        _ = try? environment.catalog.seed()
        // A workout left open is offered back before anything else. Nothing is closed on the
        // app's initiative.
        if coordinator == nil { adoptOpenSession() }
        refreshGyms()
      }
  }

  /// `nil` while a workout is open, which hides "Do it again" rather than offering a button that
  /// would silently abandon the session in progress.
  ///
  /// Spelled as a property with an explicit type instead of `coordinator == nil ? repeatWorkout : nil`
  /// inline: a ternary between a method reference and `nil` needs an optional-closure conversion the
  /// type checker cannot do here, and it fails with "failed to produce diagnostic" rather than saying so.
  private var repeatHandler: (([RepeatableExercise]) -> Void)? {
    guard coordinator == nil else { return nil }
    return { plan in repeatWorkout(plan) }
  }

  @ViewBuilder private var trainNavigation: some View {
    NavigationStack {
      trainTab
        .toolbar {
          // `.primaryAction` rather than `.topBarTrailing`: the latter does not exist on macOS,
          // and this target builds for the host so the suite can run there.
          ToolbarItem(placement: .primaryAction) {
            Button {
              isShowingSettings = true
            } label: {
              Label("Settings", systemImage: "gearshape")
            }
          }
        }
        .sheet(isPresented: $isShowingSettings) {
          SettingsSheet(
            useImperial: $useImperial,
            restSeconds: $restSeconds,
            tracksRPE: $tracksRPE,
            bodyweight: environment.bodyweight,
            unit: unit,
            restAlertsDenied: hooks.isDenied()
          ) { isShowingSettings = false }
        }
    }
  }

  /// `nil` while a workout is open, which hides "Start this day" rather than offering a button that
  /// would abandon the session in progress. Same shape and same reason as `repeatHandler`.
  private var startDayHandler: (([PlannedExercise]) -> Void)? {
    guard coordinator == nil else { return nil }
    return { plan in startPlannedDay(plan) }
  }

  @ViewBuilder private var planNavigation: some View {
    NavigationStack {
      SplitPlannerScreen(
        splits: environment.splits,
        catalog: environment.catalog,
        gyms: environment.gyms,
        volume: environment.volume,
        onStartDay: startDayHandler
      )
      .navigationTitle("Plan")
    }
  }

  @ViewBuilder private var volumeNavigation: some View {
    NavigationStack {
      WeeklyVolumeScreen(store: environment.volume)
        .navigationTitle("This week")
    }
  }

  @ViewBuilder private var historyNavigation: some View {
    NavigationStack {
      HistoryScreen(
        store: environment.history,
        unit: unit,
        onRepeat: repeatHandler,
        // The per-machine chart used to be reachable only from inside a live workout, so seeing
        // your bench progression meant starting a session first.
        progression: environment.progression
      )
        .navigationTitle("History")
    }
  }

  @ViewBuilder private var tabs: some View {
    // Each tab's content is its own property. Inlining all three made one expression large enough
    // that the type checker gave up with "failed to produce diagnostic" rather than naming a cause.
    let content = TabView(selection: $selectedTab) {
      Tab("Train", systemImage: "figure.strengthtraining.traditional", value: RootTab.train) {
        trainNavigation
      }
      Tab("Plan", systemImage: "square.split.2x2", value: RootTab.plan) {
        planNavigation
      }
      Tab("Volume", systemImage: "chart.bar", value: RootTab.volume) {
        volumeNavigation
      }
      Tab("History", systemImage: "clock.arrow.circlepath", value: RootTab.history) {
        historyNavigation
      }
    }

    #if os(iOS)
      // The accessory is attached only while a session exists. Attaching it unconditionally and
      // returning an empty view inside drew an empty pill above the tab bar on the start screen —
      // the slot is reserved by the modifier, not by its content.
      if coordinator != nil {
        content
          .tabViewBottomAccessory { liveSessionAccessory }
          .tabBarMinimizeBehavior(.onScrollDown)
      } else {
        content
      }
    #else
      content
    #endif
  }

  // MARK: - Train

  @ViewBuilder private var trainTab: some View {
    if let finished {
      // A terminal moment, so it replaces the tab's content rather than covering it. A sheet over
      // a logger that is no longer live would leave the finished session visible underneath.
      SessionSummaryScreen(
        outcome: finished.outcome,
        timeline: finished.timeline,
        sessionID: finished.sessionID,
        store: environment.volume,
        unit: unit,
        onDone: { self.finished = nil }
      )
      .navigationTitle("Summary")
    } else if let coordinator {
      LiveSessionScreen(
        coordinator: coordinator,
        unit: unit,
        tracksRPE: tracksRPE,
        hooks: hooks,
        catalog: environment.catalog,
        gyms: environment.gyms,
        progression: environment.progression,
        exercises: environment.exercises,
        onFinished: { outcome in
          self.finished = FinishedSession(
            outcome: outcome,
            timeline: coordinator.timeline,
            sessionID: coordinator.sessionID
          )
          // Cleared here, not after the summary is dismissed: the session is over, so the
          // in-progress accessory must go with it.
          self.coordinator = nil
        }
      )
      .navigationTitle("Workout")
    } else {
      startView
    }
  }

  private var startView: some View {
    VStack(spacing: Tokens.Spacing.loose) {
      ContentUnavailableView {
        Label("No workout in progress", systemImage: "figure.strengthtraining.traditional")
      } description: {
        Text("Start an empty workout and add movements as you go.")
      }
      gymRow

      // The primary action is a white fill with a `ground` label -- the brightest object on the
      // screen, and there is at most one. This was white-on-surface, which made it read as
      // secondary and disagreed with the same control on the summary screen.
      Button(action: startEmptyWorkout) {
        Text("Start workout")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
          .foregroundStyle(Tokens.Color.ground)
          .background(
            Tokens.Color.accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
          )
      }
      .buttonStyle(CommitButtonStyle())
      .padding(.horizontal, Tokens.Spacing.section)

      if startFailed {
        Text("Could not start a workout. Nothing has been lost — try again.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
      }
      if recoveryFailed {
        // A workout exists and could not be reopened. Said plainly, because training a second time
        // into a day whose sets are unreachable is the outcome this warns against.
        Text(
          "A workout from earlier is still open but could not be reopened. "
            + "Its sets are saved. Try relaunching Hardset before starting another."
        )
        .font(Tokens.Text.caption)
        .foregroundStyle(Tokens.Color.certainty(.low))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Tokens.Color.ground)
    .sheet(isPresented: $isChoosingGym) { gymSheet }
  }

  /// Sets where this workout is, which is what makes per-machine tracking reachable at all: a
  /// machine belongs to a gym, so a session with no gym can only ever log `machineID == nil`.
  ///
  /// Stated as one line rather than a required step. It is preselected from the last gym used, so
  /// the common case — training at the same place — costs nothing.
  private var gymRow: some View {
    Button {
      isChoosingGym = true
    } label: {
      HStack(spacing: Tokens.Spacing.snug) {
        Image(systemName: "mappin.and.ellipse")
        Text(selectedGymName ?? "Add a gym to track machines")
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption)
          // Decoration. Announcing it adds "chevron right" to every reading of this row.
          .accessibilityHidden(true)
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(
        selectedGymName == nil ? Tokens.Color.textSecondary : Tokens.Color.textPrimary
      )
      .frame(minHeight: Tokens.minimumTapTarget)
      .padding(.horizontal, Tokens.Spacing.regular)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, Tokens.Spacing.section)
  }

  private var selectedGymName: String? {
    selectedGym.flatMap { id in gymOptions.first { $0.id == id }?.name }
  }

  private var gymSheet: some View {
    NavigationStack {
      List {
        Section {
          ForEach(gymOptions) { gym in
            Button {
              selectedGym = gym.id
              isChoosingGym = false
            } label: {
              HStack {
                Text(gym.name).foregroundStyle(Tokens.Color.textPrimary)
                Spacer()
                if selectedGym == gym.id {
                  Image(systemName: "checkmark").foregroundStyle(Tokens.Color.accent)
                }
              }
              .frame(minHeight: Tokens.minimumTapTarget)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Rename on the leading edge and non-destructive: repairing a typo is the common need
            // and must not sit next to the destructive action.
            .swipeActions(edge: .leading) {
              Button { renamingGym = RenameTarget(id: gym.id.rawValue) } label: {
                Label("Rename", systemImage: "pencil")
              }
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                retire(gym.id)
              } label: {
                // "Retire", not "Delete": the workouts logged there stay in history.
                Label("Retire", systemImage: "archivebox")
              }
            }
            .accessibilityActions {
              Button("Rename this gym") { renamingGym = RenameTarget(id: gym.id.rawValue) }
              Button("Retire this gym") { retire(gym.id) }
            }
          }
        } footer: {
          if let gymError {
            Text(gymError).foregroundStyle(Tokens.Color.certainty(.low))
          } else {
            Text("Loads are tracked per machine, and machines belong to a gym.")
          }
        }

        Section {
          Button {
            // Not recorded stays available: someone training at home or travelling should not be
            // made to invent a gym to log a set.
            selectedGym = nil
            isChoosingGym = false
          } label: {
            HStack {
              Text("Not recorded").foregroundStyle(Tokens.Color.textSecondary)
              Spacer()
              if selectedGym == nil {
                Image(systemName: "checkmark").foregroundStyle(Tokens.Color.accent)
              }
            }
            .frame(minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          Button { isAddingGym = true } label: {
            Label("Add a gym", systemImage: "plus")
              .frame(minHeight: Tokens.minimumTapTarget)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Tokens.Color.accent)
        }
      }
      .navigationTitle("Where are you training?")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { isChoosingGym = false }
        }
      }
      // Attached INSIDE the gym sheet on purpose. Two `.sheet` modifiers on the same anchor means
      // the second one silently never presents: "Add a gym" was a button that did nothing.
      .sheet(item: $renamingGym) { wrapped in
        NameEntrySheet(
          title: "Rename gym",
          prompt: "Name",
          footnote: "Only the label changes. Every workout logged here keeps its history.",
          onConfirm: { newName in
            renamingGym = nil
            rename(GymID(rawValue: wrapped.id), to: newName)
          },
          onCancel: { renamingGym = nil }
        )
      }
      .sheet(isPresented: $isAddingGym) {
        NameEntrySheet(
          title: "Add a gym",
          prompt: "Name",
          footnote: "Machines are recorded per gym, so this is what groups them.",
          onConfirm: { name in
            isAddingGym = false
            addGym(named: name)
          },
          onCancel: { isAddingGym = false }
        )
      }
    }
  }

  /// Retires a gym without touching what was logged there.
  private func retire(_ id: GymID) {
    do {
      try environment.gyms.archiveGym(id)
      if selectedGym == id { selectedGym = nil }
      gymError = nil
      refreshGyms()
    } catch {
      gymError = "That gym could not be retired. \(error)"
    }
  }

  private func rename(_ id: GymID, to name: String) {
    do {
      try environment.gyms.renameGym(id, to: name)
      gymError = nil
      refreshGyms()
    } catch {
      gymError = "That gym could not be renamed. \(error)"
    }
  }

  private func refreshGyms() {
    gymOptions = (try? environment.gyms.gyms()) ?? []
    // Preselected from behaviour, not from a stored setting that could disagree with reality.
    if selectedGym == nil {
      selectedGym = try? environment.gyms.lastUsedGym()
    }
    // A gym that has since been archived must not stay selected invisibly.
    if let selectedGym, !gymOptions.contains(where: { $0.id == selectedGym }) {
      self.selectedGym = nil
    }
  }

  /// Takes the name as an argument rather than reading it back out of state. The version that
  /// read `@State` written by a `TextField` inside an `.alert` received an empty string every
  /// time, so no gym was ever created even though the field visibly held text.
  private func addGym(named name: String) {
    guard !name.isEmpty else { return }
    do {
      let id = try environment.gyms.createGym(name: name)
      refreshGyms()
      selectedGym = id
      gymError = nil
      isChoosingGym = false
    } catch {
      // Stated, not swallowed. The error text is included because there is nothing useful to say
      // about a storage failure without it.
      gymError = "\(name) could not be saved. \(error)"
    }
  }

  /// Starts a new workout shaped like a past one, then moves to the logger.
  ///
  /// Each movement comes back on the same machine with the same number of rows, so the loads
  /// prefill from that machine's history and the lifter starts one tap from their first set.
  private func repeatWorkout(_ plan: [RepeatableExercise]) {
    guard coordinator == nil, !plan.isEmpty else { return }
    // `start` moves to the Train tab on success. Starting a workout the lifter cannot see would be
    // the same class of defect as a button that appears to do nothing.
    start {
      try SessionCoordinator.start(
        store: environment.logger,
        gymID: selectedGym,
        plan: plan.map {
          PlannedExercise(
            exerciseID: $0.exerciseID,
            machineID: $0.machineID,
            exerciseName: $0.exerciseName,
            // Carried through, or a repeated bodyweight day opens with rows demanding a weight.
            modality: $0.modality,
            machineName: $0.machineName,
            plannedSets: $0.workingSets
          )
        },
        restAfterSet: resolvedRest,
        hooks: hooks
      )
    }
  }

  /// Starts a plan's day as today's workout.
  ///
  /// The one path from planning into the app's core loop. Deliberately thin: the movements arrive
  /// already shaped as `PlannedExercise` from `SplitStore`, each with `plannedSets` nil, because a
  /// plan carries no set counts and inventing one here would put a prescription into the logger by
  /// the back door.
  private func startPlannedDay(_ plan: [PlannedExercise]) {
    guard coordinator == nil, !plan.isEmpty else { return }
    // `start` moves to the Train tab on success -- starting a workout the lifter cannot see is the
    // same class of defect as a button that appears to do nothing.
    start {
      try SessionCoordinator.start(
        store: environment.logger,
        gymID: selectedGym,
        plan: plan,
        restAfterSet: resolvedRest,
        hooks: hooks
      )
    }
  }

  /// Reopens whatever workout is still open, if any.
  ///
  /// The launch path used `try?` here, which is how the orphaning bug was reachable: a resume that
  /// threw left `coordinator` nil while the session stayed open in the database, and the next
  /// "Start workout" created a second one -- making the first unreachable forever, since
  /// `openSession` reads only the newest and history lists only finished workouts.
  ///
  /// Now the failure is stated. A lifter whose session cannot be reopened needs to know that,
  /// because the alternative is training a second time into a day whose sets they cannot see.
  @discardableResult
  private func adoptOpenSession() -> Bool {
    do {
      coordinator = try SessionCoordinator.resume(
        store: environment.logger,
        restAfterSet: resolvedRest,
        onStartRest: { duration, metadata in hooks.start(duration, metadata) }
      )
      if coordinator != nil { startFailed = false }
      return coordinator != nil
    } catch {
      recoveryFailed = true
      return false
    }
  }

  /// Turns the store's refusal into the thing the lifter actually wanted.
  ///
  /// `startSession` now refuses when a workout is already open, which is the invariant that stops
  /// data being orphaned. Refusing is only safe if the app then offers that workout back instead of
  /// showing an error next to a button that will never work.
  private func start(_ makeCoordinator: () throws -> SessionCoordinator) {
    do {
      coordinator = try makeCoordinator()
      startFailed = false
      selectedTab = .train
    } catch LoggerStoreError.sessionAlreadyOpen {
      // Not an error the lifter caused or can act on. Their open workout is what they wanted.
      if adoptOpenSession() {
        selectedTab = .train
      } else {
        startFailed = true
      }
    } catch {
      startFailed = true
    }
  }

  private func startEmptyWorkout() {
    start {
      // An empty plan on purpose: the app does not invent a program, and there is no generator
      // yet. Movements are added from the picker as the lifter goes.
      try SessionCoordinator.start(
        store: environment.logger,
        gymID: selectedGym,
        plan: [],
        restAfterSet: resolvedRest,
        hooks: hooks
      )
    }
  }

  // MARK: - Accessory

  @ViewBuilder private var liveSessionAccessory: some View {
    if let coordinator {
      HStack(spacing: Tokens.Spacing.snug) {
        Image(systemName: "figure.strengthtraining.traditional")
        // Inflected rather than concatenated, so one set does not read "1 sets".
        Text("^[\(coordinator.loggedSetCount) set](inflect: true) logged")
          .font(Tokens.Text.caption)
          .monospacedDigit()
        Spacer(minLength: 0)
        if case .running(let endsAt) = hooks.state() {
          // System-rendered from the deadline, so the accessory costs no updates.
          Text(timerInterval: Date()...max(endsAt, Date()), countsDown: true)
            .font(Tokens.Text.caption)
            .monospacedDigit()
            .foregroundStyle(Tokens.Color.accent)
        }
      }
      .padding(.horizontal, Tokens.Spacing.regular)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        Text("Workout in progress, ^[\(coordinator.loggedSetCount) set](inflect: true) logged")
      )
    }
  }
}

/// A closed workout plus the span it occupied, carried from the logger to the summary.
///
/// The timeline travels alongside the outcome because `SessionOutcome` deliberately exposes only a
/// duration it is willing to state -- it does not hand out the raw instants -- while the summary
/// still needs them to query the muscle breakdown for exactly this session's window.
struct FinishedSession {
  let outcome: SessionOutcome
  let timeline: SessionTimeline
  /// Carried so the summary's muscle breakdown can be scoped to this workout rather than to the
  /// span between its start and finish, which is half-open at the top and cannot tell whose sets
  /// it is counting.
  let sessionID: SessionID
}

/// `sheet(item:)` needs an `Identifiable`, and an id is a value with no natural one of its own.
struct RenameTarget: Identifiable, Hashable {
  let id: UUID
}

/// The three tabs, as a value the root can set.
enum RootTab: Hashable {
  case train, plan, volume, history
}
