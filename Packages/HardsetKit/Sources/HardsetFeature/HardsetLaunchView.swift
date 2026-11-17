import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Which first-launch sequence this build shows. Raising it shows the sequence again to everyone,
/// which is how a future redesign of it reaches lifters who have already seen this one.
public enum OnboardingVersion {
  public static let current = 1
}

/// What the app opens on: the first-launch sequence until the lifter has seen it, then the app.
///
/// The gate is the stored `hardset.onboardingVersion`, so an existing install, which has none,
/// sees the sequence once on update with Setup pre-filled from what it already has. The root view
/// is not built until the sequence is done, so nothing behind it prepares or reads while the
/// lifter is still on Welcome. Finishing cross-fades to the root rather than pushing, so the app
/// does not look like one more onboarding page. Settings replays the sequence in a full-screen
/// cover, which neither restarts the app nor touches the stored version.
@MainActor
public struct HardsetLaunchView: View {
  @AppStorage("hardset.onboardingVersion") private var onboardingVersion = 0
  /// The same stored preference the root view reads, with the same locale default, so the unit the
  /// lifter sees on Welcome is the unit the app opens in.
  @AppStorage("hardset.useImperial") private var useImperial = Locale.current.measurementSystem == .us
  /// Shared with the root view's own scene storage, so the gym named in Setup is the one the first
  /// workout starts at.
  @SceneStorage("hardset.pendingGymPick") private var pendingGymPick = ""
  @State private var isReplaying = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let environment: HardsetEnvironment
  private let unit: WeightUnit?
  private let hooks: RestTimerHooks
  private let restAfterSet: Duration?

  public init(
    environment: HardsetEnvironment, unit: WeightUnit? = nil, hooks: RestTimerHooks = .inert,
    restAfterSet: Duration? = nil
  ) {
    self.environment = environment
    self.unit = unit
    self.hooks = hooks
    self.restAfterSet = restAfterSet
  }

  private var hasSeenOnboarding: Bool {
    onboardingVersion >= OnboardingVersion.current
  }

  public var body: some View {
    ZStack {
      if hasSeenOnboarding {
        HardsetRootView(
          environment: environment, unit: unit, hooks: hooks, restAfterSet: restAfterSet,
          onShowTour: { isReplaying = true }
        )
        .transition(.opacity)
        .replayCover(isPresented: $isReplaying) {
          OnboardingFlow(
            gyms: environment.gyms, useImperial: $useImperial, mode: .replay
          ) { _ in isReplaying = false }
        }
      } else {
        OnboardingFlow(gyms: environment.gyms, useImperial: $useImperial) { gymID in
          if let gymID { pendingGymPick = gymID.rawValue.uuidString }
          onboardingVersion = OnboardingVersion.current
        }
        .transition(.opacity)
      }
    }
    .animation(Tokens.Motion.adaptive(Tokens.Motion.reveal, reduceMotion: reduceMotion), value: hasSeenOnboarding)
  }
}

extension View {
  /// A full-screen cover on iOS; the macOS host build, which only compiles the package, has no
  /// such presentation and uses a sheet.
  fileprivate func replayCover<Content: View>(
    isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    #if os(iOS)
      fullScreenCover(isPresented: isPresented, content: content)
    #else
      sheet(isPresented: isPresented, content: content)
    #endif
  }
}
