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
@MainActor
public struct WeeklyVolumeScreen: View {
  @State private var snapshot = SnapshotLoader<MuscleVolumeReport>()
  @State private var isShowingMap = false
  @State private var lifetime = LifetimeAccess()
  @State private var isShowingMethodology = false

  private let store: VolumeStore
  private let now: () -> Date

  private static let title = "This week"
  private static let subtitle = "Last 7 days"

  public init(store: VolumeStore, now: @escaping () -> Date = { Date() }) {
    self.store = store
    self.now = now
  }

  public var body: some View {
    Group {
      if let report = snapshot.value {
        VolumeReportView(
          report: report,
          // Tokens the catalogue cannot train yet are content debt, not the user's coverage gap.
          excludedFromGaps: ExerciseCatalog.unauthoredDirectTokens,
          title: Self.title,
          subtitle: Self.subtitle,
          onExplainCounting: { isShowingMethodology = true }
        )
      } else if snapshot.loadFailed {
        // Says what is wrong and what is not. Logged sets are safe either way, and saying so is
        // the difference between an error and a scare. Scrollable so the pull-to-refresh the
        // message promises actually works.
        ScrollView {
          VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
            ScreenHeader(Self.title, subtitle: Self.subtitle)
            HardsetEmptyState(
              title: "Could not read this week",
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
          ScreenHeader(Self.title, subtitle: Self.subtitle)
          HardsetLoadingState("Reading this week…")
        }
        .background(Tokens.Color.background)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if snapshot.value != nil {
        Button("Deep muscle map") { isShowingMap = true }
          .buttonStyle(HardsetButtonStyle(.secondary))
          .padding(Tokens.Spacing.loose).background(Tokens.Color.background)
      }
    }
    .sheet(isPresented: $isShowingMap) {
      NavigationStack {
        ScrollView {
          if lifetime.isUnlocked, let report = snapshot.value { MuscleHeatmapView(report: report) }
          else { LifetimePurchaseSection(access: lifetime).padding(Tokens.Spacing.loose) }
        }
        .background(Tokens.Color.background)
        .hardsetNavigationTitle("Deep muscle map")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { isShowingMap = false } } }
        .task { await lifetime.load() }
      }
    }
    .task { await load() }
    .refreshable { await load() }
    .sheet(isPresented: $isShowingMethodology) {
      // Generated from the same value the counting uses, so the disclosure cannot drift from the
      // arithmetic.
      MethodologySheet(source: SetCounting.source, certainty: .moderate)
        .hardsetSheet()
    }
  }

  private func load() async {
    let store = store
    let instant = now()
    await snapshot.load { try await store.loadRollingWeek(endingAt: instant) }
  }
}
