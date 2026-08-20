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

  public init(database: any DatabaseWriter) {
    self.logger = LoggerStore(database: database)
    self.catalog = CatalogSeeder(database: database)
    self.volume = VolumeStore(database: database)
    self.history = HistoryStore(database: database)
    self.progression = ProgressionStore(database: database)
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
  private let environment: HardsetEnvironment
  private let unit: WeightUnit
  private let hooks: RestTimerHooks
  private let restAfterSet: Duration?

  public init(
    environment: HardsetEnvironment,
    unit: WeightUnit = .kilograms,
    hooks: RestTimerHooks = .inert,
    restAfterSet: Duration? = nil
  ) {
    self.environment = environment
    self.unit = unit
    self.hooks = hooks
    self.restAfterSet = restAfterSet
  }

  public var body: some View {
    tabs
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
      }
  }

  @ViewBuilder private var tabs: some View {
    let content = TabView {
      Tab("Train", systemImage: "figure.strengthtraining.traditional") {
        NavigationStack { trainTab }
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
      content
        .tabViewBottomAccessory { liveSessionAccessory }
        .tabBarMinimizeBehavior(.onScrollDown)
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
        onFinished: { self.coordinator = nil }
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
  }

  private func startEmptyWorkout() {
    do {
      // An empty plan on purpose: the app does not invent a program, and there is no generator
      // yet. Movements are added from the picker as the lifter goes.
      coordinator = try SessionCoordinator.start(
        store: environment.logger,
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
        Image(systemName: "figure.strengthtraining.traditional")
        Text("\(coordinator.loggedSetCount) sets logged")
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
      .accessibilityLabel("Workout in progress, \(coordinator.loggedSetCount) sets logged")
    }
  }
}
