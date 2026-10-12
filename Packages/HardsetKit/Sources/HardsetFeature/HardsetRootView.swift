import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The root's tabs, as a selection value, so the accessory and "Repeat this workout" can bring
/// the lifter back to Train. `nonisolated` like the Store's value types: it is a plain value, and
/// its `Hashable` conformance should not be tied to the main actor.
private nonisolated enum RootTab: Hashable {
  case train, volume, history
}

/// The finished workout whose summary is showing. Wrapped because `sheet(item:)` needs
/// `Identifiable`, the same reason `LiveSessionScreen` wraps its machine target.
private nonisolated struct SummaryTarget: Identifiable, Hashable {
  let id: SessionID
}

/// The app's three tabs, plus the workout-in-progress bar, which is also the one rest cluster.
///
/// A live session is deliberately NOT a full-screen modal. It lives in the tab bar's bottom
/// accessory, so a lifter mid-workout can still open their history or check the last 7 days of
/// volume without abandoning the session — which is what a modal would force. That slot is what
/// `tabViewBottomAccessory` exists for, and the tab bar minimises on scroll so the set grid keeps
/// the screen.
@MainActor
public struct HardsetRootView: View {
  @State private var coordinator: SessionCoordinator?
  /// Which tab shows. Held here so tapping the accessory, or repeating a workout from History,
  /// can return the lifter to Train.
  @State private var selectedTab: RootTab = .train
  /// The workout just finished, whose summary is presented over the tabs. Set only after
  /// `LiveSessionScreen` reports the finish written; a discarded workout has nothing to show.
  @State private var summaryTarget: SummaryTarget?
  @State private var startFailed = false
  /// Why a workout left open could not be reopened, in the user's words. While this is set the
  /// start button is not offered: a `try?` here made a stranded open session look like "no
  /// workout", and starting a second one on top of it is the one thing that must not be possible.
  @State private var resumeError: String?
  /// Why the movement list could not be prepared. Does not block a workout, but the picker is
  /// empty without it, so it is stated rather than left as a catalogue that is silently bare.
  @State private var catalogueError: String?
  /// Where the next workout will be. Preselected from the last one, changeable in one tap, and
  /// allowed to stay nil — training somewhere new must not require setup first.
  @State private var selectedGym: GymID?
  @State private var gymOptions: [GymRecord] = []
  @State private var isChoosingGym = false
  @State private var isShowingSettings = false
  /// Inferred from the device's locale on first launch rather than asked, and stored the moment the
  /// user disagrees. Kilograms remain the canonical storage unit either way — this only decides
  /// what is displayed and what typed numbers are read as.
  @AppStorage("hardset.useImperial") private var useImperial =
    Locale.current.measurementSystem == .us
  /// Why the last gym write failed, in the user's words. A `try?` here hid a real failure behind a
  /// button that appeared to do nothing, which is precisely what this app is not allowed to do.
  @State private var gymError: String?
  private let environment: HardsetEnvironment
  /// Overrides the stored preference. Exists for previews and tests; the app passes `nil` so the
  /// user's own choice wins.
  private let unitOverride: WeightUnit?
  private let hooks: RestTimerHooks
  private let restPreferences: any RestPreferenceStore

  public init(
    environment: HardsetEnvironment,
    unit: WeightUnit? = nil,
    hooks: RestTimerHooks = .inert,
    restPreferences: any RestPreferenceStore = InMemoryRestPreferences()
  ) {
    self.environment = environment
    self.unitOverride = unit
    self.hooks = hooks
    self.restPreferences = restPreferences
  }

  /// What every screen displays in. One derivation, so no screen can disagree with another.
  private var unit: WeightUnit {
    unitOverride ?? (useImperial ? .pounds : .kilograms)
  }

  public var body: some View {
    tabs
      // On the TabView, not inside Train: `LiveSessionScreen` is torn down the moment its session
      // ends, so a sheet it presented would go with it.
      .sheet(item: $summaryTarget) { target in
        SummarySheet(sessionID: target.id, store: environment.summaries, unit: unit) {
          summaryTarget = nil
        }
      }
      .task {
        prepareCatalogue()
        // A workout left open is offered back before anything else. Nothing is closed on the
        // app's initiative.
        resumeOpenWorkout()
        refreshGyms()
      }
  }

