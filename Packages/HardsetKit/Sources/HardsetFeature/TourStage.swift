import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        start: try TourFixtures.make(stage: .start),
        live: try TourFixtures.make(stage: .liveSession))
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
    .background {
      Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
        phoneFrame = $0
      }
    }
    .overlay { SpotlightOverlay(target: target) }
  }

  /// One staged app. Both stay alive for the whole tour, so a step never waits on a root preparing;
  /// the one not in use is hidden, inert and silent to VoiceOver.
  ///
  /// Each root sits in a hosting controller of its own (`StagedHost`). The root's tab view and
  /// navigation stacks put their content in UIKit views, which `accessibilityHidden` on a SwiftUI
  /// ancestor does not reach, so a root hidden that way was still read to VoiceOver and listed by
  /// the UI tests; hiding the hosting view does hide it. The boundary also keeps the pager's page
  /// style, a SwiftUI environment value, from reaching the staged tab view. What the root reads
  /// from the environment is passed in, because the environment does not cross it.
  private func root(_ staged: TourFixtures.Staged, staging: TourStaging, isShown: Bool) -> some View {
    StagedHost(isAccessible: isShown && isPhoneInteractive) {
      HardsetRootView(
        environment: staged.environment, unit: unit, hooks: hooks,
        // A rest starts when a set is logged, as the tour's fourth step says it does. The daily app
        // does not start one on its own.
        restAfterSet: .seconds(90),
        onShowTour: {}
      )
      .environment(\.tourStaging, staging)
      .environment(\.tourTargets, targets)
      .environment(\.dynamicTypeSize, dynamicTypeSize)
    }
    .opacity(isShown ? 1 : 0)
    .allowsHitTesting(isShown)
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
    case .train: "One tap starts a workout. Your last one is right below it."
    case .logSet: "Weight, reps, log. The check is the only thing you need to hit."
    case .keypad: "Tap a figure to change it. The keypad never hides the row."
    case .rest: "Rest starts when you log a set, and you can nudge it."
    case .machines: "The machine in front of you is at the top. Each machine keeps its own history."
    case .volume: "Sets per muscle this week, counted from what you logged, scaled to your own week."
    case .history: "Every session is a receipt you can share."
    case .settings: "Units, gyms, export, and the tour again, all here."
    }
  }
}

#if canImport(UIKit)
  /// Hosts a staged root in a `UIHostingController` of its own, so it can be hidden from
  /// accessibility at the UIKit level, where its tab view and navigation stacks keep their content.
  /// Transparent, and sized by whatever it is offered.
  private struct StagedHost<Content: View>: UIViewControllerRepresentable {
    let isAccessible: Bool
    let content: Content

    init(isAccessible: Bool, @ViewBuilder content: () -> Content) {
      self.isAccessible = isAccessible
      self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
      let host = UIHostingController(rootView: content)
      host.view.backgroundColor = .clear
      host.view.accessibilityElementsHidden = !isAccessible
      return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
      host.rootView = content
      host.view.accessibilityElementsHidden = !isAccessible
    }
  }
#else
  /// Where there is no UIKit, the root is drawn in place and hidden the SwiftUI way.
  private struct StagedHost<Content: View>: View {
    let isAccessible: Bool
    let content: Content

    init(isAccessible: Bool, @ViewBuilder content: () -> Content) {
      self.isAccessible = isAccessible
      self.content = content()
    }

    var body: some View {
      content.accessibilityHidden(!isAccessible)
    }
  }
#endif
