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
  @State private var coordinator: SessionCoordinator?
  @State private var startFailed = false
  /// Where the next workout will be. Preselected from the last one, changeable in one tap, and
  /// allowed to stay nil — training somewhere new must not require setup first.
  @State private var selectedGym: GymID?
  @State private var gymOptions: [GymRecord] = []
  @State private var isChoosingGym = false
  @State private var isAddingGym = false
  @State private var isShowingSettings = false
  /// The newest finished workout, for the start screen. `nil` when there is none, and then the
  /// start screen shows nothing in its place rather than a placeholder that implies a history.
  @State private var lastWorkout: SessionSummary?
  /// Inferred from the device's locale on first launch rather than asked, and stored the moment the
  /// user disagrees. Kilograms remain the canonical storage unit either way — this only decides
  /// what is displayed and what typed numbers are read as.
  @AppStorage("hardset.useImperial") private var useImperial =
    Locale.current.measurementSystem == .us
  /// Why the last gym write failed, in the user's words. A `try?` here hid a real failure behind a
  /// button that appeared to do nothing, which is precisely what this app is not allowed to do.
  @State private var gymError: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

  public var body: some View {
    tabs
      // Readout cyan for tab selection, toolbar buttons and every system control underneath, in
      // place of the stock blue: that blue measured 3.5:1 on the light background and is the
      // colour of every other app.
      .tint(Tokens.Color.accent)
      .task {
        // Seeding is idempotent and non-destructive, so running it every launch is the intended
        // usage rather than something to guard with a flag that can drift from reality.
        _ = try? environment.catalog.seed()
        // A workout left open is offered back before anything else. Nothing is closed on the
        // app's initiative.
        if coordinator == nil {
          coordinator = try? SessionCoordinator.resume(
            store: environment.logger,
            restAfterSet: restAfterSet,
            onStartRest: { duration, metadata in hooks.start(duration, metadata) }
          )
        }
        refreshGyms()
        refreshLastWorkout()
      }
  }

  @ViewBuilder private var tabs: some View {
    let content = TabView {
      Tab("Train", systemImage: "figure.strengthtraining.traditional") {
        NavigationStack {
          trainTab
            // Attached above both states of the tab, so Settings opens from the start screen's
            // header and from the live session's alike, and finishing a workout while it is open
            // cannot pull its anchor out from under it.
            .sheet(isPresented: $isShowingSettings) {
              SettingsSheet(useImperial: $useImperial) { isShowingSettings = false }
                .hardsetSheet()
            }
        }
      }
      Tab("Volume", systemImage: "chart.bar.xaxis") {
        NavigationStack {
          // The screen draws its own header; the title stays as the screen's accessible name.
          WeeklyVolumeScreen(store: environment.volume)
            .navigationTitle("This week")
            .hardsetTabRoot()
        }
      }
      Tab("History", systemImage: "clock.arrow.circlepath") {
        NavigationStack {
          HistoryScreen(store: environment.history, unit: unit)
            .navigationTitle("History")
            .hardsetTabRoot()
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
        // A session can belong to a gym archived since it began. It still has machines, so the
        // header says a gym is recorded rather than claiming there is none.
        gymName: gymName(for: coordinator.gymID) ?? (coordinator.gymID == nil ? nil : "Saved gym"),
        onShowSettings: { isShowingSettings = true },
        onFinished: {
          self.coordinator = nil
          // The workout just finished is now the last one, so the start screen says so.
          refreshLastWorkout()
        }
      )
      // The live session draws its own header, with the gym and the settings action. The title
      // stays as the screen's accessible name; the stock bar is hidden.
      .navigationTitle("Workout")
      .hardsetTabRoot()
    } else {
      startView
        .navigationTitle("Train")
        .hardsetTabRoot()
    }
  }

  /// The start screen: where the lifter is, the one action, and what they did last time.
  ///
  /// Deliberately calm. There is no streak to keep and no prompt to train more, and nothing is
  /// filled in that the lifter has not recorded — with no history, the last-workout card is absent
  /// rather than a placeholder implying one.
  private var startView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Tokens.Spacing.block) {
        ScreenHeader("Train", subtitle: Self.today) {
          HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
            isShowingSettings = true
          }
        }

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
    .sheet(isPresented: $isChoosingGym) { gymSheet.hardsetSheet() }
  }

  /// Today, as the start screen's context line: "Saturday 7 November", in the device's format.
  private static var today: String {
    Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
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
    gymName(for: selectedGym)
  }

  /// "Add" when there is nothing to choose from yet, "Choose" when there is. Asking someone to
  /// add a gym they already have would send them to the wrong button.
  private var gymInvitation: String {
    gymOptions.isEmpty ? "Add a gym to track machines" : "Choose a gym to track machines"
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
    return gymOptions.first { $0.id == id }?.name
  }

  // MARK: - Last workout

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
        gyms: gymOptions.map { GymOption(id: $0.id, name: $0.name) },
        selected: selectedGym,
        errorMessage: gymError,
        onSelect: { id in
          selectedGym = id
          isChoosingGym = false
        },
        onAddGym: { isAddingGym = true }
      )
      .hardsetNavigationTitle("Where are you training?")
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

  /// `try?` deliberately, unlike the gym write below: this reads something optional to show, and a
  /// failure leaves the card absent rather than wrong. The history tab, which depends entirely on
  /// the same read, states its failure in full.
  private func refreshLastWorkout() {
    lastWorkout = (try? environment.history.recentSessions(limit: 1))?.first
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

  private func startEmptyWorkout() {
    do {
      // An empty plan on purpose: the app does not invent a program, and there is no generator
      // yet. Movements are added from the picker as the lifter goes.
      coordinator = try SessionCoordinator.start(
        store: environment.logger,
        gymID: selectedGym,
        plan: [],
        restAfterSet: restAfterSet,
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
        // A steady mark, not a pulse: the workout is open, and nothing about that changes from
        // second to second, so nothing here moves.
        Circle()
          .fill(Tokens.Color.accent)
          .frame(width: Tokens.Spacing.snug, height: Tokens.Spacing.snug)
          .accessibilityHidden(true)
        loggedSetsLine(coordinator.loggedSetCount)
        Spacer(minLength: 0)
        if case .running(let endsAt) = hooks.state() {
          Image(systemName: "timer")
            .font(Tokens.Text.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.accent)
            .accessibilityHidden(true)
          // System-rendered from the deadline, so the accessory costs no updates.
          Text(timerInterval: Date()...max(endsAt, Date()), countsDown: true)
            .font(Tokens.Text.figure)
            .foregroundStyle(Tokens.Color.accent)
        }
      }
      .padding(.horizontal, Tokens.Spacing.loose)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        Text("Workout in progress, ^[\(coordinator.loggedSetCount) set](inflect: true) logged")
      )
      // The label replaces the combined children, so the countdown is restated here or it would
      // never be spoken.
      .accessibilityValue(restAccessibilityValue)
    }
  }

  /// The rest countdown for VoiceOver, rendered by the system from the deadline like the visible
  /// one. Empty when no rest is running.
  private var restAccessibilityValue: Text {
    if case .running(let endsAt) = hooks.state() {
      return Text("Resting, ")
        + Text(timerInterval: Date()...max(endsAt, Date()), countsDown: true)
        + Text(" left")
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

/// The start screen's gym card: a full-width card that is also one button.
///
/// Outlined with the measured control border rather than a card's decorative hairline, because
/// the boundary is what tells the lifter it can be tapped. Pressed, it sinks to the pressed fill;
/// with Reduce Motion on, the scale is dropped and only the fill changes.
private struct OutlinedCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
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
