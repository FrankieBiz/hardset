import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// The first launch as one horizontal pager: Welcome, three pitch pages, the Tour, then Setup.
///
/// All of its state is in `OnboardingModel`, which the pager's selection is bound to, so a swipe and
/// a button press are the same change. "Skip" is a visible control from the second page on and
/// always lands on Setup; the welcome bar owns horizontal drags inside its own region, so a swipe
/// there loads a plate and a swipe anywhere else turns the page.
///
/// A replay from Settings uses the same flow without Setup and ends by calling `onFinish`.
@MainActor
public struct OnboardingFlow: View {
  @State private var model: OnboardingModel
  @Binding private var useImperial: Bool
  private let onFinish: (GymID?) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var progressNamespace

  /// - Parameters:
  ///   - useImperial: The app's stored unit preference. Setup edits it in place.
  ///   - startingPage: The page shown first, for a capture.
  ///   - startingTourStep: The tour step shown first, for a capture.
  ///   - onFinish: Called with the gym Setup settled on, or `nil` when none was named or this is a
  ///     replay, once the lifter has finished or skipped to the end.
  public init(
    gyms: GymStore, useImperial: Binding<Bool>, mode: OnboardingModel.Mode = .firstLaunch,
    startingPage: OnboardingModel.Page = .welcome,
    startingTourStep: OnboardingModel.TourStep = .train, onFinish: @escaping (GymID?) -> Void
  ) {
    _model = State(
      initialValue: OnboardingModel(
        gyms: gyms, mode: mode, startingPage: startingPage, startingTourStep: startingTourStep))
    _useImperial = useImperial
    self.onFinish = onFinish
  }

  private var unit: WeightUnit { useImperial ? .pounds : .kilograms }

  public var body: some View {
    VStack(spacing: 0) {
      topBar
      pager
      footer
    }
    .background(Tokens.Color.canvas.ignoresSafeArea())
    .onChange(of: model.isReplayFinished) { _, finished in
      if finished { onFinish(nil) }
    }
  }

  // MARK: - Chrome

  /// The page style of `TabView` is an iOS control; the macOS host build, which only compiles the
  /// package, shows the current page without swiping.
  @ViewBuilder private var pager: some View {
    #if os(iOS)
      TabView(selection: $model.page) {
        ForEach(model.pages, id: \.self) { page in
          content(for: page).tag(page)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
    #else
      content(for: model.page)
    #endif
  }

  /// A fixed-height row, so the pages do not jump when "Skip" arrives on the second page.
  private var topBar: some View {
    HStack {
      Spacer()
      if model.canSkip {
        Button("Skip") { model.skip() }
          .buttonStyle(HardsetButtonStyle(.quiet, fullWidth: false))
          .transition(.opacity)
      }
    }
    .padding(.horizontal, Tokens.Spacing.loose)
    .frame(minHeight: Tokens.minimumTapTarget)
    .animation(Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion), value: model.canSkip)
  }

  @ViewBuilder private var footer: some View {
    switch model.page {
    case .welcome:
      footerButton("Start")
    case .pitchSetRow, .pitchEstimate, .pitchRest:
      VStack(spacing: Tokens.Spacing.regular) {
        PitchProgress(
          index: model.page.rawValue - OnboardingModel.Page.pitchSetRow.rawValue, count: 3,
          namespace: progressNamespace)
        footerButton("Next")
      }
    case .tour, .setup:
      EmptyView()
    }
  }

  private func footerButton(_ title: String) -> some View {
    Button(title) {
      withAnimation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion)) {
        model.next()
      }
    }
    .buttonStyle(HardsetButtonStyle(.primary, size: .logger))
    .padding(.horizontal, Tokens.Spacing.loose)
    .padding(.vertical, Tokens.Spacing.regular)
  }

  // MARK: - Pages

  @ViewBuilder private func content(for page: OnboardingModel.Page) -> some View {
    switch page {
    case .welcome: WelcomePage(unit: unit)
    case .pitchSetRow: PitchSetRowPage(unit: unit)
    case .pitchEstimate: PitchEstimatePage(unit: unit)
    case .pitchRest: PitchRestPage()
    case .tour: TourStage(model: model, unit: unit)
    case .setup:
      SetupPage(model: model, useImperial: $useImperial) {
        onFinish(model.chosenGymID)
      }
    }
  }
}

/// The first page: the wordmark, one line, and the bar the lifter loads. The line changes once they
/// have loaded a plate themselves.
@MainActor
private struct WelcomePage: View {
  let unit: WeightUnit
  @State private var hasLoaded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: Tokens.Spacing.block) {
      VStack(spacing: Tokens.Spacing.snug) {
        Text("Hardset")
          .hardsetText(.display)
          .foregroundStyle(Tokens.Color.chalk)
          .accessibilityAddTraits(.isHeader)
        Text(hasLoaded ? "That’s a set logged in one tap." : "A calibrated log for the lifts you actually do.")
          .hardsetText(.label)
          .foregroundStyle(Tokens.Color.chalkDim)
          .multilineTextAlignment(.center)
          .contentTransition(.opacity)
          .animation(Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion), value: hasLoaded)
      }
      .padding(.top, Tokens.Spacing.block)
      WelcomeBarView(unit: unit, onLifterLoaded: { hasLoaded = true })
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Tokens.Spacing.loose)
  }
}

/// Three short segments above the pitch pages' button. The active one is plate blue and slides to
/// the next on `Motion.state`; a `matchedGeometryEffect` moves one shape between segments inside
/// this row and never changes its layout.
private struct PitchProgress: View {
  let index: Int
  let count: Int
  let namespace: Namespace.ID
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: Tokens.Spacing.snug) {
      ForEach(0..<count, id: \.self) { position in
        ZStack {
          Rectangle().fill(Tokens.Color.hairline)
          if position == index {
            Rectangle()
              .fill(Tokens.Color.plateBlue)
              .matchedGeometryEffect(id: "pitchProgress", in: namespace)
          }
        }
        .frame(width: 28, height: 4)
      }
    }
    .animation(Tokens.Motion.adaptive(Tokens.Motion.state, reduceMotion: reduceMotion), value: index)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(index + 1) of \(count)")
  }
}
