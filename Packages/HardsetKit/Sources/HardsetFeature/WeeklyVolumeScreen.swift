import HardsetCore
import HardsetStore
import HardsetUI
import SwiftUI

/// Sets per muscle for the last seven days, wired.
///
/// Loads once per appearance rather than observing the database. The report is a snapshot of a
/// window, so a figure that changed while being read would be describing two different windows at
/// once — and there is no live-updating requirement here that would justify the complexity.
///
/// Draws its own header in every state, because the Volume tab hides the stock navigation bar.
///
/// The window is rolling, so it is named by its dates rather than called "this week", and it is
/// re-read whenever the app returns to the foreground: a window computed last night and shown this
/// morning would count a day too many under a heading that still says "last 7 days". The lifter
/// can step back a week at a time to compare.
@MainActor
public struct WeeklyVolumeScreen: View {
  @State private var snapshot = SnapshotLoader<VolumeWindow>()
  @State private var isShowingMap = false
  @State private var isShowingMethodology = false
  /// How many whole weeks before now the window ends. Zero is the last seven days.
  @State private var weeksBack = 0
  /// Bumped when the app returns to the foreground, so the rolling window is recomputed from now.
  @State private var reloadToken = 0
  @Environment(\.scenePhase) private var scenePhase

  private let store: VolumeStore
  private let now: () -> Date
  private let onShowSettings: (() -> Void)?

  /// One entitlement app-wide, shared with Settings.
  private let lifetime = LifetimeAccess.shared

  private static let title = "Volume"
  /// How far back the window can step: a year of weeks.
  private static let maximumWeeksBack = 52

  public init(
    store: VolumeStore, now: @escaping () -> Date = { Date() }, onShowSettings: (() -> Void)? = nil
  ) {
    self.store = store
    self.now = now
    self.onShowSettings = onShowSettings
  }

  public var body: some View {
    Group {
      if let window = snapshot.value {
        VolumeReportView(
          report: window.report,
          // Tokens the catalogue cannot train yet are content debt, not the user's coverage gap.
          excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
          title: Self.title,
          subtitle: window.description,
          onExplainCounting: { isShowingMethodology = true },
          period: window.period,
          onShowSettings: onShowSettings,
          onEarlier: weeksBack < Self.maximumWeeksBack ? { weeksBack += 1 } : nil,
          onLater: weeksBack > 0 ? { weeksBack -= 1 } : nil
        )
      } else if snapshot.loadFailed {
        // Says what is wrong and what is not. Logged sets are safe either way, and saying so is
        // the difference between an error and a scare. Scrollable so the pull-to-refresh the
        // message promises actually works.
        ScrollView {
          VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
            header(subtitle: "Sets per muscle")
            HardsetEmptyState(
              title: "Could not read these 7 days",
              detail: "Your logged sets are safe. Pull down to try again.",
              systemImage: "exclamationmark.triangle"
            )
          }
          .padding(.bottom, Tokens.Spacing.block)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.background)
      } else {
        // A sentence rather than a spinner: the read takes milliseconds, and a spinner would only
        // flash.
        VStack(alignment: .leading, spacing: 0) {
          header(subtitle: "Sets per muscle")
          HardsetLoadingState("Reading the last 7 days…")
        }
        .background(Tokens.Color.background)
      }
    }
    .safeAreaInset(edge: .bottom) {
      // Offered only when there is something to map. An empty window's map is all zeros.
      if let window = snapshot.value, window.report.hardSets > 0 {
        Button("Deep muscle map") { isShowingMap = true }
          .buttonStyle(HardsetButtonStyle(.secondary))
          .padding(Tokens.Spacing.loose).background(Tokens.Color.background)
      }
    }
    .sheet(isPresented: $isShowingMap) {
      NavigationStack {
        ScrollView {
          // Says it is checking rather than flashing the purchase offer before the entitlement is
          // known.
          if !lifetime.hasLoaded {
            HardsetLoadingState("Checking your purchase…")
          } else if lifetime.isUnlocked, let window = snapshot.value {
            VStack(alignment: .leading, spacing: Tokens.Spacing.regular) {
              // States why the map is open when it was not bought, such as a development build.
              LifetimeDevelopmentNote(access: lifetime).padding(.horizontal, Tokens.Spacing.loose)
              MuscleHeatmapView(report: window.report, windowLabel: window.description)
            }
          } else {
            LifetimePurchaseSection(access: lifetime).padding(Tokens.Spacing.loose)
          }
        }
        .background(Tokens.Color.background)
        .hardsetNavigationTitle("Deep muscle map")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingMap = false } } }
        .task { await lifetime.load() }
      }
      .hardsetSheet()
    }
    // Keyed on the window and the foreground token, so stepping or returning re-reads, and a
    // superseded read is cancelled.
    .task(id: WindowKey(weeksBack: weeksBack, token: reloadToken)) { await load() }
    .refreshable { await load() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { reloadToken &+= 1 }
    }
    .sheet(isPresented: $isShowingMethodology) {
      // Generated from the same value the counting uses, so the disclosure cannot drift from the
      // arithmetic.
      MethodologySheet(source: SetCounting.source, certainty: .moderate)
        .hardsetSheet()
    }
  }

  private func header(subtitle: String) -> some View {
    ScreenHeader(Self.title, subtitle: subtitle) {
      if let onShowSettings {
        HeaderIconButton(systemImage: "gearshape", accessibilityLabel: "Settings", action: onShowSettings)
      }
    }
  }

  private func load() async {
    let store = store
    // Whole local days, so the dates in the heading are exactly the days counted.
    let range = VolumeWindowRange(endingAt: now(), weeksBack: weeksBack)
    await snapshot.load {
      let report = try await store.loadReport(in: range)
      return VolumeWindow(report: report, range: range)
    }
  }
}

/// One read: the report and the window it covers, kept together so the heading always names the
/// window whose numbers are on screen, even while the next one is being read.
private nonisolated struct VolumeWindow: Sendable {
  let report: MuscleVolumeReport
  let range: VolumeWindowRange

  /// "Last 7 days, 3 Nov to now", or "7 days, 27 Oct to 2 Nov" for an earlier window. Both name
  /// days counted in full, and adjacent windows never name the same day.
  var description: String {
    let day = Date.FormatStyle.dateTime.day().month(.abbreviated)
    let from = range.start.formatted(day)
    return range.weeksBack == 0
      ? "Last 7 days, \(from) to now"
      : "7 days, \(from) to \(range.lastDay.formatted(day))"
  }

  /// The phrase every sentence on the screen uses for this window.
  var period: String { range.weeksBack == 0 ? "in the last 7 days" : "in these 7 days" }
}

private nonisolated struct WindowKey: Hashable, Sendable {
  let weeksBack: Int
  let token: Int
}
