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
/// accessory, so a lifter mid-workout can still open their history or check the week's volume
/// without abandoning the session — which is what a modal would force. That slot is what
/// `tabViewBottomAccessory` exists for, and the tab bar minimises on scroll so the set grid keeps
/// the screen.
@MainActor
public struct HardsetRootView: View {
  @State private var model: WorkoutRootModel
  @State private var startFailed = false
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
    Group {
      if model.isReady {
        tabs
      } else if model.lastError != nil {
        VStack(spacing: Tokens.Spacing.section) {
          HardsetEmptyState(
            title: "Could not load your workout",
            detail: "Try again before starting a new workout.",
            systemImage: "exclamationmark.triangle"
          )
          Button {
            Task { await model.load() }
          } label: {
            Text("Try again")
              .frame(minHeight: Tokens.minimumTapTarget)
          }
          .buttonStyle(.borderedProminent)
        }
        .padding(Tokens.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.background)
      } else {
        ProgressView("Loading your workout")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Tokens.Color.background)
      }
    }
    .task { await model.load() }
  }

  @ViewBuilder private var tabs: some View {
    let content = TabView {
      Tab("Train", systemImage: "figure.strengthtraining.traditional") {
        NavigationStack {
          trainTab
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
                .hardsetSheet()
            }
        }
      }
      Tab("Volume", systemImage: "chart.bar") {
        NavigationStack {
          WeeklyVolumeScreen(store: environment.volume)
            .navigationTitle("This week")
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
        onFinished: { model.clearFinishedWorkout() }
      )
      .navigationTitle("Workout")
    } else {
      startView
    }
  }

  private var startView: some View {
    VStack(spacing: Tokens.Spacing.loose) {
      Spacer()

      HardsetEmptyState(
        title: "No workout in progress",
        detail: "Start an empty workout and add movements as you go.",
        systemImage: "figure.strengthtraining.traditional"
      )

      gymRow

      Button(action: startEmptyWorkout) {
        Text("Start workout")
          .font(Tokens.Text.labelEmphasis)
          .foregroundStyle(Tokens.Color.background)
          .frame(maxWidth: .infinity, minHeight: Tokens.loggerTapTarget)
          .background(Tokens.Color.accent, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, Tokens.Spacing.section)

      if startFailed {
        Text("Could not start a workout. Nothing has been lost — try again.")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.certainty(.low))
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Tokens.Color.background)
    .sheet(isPresented: $isChoosingGym) { gymSheet.hardsetSheet() }
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
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Tokens.Color.accent)
        Text(selectedGymName ?? "Add a gym to track machines")
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(Tokens.Text.caption)
          .foregroundStyle(Tokens.Color.textSecondary)
      }
      .font(Tokens.Text.caption)
      .foregroundStyle(
        selectedGymName == nil ? Tokens.Color.textSecondary : Tokens.Color.textPrimary
      )
      .frame(minHeight: Tokens.minimumTapTarget)
      .padding(.horizontal, Tokens.Spacing.regular)
      .contentShape(Rectangle())
      .hardsetCard(cornerRadius: Tokens.Radius.control)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, Tokens.Spacing.section)
  }

  private var selectedGymName: String? {
    model.selectedGym.flatMap { id in model.gymOptions.first { $0.id == id }?.name }
  }

  private var gymSheet: some View {
    NavigationStack {
      GymPickerView(
        gyms: model.gymOptions.map { GymOption(id: $0.id, name: $0.name) },
        selected: model.selectedGym,
        errorMessage: gymError,
        onSelect: { id in
          model.selectedGym = id
          isChoosingGym = false
        },
        onAddGym: { isAddingGym = true }
      )
      .navigationTitle("Where are you training?")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
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
        .hardsetSheet()
      }
    }
  }

  /// Takes the name as an argument rather than reading it back out of state. The version that
  /// read `@State` written by a `TextField` inside an `.alert` received an empty string every
  /// time, so no gym was ever created even though the field visibly held text.
  private func addGym(named name: String) {
    guard !name.isEmpty else { return }
    let id: GymID
    do {
      id = try environment.gyms.createGym(name: name)
    } catch {
      gymError = "\(name) could not be saved. \(error)"
      return
    }
    model.selectedGym = id
    do {
      try model.refreshGyms()
      gymError = nil
      isChoosingGym = false
    } catch {
      // The write succeeded; a failed follow-up read must not claim it did not.
      gymError = "The gym was saved, but its list could not be read."
    }
  }

  private func startEmptyWorkout() {
    do {
      try model.startWorkout()
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