  /// Seeding is idempotent and non-destructive, so running it every launch is the intended usage
  /// rather than something to guard with a flag that can drift from reality. A failure is kept and
  /// shown, with a retry, because it used to vanish and leave an empty picker with no explanation.
  private func prepareCatalogue() {
    do {
      _ = try environment.catalog.seed()
      catalogueError = nil
    } catch {
      catalogueError = FailureCopy.message(for: error, during: .prepareCatalogue)
    }
  }

  /// Reopens the workout that was left open, if there is one. Finding none is a normal answer; a
  /// read that FAILED is not, and is kept apart from it so "no workout" is never shown while one
  /// may exist.
  private func resumeOpenWorkout() {
    guard coordinator == nil else { return }
    do {
      coordinator = try SessionCoordinator.resume(
        store: environment.logger,
        restPreferences: restPreferences,
        onStartRest: { duration, metadata in hooks.start(duration, metadata) }
      )
      resumeError = nil
    } catch {
      resumeError = FailureCopy.message(for: error, during: .resumeWorkout)
    }
  }

  @ViewBuilder private var tabs: some View {
    let content = TabView(selection: $selectedTab) {
      Tab("Train", systemImage: "figure.strengthtraining.traditional", value: RootTab.train) {
        NavigationStack {
          trainTab
            .safeAreaInset(edge: .top, spacing: 0) { catalogueNotice }
            .toolbar {
              // `.primaryAction` rather than `.topBarTrailing`: the latter does not exist on
              // macOS, and this target builds for the host so the suite can run there.
              ToolbarItem(placement: .primaryAction) {
                Button {
                  isShowingSettings = true
                } label: {
                  Label("Settings", systemImage: "gearshape")
                }
              }
            }
            .sheet(isPresented: $isShowingSettings) {
              SettingsSheet(useImperial: $useImperial) { isShowingSettings = false }
            }
        }
      }
      Tab("Volume", systemImage: "chart.bar", value: RootTab.volume) {
        NavigationStack {
          WeeklyVolumeScreen(store: environment.volume)
            .navigationTitle("Last 7 days")
        }
      }
      Tab("History", systemImage: "clock.arrow.circlepath", value: RootTab.history) {
        NavigationStack {
          HistoryScreen(
            store: environment.history,
            unit: unit,
            // Hidden, not swapped for a confirmation, while a workout is open or may be open
            // unread: repeating then would start a second workout on top of the first.
            onRepeat: canStartWorkout ? { repeatWorkout($0) } : nil
          )
          .navigationTitle("History")
        }
      }
    }

    #if os(iOS)
      // `isEnabled:` keeps one TabView identity whether or not a session exists. The old `if/else`
      // swapped identity, which reset tab state on every start and finish. Attaching the
      // accessory unconditionally, with an empty view inside, drew an empty pill above the tab
      // bar on the start screen — the slot is reserved by the modifier, not by its content.
      // `isEnabled:` is the documented way to show and hide it.
      content
        .tabViewBottomAccessory(isEnabled: coordinator != nil) {
          if let coordinator {
            LiveSessionAccessory(
              coordinator: coordinator, hooks: hooks, onOpen: { selectedTab = .train })
          }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    #else
      content
    #endif
  }

  /// Whether a new workout may start: none is open, and none may be sitting open unread. The same
  /// rule that hides Start while `resumeError` is set.
  private var canStartWorkout: Bool { coordinator == nil && resumeError == nil }

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
        shortcuts: environment.shortcuts,
        // `self.` because `coordinator` here is the unwrapped local. A finished workout's summary
        // is read back by its id; a discarded one no longer exists, so it goes straight back to
        // the start screen.
        onFinished: { exit in
          self.coordinator = nil
          if case .finished(let id) = exit { summaryTarget = SummaryTarget(id: id) }
        }
      )
      .navigationTitle("Workout")
    } else if let resumeError {
      resumeFailedView(message: resumeError)
    } else {
      startView
    }
  }

  /// Shown INSTEAD of `startView`, never beside it. "No workout in progress" and a start button
  /// would both be untrue claims while a workout may be sitting open that could not be read.
  /// "Try again" is a real button because there is no scroll view here for a pull to refresh.
  private func resumeFailedView(message: String) -> some View {
    ContentUnavailableView {
      Label("Workout unavailable", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("Try again") { resumeOpenWorkout() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Tokens.Color.background)
  }

  /// Sits above whichever Train screen is showing, because the empty picker it explains lives
  /// inside the live session and cannot say why it is empty.
  @ViewBuilder private var catalogueNotice: some View {
    if let catalogueError {
      VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
        Text(catalogueError)
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.critical)
        Button {
          prepareCatalogue()
        } label: {
          Text("Try again")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.accent)
            .frame(minHeight: Tokens.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Tokens.Spacing.section)
      .background(Tokens.Color.background)
    }
  }

  private var startView: some View {
    StartWorkoutView(
      gymName: selectedGymName,
      startFailed: startFailed,
      onChooseGym: { isChoosingGym = true },
      onStart: startEmptyWorkout
    )
    .sheet(isPresented: $isChoosingGym) {
      GymPickerSheet(
        gyms: gymOptions,
        selected: $selectedGym,
        error: gymError,
        onAddGym: { addGym(named: $0) },
        onDone: { isChoosingGym = false }
      )
    }
  }

  private var selectedGymName: String? {
    selectedGym.flatMap { id in gymOptions.first { $0.id == id }?.name }
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
      // Stated, not swallowed, and in the user's words: the underlying error can carry database
      // internals that mean nothing to a lifter and do not belong on screen.
      gymError = FailureCopy.message(for: error, during: .saveGym)
    }
  }

  private func startEmptyWorkout() {
    do {
      // An empty plan on purpose: the app does not invent a program, and there is no generator
      // yet. Movements are added from the picker as the lifter goes.
      coordinator = try SessionCoordinator.start(
        store: environment.logger,
        gymID: selectedGym,
        plan: [],
        restPreferences: restPreferences,
        hooks: hooks
      )
      startFailed = false
    } catch {
      startFailed = true
    }
  }

  /// Starts a workout from a past one: its movements, in order, on the machines it ended on.
  ///
  /// Runs only from the lifter's own choice of "Repeat this workout" on a history row; nothing
  /// preselects or suggests it. The plan is read here, from that action, never in `body`. It holds
  /// no loads, so rows and prefills come from the latest history at start, as for any workout,
  /// not from the one being repeated.
  private func repeatWorkout(_ id: SessionID) {
    // The action is hidden while this is false; this guards a menu opened just before that.
    guard canStartWorkout else { return }
    do {
      let plan = try environment.shortcuts.repeatPlan(of: id)
      guard !plan.isEmpty else { return }
      coordinator = try SessionCoordinator.start(
        store: environment.logger,
        gymID: plan.gymID,
        plan: plan.plannedExercises,
        restPreferences: restPreferences,
        hooks: hooks
      )
      selectedGym = plan.gymID
      startFailed = false
      selectedTab = .train
    } catch {
      // Nothing was started. Train's start screen says so, so the lifter is taken there.
      startFailed = true
      selectedTab = .train
    }
  }
}

