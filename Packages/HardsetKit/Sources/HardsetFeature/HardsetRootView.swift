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
  public let gyms: GymStore

  public init(database: any DatabaseWriter) {
    self.logger = LoggerStore(database: database)
    self.catalog = CatalogSeeder(database: database)
    self.volume = VolumeStore(database: database)
    self.history = HistoryStore(database: database)
    self.progression = ProgressionStore(database: database)
    self.gyms = GymStore(database: database)
  }
}

/// The app's three tabs, plus the workout-in-progress bar.
///
/// A live session is deliberately NOT a full-screen modal. It lives in the tab bar's bottom
/// accessory, so a lifter mid-workout can still open their history or check the last 7 days of
/// volume without abandoning the session — which is what a modal would force. That slot is what
/// `tabViewBottomAccessory` exists for, and the tab bar minimises on scroll so the set grid keeps
/// the screen.
@MainActor
public struct HardsetRootView: View {
  @State private var coordinator: SessionCoordinator?
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
  @State private var isAddingGym = false
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
    let content = TabView {
      Tab("Train", systemImage: "figure.strengthtraining.traditional") {
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
      Tab("Volume", systemImage: "chart.bar") {
        NavigationStack {
          WeeklyVolumeScreen(store: environment.volume)
            .navigationTitle("Last 7 days")
        }
      }
      Tab("History", systemImage: "clock.arrow.circlepath") {
        NavigationStack {
          HistoryScreen(store: environment.history, unit: unit)
            .navigationTitle("History")
        }
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
    if let coordinator {
      LiveSessionScreen(
        coordinator: coordinator,
        unit: unit,
        hooks: hooks,
        catalog: environment.catalog,
        gyms: environment.gyms,
        progression: environment.progression,
        onFinished: { _ in self.coordinator = nil }
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
          .foregroundStyle(Tokens.Color.certainty(.low))
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
    VStack(spacing: Tokens.Spacing.loose) {
      ContentUnavailableView {
        Label("No workout in progress", systemImage: "figure.strengthtraining.traditional")
      } description: {
        Text("Start an empty workout and add movements as you go.")
      }
      gymRow

      Button(action: startEmptyWorkout) {
        Text("Start workout")
          .font(Tokens.Text.label.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(Tokens.Color.accent)
      .background(Tokens.Color.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
      .padding(.horizontal, Tokens.Spacing.section)

      if startFailed {
        Text("Could not start a workout. Nothing has been lost — try again.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Tokens.Color.background)
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
