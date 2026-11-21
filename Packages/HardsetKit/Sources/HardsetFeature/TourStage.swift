import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The tour page: the real app, staged in a small phone, with a spotlight on the thing each of the
/// eight steps is about and a callout that says what it is.
///
/// Nothing here is a picture. The phone holds two real root views over two in-memory databases built
/// by `TourFixtures`: one with history only, for the start screen, and one with a workout open, for
/// everything after it. Each step reaches its state by asking the real screens through
/// `TourStaging`, and the spotlight follows the tagged controls themselves. Only step two is
/// interactive, so the lifter taps the staged check and logs a real set into the staged database,
/// and the rest that follows is a demo timer with no alarm behind it.
@MainActor
struct TourStage: View {
  @Bindable var model: OnboardingModel
  let unit: WeightUnit

  /// The two staged apps, built once the page is on screen.
  private struct Prepared {
    let start: TourFixtures.Staged
    let live: TourFixtures.Staged
  }

  @State private var prepared: Prepared?
  @State private var failure: String?
  @State private var rest = DemoRestTimer(initialState: .idle)
  @State private var targets = TourTargets()
  /// The staged phone's frame in window coordinates, measured the same way the targets are, so the
  /// spotlight can be placed in the phone's own space whatever the scale.
  @State private var phoneFrame: CGRect = .zero
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      if let prepared {
        stage(prepared)
      } else if let failure {
        failureView(failure)
      } else {
        HardsetLoadingState("Setting up the tour…")
      }
    }
    .task { await prepare() }
    .sensoryFeedback(Tokens.Haptic.selection, trigger: model.tourStep)
    // A rest that ran out while the lifter read the step starts again, so step four always has one
    // to show.
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        if model.tourStep == .rest, rest.state.hasElapsed(at: Date()) { rest.restart() }
      }
    }
    .onChange(of: model.tourStep) { _, step in
      if step == .rest, !rest.state.isRunning, !isPaused { rest.restart() }
    }
  }

  private var isPaused: Bool {
    if case .paused = rest.state { return true }
    return false
  }

  // MARK: - Preparation

  /// Builds both staged apps off the swipe that brought the lifter here: the page shows its loading
  /// line first, and the build runs on the next turn.
  private func prepare() async {
    guard prepared == nil, failure == nil else { return }
    await Task.yield()
    do {
      prepared = Prepared(
        start: try TourFixtures.make(stage: .start, unit: unit),
        live: try TourFixtures.make(stage: .liveSession, unit: unit))
      // Opened straight onto the rest step, there is no logged set to have started one.
      if model.tourStep == .rest { rest.restart() }
    } catch {
      failure = String(describing: error)
    }
  }

  private func failureView(_ detail: String) -> some View {
    VStack(spacing: Tokens.Spacing.regular) {
      HardsetEmptyState(
        title: "The tour could not be set up",
        detail: "Nothing is lost. You can skip it and start logging.",
        systemImage: "exclamationmark.triangle",
        actionTitle: "Skip the tour",
        actionSystemImage: "arrow.right",
        action: { model.skip() }
      )
      Text(verbatim: detail)
        .hardsetText(.caption)
        .foregroundStyle(Tokens.Color.chalkDim)
        .multilineTextAlignment(.center)
        .lineLimit(4)
        .textSelection(.enabled)
        .padding(.horizontal, Tokens.Spacing.section)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Stage

  private func stage(_ prepared: Prepared) -> some View {
    // Read here, not inside the reader below, so the page is redrawn when a target reports.
    let target = localTarget
    return GeometryReader { proxy in
      let width = proxy.size.width * ScaledPhoneFrame<EmptyView>.screenWidthFraction
      ZStack(alignment: calloutAtTop(for: target) ? .top : .bottom) {
        ScaledPhoneFrame(isInteractive: isPhoneInteractive) {
          phone(prepared, target: target)
        }
        .frame(maxWidth: width, maxHeight: proxy.size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        callout
          .padding(.horizontal, Tokens.Spacing.loose)
          .padding(.vertical, Tokens.Spacing.loose)
          // Read before the staged phone, which stays reachable by VoiceOver and is only a picture of
          // what the callout says.
          .accessibilitySortPriority(1)
          .id(model.tourStep)
          .transition(.opacity)
      }
      .animation(Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion), value: model.tourStep)
    }
  }

  /// The phone answers to touch only while step two waits for its tap. After the set is logged it
  /// is inert again, so the lifter cannot wander into a sheet that would present over the window.
  private var isPhoneInteractive: Bool {
    model.tourStep == .logSet && !model.hasLoggedTourSet
  }

  private func phone(_ prepared: Prepared, target: CGRect?) -> some View {
    ZStack {
      root(
        prepared.start, staging: TourStaging(presentsSheetsInline: true),
        isShown: model.tourStep == .train)
      root(prepared.live, staging: liveStaging, isShown: model.tourStep != .train)
    }
    .environment(\.tourTargets, targets)
    // The pager's page style travels down the environment to every tab view below it, so the staged
    // root's own tab view would otherwise become a second pager nested in the first, with no tab
    // bar and a scroll view fighting the one that turns the page.
    .tabViewStyle(.automatic)
    .background {
      Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
        phoneFrame = $0
      }
    }
    .overlay { SpotlightOverlay(target: target) }
  }

  /// One staged app. Both stay alive for the whole tour, so a step never waits on a root preparing;
  /// the one not in use is hidden, inert and silent to VoiceOver.
  private func root(_ staged: TourFixtures.Staged, staging: TourStaging, isShown: Bool) -> some View {
    HardsetRootView(
      environment: staged.environment, unit: unit, hooks: hooks,
      // The staged app starts a rest when its set is logged: that is how the tour learns the lifter
      // tapped the check, and it gives step four a rest to show. The daily app starts none until the
      // lifter has chosen a length for that movement, and step four's callout says so.
      restAfterSet: .seconds(90),
      // The staged app's settings must not offer a replay from inside the replay, and its roots
      // must not touch the real scene's pending gym pick.
      onShowTour: nil,
      restoresSceneState: false
    )
    .environment(\.tourStaging, staging)
    .opacity(isShown ? 1 : 0)
    .allowsHitTesting(isShown)
    .accessibilityHidden(!isShown)
    .animation(Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion), value: isShown)
  }

  /// The staged rest timer. A demo timer stands in for the alarm-backed one, and a rest starting is
  /// how the tour learns the lifter logged the staged set.
  private var hooks: RestTimerHooks {
    RestTimerHooks(
      state: { rest.state },
      start: { duration, _ in
        rest.start(for: duration)
        model.didLogTourSet()
      },
      adjust: { rest.adjust(by: $0) },
      pauseOrResume: { rest.pauseOrResume() },
      cancel: { rest.cancel() }
    )
  }

  /// What the live root is asked for at the current step.
  private var liveStaging: TourStaging {
    var staging = TourStaging(presentsSheetsInline: true)
    switch model.tourStep {
    case .train, .logSet, .rest: break
    case .keypad: staging.opensKeypad = true
    case .machines: staging.opensMachinePicker = true
    case .volume: staging.tab = .volume
    case .history: staging.tab = .history
    case .settings: staging.showsSettings = true
    }
    return staging
  }

  // MARK: - Spotlight and callout

  private var target: TourTarget {
    switch model.tourStep {
    case .train: .startAction
    case .logSet: .logCheck
    case .keypad: .keypad
    case .rest: .restBar
    case .machines: .machineList
    case .volume: .volumeFigures
    case .history: .historyList
    case .settings: .settingsUnits
    }
  }

  /// The current target in the phone's own coordinates, which is where the spotlight is drawn:
  /// the window rectangle it reported, moved to the phone's origin and divided by its scale.
  private var localTarget: CGRect? {
    guard let global = targets.rect(for: target), phoneFrame.width > 0 else { return nil }
    let scale = phoneFrame.width / ScaledPhoneFrame<EmptyView>.phoneSize.width
    return CGRect(
      x: (global.minX - phoneFrame.minX) / scale, y: (global.minY - phoneFrame.minY) / scale,
      width: global.width / scale, height: global.height / scale)
  }

  /// The callout sits in the half of the phone the target is not in, so it never covers it.
  private func calloutAtTop(for target: CGRect?) -> Bool {
    guard let target else { return false }
    return target.midY > ScaledPhoneFrame<EmptyView>.phoneSize.height / 2
  }

  private var callout: some View {
    CalloutCard(
      step: model.tourStep.number, of: OnboardingModel.tourStepCount,
      message: Self.message(for: model.tourStep),
      nextTitle: model.canAdvanceTour ? "Next" : nil,
      onNext: { withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) { model.next() } },
      onSkip: { model.skip() }
    )
  }

  /// One line per step. The first differs from the design's wording: the start screen offers one
  /// action, "Start workout", and no repeat of the last workout, so it says what is there.
  static func message(for step: OnboardingModel.TourStep) -> String {
    switch step {
    case .train: "One tap starts a workout. Your last one is further down."
    case .logSet: "Weight, reps, log. The check is the only thing you need to hit."
    case .keypad: "Tap a figure to change it. The keypad never hides the row."
    case .rest: "Choose a rest length for each movement and it runs as an alarm. Here one is started for you to nudge."
    case .machines: "The machine in front of you is at the top. Each machine keeps its own history."
    case .volume: "Sets per muscle this week, counted from what you logged, scaled to your own week."
    case .history: "Every session is a receipt you can share."
    case .settings: "Units, gyms, and export, all here."
    }
  }
}