/// A finished workout's summary, read back from the database rather than carried over from the
/// screen, so it states what was saved.
///
/// It is presented only after the finish was written, which is why its failure copy says the
/// workout is saved. The read runs in `.task` and on Try again, never in `body`.
private struct SummarySheet: View {
  private let sessionID: SessionID
  private let store: WorkoutSummaryStore
  private let unit: WeightUnit
  private let onDone: () -> Void
  @State private var summary: WorkoutSummary?
  /// Why the read failed, in the lifter's words.
  @State private var loadError: String?

  /// Spelled out: the stored properties are private, which makes the synthesised memberwise
  /// initialiser private too, and the root could not call it.
  init(
    sessionID: SessionID,
    store: WorkoutSummaryStore,
    unit: WeightUnit,
    onDone: @escaping () -> Void
  ) {
    self.sessionID = sessionID
    self.store = store
    self.unit = unit
    self.onDone = onDone
  }

  var body: some View {
    WorkoutSummaryView(
      summary: summary,
      unit: unit,
      errorMessage: loadError,
      onRetry: { load() },
      onDone: onDone
    )
    .task { load() }
  }

  private func load() {
    do {
      summary = try store.summary(for: sessionID)
      loadError = nil
    } catch {
      loadError = FailureCopy.message(for: error, during: .loadSummary)
    }
  }
}
