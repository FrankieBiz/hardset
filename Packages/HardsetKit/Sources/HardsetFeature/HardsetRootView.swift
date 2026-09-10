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
  /// Produces the CSV a lifter takes their history away in.
  public let export: ExportStore
  /// Permanently removes user-created rows while preserving the bundled exercise catalogue.
  public let dataDeletion: DataDeletionStore

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
    self.export = ExportStore(database: database)
    self.dataDeletion = DataDeletionStore(database: database)
  }
}

/// The app's tabs, plus the workout-in-progress bar.
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
  /// Starting reads prior performance and creates the first rows. While that happens the button
  /// remains visibly busy and cannot launch a duplicate session.
  @State private var isStartingWorkout = false
  /// A workout is open in the database but could not be reopened. Stated, because the alternative is
  /// the lifter training a second time into a day whose sets they cannot see.
  @State private var recoveryFailed = false
  @State private var isPreparing = true
  @State private var startupError: String?
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
  /// Whether the lifter has ever been asked about the rest timer.
  ///
  /// Distinct from `restSeconds == 0`, and that distinction is the whole point: zero means "no
  /// timer", and until this flag is set it is impossible to tell that apart from "never asked".
  /// Conflating them is why the flagship feature never started itself -- a lifter who never opened
  /// Settings had the rest timer silently off forever, and nothing ever requested the AlarmKit
  /// permission it needs either.
  ///
  /// Asking is not prescribing. DECISIONS #6 refuses a *literature* default rest length and #27
  /// refuses a *learned* one; neither says the app may not put the question in front of the
  /// person whose decision it is. Off is offered first and is a real answer.
  @AppStorage("hardset.hasChosenRest") private var hasChosenRest = false
  @State private var isChoosingRest = false
  /// The action the lifter asked for before the first-use rest question appeared.
  ///
  /// Starting immediately after setting `isChoosingRest` replaced the start screen in the same
  /// update that was supposed to present its sheet. SwiftUI discarded the presentation and the
  /// flagship choice never appeared. Holding a value here lets the sheet dismiss first, then
  /// performs the exact start the lifter requested from Train, Plan, or History.
  @State private var pendingStart: WorkoutStartRequest?
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
  /// Whether there is a plan with something on it to point at.
  ///
  /// The start screen used to describe only the empty-workout path, so a lifter with a four-day
  /// split landed on "add movements as you go" and nothing said their plan existed -- the one hop
  /// the planner was built to provide was reachable only by knowing to look in another tab. A
  /// boolean rather than the days themselves: which plan is selected belongs to the planner, and
  /// answering that twice is how two screens come to disagree.
  @State private var hasStartablePlan = false
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
      .sheet(isPresented: $isChoosingRest, onDismiss: continuePendingStart) {
        restChoiceSheet
      }
      // Dark-only in v1, and forced rather than following the system. One palette tuned precisely
      // beats two tuned adequately, and this app is read at arm's length in a badly lit gym.
      //
      // Our own tokens are appearance-independent already -- they resolve to the same values in
      // either scheme -- so this exists for the chrome we do not draw: list backgrounds, the tab
      // bar, navigation bars, `ContentUnavailableView`. Light mode stays a later decision, which
      // is cheap because `Tokens.Color.dynamic` already has a slot waiting for it.
      // Keeps a live session in step with the setting. Without this, turning the rest timer on
      // mid-workout silently does nothing until the next session.
      // A plan built in the Plan tab must be visible on the Train tab without relaunching.
      .onChange(of: selectedTab) { _, tab in
        if tab == .train { Task { await refreshPlanAvailability() } }
      }
      .onChange(of: resolvedRest) { _, updated in
        coordinator?.restAfterSet = updated
        // Asked for the first time the lifter actually chooses a rest length. Nothing in the app
        // ever requested AlarmKit permission, so every schedule on a fresh install was refused and
        // the timer counted down in silence.
        if updated != nil {
          Task { await hooks.requestAuthorization() }
          // Choosing a length in Settings *is* the answer to the first-use question. Only the rest
          // sheet wrote `hasChosenRest`, so a lifter who set 90 s in Settings was asked again at
          // their next workout and saw their own answer sitting unticked.
          //
          // Guarded on a non-nil duration rather than on any change, because deleting all data
          // resets `restSeconds` to 0 and `hasChosenRest` to false in the same update — an
          // unguarded write here would immediately mark the question answered again.
          hasChosenRest = true
        }
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
      .task { await prepareForUse() }
      // Titled with what happened, not with an instruction OK cannot carry out. "Hardset needs
      // another try" promised a retry the alert's one button does not offer — and does not need
      // to, since `catalog.seed()` runs again on every launch.
      .alert(
        "The movement list is incomplete",
        isPresented: Binding(get: { startupError != nil }, set: { if !$0 { startupError = nil } })
      ) {
        Button("OK") { startupError = nil }
      } message: {
        Text(startupError ?? "Your existing data is safe.")
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

  /// The gear, attached to every tab's stack rather than only to Train.
  ///
  /// Units, the rest length, RPE, export and delete are not Train-tab concerns: a lifter reading
  /// the week's volume in pounds had to go back to Train to change the unit. The sheet itself is
  /// hoisted onto the `TabView` (see `tabs`) rather than repeated here — all four stacks stay alive
  /// inside the tab view, so four presentations bound to one boolean would fight over it.
  @ToolbarContentBuilder private var settingsToolbar: some ToolbarContent {
    // `.primaryAction` rather than `.topBarTrailing`: the latter does not exist on macOS, and this
    // target builds for the host so the suite can run there.
    ToolbarItem(placement: .primaryAction) {
      Button {
        isShowingSettings = true
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
    }
  }

  private var settingsSheet: some View {
    SettingsSheet(
      useImperial: $useImperial,
      restSeconds: $restSeconds,
      tracksRPE: $tracksRPE,
      bodyweight: environment.bodyweight,
      export: environment.export,
      dataDeletion: environment.dataDeletion,
      gyms: environment.gyms,
      unit: unit,
      restAlertsDenied: hooks.isDenied(),
      canDeleteData: coordinator == nil,
      onDataDeleted: handleAllDataDeleted
    ) { isShowingSettings = false }
  }

  @ViewBuilder private var trainNavigation: some View {
    NavigationStack {
      trainTab
        .toolbar { settingsToolbar }
    }
  }

  /// `nil` while a workout is open, which hides "Start this day" rather than offering a button that
  /// would abandon the session in progress. Same shape and same reason as `repeatHandler`.
  private var startDayHandler: ((PlannedDayStart) -> Void)? {
    guard coordinator == nil else { return nil }
    return { day in startPlannedDay(day) }
  }

  @ViewBuilder private var planNavigation: some View {
    NavigationStack {
      SplitPlannerScreen(
        splits: environment.splits,
        catalog: environment.catalog,
        gyms: environment.gyms,
        volume: environment.volume,
        exercises: environment.exercises,
        unit: unit,
        // The gym the next workout will be at, so the planner's machine choices and its
        // "available here" section agree with the session its own button starts.
        gymID: selectedGym,
        onStartDay: startDayHandler
      )
      .navigationTitle("Plan")
      .toolbar { settingsToolbar }
    }
  }

  @ViewBuilder private var volumeNavigation: some View {
    NavigationStack {
      WeeklyVolumeScreen(store: environment.volume)
        .navigationTitle("Volume")
        .toolbar { settingsToolbar }
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
      .toolbar { settingsToolbar }
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
    // One presentation for four gears. Bound above the tab view rather than inside each stack,
    // because all four stacks stay alive and four `.sheet`s on one boolean race to present.
    //
    // Refreshed on dismissal: Settings → Machines can create a gym, and `gymOptions` is only
    // rebuilt by `refreshGyms()`. A gym added there was missing from the start screen's picker
    // until the next launch, so the lifter added it a second time.
    .sheet(isPresented: $isShowingSettings, onDismiss: { Task { await refreshGyms() } }) {
      settingsSheet
    }

    #if os(iOS)
      // The accessory is attached only while a session exists. Attaching it unconditionally and
      // returning an empty view inside drew an empty pill above the tab bar on the start screen —
      // the slot is reserved by the modifier, not by its content.
      //
      // Flipping this conditional is not free, and merging the branches is not the fix. The two
      // arms are a `_ConditionalContent` with different static types, so the whole tab view is torn
      // down and rebuilt on each flip: every tab's `NavigationStack` path and per-screen `@State`
      // resets, `WeeklyVolumeScreen`'s `anchor`/`weekOffset` most visibly. It is paid at start and
      // at finish, both of which move the lifter to Train anyway. The only correct fix is hoisting
      // the browsing state that matters to the root — not attaching the accessory unconditionally,
      // which brings the empty pill back.
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
    } else if isPreparing {
      ProgressView("Preparing Hardset…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.ground)
    } else {
      startView
    }
  }

  /// Scrolls rather than clips.
  ///
  /// This was a fixed-height centred stack. At AX5 the empty state's two multi-line paragraphs, the
  /// gym row, the plan link, a 56 pt primary button and up to three error paragraphs are taller
  /// than the screen, and the bottom of it — including the button the screen exists for — was
  /// simply cut off.
  private var startView: some View {
    GeometryReader { proxy in
      ScrollView {
        startContent
          // Preserves the vertical centring the old `maxHeight: .infinity` gave: `minHeight` on a
          // frame centres its content, and only grows past the screen once the content does.
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
      // No rubber-banding at default text sizes, where nothing overflows and a scroll view that
      // bounces reads as a screen with something hidden below it.
      .scrollBounceBehavior(.basedOnSize)
    }
    .background(Tokens.Color.ground)
    .sheet(isPresented: $isChoosingGym) { gymSheet }
  }

  private var startContent: some View {
    VStack(spacing: Tokens.Spacing.loose) {
      workoutEmptyState
      gymRow

      if hasStartablePlan {
        // Navigation, not a recommendation. It names no day and orders nothing -- it says a plan
        // exists and moves to it, which is the tab that owns choosing a day.
        Button {
          selectedTab = .plan
        } label: {
          HStack(spacing: Tokens.Spacing.snug) {
            Image(systemName: "square.split.2x2")
            Text("Start a day from your plan")
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
              .font(Tokens.Text.caption)
          }
          .font(Tokens.Text.label)
          .foregroundStyle(Tokens.Color.textPrimary)
          .frame(minHeight: Tokens.minimumTapTarget)
          .padding(.horizontal, Tokens.Spacing.regular)
          .background(
            Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.Spacing.edge)
      }

      // The primary action is a white fill with a `ground` label -- the brightest object on the
      // screen, and there is at most one. This was white-on-surface, which made it read as
      // secondary and disagreed with the same control on the summary screen.
      Button(action: startEmptyWorkout) {
        HStack(spacing: Tokens.Spacing.snug) {
          if isStartingWorkout { ProgressView().controlSize(.small) }
          Text(isStartingWorkout ? "Starting…" : "Start workout")
        }
        .font(Tokens.Text.label.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
        .foregroundStyle(Tokens.Color.ground)
        .background(
          Tokens.Color.accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.control)
        )
      }
      .buttonStyle(CommitButtonStyle())
      .disabled(isStartingWorkout)
      .padding(.horizontal, Tokens.Spacing.edge)

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
      if let gymError {
        // Said here as well as in the gym sheet. The sheet is the only place this was rendered, and
        // it is not open at launch — so a failed read left the row reading "Add a gym to track
        // machines", which is a fresh-install invitation printed over an unknown failure.
        Text(gymError)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The system `ContentUnavailableView` rendered this description correctly, but exposed it to
  /// the iOS 26 accessibility runtime as a fixed-size node. This state uses only semantic fonts,
  /// so a lifter's Dynamic Type setting reaches the first instructions the app ever shows them.
  private var workoutEmptyState: some View {
    VStack(spacing: Tokens.Spacing.snug) {
      Image(systemName: "figure.strengthtraining.traditional")
        .font(Tokens.Text.hero)
        .foregroundStyle(Tokens.Color.textSecondary)
        .accessibilityHidden(true)
      Text("No workout in progress")
        .font(Tokens.Text.title)
        .foregroundStyle(Tokens.Color.textPrimary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      // Names both paths when both exist. Describing only the empty one made the planner look
      // like a document rather than a way into a workout.
      Text(
        hasStartablePlan
          ? "Start a day from your plan, or an empty workout you add movements to as you go."
          : "Start an empty workout and add movements as you go."
      )
      .font(Tokens.Text.label)
      .foregroundStyle(Tokens.Color.textSecondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, Tokens.Spacing.section)
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
        // Two different nil cases, and only one of them is an invitation: "Not recorded" is a
        // choice the sheet deliberately offers, and inviting someone to add a gym they already
        // declined reads as the app having lost their answer. Same wording as the sheet's own row.
        Text(
          selectedGymName ?? (gymOptions.isEmpty ? "Add a gym to track machines" : "Not recorded")
        )
        .fixedSize(horizontal: false, vertical: true)
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
    .padding(.horizontal, Tokens.Spacing.edge)
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
              Button {
                renamingGym = RenameTarget(id: gym.id.rawValue)
              } label: {
                Label("Rename", systemImage: "pencil")
              }
            }
            // `allowsFullSwipe: false`, matching `HistoryView`: the default fires the destructive
            // action on one continuous swipe without ever drawing the button, and retiring is
            // currently one-way — `GymStore` has no unarchive, so a gym retired by a gesture the
            // lifter never saw takes its machines out of every picker for good. Revealing the
            // button and having it tapped is this project's confirmation; a dialog here would
            // disagree with the equally destructive workout delete.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

          Button {
            isAddingGym = true
          } label: {
            // Spacer and `contentShape` so the hit area is the row, not the glyph and its label —
            // the same defect the history row had, and the sibling directly above already fixes.
            HStack {
              Label("Add a gym", systemImage: "plus")
              Spacer(minLength: 0)
            }
            .frame(minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
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

  /// Performs launch reads without freezing the first interactive frame. The only main-actor step
  /// is rebuilding an open coordinator, whose observable state belongs to the UI by design.
  private func prepareForUse() async {
    // Seeding is idempotent and non-destructive, so running it every launch is intended. It is also
    // dozens of writes and used to run synchronously before the first screen could respond.
    let catalog = environment.catalog
    let seedResult = await readOffMain { try catalog.seed() }
    guard !Task.isCancelled else { return }
    if case .failure = seedResult {
      startupError =
        "The movement catalogue could not be prepared, so the movement picker may be short or "
        + "empty. Nothing you have logged is affected. Reopening Hardset tries again."
    }

    // A workout left open is offered back before the start controls become available. Nothing is
    // closed on the app's initiative.
    if coordinator == nil { _ = await adoptOpenSession() }
    await refreshGyms()
    await refreshPlanAvailability()
    isPreparing = false
  }

  /// Retires a gym without touching what was logged there.
  private func retire(_ id: GymID) {
    do {
      try environment.gyms.archiveGym(id)
      if selectedGym == id { selectedGym = nil }
      gymError = nil
      Task { await refreshGyms() }
    } catch {
      // Said in the lifter's words rather than as a raw `\(error)` dump. "GymStoreError error 1"
      // tells them nothing about the only thing they need to know, which is that the gym and every
      // workout logged there are exactly as they were.
      gymError = "That gym could not be retired. Nothing was changed."
    }
  }

  private func rename(_ id: GymID, to name: String) {
    do {
      try environment.gyms.renameGym(id, to: name)
      gymError = nil
      Task { await refreshGyms() }
    } catch {
      gymError = "That gym could not be renamed. \(error)"
    }
  }

  /// Re-reads whether a plan exists to point at.
  ///
  /// A failure leaves the affordance hidden rather than showing a button to somewhere that may not
  /// be there: a control that navigates to an empty planner is worse than no control.
  private func refreshPlanAvailability() async {
    let splits = environment.splits
    let result = await readOffMain { try splits.hasStartableDay() }
    guard !Task.isCancelled else { return }
    switch result {
    case .success(let available): hasStartablePlan = available
    case .failure: hasStartablePlan = false
    }
  }

  private func refreshGyms() async {
    let gyms = environment.gyms
    let result = await readOffMain {
      let records = try gyms.gyms()
      return (records, try? gyms.lastUsedGym())
    }
    guard !Task.isCancelled else { return }
    guard case .success(let loaded) = result else {
      gymError = "Your gyms could not be read. Your workout history is safe; try again."
      return
    }
    gymOptions = loaded.0
    // Preselected from behaviour, not from a stored setting that could disagree with reality.
    if selectedGym == nil {
      selectedGym = loaded.1
    }
    // A gym that has since been archived must not stay selected invisibly.
    if let selectedGym, !gymOptions.contains(where: { $0.id == selectedGym }) {
      self.selectedGym = nil
    }
  }

  /// Resets the process state that lives outside SQLite after the database transaction succeeds.
  ///
  /// Settings disables deletion during an open workout, so there is no coordinator holding rows
  /// that just disappeared. The AlarmKit cancellation is still explicit: deleting the persisted
  /// timer row without cancelling the system alarm would leave an alert the app can no longer own.
  private func handleAllDataDeleted() {
    hooks.cancel()
    useImperial = Locale.current.measurementSystem == .us
    restSeconds = 0
    hasChosenRest = false
    tracksRPE = false
    selectedGym = nil
    gymOptions = []
    hasStartablePlan = false
    finished = nil
    // The warnings go too, or someone who has just erased everything is greeted by "A workout from
    // earlier is still open" over an empty database.
    recoveryFailed = false
    startFailed = false
    startupError = nil
    Task {
      await refreshGyms()
      await refreshPlanAvailability()
    }
  }

  /// Takes the name as an argument rather than reading it back out of state. The version that
  /// read `@State` written by a `TextField` inside an `.alert` received an empty string every
  /// time, so no gym was ever created even though the field visibly held text.
  private func addGym(named name: String) {
    guard !name.isEmpty else { return }
    do {
      let id = try environment.gyms.createGym(name: name)
      selectedGym = id
      gymError = nil
      isChoosingGym = false
      Task { await refreshGyms() }
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
    requestStart(.repeated(plan))
  }

  private func startRepeatedWorkout(_ plan: [RepeatableExercise]) {
    // `start` moves to the Train tab on success. Starting a workout the lifter cannot see would be
    // the same class of defect as a button that appears to do nothing.
    start {
      try await SessionCoordinator.startAsync(
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
  private func startPlannedDay(_ day: PlannedDayStart) {
    guard coordinator == nil, !day.exercises.isEmpty else { return }
    requestStart(.planned(day))
  }

  private func startRequestedDay(_ day: PlannedDayStart) {
    // `start` moves to the Train tab on success -- starting a workout the lifter cannot see is the
    // same class of defect as a button that appears to do nothing.
    start {
      try await SessionCoordinator.startAsync(
        store: environment.logger,
        gymID: selectedGym,
        // The lifter's own name for the day. Every workout the app started used to be nameless, so
        // starting "Push" produced a row that history could label only with its date -- discarding
        // a name the app already had. Still renameable from the live session.
        title: day.name,
        // Recorded on the session, which is what lets the planner say when each day was last
        // trained instead of asking the lifter to remember where they are in their own split.
        splitDayID: day.dayID,
        plan: day.exercises,
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
  private func adoptOpenSession() async -> Bool {
    // Cleared before the attempt, not only set after a failed one. Nothing ever set it back to
    // false, so one failed resume left the warning on the start screen for the rest of the process
    // — through a workout that started, finished and was summarised perfectly well.
    recoveryFailed = false
    do {
      coordinator = try await SessionCoordinator.resumeAsync(
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
  private func start(
    _ makeCoordinator: @escaping @MainActor () async throws -> SessionCoordinator
  ) {
    guard !isStartingWorkout, coordinator == nil else { return }
    isStartingWorkout = true
    startFailed = false
    recoveryFailed = false
    Task {
      defer { isStartingWorkout = false }
      do {
        coordinator = try await makeCoordinator()
        // The previous workout's summary is dismissed by the workout that replaces it. `trainTab`
        // renders `finished` ahead of `coordinator`, so Repeat or Start-this-day from another tab
        // used to switch to Train and show last session's summary over the live logger it had just
        // created. Cleared here on success rather than before the await: a start that then fails
        // would otherwise have thrown away a summary the lifter had not read.
        finished = nil
        selectedTab = .train
      } catch LoggerStoreError.sessionAlreadyOpen {
        // Not an error the lifter caused or can act on. Their open workout is what they wanted.
        if await adoptOpenSession() {
          finished = nil
          selectedTab = .train
        } else {
          startFailed = true
        }
      } catch {
        // Preparation begins by opening the session. If a later history read fails, recover that
        // real session instead of leaving the user beside a generic error after Start appeared to
        // do nothing.
        if await adoptOpenSession() {
          finished = nil
          selectedTab = .train
        } else {
          startFailed = true
        }
      }
    }
  }

  /// The one-time rest question.
  ///
  /// Every option is the lifter's; the app supplies no recommendation and marks nothing as
  /// suggested, because it has none — see DECISIONS #6 and #27. What it does supply is the
  /// question, at the one moment it is about to matter.
  @ViewBuilder private var restChoiceSheet: some View {
    NavigationStack {
      List {
        Section {
          ForEach(SettingsSheet.restOptions, id: \.self) { seconds in
            Button {
              restSeconds = seconds
              hasChosenRest = true
              isChoosingRest = false
            } label: {
              HStack {
                Text(seconds == 0 ? "No timer" : SettingsSheet.restLabel(seconds))
                  .foregroundStyle(Tokens.Color.textPrimary)
                Spacer()
                if restSeconds == seconds, hasChosenRest {
                  Image(systemName: "checkmark").foregroundStyle(Tokens.Color.accent)
                }
              }
              .frame(minHeight: Tokens.minimumTapTarget)
              .contentShape(Rectangle())
            }
          }
        } header: {
          Text("Rest between working sets")
        } footer: {
          Text(
            "Hardset has no recommended rest length — the literature does not establish one, so "
              + "the app will not invent one. Pick what you already do. It never starts after a "
              + "warm-up, and it keeps running if you leave the app or force-quit it. You can "
              + "change this any time in Settings."
          )
        }
      }
      .navigationTitle("Rest timer")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          // Dismissing without choosing still counts as answered. Asking again at the start of
          // every workout would be nagging, and Settings is one tap away.
          Button("Not now") {
            hasChosenRest = true
            isChoosingRest = false
          }
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func startEmptyWorkout() {
    requestStart(.empty)
  }

  /// Presents the one-time question before changing the screen that owns the start control.
  private func requestStart(_ request: WorkoutStartRequest) {
    guard coordinator == nil, pendingStart == nil else { return }
    guard hasChosenRest else {
      pendingStart = request
      isChoosingRest = true
      return
    }
    performStart(request)
  }

  /// Continues after the sheet is fully gone, including a swipe-down dismissal.
  private func continuePendingStart() {
    guard let request = pendingStart else { return }
    pendingStart = nil
    // Dismissing is the same answer as “Not now”. Asking on every workout would turn an optional
    // timer into a nag, and Settings remains one tap away.
    if !hasChosenRest { hasChosenRest = true }
    performStart(request)
  }

  private func performStart(_ request: WorkoutStartRequest) {
    switch request {
    case .empty:
      startEmptyWorkoutNow()
    case .repeated(let plan):
      startRepeatedWorkout(plan)
    case .planned(let day):
      startRequestedDay(day)
    }
  }

  private func startEmptyWorkoutNow() {
    start {
      // An empty plan on purpose: the app does not invent a program, and there is no generator
      // yet. Movements are added from the picker as the lifter goes.
      try await SessionCoordinator.startAsync(
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
      // A button, not a readout. This is the same slot the system gives a mini player, and it looks
      // exactly like one -- a capsule pinned above the tab bar naming what is playing -- so a lifter
      // three tabs away taps it to get back to their workout. It did nothing, which is the worst
      // shape a control can have: present, obvious, and inert.
      Button {
        selectedTab = .train
      } label: {
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
        .frame(maxWidth: .infinity, minHeight: Tokens.minimumTapTarget)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.textPrimary)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        Text("Workout in progress, ^[\(coordinator.loggedSetCount) set](inflect: true) logged")
      )
      .accessibilityHint("Double tap to return to your workout.")
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

/// The tabs, as a value the root can set.
enum RootTab: Hashable {
  case train, plan, volume, history
}

/// A first-use rest choice must not erase which route requested the workout.
private enum WorkoutStartRequest {
  case empty
  case repeated([RepeatableExercise])
  case planned(PlannedDayStart)
}
